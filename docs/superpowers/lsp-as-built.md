# Language servers, as built

What actually shipped, why it differs from the spec, and what is still open.
Written at the end of the implementation run because the reasoning behind the
deviations lived only in gitignored scratch and would otherwise have been lost.

The design doc is `specs/2026-09-03-lsp-plugin-design.md` and the execution plan
is `plans/2026-09-03-lsp-plugin.md`. Where either disagrees with this file, this
file is right — both were written before the facts below were known.

## What is deployed

One plugin, `~/.claude/skills/lsp/.claude-plugin/plugin.json`, auto-loading as
`lsp@skills-dir`. Nine servers, no marketplace entry, no `enabledPlugins` line.
`MANIFEST` already mirrors `.claude/skills/`, so `sync` carries it unchanged.

| Key | Command | Extensions | State |
|---|---|---|---|
| `typescript` | `typescript-language-server` | .ts .tsx .js .jsx .mts .cts .mjs .cjs | working |
| `gopls` | `bin/gopls-launch` | .go | working, 6 of 7 modules |
| `intelephense` | `intelephense` | .php | working |
| `sourcekit` | `/usr/bin/sourcekit-lsp` | .swift | **syntax only** |
| `csharp` | `bin/csharp-ls-launch` | .cs | working when rooted at a service |
| `css` | `vscode-css-language-server` | .css .scss .less | **single-file only** |
| `graphql` | `graphql-lsp` | .graphql .gql | **no positive signal yet** |
| `pyright` | `pyright-langserver` | .py .pyi | working |
| `bash` | `bash-language-server` | .sh .bash | working (not this repo — see below) |

The four official `*-lsp` plugins are set `false` in `settings.json` so exactly
one definition claims each extension. All twenty extensions are disjoint.

**Servers spawn lazily and die with their session.** Proven: a monorepo session
that made no LSP call spawned zero servers, and a second check after adding four
more servers showed delta-zero. Cost is one server per *(session × language
actually touched)* — so four agents editing TypeScript means four tsservers,
which is why that entry carries `--max-old-space-size=4096`.

## The one thing most likely to waste an hour

`lspServers` is a **plugin-manifest field, not a settings field**. Put it in
`settings.json` or pass it via `--settings` and it is silently ignored — no
error, the server simply never registers. Probed three ways before the design
was settled.

## Why C# is not what the spec says

The spec specifies Roslyn with `--solution src/dotnet/GlobalSolution.sln`. Both
halves are impossible. Three facts, each expensive to rediscover:

1. **This Roslyn build has no `--solution` flag.** `--help` offers only
   `--pipe`, `--brokeredServicePipeName`, `--stdio`. Cross-project loading is
   exposed only through custom `solution/open` / `project/open` notifications
   that a generic LSP client never sends, so it is stuck in "misc files" mode.
   Shipped as-is it returned `null` hover, `[]` documentSymbol, `[]`
   goToDefinition on a cross-project symbol.
2. **`src/dotnet/GlobalSolution.sln` is corrupt.** `dotnet build` on it fails
   `MSB5023`: a `NestedProjects` entry names GUID
   `{5E6FC612-424D-4002-95DC-1675C0D29AF4}`, which appears 13 times in config
   sections and zero times as a `Project(...)` declaration. No LSP involved —
   Rider, Visual Studio, `dotnet build`, csharp-ls and Roslyn all reject it.
   This is a pre-existing monorepo defect, not an LSP one.
3. **The Homebrew cask needs interactive root**, which no agent can supply.
   SDK 10.0.400 was installed user-local via Microsoft's `dotnet-install.sh` at
   `~/.local/share/dotnet`. The orphaned SDK 8.0.422 at `~/.dotnet` is untouched.

So `csharp-ls` shipped instead, behind `bin/csharp-ls-launch`, which walks up
from `${CLAUDE_PROJECT_DIR}` to the nearest per-service `.sln` and deliberately
never selects `GlobalSolution.sln`. `--features metadata-uris` is set so
`goToDefinition` on a compiled-package symbol yields a decompiled location
rather than nothing.

**This makes rooting load-bearing for C#.** From `src/dotnet/cars/service-car`
you get `CarService.sln` in ~2.7s with real cross-project hover. From the
monorepo root there is no ancestor `.sln`, so the server starts but answers with
**zero symbols on a real class** — a confident empty answer, not an error. Start
C# agents inside the service you are working on.

## Go: a generated workspace, and one module left out

The monorepo has 7 `go.mod` under `src/go` and no `go.work`, so nothing resolved
cross-module. `bin/gopls-launch` generates one under `~/.cache/claude-lsp/`,
keyed by project path, and exports `GOWORK`.

Deliberately outside the repo, which has a cost worth knowing: a shell
`go build` does not see it, so an LSP-only `BrokenImport` will not reproduce on
the command line.

`fastly-wasm/html-scrubber` and `fastly-wasm/wonderpush-handler` **both declare
`module compute-starter-kit-go`** — never renamed from the Fastly starter
template. In workspace mode that makes `go list` fail for the *entire*
workspace, so the wrapper de-duplicates on the declared module path and drops
`wonderpush-handler` (first-in-sorted-order wins). 6 of 7 modules get type info
instead of 0 of 7. Renaming that module in the monorepo recovers the seventh.

## Known limitations

