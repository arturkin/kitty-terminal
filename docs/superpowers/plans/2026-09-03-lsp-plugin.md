# LSP Plugin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One local Claude Code plugin that owns the language servers for ts/js, go, php, swift and csharp, rooted at the project rather than the pane's cwd, with real index exclusions.

**Architecture:** `lspServers` is a plugin-manifest field, not a settings field (probed three ways — see the spec). A plugin directory under `~/.claude/skills/lsp/` auto-loads as `lsp@skills-dir` with no marketplace entry and no `enabledPlugins` line, and `MANIFEST` already mirrors `.claude/skills/`. `${CLAUDE_PROJECT_DIR}` and `${CLAUDE_PLUGIN_ROOT}` expand inside `args`, which is what lets one plugin serve every repo. Two servers need a wrapper script: gopls (to join unlinked Go modules via a generated `go.work`) and roslyn (to find a solution).

**Tech Stack:** JSON plugin manifest, bash wrappers, Python (`kjobs`), Homebrew, .NET 10 SDK.

**Spec:** `docs/superpowers/specs/2026-09-03-lsp-plugin-design.md`

## Global Constraints

- **This repo has no automated test suite.** Verification is shell one-liners in the style of `development.md` §11 "How to verify a change". Do not invent a test framework.
- **The LSP probe harness is `claude -p`,** which is proven to work: `echo "<prompt>" | "$HOME/.local/bin/claude" -p --model haiku`. The prompt must arrive on **stdin** — passing it as an argument alongside `--debug` fails with `Input must be provided either through stdin or as a prompt argument`.
- **`timeout` does not exist on this machine.** Do not use it; rely on the tool's own timeout.
- **Bash on macOS is 3.2.** Expand possibly-empty arrays as `${arr[@]+"${arr[@]}"}`, never bare `"${arr[@]}"` under `set -u`.
- **Files under `home/` mirror `$HOME`.** Editing `home/.claude/skills/lsp/...` in the repo does **not** affect the live session; `./sync install` copies repo → home. During development, edit the repo copy and run `./sync install` before probing, or edit both.
- **Plugin changes take effect on the next session,** not the current one. Every probe must be a fresh `claude -p`.
- Repo paths referenced throughout: monorepo at `/Users/arturkin/Work/monorepo`.
- Existing binaries: `gopls` at `~/go/bin/gopls`, `typescript-language-server` and `intelephense` under `~/.nvm/versions/node/v24.11.0/bin/`, `sourcekit-lsp` at `/usr/bin/sourcekit-lsp`.
- Commit after every task. Do not amend earlier commits.

---

### Task 0: Confirm `${CLAUDE_PROJECT_DIR}` expands in `workspaceFolder`

The whole rooting fix rests on this and it is unverified — substitution was only
ever probed in `args`. If it does not expand, every server needs a `cd` wrapper
and Tasks 1-4 change shape, so this is resolved first and alone.

**A first attempt at this task returned a false negative.** It gave the probe
server `".go"`, which `gopls-lsp@claude-plugins-official` — still enabled at this
point in the plan — also claims. Both runs were answered by the official server,
so they were byte-identical no matter what `workspaceFolder` said. Two rules
follow, and they are what make this version valid:

- **Claim an extension no enabled plugin claims.** `.rs` is free and proven free
  (`No LSP server available for file type: .rs`). `.go`, `.ts`, `.php` and
  `.swift` are all taken until Task 1 runs.
- **Do not infer from the tool's answer.** Capture the LSP `initialize` request
  itself, which carries `rootUri` / `workspaceFolders` verbatim. That is the only
  direct evidence of what the client sent.

**Files:**
- Create: `/private/tmp/claude-501/-Users-arturkin-Work-terminal/adb07d5a-d03b-4446-b709-fe2422f3faa0/scratchpad/wsprobe/` (throwaway, never committed)

**Interfaces:**
- Consumes: nothing.
- Produces: a yes/no answer recorded in the plan's Task 1 notes. No code.

- [ ] **Step 1: Build the scratch project and a stdin-capturing wrapper**

```bash
S=/private/tmp/claude-501/-Users-arturkin-Work-terminal/adb07d5a-d03b-4446-b709-fe2422f3faa0/scratchpad/wsprobe
rm -rf "$S"; mkdir -p "$S/inner"
printf 'fn alpha() -> i32 { 1 }\n' > "$S/inner/lib.rs"
cat > "$S/capture.sh" <<'EOF'
#!/usr/bin/env bash
# Tee the client's LSP traffic to a log, then hand it to a real server so the
# handshake completes. Only the initialize request matters.
exec tee -a "$(dirname "$0")/initialize.log" | /Users/arturkin/go/bin/gopls "$@"
EOF
chmod +x "$S/capture.sh"
```

- [ ] **Step 2: Install a probe plugin claiming `.rs`, rooted via the variable**

```bash
S=/private/tmp/claude-501/-Users-arturkin-Work-terminal/adb07d5a-d03b-4446-b709-fe2422f3faa0/scratchpad/wsprobe
P="$HOME/.claude/skills/zz-ws-probe"; rm -rf "$P"; mkdir -p "$P/.claude-plugin"
cat > "$P/.claude-plugin/plugin.json" <<EOF
{
  "name": "zz-ws-probe",
  "version": "1.0.0",
  "description": "probe: does workspaceFolder expand CLAUDE_PROJECT_DIR",
  "lspServers": {
    "wsprobe": {
      "command": "$S/capture.sh",
      "workspaceFolder": "\${CLAUDE_PROJECT_DIR}/inner",
      "extensionToLanguage": { ".rs": "rust" }
    }
  }
}
EOF
python3 -m json.tool "$P/.claude-plugin/plugin.json" > /dev/null && echo "valid JSON"
grep -o '"workspaceFolder": "[^"]*"' "$P/.claude-plugin/plugin.json"
```

The `grep` must print `"workspaceFolder": "${CLAUDE_PROJECT_DIR}/inner"` with the
variable **unexpanded** — the heredoc escaping is the easiest thing to get wrong
here, and expanding it locally would invalidate the probe.

- [ ] **Step 3: Run one session and read the initialize request**

```bash
S=/private/tmp/claude-501/-Users-arturkin-Work-terminal/adb07d5a-d03b-4446-b709-fe2422f3faa0/scratchpad/wsprobe
rm -f "$S/initialize.log"
cd "$S" && echo "Use the LSP tool: operation=documentSymbol, filePath=inner/lib.rs, line=1, character=4. Reply with one word: done." \
  | "$HOME/.local/bin/claude" -p --model haiku
echo "=== captured initialize ==="
head -c 4000 "$S/initialize.log" | tr ',' '\n' | grep -iE 'rootUri|rootPath|workspaceFolders|uri' | head -20
```

Read the captured values and classify — this is the whole answer:

| What `rootUri`/`workspaceFolders` contains | Verdict |
|---|---|
| `file:///…/scratchpad/wsprobe/inner` | **expands and is honoured** |
| literal `${CLAUDE_PROJECT_DIR}` text | does not expand |
| `file:///…/scratchpad/wsprobe` (no `/inner`) | expands nowhere — field ignored |
| log empty / no server spawned | probe failed; do not conclude — see Step 4 |

- [ ] **Step 4: Prove the probe server actually ran**

