# Cutting Claude Code token use without losing quality

A runbook for reducing what a Claude Code session spends, while keeping output
quality and improving the security posture. Written to be executed top to bottom
by a person or an agent, on macOS, Linux or Windows.

Every step is reversible and independent — skip any of them.

**Measured on one real setup:** removing unused MCP connectors dropped **318
tool names** (~4K tokens) from the system prompt of every session. Everything
else is smaller, and one commonly-recommended change saves nothing at all. The
honest accounting is at the end.

---

## Before you start

Claude Code ≥ 2.1. All settings below live in `~/.claude/settings.json`, which
is the same path on every platform. Create it as `{}` if absent.

**Record a baseline.** In a fresh session run `/context` and write down the
total and the `MCP tools` line. Without it you cannot tell whether any of this
worked. It takes ten seconds and is the single most skipped step.

---

## Step 1 — Detach MCP servers you do not use

**This is the largest saving, by a wide margin.**

Every attached MCP server advertises itself in the system prompt of *every*
session, whether or not you use it. Tool *schemas* are deferred in recent
versions, but tool **names** are not, and neither are per-server instruction
blocks. A single large connector can contribute 100+ names.

Check what is attached:

```bash
claude mcp list
```

Servers reporting `Needs authentication` are pure overhead — they cost context
and return nothing.

### Option A — detach all hosted connectors (biggest win)

```json
{ "disableClaudeAiConnectors": true }
```

This is **absolute**: `enabledMcpServers` does not re-admit individual
connectors past it. All or nothing. It takes effect without a restart.

Hosted connectors remain available in the web app; this only detaches them from
the CLI.

### Option B — detach individually

```json
{ "disabledMcpServers": ["<name>", "<name>"] }
```

Names must match `claude mcp list` output exactly, including any prefix. Use
this, not `claude mcp remove` — hosted connectors are account-scoped and
removing one can detach it from the account entirely.

### Keeping one or two past Option A

Re-add them as ordinary local HTTP servers rather than hosted connectors:

```bash
claude mcp add --transport http --scope user <name> https://<host>/mcp
claude mcp login <name>          # interactive OAuth, once per machine
```

This is better than the connector route in two ways: local servers live in your
MCP config, so they travel with your dotfiles, and a connector added to the
account later stays detached by default instead of silently appearing in every
session.

> **Verify:** `/context` in a fresh session. The `MCP tools` line is the number
> that should have moved.

---

## Step 2 — Lower the default effort level

```json
{
  "effortLevel": "medium",
  "modelSettings": { "<your-model-id>": { "effortLevel": "medium" } }
}
```

Keep your usual model. Effort is a bigger lever than model choice and a much
smaller quality risk: high effort spends reasoning tokens on turns that do not
need them.

Low risk for edits, debugging with a clear repro, refactors and small-diff
review. Raise it with `/effort high` at the start of a session involving race
conditions, architectural design, or many interacting constraints.

This is probably the **largest real saving on your limits**, and `/context` will
never show it — it is reasoning tokens per turn, not context bytes. It shows up
in usage over days.

---

## Step 3 — Terser output

```json
{ "outputStyle": "Concise" }
```

Cuts preamble and narration from responses. Native, so no third-party skill, and
it does not touch reasoning. Prefer this to any "terse output" plugin.

---

## Step 4 — Compress command output with `rtk`

