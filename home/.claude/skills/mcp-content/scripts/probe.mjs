#!/usr/bin/env node
/**
 * probe.mjs — the checks that took hours to reconstruct by hand, in one place.
 *
 *   node ~/.claude/skills/mcp-content/scripts/probe.mjs health
 *   node …/probe.mjs tools            # both endpoints, diffed — the cheapest drift signal
 *   node …/probe.mjs limits
 *   node …/probe.mjs codes            # the error-code matrix against a LIVE connector
 *   node …/probe.mjs compressed       # prove the gzip+base64 relay path end to end
 *   node …/probe.mjs drafts           # draft reconciliation, incl. the did-anything-publish check
 *
 * Options: --mcp <url> (default http://127.0.0.1:8790/mcp), --ref <url> (default …:8791/mcp),
 *          --token <bearer>, --type/--id/--locale for the page the write probes use.
 *
 * Everything it writes is `draft = 1`, and it deletes what it writes. It cannot publish.
 *
 * Why this exists: every push defect found in this project was invisible to the reference harness and
 * visible only against the real .NET connector. `codes` and `compressed` are therefore written to run
 * against a live connector, not a mock.
 */
import { execFileSync } from 'node:child_process';
import { gzipSync } from 'node:zlib';
import { createHash } from 'node:crypto';

const GUIDE = process.env.CONTENT_STUDIO_REPO || `${process.env.HOME}/Work/guide/tools/content-studio`;
const { createMcpClient } = await import(`${GUIDE}/lib/transport/mcp-client.mjs`);

const argv = process.argv.slice(2);
const cmd = argv[0];
const opt = (n, d) => { const i = argv.indexOf(n); return i === -1 ? d : argv[i + 1]; };

const MCP = opt('--mcp', 'http://127.0.0.1:8790/mcp');
const REF = opt('--ref', 'http://127.0.0.1:8791/mcp');
const TARGET = { type: opt('--type', 'article'), id: Number(opt('--id', 286)), locale: opt('--locale', 'de') };
const TIMEOUT = Number(process.env.CONTENT_STUDIO_TIMEOUT_MS || 600000);

const sql = (q) => execFileSync('docker', [
  'exec', 'mysql', 'sh', '-c',
  `mysql -uroot -p"$MYSQL_ROOT_PASSWORD" "staging-gti" -N -B -e ${JSON.stringify(q)} 2>/dev/null`,
], { encoding: 'utf8', env: { ...process.env, DOCKER_HOST: `unix://${process.env.HOME}/.colima/default/docker.sock` } }).trim();

function token() {
  const given = opt('--token', process.env.CONTENT_STUDIO_MCP_TOKEN);
  if (given) return given;
  const origin = new URL(MCP).origin;
  return execFileSync(process.execPath, [`${GUIDE}/harness/connector-token.mjs`, origin], { encoding: 'utf8', cwd: GUIDE }).trim().split('\n').pop();
}
const un = (r) => (r && r.structuredContent) ? r.structuredContent : r;
const client = (url, tok) => createMcpClient({ url, token: tok, timeoutMs: TIMEOUT });

async function listTools(url, tok) {
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'content-type': 'application/json', accept: 'application/json, text/event-stream', ...(tok ? { authorization: `Bearer ${tok}` } : {}) },
    body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'tools/list' }),
    signal: AbortSignal.timeout(60000),
  });
  const text = await res.text();
  const line = text.split('\n').find((l) => l.startsWith('data: ')) || text;
  const body = JSON.parse(line.replace(/^data: /, ''));
  return (body.result?.tools ?? []).map((t) => t.name).sort();
}

/* ------------------------------------------------------------------ */