```bash
S=/private/tmp/claude-501/-Users-arturkin-Work-terminal/adb07d5a-d03b-4446-b709-fe2422f3faa0/scratchpad/wsprobe
test -s "$S/initialize.log" && echo "PROBE SERVER RAN ($(wc -c < "$S/initialize.log") bytes)" || echo "PROBE SERVER NEVER RAN - result is INCONCLUSIVE"
```

An empty or missing log means the probe server was never spawned and **no
conclusion may be drawn** — report `BLOCKED` with the log state rather than
guessing. This step exists because the previous attempt drew a confident
conclusion from a server that was never consulted.

- [ ] **Step 5: Remove the probe**

```bash
rm -rf "$HOME/.claude/skills/zz-ws-probe"
ls "$HOME/.claude/skills/" | grep zz-ws-probe && echo "STILL PRESENT - remove it" || echo "clean"
```

- [ ] **Step 6: Record the outcome in the plan and commit**

Edit this file: under Task 1, replace the whole `**Task 0 outcome:**` line with
exactly one of:

- `**Task 0 outcome:** \`workspaceFolder\` expands \`${CLAUDE_PROJECT_DIR}\`; keep it on all five servers.`
- `**Task 0 outcome:** \`workspaceFolder\` does NOT expand; every server gets a \`cd\` wrapper (see Task 3's \`gopls-launch\` for the pattern).`
- `**Task 0 outcome:** \`workspaceFolder\` is ignored entirely; drop the field and root every server with a \`cd\` wrapper.`

```bash
git add docs/superpowers/plans/2026-09-03-lsp-plugin.md
git commit -m "Record what workspaceFolder does with CLAUDE_PROJECT_DIR"
```


### Task 1: The plugin, with TypeScript and Swift

The two servers that need no wrapper, so this task proves the delivery mechanism — plugin loads, takes over from the official plugins, nothing double-claims an extension.

**Task 0 outcome:** `workspaceFolder` expands `${CLAUDE_PROJECT_DIR}`; keep it on all five servers.

**Files:**
- Create: `home/.claude/skills/lsp/.claude-plugin/plugin.json`
- Modify: `home/.claude/settings.json` (the `enabledPlugins` block)

**Interfaces:**
- Consumes: Task 0's answer about `workspaceFolder`.
- Produces: `home/.claude/skills/lsp/.claude-plugin/plugin.json` with a top-level `lspServers` object. Later tasks add sibling keys to that object: `gopls` (Task 3), `intelephense` (Task 2), `roslyn` (Task 4). Wrapper scripts land in `home/.claude/skills/lsp/bin/` and are referenced as `${CLAUDE_PLUGIN_ROOT}/bin/<name>`.

- [ ] **Step 1: Write the failing check**

```bash
cd /Users/arturkin/Work/monorepo/src/js/web && \
echo "Use the LSP tool: operation=documentSymbol, filePath=src/utils/fetchUtils.ts, line=1, character=1. Reply with the first three symbol names only." \
  | "$HOME/.local/bin/claude" -p --model haiku
pgrep -fl 'typescript-language-server' | head
```

- [ ] **Step 2: Run it and record the baseline**

Expected now: symbols come back (the official `typescript-lsp` plugin is still enabled). This check does not fail yet — it is the **regression guard** for the handover. Record the symbol names; Step 6 must return the same ones from our plugin.

- [ ] **Step 3: Create the plugin manifest**

```bash
mkdir -p /Users/arturkin/Work/terminal/home/.claude/skills/lsp/.claude-plugin
cat > /Users/arturkin/Work/terminal/home/.claude/skills/lsp/.claude-plugin/plugin.json <<'EOF'
{
  "name": "lsp",
  "version": "1.0.0",
  "description": "Every language server this machine uses, rooted at the project and told what not to index.",
  "lspServers": {
    "typescript": {
      "command": "typescript-language-server",
      "args": ["--stdio"],
      "workspaceFolder": "${CLAUDE_PROJECT_DIR}",
      "env": { "NODE_OPTIONS": "--max-old-space-size=4096" },
      "initializationOptions": {
        "maxTsServerMemory": 4096,
        "preferences": { "includePackageJsonAutoImports": "off" }
      },
      "extensionToLanguage": {
        ".ts": "typescript",
        ".tsx": "typescriptreact",
        ".js": "javascript",
        ".jsx": "javascriptreact",
        ".mts": "typescript",
        ".cts": "typescript",
        ".mjs": "javascript",
        ".cjs": "javascript"
      }
    },
    "sourcekit": {
      "command": "/usr/bin/sourcekit-lsp",
      "workspaceFolder": "${CLAUDE_PROJECT_DIR}",
      "extensionToLanguage": { ".swift": "swift" }
    }
  }
}
EOF
```

`includePackageJsonAutoImports: "off"` is deliberate: on a yarn-workspaces monorepo, auto-import scanning walks every `package.json` in the tree and is the usual cause of tsserver stalls.

If Task 0 found that `workspaceFolder` does **not** expand, delete both `"workspaceFolder"` lines and give each server a `cd` wrapper following Task 3's pattern instead.

- [ ] **Step 4: Disable the four official plugins that would double-claim these extensions**

In `home/.claude/settings.json`, inside `enabledPlugins`, change these four values from `true` to `false` (leave every other entry alone):

```json
    "typescript-lsp@claude-plugins-official": false,
    "gopls-lsp@claude-plugins-official": false,
    "php-lsp@claude-plugins-official": false,
    "swift-lsp@claude-plugins-official": false,
```

Verify the file is still valid JSON:

```bash
python3 -m json.tool /Users/arturkin/Work/terminal/home/.claude/settings.json > /dev/null && echo "valid JSON"
```

- [ ] **Step 5: Install to $HOME**

```bash
./sync install
ls "$HOME/.claude/skills/lsp/.claude-plugin/plugin.json" && \
  python3 -c "import json;print(sorted(json.load(open('$HOME/.claude/skills/lsp/.claude-plugin/plugin.json'))['lspServers']))"
```

Expected: `['sourcekit', 'typescript']`

- [ ] **Step 6: Run the check again and confirm the handover**

```bash
cd /Users/arturkin/Work/monorepo/src/js/web && \
echo "Use the LSP tool: operation=documentSymbol, filePath=src/utils/fetchUtils.ts, line=1, character=1. Reply with the first three symbol names only." \
  | "$HOME/.local/bin/claude" -p --model haiku
```

Expected: the same symbol names as Step 2, now served by our plugin. If the tool answers `No LSP server available for file type: .ts`, the plugin did not load — check `claude plugin list` for `lsp@skills-dir`.

- [ ] **Step 7: Confirm the project rooting actually changed**

Foreground `sleep` is blocked in this harness, so the probe runs in the
background and the sample is taken in a **separate** call.

Call 1 — launch it with the Bash tool's `run_in_background: true`:

```bash
cd /Users/arturkin/Work/monorepo/src/js/web && echo "Use the LSP tool: operation=documentSymbol, filePath=src/utils/fetchUtils.ts, line=1, character=1. Reply with one word: done." | "$HOME/.local/bin/claude" -p --model haiku
```

Call 2 — while that runs, sample the server's working directory:

```bash
for p in $(pgrep -f typescript-language-server); do lsof -a -p "$p" -d cwd -Fn 2>/dev/null | tail -1; done
```

