# Token budget

Claude Code limits got cut. This is what this repo does about it, and what it
deliberately refused to install. Everything here travels with `./sync install`
plus `brew bundle` — nothing needs re-running on a second machine.

## What changed

| Change | Where | Effect |
|---|---|---|
| Effort `high` → `medium` | `.claude/settings.json`, top level and `modelSettings.claude-opus-5` | Still Opus everywhere. High effort spends thinking tokens on turns that do not need them; raise it per session with `/effort high`. |
| `outputStyle: "Concise"` | `.claude/settings.json` | Cuts preamble and narration from responses. Native, so no third-party skill and no effect on reasoning. |
| All claude.ai connectors off | `.claude/settings.json`, `disableClaudeAiConnectors` | Every attached MCP server advertises itself in the system prompt of *every* session whether or not you use it. **Measured: 318 tool names, ~4K tokens.** Sentry and Content Studio were re-added as local servers. |
| `rtk` | `Brewfile`, hook in `.claude/settings.json`, `Library/Application Support/rtk/config.toml` | Compresses bash output before it reaches context. |
| 3 pinned subagents | `.claude/agents/` | `scout` and `verifier` on Haiku, `reviewer` on Sonnet. Subagents run in an isolated context, so a cheap one does **not** invalidate the main session's prompt cache. |
| Allowlist 81 → 47 | `.claude/settings.json`, `permissions.allow` | Dropped finished one-offs, two stale MCP tool names, and two `rm -rf /tmp/...` grants. |

### Measuring it

`/context` is the only honest scoreboard — it breaks out `MCP tools` as its own
line. Record it before and after any change here.

The connector change is the one measured number: **318 tool names removed**,
roughly 4K tokens per session. Everything else is either unmeasured or not a
context saving at all:

- **Effort `high` → `medium`** is probably the largest real saving on your
  limits, and `/context` will never show it — it is thinking tokens per turn,
  not context bytes. It shows up in usage over days.
- **`outputStyle: "Concise"`** cuts output tokens per turn. Same story.
- **The allowlist prune saves nothing.** Permission rules never enter context.
  It was a security fix (two `rm -rf` grants removed), not a budget one.
- **`rtk`** is measured continuously by `rtk gain`, but it compresses bash
  output only — one contributor to input tokens, not the bill.
- **RTK.md costs ~245 tokens a session**, imported into `CLAUDE.md`.

## The connectors

`"disableClaudeAiConnectors": true` switches off **every** claude.ai connector
in Claude Code. They stay live in claude.ai on the web; this only detaches them
from the terminal.

**Measured: 318 tool names left the system prompt** the moment it took effect —
Ahrefs 135, Slite 40, Asana 39, Figma 38, Google Drive 11, Calendar 9, Sentry 9,
Content Studio 6, and 2 apiece for the fourteen that only ever offered
`authenticate`. At roughly 12 tokens a name that is ~4K tokens per session,
before their instruction blocks.

The flag is **absolute**. `enabledMcpServers` does not re-admit individual
connectors past it — tested, not assumed. It is all or nothing.

So the two connectors worth keeping were **re-added as ordinary local HTTP
servers** instead:

```
sentry                  https://mcp.sentry.dev/mcp
content-studio-staging  https://admin.staging.guidetoiceland.is/mcp
```

That costs 15 tool names back instead of 318, and it is strictly better than the
connector route in two ways: local servers live in `mcp-servers.json`, so they
travel with this repo (account connectors never did), and a connector added to
the account later stays blocked by default rather than silently appearing in
every session.

They need OAuth once per machine — `install` prints the `claude mcp add-json`
lines, then:

```bash
claude mcp login sentry
claude mcp login content-studio-staging
```

`disabledMcpServers` still lists the fourteen dead ones. That is redundant while
the flag is true, and deliberately kept: flip the flag back and they stay off.

Local servers are unaffected throughout: `webstorm`, `chrome-devtools`,
`phpstorm`. `phpstorm` reporting `ConnectionRefused` is normal — it only listens
while PhpStorm is open, and the `ide` skill launches it.

## rtk

A single Rust binary that filters command output before the agent reads it —
`tsc`, `eslint`, `jest`, `go test`, `pytest`, `phpt`, `git`, `gh`, `kubectl`,
`docker`, `pulumi`, `aws`. It filters once per command, so the prompt cache is
unaffected.