if (cmd === 'health') {
  const checks = [
    ['admin :4001', async () => {
      const r = await fetch('http://127.0.0.1:4001/translate/article/286?locale=de', { headers: { host: 'admin.traveldev.localhost' }, signal: AbortSignal.timeout(180000) });
      const b = await r.text();
      if (b.includes("Can't translate")) throw new Error('answered the locale error page');
      return `${(b.length / 1024).toFixed(0)} KB`;
    }],
    [`connector ${MCP}`, async () => {
      const r = await fetch(MCP, { method: 'POST', signal: AbortSignal.timeout(30000) });
      if (r.status !== 401) throw new Error(`HTTP ${r.status} (401 is the healthy unauthenticated answer)`);
      return '401 as expected';
    }],
    [`shim ${REF}`, async () => `${(await listTools(REF)).length} tools`],
  ];
  for (const [label, fn] of checks) {
    try { console.log(`  ok    ${label} — ${await fn()}`); }
    catch (e) { console.log(`  FAIL  ${label} — ${e.message}`); }
  }
} else if (cmd === 'tools') {
  const tok = token();
  const [a, b] = await Promise.all([listTools(MCP, tok), listTools(REF)]);
  console.log('connector:', a.join(', '));
  console.log('reference:', b.join(', '));
  const only = (x, y) => x.filter((n) => !y.includes(n));
  if (!only(a, b).length && !only(b, a).length) console.log('\nIDENTICAL — no drift.');
  else {
    console.log('\nDRIFT');
    if (only(a, b).length) console.log('  connector only:', only(a, b).join(', '));
    if (only(b, a).length) console.log('  reference only:', only(b, a).join(', '));
  }
} else if (cmd === 'limits') {
  const c = client(MCP, token());
  const p = un(await c.call('open_page', TARGET));
  const s = un(await c.call('start_push', { ...TARGET, version_hash: p.version_hash }));
  console.log(JSON.stringify(s.limits ?? null, null, 2));
  if (!s.limits) console.log('\nNo `limits` — the skill falls back to its own constant and to identity only.');
} else if (cmd === 'codes') {
  // Each case is a refusal the contract names. What matters is not that it refuses but WHICH code it
  // gives: a wrong code sends the caller to fix something that was never wrong. That has been the
  // single most damaging defect class in this project.
  const tok = token();
  const c = client(MCP, tok);
  const p = un(await c.call('open_page', TARGET));
  const payload = JSON.stringify({ fields: { title: p.fields.title } });
  const b64 = gzipSync(Buffer.from(payload, 'utf8'), { level: 9 }).toString('base64');
  const good = `sha256:${createHash('sha256').update(Buffer.from(payload, 'utf8')).digest('hex')}`;
  const wrong = `sha256:${createHash('sha256').update(Buffer.from(b64, 'base64')).digest('hex')}`;

  const cases = [
    ['digest over the COMPRESSED bytes', { payload: b64, payload_encoding: 'gzip+base64', payload_sha256: wrong }, 'payload_corrupt'],
    ['corrupt base64', { payload: `${b64.slice(0, -8)}ZZZZZZZZ`, payload_encoding: 'gzip+base64', payload_sha256: good }, 'payload_corrupt'],
    ['decompression bomb', { payload: gzipSync(Buffer.alloc(8 << 20, 0x41), { level: 9 }).toString('base64'), payload_encoding: 'gzip+base64', payload_sha256: good }, 'admin_rejected'],
    ['unsupported encoding', { payload: b64, payload_encoding: 'brotli', payload_sha256: good }, 'bad_argument'],
    ['encoding named, no payload', { payload_encoding: 'gzip+base64' }, 'upload_missing'],
    ['no payload at all', {}, 'upload_missing'],
    ['empty payload', { payload: '{"fields":{},"faq":null}', payload_sha256: `sha256:${createHash('sha256').update('{"fields":{},"faq":null}').digest('hex')}` }, 'bad_argument'],
  ];
  let bad = 0;
  for (const [name, extra, want] of cases) {
    const s = un(await c.call('start_push', { ...TARGET, version_hash: p.version_hash }));
    let got;
    try { const r = un(await c.call('finish_push', { ticket: s.ticket, ...extra })); got = r.ok ? 'ACCEPTED' : r.error; }
    catch (e) { got = e.code || 'THREW'; }
    const ok = got === want;
    if (!ok) bad += 1;
    console.log(`${ok ? 'ok  ' : 'BAD '} ${name.padEnd(34)} want ${want.padEnd(15)} got ${got}`);
  }
  console.log(bad ? `\n${bad} wrong code(s) — each one sends the caller somewhere useless.` : '\nAll codes correct.');
} else if (cmd === 'compressed') {
  const c = client(MCP, token());
  const p = un(await c.call('open_page', TARGET));
  const s = un(await c.call('start_push', { ...TARGET, version_hash: p.version_hash }));
  const cap = s.limits?.relay_max_chars ?? 150000;
  const body = p.fields.content ?? p.fields.description ?? '';
  let content = body;
  while (JSON.stringify({ fields: { content } }).length <= cap) content += `${body}\n\n<p>pad</p>\n\n`;
  const text = JSON.stringify({ fields: { content } });
  const bytes = Buffer.from(text, 'utf8');
  const wire = gzipSync(bytes, { level: 9 }).toString('base64');
  console.log(`identity ${text.length} > cap ${cap}; gzip+base64 ${wire.length} (${(text.length / wire.length).toFixed(2)}x)`);
  const r = un(await c.call('finish_push', {
    ticket: s.ticket, payload: wire, payload_encoding: 'gzip+base64',
    payload_sha256: `sha256:${createHash('sha256').update(bytes).digest('hex')}`,
  }));
  console.log(r.ok ? `WROTE draft — ${r.admin_draft_url}` : `REFUSED ${r.error}: ${r.detail ?? ''}`);
  if (r.ok) {
    const n = sql(`DELETE FROM translations WHERE type='${TARGET.type}' AND orm_id=${TARGET.id} AND locale_id='${TARGET.locale}' AND draft=1; SELECT ROW_COUNT();`);
    console.log(`cleaned up ${n} draft row(s)`);
  }
} else if (cmd === 'drafts') {
  console.log('draft=1 total              ', sql('SELECT COUNT(*) FROM translations WHERE draft=1'));
  console.log('draft=1 dated today        ', sql('SELECT COUNT(*) FROM translations WHERE draft=1 AND updated_time >= CURDATE()'));
  console.log('stale translations_draft   ', sql('SELECT COUNT(*) FROM translations_draft d WHERE NOT EXISTS (SELECT 1 FROM translations t WHERE t.draft=1 AND t.type=d.type AND t.orm_id=d.orm_id AND t.locale_id=d.locale_id)'));
  const published = sql('SELECT COUNT(*) FROM translations WHERE draft=0 AND updated_time >= CURDATE()');
  console.log('draft=0 written today      ', published, Number(published) ? '  <-- SOMETHING PUBLISHED. Investigate.' : '  (correct: nothing published)');
  console.log('\nby target, today:');
  console.log(sql("SELECT CONCAT('  ', type, ' ', orm_id, ' ', locale_id, '  x', COUNT(*)) FROM translations WHERE draft=1 AND updated_time >= CURDATE() GROUP BY type, orm_id, locale_id") || '  (none)');
} else {
  console.log('commands: health | tools | limits | codes | compressed | drafts   (--help in the header)');
  process.exitCode = 2;
}