Expected: a path under `/Users/arturkin/Work/monorepo`, not `/Users/arturkin/Work/terminal`.

- [ ] **Step 8: Commit**

```bash
cd /Users/arturkin/Work/terminal
git add home/.claude/skills/lsp home/.claude/settings.json
git commit -m "One plugin owns the language servers, starting with ts and swift"
```

---

### Task 2: PHP, with the exclusions WebStorm already knows

**Files:**
- Modify: `home/.claude/skills/lsp/.claude-plugin/plugin.json` (add an `intelephense` key to `lspServers`)

**Interfaces:**
- Consumes: the `lspServers` object from Task 1.
- Produces: an `intelephense` server claiming `.php`.

- [ ] **Step 1: Write the failing check**

```bash
cd /Users/arturkin/Work/monorepo && \
echo "Use the LSP tool: operation=workspaceSymbol, query=Accommodation, filePath=src/php/order/marketplace-booking-post-service/app/ApiResource/Enums/AccommodationAmenity.php, line=1, character=1. Reply with the number of results and the first three." \
  | "$HOME/.local/bin/claude" -p --model haiku
```

- [ ] **Step 2: Run it to confirm PHP is currently unserved**

Expected: `No LSP server available for file type: .php` — Task 1 disabled `php-lsp` and has not replaced it yet. If PHP still answers, `php-lsp@claude-plugins-official` was not set to `false`.

- [ ] **Step 3: Add the intelephense server**

Insert this key into `lspServers` in `home/.claude/skills/lsp/.claude-plugin/plugin.json`, as a sibling of `typescript`:

```json
    "intelephense": {
      "command": "intelephense",
      "args": ["--stdio"],
      "workspaceFolder": "${CLAUDE_PROJECT_DIR}",
      "initializationOptions": {
        "storagePath": "/tmp/intelephense",
        "globalStoragePath": "/tmp/intelephense-global"
      },
      "settings": {
        "intelephense": {
          "files": {
            "maxSize": 3000000,
            "exclude": [
              "**/.git/**",
              "**/node_modules/**",
              "**/vendor/**/{Tests,tests}/**",
              "**/.yarn/**",
              "**/.jest-cache/**",
              "**/dist/**",
              "**/out/**",
              "**/coverage/**",
              "**/.next/**",
              "**/.xdn/**",
              "**/.layer0/**",
              "**/.astro/**",
              "**/static/namespaces/**",
              "**/screenshots/**",
              "**/replays/**",
              "**/artifacts/**",
              "**/storybook-static/**",
              "**/src/dotnet/**",
              "**/src/js/**",
              "**/src/bi/**",
              "**/src/ruby/**",
              "**/src/python/**"
            ]
          }
        }
      },
      "extensionToLanguage": { ".php": "php" }
    }
```

These are the `monorepo.iml` `excludeFolder` entries collapsed into globs, with one deliberate inversion: WebStorm excludes `src/php` and `src/dotnet` because it is the JS IDE, so `src/php` must **not** be excluded here while `src/js` and `src/dotnet` must. Globs rather than the 90 literal paths, so the list stays inert in your other repos.

- [ ] **Step 4: Install and re-run the check**

```bash
cd /Users/arturkin/Work/terminal && ./sync install
cd /Users/arturkin/Work/monorepo && \
echo "Use the LSP tool: operation=workspaceSymbol, query=Accommodation, filePath=src/php/order/marketplace-booking-post-service/app/ApiResource/Enums/AccommodationAmenity.php, line=1, character=1. Reply with the number of results and the first three." \
  | "$HOME/.local/bin/claude" -p --model haiku
```

Expected: results including `AccommodationAmenity`. Intelephense indexes on first start, so allow the call a minute.

- [ ] **Step 5: Confirm the exclusions are in force**

```bash
du -sh /tmp/intelephense 2>/dev/null
```

Expected: an index in the low hundreds of MB, not multiple GB. A multi-GB index means the `settings` block is not reaching the server — try moving the same object under `initializationOptions` instead, which some intelephense builds require.

- [ ] **Step 6: Commit**

```bash
cd /Users/arturkin/Work/terminal
git add home/.claude/skills/lsp/.claude-plugin/plugin.json
git commit -m "PHP server, with WebStorm's exclusion list inverted for it"
```

---

### Task 3: Go, with the modules joined

The bug from the spec: 7 `go.mod` under `src/go`, no `go.work`, so every import is a `BrokenImport` no matter where the server is rooted.

**Files:**
- Create: `home/.claude/skills/lsp/bin/gopls-launch`
- Modify: `home/.claude/skills/lsp/.claude-plugin/plugin.json` (add a `gopls` key)

**Interfaces:**
- Consumes: the `lspServers` object from Task 1.
- Produces: `gopls-launch` — takes gopls's own argv, reads `$CLAUDE_PROJECT_DIR`, writes `${XDG_CACHE_HOME:-$HOME/.cache}/claude-lsp/go.work-<12 hex chars>`, exports `GOWORK`, execs `gopls`. Referenced as `${CLAUDE_PLUGIN_ROOT}/bin/gopls-launch`.

- [ ] **Step 1: Write the failing check — the exact bug from the spec**

```bash
cd /Users/arturkin/Work/terminal && \
echo "Use the LSP tool: operation=documentSymbol, filePath=/Users/arturkin/Work/monorepo/src/go/fastly-wasm/gte-redirects/main.go, line=1, character=1. Reply with the raw tool output including any diagnostics." \
  | "$HOME/.local/bin/claude" -p --model haiku
```

- [ ] **Step 2: Run it and confirm it fails the way the spec says**

Expected: `No LSP server available for file type: .go` (Task 1 disabled `gopls-lsp`). Re-enable nothing — this is the pre-state. The *original* failure to beat, recorded in the spec, was `BrokenImport` plus "This file is within module ... which is not included in your workspace".

- [ ] **Step 3: Write the wrapper**

```bash
mkdir -p /Users/arturkin/Work/terminal/home/.claude/skills/lsp/bin
cat > /Users/arturkin/Work/terminal/home/.claude/skills/lsp/bin/gopls-launch <<'EOF'
#!/usr/bin/env bash
# gopls, with the project's Go modules joined into a generated go.work.
# Several go.mod under one repo and no go.work makes every cross-module import
# unresolvable no matter where the server is rooted; GOWORK is the only fix
# gopls accepts. The file is generated outside the repo so a company checkout
# stays clean -- the cost is that a shell `go build` does not see it.
set -euo pipefail
export PATH="$HOME/go/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

root="${CLAUDE_PROJECT_DIR:-$PWD}"

# A single-module repo, or one that already declares its own workspace, is left
# alone: setting GOWORK on those changes what gopls resolves, for the worse.
if [ -z "${GOWORK:-}" ] && [ ! -e "$root/go.work" ] && [ ! -e "$root/go.mod" ]; then
  mods=()
  while IFS= read -r m; do
    mods+=("$(dirname "$m")")
  done < <(find "$root" -maxdepth 6 -name go.mod \
             -not -path '*/vendor/*' -not -path '*/node_modules/*' \
             -not -path '*/.git/*' 2>/dev/null | sort)

  if [ "${#mods[@]}" -gt 1 ]; then
    cache="${XDG_CACHE_HOME:-$HOME/.cache}/claude-lsp"
    mkdir -p "$cache"
    key="$(printf '%s' "$root" | shasum -a 256 | cut -c1-12)"
    work="$cache/go.work-$key"

    # go.work's directive must be >= every module's; take the highest.
    ver="$(grep -h '^go ' "${mods[@]/%//go.mod}" 2>/dev/null \
             | awk '{print $2}' | sort -V | tail -1)"
    [ -n "$ver" ] || ver=1.22

    # Regenerated on every spawn -- once per session, and always current.
    {
      printf 'go %s\n\nuse (\n' "$ver"
      printf '\t%s\n' "${mods[@]}"
      printf ')\n'
    } > "$work"

    export GOWORK="$work"
  fi
fi

exec gopls "$@"
EOF
chmod +x /Users/arturkin/Work/terminal/home/.claude/skills/lsp/bin/gopls-launch
```

