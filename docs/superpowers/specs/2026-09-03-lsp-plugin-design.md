# One plugin that owns every language server

> **Superseded in part — read `../lsp-as-built.md` first.** The C# design
> below (Roslyn, `--solution GlobalSolution.sln`), the Homebrew-cask .NET
> install and the `kjobs` section did not survive contact: that Roslyn build has
> no `--solution` flag, `GlobalSolution.sln` is corrupt (`MSB5023`), the cask
> needs interactive root, and the shipped csharp-ls is a native binary with no
> interpreter to strip. Nine servers shipped, not five.

Claude Code already spawns a language server per agent, lazily, and `kjobs`
already lists it. What it does not do is root that server anywhere useful,
exclude anything from its index, or know what a `.cs` file is. This replaces
five separately-owned server definitions with one local plugin that answers all
three.

## What is there today

`ENABLE_LSP_TOOL` is on and four official plugins are enabled — `typescript-lsp`,
`gopls-lsp`, `php-lsp`, `swift-lsp` — with the binaries installed
(`typescript-language-server`, `gopls`, `intelephense`, `/usr/bin/sourcekit-lsp`).
`README.md:190` documents `intelephense --stdio` appearing under an agent row.
So automatic spawning is not the gap. Four other things are.

### 1. The workspace root is the pane's cwd, not the project

`documentSymbol` on `monorepo/src/go/fastly-wasm/gte-redirects/main.go`, from a
session whose cwd was `~/Work/terminal`, returned symbols along with:

```
This file is within module ".../gte-redirects", which is not included in
your workspace.  [go list]
could not import github.com/fastly/compute-sdk-go/fsthttp
  (cannot find package in GOROOT)  [BrokenImport]
```

`lsof -a -p <gopls> -d cwd` confirmed the cause: gopls's cwd was
`/Users/arturkin/Work/terminal`. One server per agent, rooted wherever the agent
started. Symbols resolve; imports and references do not.

Rooting at the monorepo root would not fix Go on its own — `src/go` holds **7
separate `go.mod` files with no `go.work`**, so the modules are not joined and
the same error appears from the root. The monorepo has no single project root in
any language: no root `tsconfig.json`, 7 `composer.json`, and a 45-project
`src/dotnet/GlobalSolution.sln`.

### 2. No C# at all

`.cs` returns `No LSP server available for file type: .cs`. That is **17,623
files** — the largest language in the repo, against 3,758 TS/TSX, 2,610 PHP and
43 Go. `csharp-lsp` exists in the official marketplace but is not enabled, and
`csharp-ls`, a usable `dotnet`, and Rider are all absent.

There *is* a .NET SDK at `~/.dotnet/dotnet` — **8.0.422**, last touched in July —
but it is not on `PATH` (`.zshrc` adds `~/.local/bin`, `$GOPATH/bin` and
`$BUN_INSTALL/bin`, nothing for dotnet), and the csproj files target `net10.0`
with no `global.json` pin. It is two majors short of the repo regardless.

### 3. Every server runs unconfigured

The marketplace entries are bare `{command, args, extensionToLanguage}` — no
exclusions, no memory cap, no PHP stubs or include paths. Meanwhile
`monorepo/.idea/monorepo.iml` carries ~50 hand-tuned `excludeFolder` entries
(`src/dotnet`, `src/php`, `node_modules`, `.next`, `.yarn`, `dist`,
`.jest-cache`, …). intelephense indexes all of it by default.

### 4. None of it lives in this repo

No LSP config anywhere in `home/`, nothing in `sync`, nothing in the README. A
restored machine gets whatever `npm -g` happens to hold.

## Where the config can go, established by probe

`lspServers` is **not a settings field.** A `.claude/settings.json` in the
project defining a server for `.rs` never registered (`No LSP server available
for file type: .rs`), and neither did the same JSON passed as
`--settings <file>`. The same definition passed via `--plugin-dir` with a
`.claude-plugin/plugin.json` spawned immediately. The binary's
`[lspRecommendation] Skipping string path lspServers (not readable from
marketplace)` agrees: it is a plugin-manifest field.

Two consequences, both probed:

- **A plugin directory under `~/.claude/skills/<name>/` auto-loads** its
  `lspServers` with no marketplace entry and no `enabledPlugins` line, matching
  what `claude plugin init` scaffolds. MANIFEST already mirrors
  `.claude/skills/`, so this needs **no change to `sync` or MANIFEST**. Only
  `.claude-plugin/plugin.json` is required; no `SKILL.md`.
- **`${CLAUDE_PROJECT_DIR}` and `${CLAUDE_PLUGIN_ROOT}` expand inside `args`.**
  The probe server was spawned with `--solution /…/lsptest/some.sln` and
  `--plugroot /Users/arturkin/.claude/skills/zz-lsp-probe`. That is what lets one
  plugin serve every repo without per-repo files — which is just as well, since
  per-repo settings files are not an option.

The full `lspServers` schema, read out of the binary: `command`, `args`,
`extensionToLanguage`, `transport` (`stdio`|`socket`), `env`,
`initializationOptions`, `settings`, `workspaceFolder`, `startupTimeout`,
`shutdownTimeout`, `restartOnCrash`, `maxRestarts`, `diagnostics`.