[`rtk`](https://github.com/rtk-ai/rtk) is a single Rust binary that filters
command output before the agent reads it — type-checkers, test runners, linters,
`git`, `gh`, container and cloud CLIs. Apache-2.0, no dependencies. It filters
once per command, so the prompt cache is unaffected.

```bash
brew install rtk                 # macOS / Linux
cargo install --git https://github.com/rtk-ai/rtk
winget install rtk-ai.rtk        # Windows
curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh
```

Then:

```bash
rtk init -g          # registers a PreToolUse hook; writes RTK.md + a CLAUDE.md import
rtk config --create
rtk config | head -1 # prints the active config path -- platform dependent
```

The config path differs per platform (`~/.config/rtk/` on Linux, an
application-support directory on macOS). **Always read it from `rtk config`
rather than assuming.**

Edit that file:

```toml
[telemetry]
enabled = false          # stock rtk may ship a daily anonymous ping

[awareness]
level = "high"           # see below

[hooks]
exclude_commands = [
  "doppler", "op", "vault",          # auth flows: exact output matters
  "env", "printenv",
  "git rebase", "git cherry-pick", "git bisect",  # conflict output must be verbatim
  "git checkout",                     # see the caveat below
  "helm",                             # deploy output
  "kubectl exec", "docker exec",      # interactive
  "psql", "mysql",                    # data correctness
]
```

Belt and braces for telemetry, in `settings.json`:

```json
{ "env": { "RTK_TELEMETRY_DISABLED": "1" } }
```

**Why `awareness = "high"`.** rtk's one real risk is silent truncation. This
level tells the agent about its escape hatches, which is the mitigation:

```
rtk recall <hash>       # full output of something a filter trimmed
RTK_DISABLED=1 <cmd>    # skip the hook for one command
rtk proxy <cmd>         # run unfiltered, still tracked
rtk gain                # what it has actually saved
```

It costs ~245 tokens per session via an `@RTK.md` import into `CLAUDE.md`. Worth
it. If you track dotfiles, `RTK.md` must travel with `CLAUDE.md` or the import
dangles.

**Exclusions target commands where losing detail causes a wrong decision**, not
"secret-bearing" commands. rtk is local and never transmits output, and its
cloud filters actively strip secrets — so excluding those would be backwards.

> ### Caveat worth knowing
>
> rtk's hook returns `permissionDecision: "allow"` for commands it rewrites, so
> those skip the normal permission path. It is mostly careful — it will not
> rewrite `rm -rf`, `kubectl delete` or `docker rm` at all, and withholds the
> auto-allow on `git push` and destructive cloud verbs. But it *does*
> auto-allow `git commit`, `git checkout .` and `gh pr create/close/merge`.
>
> `git checkout .` discards uncommitted work, which is why it is excluded above.
> **If your allowlist is narrow, audit this before enabling rtk.** Verify with:
>
> ```bash
> echo '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}' | rtk hook claude
> ```

---

## Step 5 — Pin subagents to cheaper models

Subagents run in an **isolated context**, so a cheap one does **not** invalidate
the parent session's prompt cache. This is often stated backwards: swapping
models *mid-session* breaks the prefix cache; dispatching a subagent does not.

Create `~/.claude/agents/scout.md`:

```markdown
---
name: scout
description: Read-only code locator. Use for "where is X defined, used, or configured" sweeps across many files when only the answer is needed, not the file contents. Returns paths and line numbers, never file dumps.
model: haiku
tools: Read, Grep, Glob, Bash
---

You locate code. You do not review, refactor, or explain it.

Report as a flat list of `path:line — one-line description`. Quote at most three
lines of code per finding, and only when the line alone is ambiguous. Never
paste a whole file or function body. If you found nothing, say so in one line.
```

And `~/.claude/agents/verifier.md`:

```markdown
---
name: verifier
description: Runs builds, tests, type-checks and linters, and reports only pass/fail plus the failing lines. Use to confirm a change works without pulling full tool output into the main context.
model: haiku
tools: Bash, Read, Grep, Glob
---

You run verification commands and compress the result.

Run exactly the commands you were given. Do not fix anything or edit files.

Report one line per command — the command, PASS or FAIL, and the count — then
for each failure the file, line and actual error message, with stack frames
inside dependencies or the test runner trimmed. Nothing about passing cases
beyond the count.
```

**Definitions alone change nothing.** Many setups instruct the agent not to
delegate unless asked. Add a scoped rule to `CLAUDE.md`:

```markdown
## Delegation
Delegate to the `scout` agent for "where is X defined/used/configured" sweeps
that span 5+ files, when only the conclusion is needed and not the file
contents. Do not delegate a lookup you can answer in one or two reads — a
subagent pays its own system prompt, so delegating a small search costs more
than doing it.
```

**Do not enforce delegation broadly.** A subagent costs its own system prompt
plus its own reads. It only wins when the intermediate output is large and the
conclusion is small. For code *review* specifically, a cheaper model is a
reasonable breadth pass but a poor sole gate on security-sensitive diffs —
subtle correctness bugs are exactly where model strength shows.

---

## Step 6 — Require approval for infrastructure mutations

Not a token saving — a safety net that becomes important once an agent is
running cloud CLIs with your credentials. Skip if you have no cloud access.

Save as `~/.claude/hooks/approve-cloud-mutations.sh` (`chmod +x`), and note it
needs `bash` and `jq` — on Windows, WSL or Git Bash.

```bash
#!/usr/bin/env bash
# PreToolUse guard: cloud and IaC mutations need explicit approval.
# Reads are silent. Unrecognised verbs prompt -- fail closed.
set -uo pipefail

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command? // empty' 2>/dev/null) || exit 0
[ -z "${cmd//[[:space:]]/}" ] && exit 0

ask() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"%s"}}\n' "$1"
  exit 0
}

LOCAL_CTX='(kind-[A-Za-z0-9_.-]+|k3d-[A-Za-z0-9_.-]+|minikube|docker-desktop|docker-for-desktop|rancher-desktop|colima|orbstack)'

names_local_context() {
  printf '%s' "$1" | grep -qiE -- '--(kube-)?context[[:space:]=]+["'"'"']?[A-Za-z0-9_.-]*(prod|live)' && return 1
  printf '%s' "$1" | grep -qE -- "--(kube-)?context[[:space:]=]+[\"']?${LOCAL_CTX}([\"'[:space:]]|$)"
}

segments=$(printf '%s' "$cmd" | sed -E 's/\|\||&&|[;|&]/\n/g')

while IFS= read -r seg; do
  seg="${seg#"${seg%%[![:space:]]*}"}"
  [ -z "$seg" ] && continue

  while :; do
    if   [[ $seg =~ ^[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+ ]]; then seg="${seg#* }"
    elif [[ $seg =~ ^(sudo|command|nohup|time|stdbuf|env)[[:space:]]+ ]];  then seg="${seg#* }"
    else break
    fi
    seg="${seg#"${seg%%[![:space:]]*}"}"
  done

  read -r bin rest <<<"$seg"
  bin="${bin##*/}"; bin="${bin//\"/}"; bin="${bin//\'/}"

  set -f; read -r -a toks <<<"$rest"; set +f
  verbs=$(printf '%s\n' "${toks[@]+"${toks[@]}"}" | tr -d "\"'" | grep -vE '^-|^$' || true)
  has()  { printf '%s\n' "$verbs" | grep -qxE "$1"; }   # exact: gcloud-style separate tokens
  hasp() { printf '%s\n' "$verbs" | grep -qE "^($1)"; } # prefix: aws-style hyphenated verbs

  case "$bin" in
    kubectl|oc)
      names_local_context "$seg" && continue
      has 'rollout' && { has 'status|history' && continue; ask "kubectl rollout changes cluster state"; }
      has 'config'  && { has 'view|current-context|get-contexts|get-clusters' && continue; ask "kubectl config modifies kubeconfig"; }
      has 'get|describe|logs|top|explain|api-resources|api-versions|version|cluster-info|events|diff|auth|wait' && continue
      ask "kubectl mutates cluster state and no local --context was given"
      ;;
    helm)
      names_local_context "$seg" && continue
      has 'repo|plugin|dependency' && { has 'list|ls|update' && continue; ask "helm repo/plugin change is a mutation"; }
      has 'list|ls|get|status|history|show|search|template|lint|version|env|inspect' && continue
      ask "helm mutates a release and no local --kube-context was given"
      ;;
    gcloud)
      has 'create|delete|update|patch|set|deploy|import|restore|enable|disable|ssh|scp|reset|start|stop|resize|add|remove|attach|detach|clone|promote|rollback|migrate|submit|apply|replace|undelete|revoke|grant|move|rename|cancel|abandon|drain|upgrade|install|uninstall|activate|deactivate|bind|unbind|set-iam-policy|add-iam-policy-binding|remove-iam-policy-binding|sign|untag|expire' \
        && ask "cloud mutation -- confirm the project and resource"
      has 'list|describe|get|get-iam-policy|get-value|read|show|check|validate|lookup|search|test-iam-permissions|tail|info|version|help|topic|access' && continue
      ask "unrecognised gcloud verb -- approving explicitly (fail closed)"
      ;;
    aws)
      # aws verbs are hyphenated (describe-instances, get-caller-identity), so
      # these match on prefix, not exact.
      hasp 'create|delete|update|put|run|start|stop|terminate|modify|attach|detach|associate|disassociate|register|deregister|deploy|invoke|copy|restore|reboot|tag|untag|enable|disable|apply|remove|set|add|revoke|authorize|import|publish|send|cancel|reset|rotate|replace|rm|mv|cp|sync' \
        && ask "cloud mutation -- confirm the account and resource"
      hasp 'describe|list|get|search|lookup|scan|head|wait|help|ls|cat|select|validate|check|estimate|preview|test' && continue
      ask "unrecognised aws verb -- approving explicitly (fail closed)"
      ;;
    gsutil)
      has 'ls|cat|stat|du|hash|version|help' && continue
      ask "object storage mutation"
      ;;
    bq)
      has 'query' && ask "bq query can run DML (DELETE/UPDATE/INSERT)"
      has 'ls|show|head|version|help' && continue
      ask "unrecognised bq verb -- approving explicitly (fail closed)"
      ;;
    pulumi)
      has 'stack'  && { has 'ls|output|history|graph' && continue; ask "pulumi stack change"; }
      has 'config' && { has 'get' && continue; ask "pulumi config set is a mutation"; }
      has 'plugin' && { has 'ls' && continue; ask "pulumi plugin change"; }
      has 'preview|about|version|whoami|logs' && continue
      ask "pulumi mutates infrastructure state"
      ;;
    terraform|tofu)
      has 'state'     && { has 'list|show' && continue; ask "terraform state mutation"; }
      has 'workspace' && { has 'list|show' && continue; ask "terraform workspace change"; }
      has 'plan|show|validate|output|providers|version|graph|console' && continue
      ask "terraform mutates infrastructure"
      ;;
  esac
done <<<"$segments"

exit 0
```

Register it, **before** any rtk hook — rtk rewrites the command, and an approval
prompt must be decided on what was actually typed:

```json
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash",
        "hooks": [{ "type": "command",
                    "command": "$HOME/.claude/hooks/approve-cloud-mutations.sh",
                    "statusMessage": "Checking for cloud/IaC mutations..." }] },
      { "matcher": "Bash",
        "hooks": [{ "type": "command", "command": "rtk hook claude" }] }
    ]
  }
}
```

### Design notes

- **Fail closed.** An unrecognised verb prompts rather than runs. A new
  subcommand nobody taught the hook about is a confirmation, not a surprise
  mutation. The inverse — a verb wrongly classified as a *read* — does not fail
  closed, so add a test alongside any fix.
- **The binary cannot be hidden.** The command is split on `&&`, `||`, `;` and
  `|` first, then env assignments, wrappers and absolute paths are peeled off.
  `ls && helm uninstall x` prompts.
- **Local clusters must be named explicitly.** The exemption requires
  `--context kind-*|minikube|docker-desktop|…` on the command. It deliberately
  does **not** consult `kubectl config current-context`: a command with no
  `--context` inherits whatever is active, and a forgotten context switch is
  exactly how a production mutation gets waved through. Any context naming
  `prod` or `live` never qualifies.
- **Bash only.** MCP tool calls bypass this entirely. If you use MCP servers
  that can write, add a second hook with matcher `^mcp__`.
- **Reads that return secrets are not covered.** Commands like
  `kubectl get secret -o yaml` or a secret-manager `access` call are read verbs
  that print credentials. Move them out of the read lists to close that gap.

### Test it

Two bugs in early versions of this script silently let mutations through, and
both passed a naive "does `kubectl delete` prompt?" check. Test the awkward
cases:

```bash
h() { printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$1" \
      | bash ~/.claude/hooks/approve-cloud-mutations.sh; echo " <- $1"; }

h "kubectl get pods"                    # expect: no output (allowed)
h "kubectl scale deploy api --replicas=0"   # expect: ask   (flag with '=')
h "gcloud sql instances patch db --tier=x"  # expect: ask   (flag with '=')
h "ls && helm uninstall api"                # expect: ask   (second segment)
h "kubectl frobnicate widgets"              # expect: ask   (fail closed)
h "kubectl delete pod x --context kind-dev" # expect: no output (local)
h "kubectl delete pod x --context kind-prod"# expect: ask   (prod tripwire)
```

The `--flag=value` cases are the important ones: a glob-based env-assignment
check treats *any* command containing `=` as an assignment and strips its binary.

Two further notes from running this in anger:

- **Put the tests in a file and run the file.** The guard matches on command
  text, so a test harness that inlines `aws s3 rm …` as an argument will trip
  the guard on itself. Inside a script file the verbs never reach the command
  line.
- **`aws` verbs are hyphenated** (`describe-instances`, `get-caller-identity`),
  unlike `gcloud`, which splits them into separate tokens. That is why the `aws`
  branch matches on prefix and the others match exactly. Get this wrong and
  every `aws` command prompts via fail-closed — safe, but useless enough that
  people disable the hook.

---

## Step 7 — Prune the permission allowlist

Allowlists accumulate one-off entries from finished work — pinned paths, literal
`echo` strings, and occasionally a `rm -rf` grant that outlived its task.

Review `permissions.allow` and delete anything referencing a path that no longer
exists, a one-shot command, or a tool name that has since been renamed. Replace
clusters of pinned invocations with one `:*` form.

**This saves no tokens** — permission rules never enter the context window. It is
a security and hygiene fix. Worth doing; do not count it as budget.

---

## Verification

1. **Settings parse:** `python3 -c "import json;json.load(open('$HOME/.claude/settings.json'))"`
2. **`/context`** in a fresh session, compared against your baseline.
3. **Existing guards still fire.** If you had a hook denying credential reads,
   confirm it still triggers after adding rtk — rtk rewrites commands, so verify
   rather than assume. A `deny` decision correctly beats a later `allow`.
4. **`rtk gain`** shows a non-zero saving after a few commands.
5. **Subagents are pinned** — dispatch one and confirm which model ran.
6. **Cloud hook** — run the test block in Step 6.

## Rollback

Each step is one settings key, one file, or one package. Remove the key, delete
the file, or `brew uninstall rtk` and drop its hook entry.

---

## Tools evaluated and rejected

A widely-circulated optimisation guide recommends the following. Each was
checked against the live registries; most do not survive.

| Proposed | Finding |
|---|---|
| `@ooples/token-optimizer-mcp` | The CVE IDs usually cited for it (`CVE-2026-55157`, `CVE-2026-55156`) **do not exist** — MITRE returns `CVE_RECORD_DNE`. A real advisory does: **GHSA-49mq-fc6q-3h46**, HIGH, OS command injection, fixed in 5.1.0. Interpolating unsanitised input into a shell inside an MCP server is disqualifying regardless of the patch. |
| `code-review-graph` | The stated rationale — a vulnerable `fastmcp <2.14.0` — is false; it requires `fastmcp>=3.2.4,<4`, so the prescribed "fix" is a no-op. Redundant anyway if you have LSP tooling, which gives the same structural map with no new dependency. |
| `claude-token-optimizer` | Real, but very low adoption, and it installs hooks that read every user prompt and inject files by filename match. Large blast radius for a small saving. |
| "Caveman"-style terse-output skills | Superseded by native `outputStyle: "Concise"`, without the reasoning degradation these warn about at their higher tiers. |
| Artifact-first "thinking suppression" protocols | Fight native model behaviour and are premised on older model generations. |
| Budget-model orchestrators | Correct that swapping models *mid-session* destroys the prefix cache — but this is routinely over-generalised into "never use a cheaper model", which is wrong for subagents. See Step 5. |

`rtk` is frequently rejected in the same guides on fabricated grounds. It is the
one item from that list worth having.

**General rule:** anything that installs a hook reading every prompt, or an MCP
server shelling out, gets checked against OSV and MITRE and its download counts
before installation. Verify CVE IDs — fabricated ones are common in
AI-generated security write-ups, and a real advisory sitting next to a fake CVE
number is a strong signal the rest of the document is unreliable.

---

## Honest accounting

| Change | Saving |
|---|---|
| Detaching unused MCP servers | **Largest and the only easily measured one.** 318 tool names / ~4K tokens per session in one real setup |
| Lower effort level | Probably the largest saving on your *limits*, and **invisible to `/context`** — reasoning tokens per turn, not context bytes |
| `rtk` | ~30% of command output in practice. Command output is one contributor to input tokens, not the bill |
| Concise output style | Output tokens per turn. Modest, real |
| `RTK.md` import | **−245 tokens per session (a cost)** |
| Allowlist pruning | **Zero.** Security hygiene, not budget |
| Cloud approval hook | **Zero.** Safety, not budget |

Two of the seven steps save no tokens at all. They are included because they are
worth doing, not because they help the number — and a guide that claimed
otherwise would be the same genre as the one debunked above.

Percentages quoted by any of these tools describe *their own* slice — compressed
command output, or names removed from a prompt — not your bill, which also
counts output tokens and is discounted heavily on cache reads. `/context` before
and after is the only measurement that answers the question you actually care
about.