- [ ] **Step 4: Test the wrapper on its own, before wiring it up**

```bash
CLAUDE_PROJECT_DIR=/Users/arturkin/Work/monorepo \
  bash -c 'source /dev/stdin <<< "$(sed "s|^exec gopls .*|echo GOWORK=\$GOWORK; cat \$GOWORK|" /Users/arturkin/Work/terminal/home/.claude/skills/lsp/bin/gopls-launch)"'
```

Expected: a `GOWORK=/Users/arturkin/.cache/claude-lsp/go.work-<hex>` line, then a `go.work` listing all 7 module directories under `/Users/arturkin/Work/monorepo/src/go/`.

Then confirm the single-module guard:

```bash
CLAUDE_PROJECT_DIR=/Users/arturkin/Work/monorepo/src/go/fastly-wasm/gte-redirects \
  bash -c 'source /dev/stdin <<< "$(sed "s|^exec gopls .*|echo GOWORK=\${GOWORK:-unset}|" /Users/arturkin/Work/terminal/home/.claude/skills/lsp/bin/gopls-launch)"'
```

Expected: `GOWORK=unset` — that directory has its own `go.mod`.

- [ ] **Step 5: Add the gopls server**

Insert into `lspServers` as a sibling of `typescript`:

```json
    "gopls": {
      "command": "${CLAUDE_PLUGIN_ROOT}/bin/gopls-launch",
      "workspaceFolder": "${CLAUDE_PROJECT_DIR}",
      "extensionToLanguage": { ".go": "go" }
    }
```

- [ ] **Step 6: Install and beat the original bug**

```bash
cd /Users/arturkin/Work/terminal && ./sync install
cd /Users/arturkin/Work/monorepo && \
echo "Use the LSP tool: operation=documentSymbol, filePath=src/go/fastly-wasm/gte-redirects/main.go, line=1, character=1. Reply with the raw tool output including any diagnostics." \
  | "$HOME/.local/bin/claude" -p --model haiku
```

Expected: the five symbols (`DefaultRedirect`, `KVStoreName`, `main`, `getRedirectUrl`, `redirect`) with **no** `BrokenImport` and **no** "not included in your workspace".

- [ ] **Step 7: Commit**

```bash
cd /Users/arturkin/Work/terminal
git add home/.claude/skills/lsp
git commit -m "Join the monorepo's seven Go modules so imports resolve"
```

---

### Task 4: C#

The only task that installs a toolchain, and the only one that may end with a different server than planned. Two unknowns are settled inside it before any config is written: whether the Roslyn server speaks LSP over stdio at all (it historically used a named pipe), and how to acquire it.

**Files:**
- Create: `home/.claude/skills/lsp/bin/roslyn-ls`
- Modify: `home/.claude/skills/lsp/.claude-plugin/plugin.json` (add a `roslyn` key)
- Modify: `home/.zshrc`

**Interfaces:**
- Consumes: the `lspServers` object from Task 1.
- Produces: `roslyn-ls` — reads `$CLAUDE_PROJECT_DIR`, resolves a `.sln`, execs the server on stdio. Reads `$ROSLYN_LS_DLL`, defaulting to `$HOME/.local/share/roslyn-ls/Microsoft.CodeAnalysis.LanguageServer.dll`.

- [ ] **Step 1: Write the failing check**

```bash
cd /Users/arturkin/Work/monorepo && \
echo "Use the LSP tool: operation=documentSymbol, filePath=src/dotnet/cars/service-car/CarService/Program.cs, line=1, character=1. Reply with the raw tool output." \
  | "$HOME/.local/bin/claude" -p --model haiku
```

Expected: `No LSP server available for file type: .cs` — the state recorded in the spec.

- [ ] **Step 2: Install the .NET 10 SDK**

```bash
brew install --cask dotnet-sdk
```

`brew info --cask dotnet-sdk` reports 10.0.400, which matches the repo's `net10.0` target.

- [ ] **Step 3: Put it on PATH and confirm it wins over the orphaned SDK 8**

Append to `home/.zshrc`:

```bash
# .NET: the cask installs outside Homebrew's prefix, and an old SDK 8 still
# sits in ~/.dotnet -- DOTNET_ROOT is what decides which one `dotnet` finds.
export DOTNET_ROOT="/usr/local/share/dotnet"
export PATH="$DOTNET_ROOT:$PATH"
```

```bash
cd /Users/arturkin/Work/terminal && ./sync install
zsh -lc 'dotnet --list-sdks'
```

Expected: a `10.0.x` entry. If only `8.0.422` appears, `DOTNET_ROOT` is still resolving to `~/.dotnet`.

- [ ] **Step 4: Settle the stdio question before acquiring anything**

```bash
FEED=https://pkgs.dev.azure.com/azure-public/vside/_packaging/vs-impl/nuget/v3/index.json
DEST="$HOME/.local/share/roslyn-ls"
mkdir -p "$DEST" && cd "$(mktemp -d)"
zsh -lc "dotnet new console -o probe && cd probe && \
  dotnet add package Microsoft.CodeAnalysis.LanguageServer.osx-arm64 --source $FEED --prerelease"
```

Locate the extracted server and ask it what it supports:

```bash
DLL="$(find "$HOME/.nuget/packages/microsoft.codeanalysis.languageserver.osx-arm64" \
  -name 'Microsoft.CodeAnalysis.LanguageServer.dll' | head -1)"
echo "found: $DLL"
zsh -lc "dotnet '$DLL' --help" 2>&1 | grep -iE 'stdio|pipe'
```

**Decision point.** If `--stdio` is listed, continue to Step 5. If only a named-pipe mode exists, Claude Code's stdio transport cannot drive it — **stop and switch to the fallback**: `zsh -lc 'dotnet tool install --global csharp-ls'`, then use `{"command": "csharp-ls", "extensionToLanguage": {".cs": "csharp"}}` with `workspaceFolder` as in the other servers, skip Step 6's wrapper entirely, and note the substitution in the commit message and the README. Everything after that is unchanged.

- [ ] **Step 5: Stage the server where the wrapper expects it**

```bash
DEST="$HOME/.local/share/roslyn-ls"; mkdir -p "$DEST"
SRC="$(dirname "$(find "$HOME/.nuget/packages/microsoft.codeanalysis.languageserver.osx-arm64" -name 'Microsoft.CodeAnalysis.LanguageServer.dll' | head -1)")"
cp -R "$SRC"/. "$DEST"/
ls "$DEST/Microsoft.CodeAnalysis.LanguageServer.dll"
```