- **Swift is syntax-only.** `itvlive` is Xcode-project-only: no `Package.swift`,
  no `buildServer.json`, no `compile_commands.json`, and `xcode-build-server` is
  not installed, so sourcekit-lsp has no compilation database. Installing
  `xcode-build-server` and generating `buildServer.json` would fix it.
- **SCSS is single-file.** `vscode-css-language-server` did not resolve
  `goToDefinition` on a `$variable` defined in a sibling `.scss` reached via
  legacy `@import`. `some-sass-language-server` (v2.3.8 on npm) is purpose-built
  for cross-file `@use`/`@import` and is the obvious swap if cross-file Sass
  navigation matters — untested here.
- **GraphQL has no positive signal yet.** It registers and does not error, but
  returned nothing useful. The cause is rooting, not a missing config: the
  config **does** exist at `src/js/.graphql.config.yml` (schemas
  `./graphql-schema.graphql` and `./graphql-hygraph-schema.graphql`, documents
  `web/src/**/*.graphql`). A server rooted at the monorepo root never sees it.
  Re-test from `src/js` before concluding anything.
- **Bash cannot see this repo's own scripts.** `extensionToLanguage` is
  extension-keyed and `kdiff`, `kjobs`, `kitty-session`, `wt-help`, `wt-ide`,
  `wt-link`, `gopls-launch` and `csharp-ls-launch` have no extension. The server
  covers the monorepo's 84 `.sh` files and nothing here.
- **intelephense's exclusion mechanism is proven, its glob list mostly is not.**
  Temporarily excluding `src/php/service-stays` dropped a query from 77 symbols
  to 67 with three named symbols disappearing, so `settings` reaches the server.
  But most listed globs target trees with essentially no PHP and are near-no-ops.

## A restored machine needs the binaries too

`sync` restores the manifest; it does not install the servers. On a new machine:

```bash
npm install -g typescript-language-server typescript intelephense \
  vscode-langservers-extracted graphql-language-service-cli pyright \
  bash-language-server
go install golang.org/x/tools/gopls@latest
curl -sSL https://dot.net/v1/dotnet-install.sh | bash -s -- --channel 10.0
dotnet tool install --global csharp-ls
```
`sourcekit-lsp` ships with Xcode's toolchain at `/usr/bin/sourcekit-lsp`.

## Still open

- README's language-servers section documents five servers; Task 7's four are
  written up in `.superpowers/sdd/2026-09-03-lsp-plugin/task-7-report.md` and
  need merging by hand (the file held in-flight edits during the run).
- Swap SCSS to `some-sass-language-server`, or accept single-file.
- Re-test GraphQL rooted at `src/js`.
- Neither wrapper canonicalises its root. Harmless today because Claude Code
  always sets `CLAUDE_PROJECT_DIR` absolute, but a relative value would make
  `csharp-ls-launch`'s upward walk spin forever. One line in each fixes it:
  `root="$(cd "${CLAUDE_PROJECT_DIR:-$PWD}" 2>/dev/null && pwd -P || printf '%s' "${CLAUDE_PROJECT_DIR:-$PWD}")"`.
- `startupTimeout: 180000` on `csharp` is a Roslyn vestige; csharp-ls loads in
  2.7s, so its only effect now is making a wedged server take three minutes to
  give up.
- intelephense indexes to `/tmp/intelephense` (mode 1777) rather than
  `~/.cache/claude-lsp` like the Go wrapper. Worth aligning.

## Two monorepo bugs found by this work

Neither is an LSP problem; both predate it.

1. `src/dotnet/GlobalSolution.sln` fails `MSB5023` for every MSBuild-based tool.
2. `src/go/fastly-wasm/html-scrubber` and `.../wonderpush-handler` declare the
   same module path, which breaks any Go workspace spanning both.

## Appendix: README text for the four servers added last

Written during the run but never applied, because `README.md` held in-flight
edits at the time. Paste into the language-servers section and change its
opening from "Five servers" to "Nine".

**SCSS/CSS** — `vscode-css-language-server` (from `vscode-langservers-extracted`;
there is no official `css-lsp` marketplace plugin, hence hand-written). Covers
`.css`, `.scss`, `.less` — the third-largest language in the monorepo by file
count (801+321 `.scss`, 29+410 `.css`). `unknownAtRules: "ignore"` is set for
both lint settings; without it the server flags every SCSS `@use`, `@forward`
and `@mixin` as an unknown at-rule and buries real diagnostics under hundreds of
false ones. Single-file `documentSymbol` is accurate. Cross-file
`goToDefinition` on a `$variable` defined in a sibling file is **not** supported.

**GraphQL** — `graphql-lsp` (from `graphql-language-service-cli`), covering
`.graphql`/`.gql` (405+61 files). It needs a `graphql.config.yml` or `.graphqlrc`
to find a schema; one exists at `src/js/.graphql.config.yml`, so the server must
be rooted there rather than at the monorepo root to be useful. Untested from
that root.

**Python** — `pyright-langserver`, covering `.py`/`.pyi`. Only 14 tracked `.py`
files, 9 of them under `src/bi`. Nearly free, since spawning is lazy.

**Bash** — `bash-language-server`, covering `.sh`/`.bash` (84 `.sh` files in the
monorepo). `extensionToLanguage` is extension-keyed and every script in *this*
repo has no extension, so it is invisible to `kdiff`, `kjobs`, `kitty-session`,
`wt-help`, `wt-ide`, `wt-link` and both LSP wrappers.