A `PreToolUse` hook rewrites `git status` into `rtk git status` transparently.
It is registered **last**, after the git-push confirmation and
`deny-sensitive-files.sh`, so both guards evaluate before any rewrite.

**Escape hatches** — the config sets `awareness.level = "high"` specifically so
the agent knows about these. Silent truncation is rtk's one real risk; these are
the answer to it.

```
rtk recall <hash>       # full output of something a filter trimmed
RTK_DISABLED=1 <cmd>    # skip the hook for one command
rtk proxy <cmd>         # run unfiltered, still tracked
rtk gain                # what it has actually saved
```

**`exclude_commands`** targets commands where losing detail causes a *wrong
decision*, not "secret-bearing" commands. rtk is local and never transmits
output, and its `aws` filters actively strip secrets — so `aws` and plain
`kubectl` stay on. Excluded: `doppler`, `op`, `vault` (auth flows), `git
rebase`/`cherry-pick`/`bisect` (conflict output must be verbatim), `helm`
(deploys), `kubectl exec`/`docker exec` (interactive), `psql`/`mysql` (data),
`env`/`printenv`.

### The one sharp edge: rtk asserts `allow`

For commands it rewrites, rtk's hook returns
`"permissionDecision": "allow"` — not just the rewritten command. So those
commands skip the normal permission path.

It is mostly careful about this. `rm -rf`, `npm install`, `kubectl delete`,
`docker rm` are not rewritten at all, and `git push`, `gh repo delete`,
`gh release delete` and `aws s3 rm` are rewritten but *without* the auto-allow,
so they still go through permissions. `deny` also still wins: the
`deny-sensitive-files.sh` guard runs first and blocks `cat ~/.ssh/id_rsa`
even though rtk would rewrite it — verified, not assumed.

It does auto-allow `git commit`, `git checkout .`, `gh pr create/close/merge`.
Given the `Bash(git *)` and `Bash(gh pr *)` entries in `permissions.allow`,
none of that is new — every one was already permitted. `git checkout` is in
`exclude_commands` anyway, because discarding uncommitted work should not be
approved by a third-party heuristic.

**If `Bash(git *)` is ever narrowed, re-check this** — rtk's hook would keep
auto-allowing `git commit` regardless of what the allowlist says.

Telemetry is off in the config, and `RTK_TELEMETRY_DISABLED=1` is set in
`settings.json` as a second layer. (0.49.0 already defaults it off; both stay
pinned in case that changes.)

`rtk init` also writes `.claude/RTK.md` and an `@RTK.md` import into
`CLAUDE.md`. Both are tracked here — without RTK.md the import dangles.

## Rejected, with evidence

A research document proposed a seven-tool stack. Checked against npm, PyPI, OSV,
MITRE and Homebrew, most of it did not hold up. Do not install these.

| Proposed | Finding |
|---|---|
| `@ooples/token-optimizer-mcp` | The cited **CVE-2026-55157 / CVE-2026-55156 do not exist** — MITRE returns `CVE_RECORD_DNE` for both. A real advisory does exist: **GHSA-49mq-fc6q-3h46**, HIGH, OS command injection, fixed in 5.1.0. Shipping unsanitised input into `execAsync` inside an MCP server is disqualifying on its own. 688 downloads/week. |
| `code-review-graph` | The stated rationale is false. It requires **`fastmcp>=3.2.4,<4`**, not the claimed vulnerable `<2.14.0`, so the prescribed fix `pip install "fastmcp>=2.14.0"` is a no-op. Redundant anyway: `ENABLE_LSP_TOOL` is on and CLAUDE.md already mandates LSP-first navigation — the same structural map, no new dependency. |
| `claude-token-optimizer` | Real (v2.3.20) but **76 downloads/week**, and it installs hooks that read every user prompt and inject files by filename match. Too much blast radius for the saving. |
| `JuliusBrussee/caveman` | Superseded by native `outputStyle: "Concise"` — same effect, no third-party skill, and none of the reasoning degradation the research itself warns about at higher tiers. |
| Antigravity Protocol V2.0 | Correctly rejected by the research. Also premised on Opus 4.5 behaviour; this setup runs Opus 5. |
| Kilo Code Orchestrator | Correctly rejected for mid-session model swapping, which does break the prefix cache. But the research over-generalised that into "never use a cheaper model", which is wrong for subagents — hence `.claude/agents/`. |

The research also **wrongly rejected `rtk`** in its final section (while its own
table said retain), citing a fabricated "+7.6% cost" figure. It is the one item
from that list worth having.