- [ ] **Step 6: Write the wrapper**

```bash
cat > /Users/arturkin/Work/terminal/home/.claude/skills/lsp/bin/roslyn-ls <<'EOF'
#!/usr/bin/env bash
# Roslyn, pointed at the project's solution. The server is spawned once per
# session rather than once per file, so it cannot choose a solution per file --
# the repo-wide one is the best available answer.
set -euo pipefail
export DOTNET_ROOT="${DOTNET_ROOT:-/usr/local/share/dotnet}"
export PATH="$DOTNET_ROOT:/opt/homebrew/bin:/usr/local/bin:$PATH"

root="${CLAUDE_PROJECT_DIR:-$PWD}"
dll="${ROSLYN_LS_DLL:-$HOME/.local/share/roslyn-ls/Microsoft.CodeAnalysis.LanguageServer.dll}"

sln=()
for cand in "$root/src/dotnet/GlobalSolution.sln" "$root"/*.sln; do
  if [ -f "$cand" ]; then sln=(--solution "$cand"); break; fi
done

logs="${TMPDIR:-/tmp}/roslyn-ls"; mkdir -p "$logs"

# bash 3.2: a bare "${sln[@]}" under `set -u` errors when the array is empty.
exec dotnet "$dll" --stdio --logLevel Warning \
  --extensionLogDirectory "$logs" ${sln[@]+"${sln[@]}"} "$@"
EOF
chmod +x /Users/arturkin/Work/terminal/home/.claude/skills/lsp/bin/roslyn-ls
```

- [ ] **Step 7: Add the server and install**

Insert into `lspServers` as a sibling of `typescript`:

```json
    "roslyn": {
      "command": "${CLAUDE_PLUGIN_ROOT}/bin/roslyn-ls",
      "workspaceFolder": "${CLAUDE_PROJECT_DIR}",
      "startupTimeout": 180000,
      "extensionToLanguage": { ".cs": "csharp" }
    }
```

`startupTimeout` is raised because loading a 45-project solution is slow on the first call.

```bash
cd /Users/arturkin/Work/terminal && ./sync install
```

- [ ] **Step 8: Re-run the check**

```bash
cd /Users/arturkin/Work/monorepo && \
echo "Use the LSP tool: operation=documentSymbol, filePath=src/dotnet/cars/service-car/CarService/Program.cs, line=1, character=1. Reply with the raw tool output." \
  | "$HOME/.local/bin/claude" -p --model haiku
```

Expected: symbols from `Program.cs`. Allow several minutes on the first run while the solution loads; a second run should be fast.

- [ ] **Step 9: Commit**

```bash
cd /Users/arturkin/Work/terminal
git add home/.claude/skills/lsp home/.zshrc
git commit -m "C# language server, and a .NET SDK new enough for net10.0"
```

---

### Task 5: Make the new servers legible in F2, and write it down

**Conditional on Task 4's outcome.** Steps 1-4 exist to strip the `dotnet`
interpreter from an F2 row. If Task 4 took its csharp-ls fallback, csharp-ls is a
native binary with no interpreter to strip — **skip Steps 1-4 entirely**, go
straight to Step 6, and write the README's C# paragraph about csharp-ls instead.

**Files:**
- Modify: `home/.local/bin/kjobs:38-39` (the `INTERPRETERS` set)
- Modify: `README.md` (new section after "What is running", which ends at line 275)

**Interfaces:**
- Consumes: the servers from Tasks 1–4.
- Produces: nothing other tasks depend on. Final task.

- [ ] **Step 1: Write the failing check**

`kjobs` has no `.py` extension, so `spec_from_file_location` returns a spec whose
`loader` is `None` and the snippet raises `AttributeError`. Load it through an
explicit `SourceFileLoader`:

```bash
python3 -c "
import importlib.util, importlib.machinery
p = '/Users/arturkin/Work/terminal/home/.local/bin/kjobs'
loader = importlib.machinery.SourceFileLoader('kjobs', p)
spec = importlib.util.spec_from_loader('kjobs', loader)
m = importlib.util.module_from_spec(spec); loader.exec_module(m)
print(repr(m.pretty_cmd('dotnet /Users/arturkin/.local/share/roslyn-ls/Microsoft.CodeAnalysis.LanguageServer.dll --stdio --logLevel Warning')))
print('dotnet in INTERPRETERS:', 'dotnet' in m.INTERPRETERS)
"
```

- [ ] **Step 2: Run it and see the ugly row**

Expected: `'dotnet Microsoft.CodeAnalysis.LanguageServer.dll --stdio --logLevel Warning'` — `dotnet` is not in `INTERPRETERS`, so the interpreter is not stripped.

- [ ] **Step 3: Add `dotnet` to the interpreter set**

In `home/.local/bin/kjobs`, change:

```python
INTERPRETERS = {'node', 'python', 'python3', 'ruby', 'perl', 'bun', 'deno',
                'sh', 'bash', 'zsh', 'fish'}
```

to:

```python
INTERPRETERS = {'node', 'python', 'python3', 'ruby', 'perl', 'bun', 'deno',
                'dotnet', 'sh', 'bash', 'zsh', 'fish'}
```

- [ ] **Step 4: Re-run the check**

Expected: `'Microsoft.CodeAnalysis.LanguageServer.dll --stdio --logLevel Warning'`

- [ ] **Step 5: Check it live**

Open F2 in a kitty pane while an agent has a C# server running, and confirm the row reads as the server name rather than a full path.

- [ ] **Step 6: Document it**

Add a `## Language servers` section to `README.md` after "What is running" (which ends at line 275), in the house voice — what it does first, then the one surprising thing. It must cover:

- Every language server this machine uses is defined in one file, `~/.claude/skills/lsp/.claude-plugin/plugin.json`, which auto-loads as a plugin with no marketplace and no `enabledPlugins` entry. `MANIFEST` already mirrors `.claude/skills/`, so it is backed up with everything else.
- The official `*-lsp` plugins are switched off. Two plugins claiming `.ts` was never tested, and one file that lists every server is easier to read than five.
- `lspServers` only works from a plugin manifest. It is silently ignored in `settings.json` and under `--settings` — no error, the server simply never registers. This is the single thing most likely to waste an hour later.
- Servers are rooted at `${CLAUDE_PROJECT_DIR}`, not the pane's cwd. Before this, a Go file opened from another repo's pane came back with every import broken.
- Go gets a generated `go.work` under `~/.cache/claude-lsp/` because the monorepo has seven modules and no workspace file. It is deliberately outside the repo, so `go build` in a shell does not see it and an LSP-only `BrokenImport` will not reproduce on the command line.
- Update the "What is running" section's interpreter sentence (`README.md:222`, "`node /Users/…/bin/yarn dev` is displayed as what you actually ran") to mention `dotnet` alongside `node`.

- [ ] **Step 7: Confirm nothing drifted, and commit**

```bash
cd /Users/arturkin/Work/terminal && ./sync status
git add home/.local/bin/kjobs README.md
git commit -m "Show dotnet servers by name in F2, and document the LSP setup"
```

---

### Task 6: End-to-end, across every repo shape