## Design

### One plugin owns all five servers

`home/.claude/skills/lsp/.claude-plugin/plugin.json` defines ts/js, go, php,
swift and csharp. The four enabled official `*-lsp` plugins are disabled in
`home/.claude/settings.json`, so exactly one definition claims each extension.

This is deliberate: it was never established what two plugins claiming `.go` do
to each other, and owning all five sidesteps the question while putting every
server in one readable file. Swift is folded in for that reason rather than
because Swift needs anything.

### Rooting

`workspaceFolder: "${CLAUDE_PROJECT_DIR}"` on every server, so the root is the
project rather than whichever pane the agent started in.

Go needs the modules joined as well. A wrapper, `bin/gopls-launch`, generates a
`go.work` **under `~/.cache/claude-lsp/`** keyed by project path, exports
`GOWORK` at it, and execs `gopls`. Out-of-repo was chosen over a gitignored
`go.work` at the monorepo root to keep a company repo pristine; the accepted
cost is that gopls and a shell `go build` see different views, so a
`BrokenImport` visible in LSP will not reproduce on the command line.

The wrapper only generates when it finds 2+ `go.mod` files and no root `go.mod`
and no existing `go.work` — setting `GOWORK` on an ordinary single-module repo
would break it. It regenerates when the module list changes.

### Indexing

- **intelephense** — `files.exclude` globs ported from `monorepo.iml`, plus
  `**/node_modules/**`, `**/vendor/**`, `**/.next/**`, `**/dist/**`,
  `**/.yarn/**`, `**/.jest-cache/**`, `**/src/dotnet/**`, and a `maxSize`. Globs,
  so they are inert in repos that lack those paths.
- **typescript** — tsserver resolves the nearest `tsconfig.json` per file
  itself, so no root config is needed; this is a memory cap only
  (`maxTsServerMemory`, plus `NODE_OPTIONS=--max-old-space-size`).
- **roslyn** — `bin/roslyn-ls` passes
  `--solution ${CLAUDE_PROJECT_DIR}/src/dotnet/GlobalSolution.sln` when that path
  exists and starts solution-less otherwise. The server is spawned once per
  session, not once per file, so it cannot pick a solution per opened file.

### The .NET prerequisite

A .NET 10 SDK on `PATH` with `DOTNET_ROOT` set in `.zshrc` (already tracked),
and a pinned `Microsoft.CodeAnalysis.LanguageServer.osx-arm64`. This is the only
step that installs a toolchain and it gates the C# server entirely. The orphaned
SDK 8 at `~/.dotnet` is left alone unless the install upgrades it in place.

### kjobs

Roslyn runs as `dotnet …/Microsoft.CodeAnalysis.LanguageServer.dll`. `kjobs`
already strips interpreters for node and yarn; it needs a `dotnet` case or the
F2 row is a 200-character path. README documents that stripping, so it needs a
line too.

## Files touched

| File | Change |
|---|---|
| `home/.claude/skills/lsp/.claude-plugin/plugin.json` | new — all five `lspServers` |
| `home/.claude/skills/lsp/bin/gopls-launch` | new — `go.work` generation + `GOWORK` |
| `home/.claude/skills/lsp/bin/roslyn-ls` | new — solution resolution |
| `home/.claude/settings.json` | disable the four enabled official `*-lsp` plugins |
| `home/.zshrc` | `DOTNET_ROOT` + `PATH` for the .NET 10 SDK |
| `home/.local/bin/kjobs` | strip `dotnet` the way node and yarn are stripped |
| `README.md` | new LSP section; kjobs interpreter line |

`sync` and `MANIFEST` are untouched — `.claude/skills/`, `.zshrc`,
`.claude/settings.json` and `.local/bin/kjobs` are all already tracked.

## Verification

The reproduction, in reverse:

1. `documentSymbol` and `hover` on
   `monorepo/src/go/fastly-wasm/gte-redirects/main.go` from a session rooted in a
   *different* repo — no `BrokenImport`, no "not included in your workspace".
2. `documentSymbol` on a `src/dotnet/cars/service-car` file returns symbols.
3. `findReferences` on an exported symbol in `src/js/web` returns cross-package
   hits, not just same-file ones.
4. `lsof -d cwd` on each spawned server shows the project dir.
5. F2 / `kjobs` shows all five with readable names.
6. `./sync status` clean after `./sync export`.

## Risks

- **Roslyn acquisition** is the main unknown: the language server ships from the
  Azure DevOps `vs-impl` NuGet feed rather than nuget.org, and its version has to
  match the SDK. If pinning proves fragile, `csharp-ls` remains the fallback at
  the cost of scale.
- **`workspaceFolder` substitution is unverified.** `${CLAUDE_PROJECT_DIR}` was
  probed in `args` only. First implementation step is to confirm it expands in
  `workspaceFolder` too, and to fall back to a wrapper that `cd`s if it does not.
- **Disabling the official plugins** forfeits their upstream updates; the plugin
  becomes the only place a server command is defined.

## Out of scope

- Shared or pre-warmed servers across panes — considered and declined; servers
  stay per-agent and lazily spawned.
- Per-repo settings files — not possible, `lspServers` is not a settings field.
- Python, despite `src/python` existing and being excluded in WebStorm.
