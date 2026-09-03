#!/usr/bin/env node
// csharp-ls, re-rooted onto the solution that owns the first .cs file opened.
//
// csharp-ls loads exactly one solution, chosen before it starts. The session's
// root is the only thing available then, so from a monorepo root there is no
// ancestor .sln and every answer comes back empty -- confidently, not as an
// error. An aggregate solution is not the way out: this repo has 322 projects
// across 120 solutions and five target frameworks, most of which the installed
// SDK cannot load.
//
// So the solution is picked late. The server starts on whatever the root gives
// (usually nothing), and the first textDocument/didOpen naming a .cs file says
// which service is actually being worked on. If that differs from what is
// loaded, the server is restarted against the right .sln and the session is
// replayed into it. The client is never told: it keeps the capabilities the
// first server gave it, which are the same ones, from the same binary.
'use strict';
const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const SENTINEL = 2147483647;   // id for our replayed initialize; never forwarded
const MAX_REROOTS = 5;         // bound the cost of an agent hopping services

const root = canonical(process.env.CLAUDE_PROJECT_DIR || process.cwd());

function canonical(p) {
  try { return fs.realpathSync(path.resolve(p)); } catch { return path.resolve(p); }
}

function gitTop(from) {
  try {
    return execFileSync('git', ['-C', from, 'rev-parse', '--show-toplevel'],
      { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
  } catch { return null; }
}

// GlobalSolution.sln is never a candidate: it fails MSB5023 on a stale
// NestedProjects GUID in every MSBuild-based tool, csharp-ls included.
function solutionFor(startDir) {
  const stop = gitTop(startDir) || path.parse(startDir).root;
  let dir = canonical(startDir);
  for (;;) {
    let names = [];
    try { names = fs.readdirSync(dir); } catch {}
    const hit = names.filter(n => n.endsWith('.sln') && n !== 'GlobalSolution.sln').sort()[0];
    if (hit) return path.join(dir, hit);
    if (dir === stop || dir === path.parse(dir).root) return null;
    const up = path.dirname(dir);
    if (up === dir) return null;
    dir = up;
  }
}

function uriToPath(uri) {
  if (typeof uri !== 'string' || !uri.startsWith('file://')) return null;
  try { return decodeURIComponent(uri.slice('file://'.length)); } catch { return null; }
}

function frame(msg) {
  const body = Buffer.from(JSON.stringify(msg), 'utf8');
  return Buffer.concat([Buffer.from(`Content-Length: ${body.length}\r\n\r\n`, 'ascii'), body]);
}

// --- the server -------------------------------------------------------------

let child = null;
let currentSolution = null;
let reroots = 0;
let restarting = false;
const clientQueue = [];        // client frames held while a restart is in flight

// Replayed verbatim into a restarted server, in arrival order: initialized,
// any workspace/* notification, and every didOpen seen so far.
let initializeParams = null;
const replay = [];

function startServer(solution) {
  currentSolution = solution;
  const args = solution ? ['--solution', solution, '--features', 'metadata-uris']
                        : ['--features', 'metadata-uris'];
  const c = spawn('csharp-ls', args, { stdio: ['pipe', 'pipe', 'inherit'] });
  c.on('error', e => { process.stderr.write(`csharp-ls-proxy: ${e.message}\n`); process.exit(127); });
  c.on('exit', (code, sig) => { if (!restarting) process.exit(sig ? 1 : code === null ? 1 : code); });
  readFrames(c.stdout, onServerMessage);
  return c;
}

function onServerMessage(buf, msg) {
  // Our replayed initialize is ours alone: the client already has its answer
  // from the first server and a second one would be a duplicate response.
  if (msg && msg.id === SENTINEL) return;
  process.stdout.write(buf);
}

async function reroot(solution) {
  restarting = true;
  reroots++;
  try { child.kill('SIGTERM'); } catch {}
  child = startServer(solution);

  await new Promise(resolve => {
    const done = (_buf, m) => { if (m && m.id === SENTINEL) resolve(); };
    pendingInit = done;
    child.stdin.write(frame({ jsonrpc: '2.0', id: SENTINEL, method: 'initialize', params: initializeParams }));
  });
  pendingInit = null;

  for (const f of replay) child.stdin.write(f);
  restarting = false;
  while (clientQueue.length) child.stdin.write(clientQueue.shift());
}

let pendingInit = null;

// --- framing ----------------------------------------------------------------

function readFrames(stream, onMessage) {
  let buf = Buffer.alloc(0);
  stream.on('data', chunk => {
    buf = Buffer.concat([buf, chunk]);
    for (;;) {
      const sep = buf.indexOf('\r\n\r\n');
      if (sep < 0) return;
      const m = /content-length:\s*(\d+)/i.exec(buf.slice(0, sep).toString('ascii'));
      if (!m) { buf = buf.slice(sep + 4); continue; }
      const len = parseInt(m[1], 10);
      if (buf.length < sep + 4 + len) return;
      const full = buf.slice(0, sep + 4 + len);
      const bodyStr = buf.slice(sep + 4, sep + 4 + len).toString('utf8');
      buf = buf.slice(sep + 4 + len);
      let msg = null;
      try { msg = JSON.parse(bodyStr); } catch {}
      if (pendingInit) pendingInit(full, msg);
      onMessage(full, msg);
    }
  });
}

// --- client → server --------------------------------------------------------

child = startServer(solutionFor(root));

readFrames(process.stdin, (buf, msg) => {
  if (msg && msg.method === 'initialize') initializeParams = msg.params;

  if (msg && (msg.method === 'initialized'
              || (typeof msg.method === 'string' && msg.method.startsWith('workspace/')
                  && msg.id === undefined)
              || msg.method === 'textDocument/didOpen')) {
    replay.push(buf);
  }

  if (msg && msg.method === 'textDocument/didOpen' && !restarting && reroots < MAX_REROOTS) {
    const file = uriToPath(msg.params && msg.params.textDocument && msg.params.textDocument.uri);
    if (file && file.endsWith('.cs')) {
      const want = solutionFor(path.dirname(file));
      if (want && want !== currentSolution) {
        clientQueue.push(buf);
        reroot(want);
        return;
      }
    }
  }

  if (restarting) { clientQueue.push(buf); return; }
  child.stdin.write(buf);
});

process.stdin.on('end', () => { try { child.stdin.end(); } catch {} });