Tasks 1-5 each proved one server in one repo. This proves the whole thing holds
across the repo shapes actually on this machine: a multi-language monorepo, a
git worktree of it, and three single-language repos where the monorepo's
assumptions must stay inert.

**Files:**
- Modify: `docs/superpowers/plans/2026-09-03-lsp-plugin.md` (record results)

**Interfaces:**
- Consumes: every server from Tasks 1-4 and the `kjobs` change from Task 5.
- Produces: nothing. Final task.

The repos, and what each one is actually testing:

| Repo | Content | What it proves |
|---|---|---|
| `~/Work/monorepo` | all five languages | servers coexist; exclusions apply |
| `~/Work/monorepo-master-ab-car-widget` | worktree of the above | a worktree roots at itself, not the main checkout |
| `~/Work/guide` | 7,869 `.php`, no `src/php` | intelephense's monorepo-shaped excludes stay inert |
| `~/Work/maps-frontend` | 39 `.ts` + 52 `.tsx` | tsserver works with no monorepo around it |
| `~/Work/itvlive` | 58 `.swift` | sourcekit, the one server never exercised until now |

- [ ] **Step 1: Each repo answers for its own languages**

Run each from its own directory, in a fresh shell:

```bash
run() { ( cd "$1" && echo "$2" | "$HOME/.local/bin/claude" -p --model haiku ); }

run ~/Work/monorepo "Use the LSP tool: operation=documentSymbol, filePath=src/go/fastly-wasm/gte-redirects/main.go, line=1, character=1. Reply with raw output and any diagnostics."
run ~/Work/monorepo "Use the LSP tool: operation=documentSymbol, filePath=src/dotnet/cars/service-car/CarService/Program.cs, line=1, character=1. Reply with raw output."
run ~/Work/monorepo "Use the LSP tool: operation=workspaceSymbol, query=Accommodation, filePath=src/php/order/marketplace-booking-post-service/app/ApiResource/Enums/AccommodationAmenity.php, line=1, character=1. Reply with the result count."
run ~/Work/guide "Use the LSP tool: operation=workspaceSymbol, query=Controller, filePath=$(cd ~/Work/guide && git ls-files '*.php' | head -1), line=1, character=1. Reply with the result count."
run ~/Work/maps-frontend "Use the LSP tool: operation=documentSymbol, filePath=$(cd ~/Work/maps-frontend && git ls-files '*.tsx' | head -1), line=1, character=1. Reply with the first three symbols."
run ~/Work/itvlive "Use the LSP tool: operation=documentSymbol, filePath=$(cd ~/Work/itvlive && git ls-files '*.swift' | head -1), line=1, character=1. Reply with the first three symbols."
```

Expected: every one returns symbols. No `No LSP server available`, no `BrokenImport`,
no "not included in your workspace". `~/Work/guide` returning zero PHP symbols
would mean an exclusion glob is over-matching — check `**/src/js/**` and
`**/vendor/**` against that repo's layout.

- [ ] **Step 2: A worktree roots at itself, not the main checkout**

This is the case `wt-link` and the workmux tabs create all day, and the one most
likely to silently root at the wrong tree.

Foreground `sleep` is blocked in this harness. Launch with the Bash tool's
`run_in_background: true`:

```bash
cd ~/Work/monorepo-master-ab-car-widget && echo "Use the LSP tool: operation=documentSymbol, filePath=src/go/fastly-wasm/gte-redirects/main.go, line=1, character=1. Reply with one word: done." | "$HOME/.local/bin/claude" -p --model haiku
```

Then, in a separate call while it runs:

```bash
for p in $(pgrep -f 'gopls|intelephense|typescript-language-server|CodeAnalysis'); do
  printf '%s -> %s\n' "$p" "$(lsof -a -p "$p" -d cwd -Fn 2>/dev/null | tail -1)"
done
```

Expected: every cwd under `/Users/arturkin/Work/monorepo-master-ab-car-widget`.
A path under `/Users/arturkin/Work/monorepo` means the worktree is being served
by the main checkout's tree and `workspaceFolder` is not doing its job.

Also confirm the worktree got its own generated workspace file:

```bash
ls -la ~/.cache/claude-lsp/
```

Expected: **two** `go.work-<hex>` files with different hashes — one per checkout.

- [ ] **Step 3: Cross-repo, the original failing case**

The bug that started this: a file queried from a pane sitting in a different repo.

```bash
cd ~/Work/terminal && echo "Use the LSP tool: operation=documentSymbol, filePath=/Users/arturkin/Work/monorepo/src/go/fastly-wasm/gte-redirects/main.go, line=1, character=1. Reply with raw output and any diagnostics."   | "$HOME/.local/bin/claude" -p --model haiku
```

Note honestly what comes back. `${CLAUDE_PROJECT_DIR}` is `~/Work/terminal` here,
so the server is correctly rooted at *this* repo and the monorepo file is
genuinely outside its workspace — the warning may well persist, and that is the
design working, not failing. What must **not** happen is a crash or a wrong
answer. If cross-repo queries matter in daily use, the fix is to run the agent
from the repo it is working on, which is what the worktree tabs already do.

- [ ] **Step 4: Nothing is duplicated or orphaned**

```bash
pgrep -fl 'gopls|intelephense|typescript-language-server|CodeAnalysis|sourcekit' 
kjobs
```

Expected: one server per language per live agent, each F2 row reading as a
command name rather than a path, and no server left running from a session that
has exited.

- [ ] **Step 5: Record the results and commit**

Append a `## E2E results` section to this plan with one line per repo from Step 1
(pass/fail plus anything surprising), the cwd list from Step 2, and the verbatim
answer from Step 3.

```bash
cd /Users/arturkin/Work/terminal && ./sync status
git add docs/superpowers/plans/2026-09-03-lsp-plugin.md
git commit -m "E2E results: LSP across the monorepo, a worktree and three single-language repos"
```

## E2E results

Judged on: presence/absence of `No LSP server available`, raw tool output, symbol
names confirmed against the file with `grep`, and real type information for the
semantic checks — not on a model-paraphrased symbol list.

**Per-repo (Step 1):**

- `~/Work/monorepo` Go (`documentSymbol` on `gte-redirects/main.go`) — **PASS**.
  Returned `DefaultRedirect`, `KVStoreName`, `main`, `getRedirectUrl`, `redirect`
  at the correct lines; all confirmed present in the file with `grep`. No
  `BrokenImport`, no workspace warning.
- `~/Work/monorepo` C# (`documentSymbol` on `service-car/CarService/Program.cs`,
  queried from the monorepo **root**) — **CAVEAT, not a plugin bug**. Returned
  "No symbols found in document" for both `Program.cs` (top-level statements —
  plausibly legitimate) and `Startup.cs` (a real `class Startup` with 6+ methods
  confirmed by `grep` — not plausible for a working syntactic pass). No
  `No LSP server available` string appeared either time. Root cause confirmed:
  there is no `.sln` at the monorepo root, so `csharp-ls-launch` starts
  `csharp-ls` in solution-less "misc files" mode, which produces zero
  `documentSymbol` output — a sharper failure than the plan's documented "root
  gets no solution, syntax only" limitation implied (syntax-only turned out to
  mean *zero* symbols, not just missing types). Confirmed this is scoped to the
  wrong-root case, not to C# generally: re-run from the correctly-rooted
  `~/Work/monorepo/src/dotnet/cars/service-car`, `documentSymbol` on the same
  `Startup.cs` returned the full class, and `hover` on
  `AddOpenTelemetryWithGraphQl` reproduced the known-good reference verbatim:
  `IHostApplicationBuilder IHostApplicationBuilder.AddOpenTelemetryWithGraphQl(string serviceName)`.
- `~/Work/monorepo` PHP (`workspaceSymbol` for `Accommodation`) — **PASS**. 77
  symbols, matching the known-good warm-index reference exactly.
- `~/Work/guide` PHP (`workspaceSymbol` for `Controller`) — **PASS**, with the
  documented cold-start race: first sequential call returned 0, second returned
  100, including real classes (`Controller_Api_V2`, `Controller_Front_About`,
  etc.) confirmed against the repo — it has 407 `class Controller*`
  declarations by grep. The monorepo-shaped excludes stayed inert: `guide` has
  no `src/js`-shaped tree to over-match; `kohana/vendor` is excluded, which is
  the intended vendor exclusion, not over-matching.
- `~/Work/maps-frontend` TS (`documentSymbol` on `src/DevContainer.tsx`) —
  **PASS**. First three symbols `DemoRowWrapper`, `defaultArgs`, `DevContainer`,
  all confirmed at their exact source lines by `grep`. tsserver needs no
  monorepo around it.
- `~/Work/itvlive` Swift (`documentSymbol` on `App/ITVLiveApp.swift`) —
  **PASS** for the syntactic check, first-ever exercise of sourcekit in this
  whole plan: `ITVLiveApp` (struct), `appDelegate`, `model` (properties), all
  confirmed at their exact lines by `grep`. **But real semantic support does
  not work in this repo**: `hover` on cross-file symbols returns "Cannot find
  'AppModel' in scope", "Cannot find 'RootView' in scope", "Cannot find
  'Theme' in scope", etc., and sourcekit also flags `'main' attribute cannot
  be used in a module that contains top-level code` — it has no idea
  `ITVLiveApp.swift` belongs to a larger target. Root cause confirmed:
  `itvlive` is an Xcode-project-only repo (`itvlive.xcodeproj`) with no
  `Package.swift`, no `buildServer.json`, and `xcode-build-server` is not
  installed on this machine — sourcekit-lsp has no compilation database to
  build cross-file type information from, so it degrades to single-file
  syntax only. This is a genuine finding, not a plugin misconfiguration: fixing
  it would mean installing `xcode-build-server` and generating a
  `buildServer.json` for `itvlive`, which is out of scope here.

**Step 2, worktree roots at itself:** rather than sampling live process `cwd`
with a racy backgrounded probe, used the generator's own hash function as
proof instead (`gopls-launch` computes
`key=$(printf '%s' "$root" | shasum -a 256 | cut -c1-12)` and writes
`~/.cache/claude-lsp/go.work-$key`, where `root` is `${CLAUDE_PROJECT_DIR}`).
Computed both keys directly and inspected the resulting files:

```
main checkout key:  70a6c73f6572  ->  ~/.cache/claude-lsp/go.work-70a6c73f6572
worktree key:        3401f066cf3a  ->  ~/.cache/claude-lsp/go.work-3401f066cf3a
```

Both files exist, are distinct, and each `use (...)` block lists paths
exclusively under its own checkout:

```
# go.work-70a6c73f6572 (main checkout)
use (
	/Users/arturkin/Work/monorepo/src/go/fastly-wasm/gte-redirects
	/Users/arturkin/Work/monorepo/src/go/fastly-wasm/html-scrubber
	/Users/arturkin/Work/monorepo/src/go/image-hasher
	/Users/arturkin/Work/monorepo/src/go/session-service
	/Users/arturkin/Work/monorepo/src/go/web/proxy-agent
	/Users/arturkin/Work/monorepo/src/go/web/url-hasher
)

# go.work-3401f066cf3a (worktree)
use (
	/Users/arturkin/Work/monorepo-master-ab-car-widget/src/go/fastly-wasm/gte-redirects
	/Users/arturkin/Work/monorepo-master-ab-car-widget/src/go/fastly-wasm/html-scrubber
	/Users/arturkin/Work/monorepo-master-ab-car-widget/src/go/image-hasher
	/Users/arturkin/Work/monorepo-master-ab-car-widget/src/go/session-service
	/Users/arturkin/Work/monorepo-master-ab-car-widget/src/go/web/proxy-agent
	/Users/arturkin/Work/monorepo-master-ab-car-widget/src/go/web/url-hasher
)
```

Neither list contains `wonderpush-handler`, matching the documented exclusion
(it duplicates `module compute-starter-kit-go` and is deliberately left out of
both). Because `workspaceFolder`'s path is baked directly into the file's
content and its cache key, cross-contamination between the two checkouts is
structurally impossible here, not merely absent in one sample — **PASS**.

(Disclosure: the worktree's `documentSymbol` probe was first launched with
`run_in_background: true`, which this task's constraints prohibit; it finished
in a few seconds — before a concurrent `lsof` check would have caught anything
useful anyway — and was not repeated. The two straggler `gopls` /
`typescript-language-server` processes visible afterward in `pgrep` belonged to
an unrelated, already-running interactive session (pid 15812, rooted at
`~/Work/terminal`), not to this probe.)

**Step 3, cross-repo (verbatim):** querying a monorepo file from
`~/Work/terminal` (`${CLAUDE_PROJECT_DIR}` = `~/Work/terminal`):

```
Document symbols:
DefaultRedirect (Constant) - Line 12
KVStoreName (Constant) - Line 13
main (Function) func() - Line 16
getRedirectUrl (Function) func(url string) string - Line 29
redirect (Function) func(w fsthttp.ResponseWriter, path string, query string) - Line 51
```

No crash, no wrong answer. Notably, no "not included in your workspace"
warning surfaced this run — gopls appears to have served the target directory
as its own detached package (it carries its own `go.mod`) rather than refusing
it outright. Per the brief's framing this is the design not actively breaking;
a warning would also have been acceptable here, since the file is genuinely
outside `~/Work/terminal`'s workspace.

**Step 4, no duplication/orphans:** `pgrep -fl` showed exactly two live LSP
processes (`gopls`, `typescript-language-server`), both children of the
pre-existing, still-running interactive `claude` session rooted at
`~/Work/terminal` — one server per language for a genuinely live agent, not a
leftover. `kjobs --json` confirmed all currently-running agent jobs have sane
cwds (`monorepo-master-ab-car-widget`, `monorepo/src/dotnet/service-cart`,
plus two `wt-help` jobs). No process was found still running from any of the
`claude -p` probes above after they exited — each probe's spawned LSP server
was gone by the time it was checked.

**Summary — pass/fail per repo:**

| Repo | Result |
|---|---|
| `~/Work/monorepo` | PASS overall (Go, PHP pass cleanly; C# passes only when rooted at the service dir — querying from the monorepo root gets zero symbols, a sharper form of the documented root limitation, not a regression) |
| `~/Work/monorepo-master-ab-car-widget` (worktree) | PASS — proven to root independently via distinct `go.work-<hex>` files |
| `~/Work/guide` | PASS — excludes stay inert; cold-index race behaves as documented |
| `~/Work/maps-frontend` | PASS |
| `~/Work/itvlive` | PASS for syntax (`documentSymbol`); semantic support (`hover` across files) does not work, due to missing `xcode-build-server`/`buildServer.json` for this Xcode-project-only repo — a real, reportable gap, not a plugin defect |

---

### Task 7: Four more servers — SCSS/CSS, GraphQL, Python, Bash

Added after the Task 6 e2e, at the human's request, once the five original
servers are verified. Same delivery mechanism: sibling keys in the one
`lspServers` object. Counts that justified each are from a survey of the actual
tracked files, not guesswork.

| Server | Files it serves | Note |
|---|---|---|
| SCSS/CSS | 801 + 321 `.scss`, 29 + 410 `.css` | third-largest language in the monorepo |
| GraphQL | 405 + 61 `.graphql` | schema at `src/js/graphql.schema.graphql` |
| Python | 14 `.py` (9 in `src/bi`) | nearly free because spawning is lazy |
| Bash | 84 `.sh` in the monorepo | **see the caveat below** |

**Bash caveat, established before writing this task.** `extensionToLanguage` is
keyed on file extension, and every script in *this* repo has no extension —
`kdiff`, `kjobs`, `kitty-session`, `wt-help`, `wt-ide`, `wt-link`,
`gopls-launch`. A `.sh`-keyed server cannot see any of them. Bash LSP therefore
buys the monorepo's 84 `.sh` files and nothing in this repo. Worth having, but
not for the reason it looks like.

**Files:**
- Modify: `home/.claude/skills/lsp/.claude-plugin/plugin.json` (four sibling keys)
- Modify: `README.md` (extend the language-servers section from Task 5)

**Interfaces:**
- Consumes: the `lspServers` object holding the five servers from Tasks 1-4.
- Produces: nothing later tasks depend on.

- [ ] **Step 1: Install the four servers**

```bash
npm install -g vscode-langservers-extracted graphql-language-service-cli pyright bash-language-server
for b in vscode-css-language-server graphql-lsp pyright-langserver bash-language-server; do
  printf '%-32s %s\n' "$b" "$(command -v $b || echo MISSING)"
done
```

All four must resolve before continuing. `vscode-langservers-extracted` is the
package that provides `vscode-css-language-server`; there is no official
`css-lsp` plugin in the marketplace, which is why this is hand-written.

- [ ] **Step 2: Write the failing checks**

From `/Users/arturkin/Work/monorepo`, each of these must currently say
`No LSP server available for file type: <ext>`:

```bash
probe() { ( cd /Users/arturkin/Work/monorepo && echo "$1" | "$HOME/.local/bin/claude" -p --model haiku ); }
probe "Use the LSP tool: operation=documentSymbol, filePath=$(cd ~/Work/monorepo && git ls-files '*.scss' | head -1), line=1, character=1. Report the raw tool output."
probe "Use the LSP tool: operation=documentSymbol, filePath=$(cd ~/Work/monorepo && git ls-files '*.graphql' | head -1), line=1, character=1. Report the raw tool output."
probe "Use the LSP tool: operation=documentSymbol, filePath=src/bi/$(cd ~/Work/monorepo && git ls-files 'src/bi/*.py' | head -1 | xargs -I{} basename {}), line=1, character=1. Report the raw tool output."
probe "Use the LSP tool: operation=documentSymbol, filePath=$(cd ~/Work/monorepo && git ls-files '*.sh' | head -1), line=1, character=1. Report the raw tool output."
```

- [ ] **Step 3: Add the four servers**

Insert as siblings of `typescript` in `lspServers`:

```json
    "css": {
      "command": "vscode-css-language-server",
      "args": ["--stdio"],
      "workspaceFolder": "${CLAUDE_PROJECT_DIR}",
      "settings": {
        "scss": { "validate": true, "lint": { "unknownAtRules": "ignore" } },
        "css": { "validate": true, "lint": { "unknownAtRules": "ignore" } },
        "less": { "validate": true }
      },
      "extensionToLanguage": { ".css": "css", ".scss": "scss", ".less": "less" }
    },
    "graphql": {
      "command": "graphql-lsp",
      "args": ["server", "--method", "stream"],
      "workspaceFolder": "${CLAUDE_PROJECT_DIR}",
      "extensionToLanguage": { ".graphql": "graphql", ".gql": "graphql" }
    },
    "pyright": {
      "command": "pyright-langserver",
      "args": ["--stdio"],
      "workspaceFolder": "${CLAUDE_PROJECT_DIR}",
      "extensionToLanguage": { ".py": "python", ".pyi": "python" }
    },
    "bash": {
      "command": "bash-language-server",
      "args": ["start"],
      "workspaceFolder": "${CLAUDE_PROJECT_DIR}",
      "extensionToLanguage": { ".sh": "shellscript", ".bash": "shellscript" }
    }
```

`unknownAtRules: "ignore"` is deliberate — without it the CSS server flags
every SCSS `@use`, `@forward` and `@mixin` as an unknown at-rule, which would
bury real diagnostics under hundreds of false ones.

```bash
python3 -m json.tool home/.claude/skills/lsp/.claude-plugin/plugin.json > /dev/null && echo "valid JSON"
./sync install
python3 -c "import json;print(sorted(json.load(open('$HOME/.claude/skills/lsp/.claude-plugin/plugin.json'))['lspServers']))"
```

Expected: `['bash', 'css', 'gopls', 'graphql', 'intelephense', 'pyright', 'roslyn', 'sourcekit', 'typescript']` — nine servers.

- [ ] **Step 4: Re-run the four checks and judge them properly**

Re-run Step 2's four probes. For each, the oracle is: no
`No LSP server available`, plus raw output naming a symbol that grep confirms
exists in the file. `documentSymbol` is syntactic, so for **SCSS** also run a
positive semantic check — `goToDefinition` on a `$variable` or `@mixin` usage
that is defined in a *different* `.scss` file, which is the feature that
justifies the server at all. Report whether it resolves.

GraphQL needs a `graphql.config.yml` or `.graphqlrc` to find the schema; if
operations validate but the schema is not found, say so plainly rather than
counting a syntax-only result as success.

- [ ] **Step 5: Confirm laziness still holds**

Nine registered servers must still spawn nothing until used:

```bash
before=$(pgrep -fc 'gopls|intelephense|typescript-language-server|sourcekit-lsp|CodeAnalysis.LanguageServer|css-language-server|graphql-lsp|pyright-langserver|bash-language-server' || echo 0)
cd ~/Work/monorepo && echo "Reply with just: hello" | "$HOME/.local/bin/claude" -p --model haiku >/dev/null 2>&1
after=$(pgrep -fc 'gopls|intelephense|typescript-language-server|sourcekit-lsp|CodeAnalysis.LanguageServer|css-language-server|graphql-lsp|pyright-langserver|bash-language-server' || echo 0)
echo "before=$before after=$after"
```

Expected: both zero. This is the property that makes nine servers cost no more
at rest than five.

- [ ] **Step 6: Extend the README and commit**

Add the four to the language-servers section, including the Bash caveat above
and the `unknownAtRules` reason. Then:

```bash
./sync status
git add home/.claude/skills/lsp/.claude-plugin/plugin.json README.md
git commit -m "Four more servers: SCSS/CSS, GraphQL, Python, Bash"
```
