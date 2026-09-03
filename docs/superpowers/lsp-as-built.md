# Language servers, as built

What actually shipped, why it differs from the spec, and what is still open.
Written at the end of the implementation run because the reasoning behind the
deviations lived only in gitignored scratch and would otherwise have been lost.

The design doc is `specs/2026-09-03-lsp-plugin-design.md` and the execution plan
is `plans/2026-09-03-lsp-plugin.md`. Where either disagrees with this file, this
file is right — both were written before the facts below were known.

## What is deployed

One plugin, `~/.claude/skills/lsp/.claude-plugin/plugin.json`, auto-loading as
`lsp@skills-dir`. Ten servers, no marketplace entry, no `enabledPlugins` line.
`MANIFEST` already mirrors `.claude/skills/`, so `sync` carries it unchanged.

| Key | Command | Extensions | State |
|---|---|---|---|
| `typescript` | `typescript-language-server` | .ts .tsx .js .jsx .mts .cts .mjs .cjs | working |
| `gopls` | `bin/gopls-launch` | .go | working, all 7 modules |
| `intelephense` | `intelephense` | .php | working |
| `sourcekit` | `/usr/bin/sourcekit-lsp` | .swift | working, **after a build** |
| `csharp` | `bin/csharp-ls-launch` | .cs | working when rooted at a service |
| `css` | `vscode-css-language-server` | .css .less | working, single-file |
| `scss` | `bin/lsp-settle` → `some-sass-language-server` | .scss .sass | working, cross-file |
| `graphql` | `bin/lsp-settle` → `bin/graphql-launch` | .graphql .gql | working from any root |
| `pyright` | `pyright-langserver` | .py .pyi | working |
| `bash` | `bash-language-server` | .sh .bash | working (not this repo — see below) |

The four official `*-lsp` plugins are set `false` in `settings.json` so exactly
one definition claims each extension. All twenty-two extensions are disjoint —
worth re-checking programmatically after any edit, because a duplicate claim
fails silently.

**Servers spawn lazily and die with their session.** Proven: a monorepo session
that made no LSP call spawned zero servers, and a second check after adding four
more servers showed delta-zero. Cost is one server per *(session × language
actually touched)* — so four agents editing TypeScript means four tsservers,
which is why that entry carries `--max-old-space-size=4096`.

## The four things most likely to waste an hour

**1. `lspServers` is a plugin-manifest field, not a settings field.** Put it in
`settings.json` or pass it via `--settings` and it is silently ignored — no
error, the server simply never registers. Probed three ways before the design
was settled.

**2. Only `${CLAUDE_PROJECT_DIR}` and `${CLAUDE_PLUGIN_ROOT}` expand.** Nothing
else does. `${HOME}` in an `initializationOptions` value is passed through
verbatim, and the server then creates a directory *literally named* `${HOME}`
relative to its own cwd — which is the project you are working in. This was
tested by trying to move intelephense's index out of `/tmp`; it created
`monorepo/${HOME}/`. That is why intelephense still indexes to
`/tmp/intelephense` (30MB, owned by the user, mode 755). Anything needing a real
`$HOME` path has to go through a wrapper script, which is what the three
wrappers in `bin/` are for.

**3. Claude Code sends the request immediately after `didOpen`.** There is no
settle time. A server that indexes asynchronously and answers an unindexed
question with an empty result — rather than waiting — therefore reports "no
definition" on the first call of every session. `some-sass` and `graphql-lsp`
both do this; neither has a setting to change it. This is invisible to raw
probing, because any hand-written client naturally waits between `didOpen` and
the request. Both entries now run behind `bin/lsp-settle`.

**4. A wrong answer is the real failure mode, not an empty one.** Every trap in
this project looked like success: `documentSymbol` returning a full tree with no
project loaded, a hover returning `any` instead of the true type, C# answering
zero symbols instead of erroring, GraphQL returning `null` for three unrelated
reasons at once. Test with an oracle that can come out negative, and always run
the negative control.

## TypeScript: the syntax server answers first, and it lies

`typescript-language-server` runs a syntax-only server alongside the semantic
one and lets it answer while the semantic server is still loading. On a cold
session that produces a **confidently wrong hover**: in `src/js`, a const whose
type is `TravelshiftCustomHeader.DEBUG` came back as `any`, and was *still*
`any` after a 3-second settle. `goToDefinition` is correct throughout, so a
definition-only check never notices.

`initializationOptions.tsserver.useSyntaxServer: "never"` fixes it: the same
probe returns the true type. The cost is that the first hover of a session
blocks about 6 seconds instead of returning in 0.5. That is the right trade for
an agent, which has no way to tell a cold answer from a settled one and no
reason to ask twice.

Found only by the `claude -p` integration run — the raw probes all used a
generous settle time and never saw it.

## lsp-settle: holding the first request

`bin/lsp-settle <ms> <command> [args…]` holds the first `textDocument/*`
request of a session by `<ms>` and pipes everything else through untouched.
Measured thresholds: about 100ms for `some-sass`, under 400ms for
`graphql-lsp`; both entries use 500. The cost is paid once per server per
session.

Two details in there were each good for an hour, and both are the kind that
look like the server's fault:

- **The delay must be measured from the request's arrival, not from spawn.**
  Measured from spawn, startup latency eats the whole budget and the hold
  silently becomes a no-op — a 3000ms setting produced a 0ms delay.
- **Responses must bypass the hold queue.** Serialising all client→server
  traffic behind the held request also holds the client's *reply* to the
  server's own `workspace/configuration` request — which is exactly what
  graphql-lsp waits on before loading a schema. The delay then guarantees the
  failure it was added to prevent: graphql stayed empty at a 10-second hold and
  worked at 400ms once responses were allowed through.

Verified with a control that still misses, and a TypeScript regression check
confirming the proxy does not disturb a server that never had the problem.

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
C# agents inside the service you are working on. Both halves re-confirmed in the
final e2e.

## Go: a generated workspace, and one module served from outside it

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
`wonderpush-handler` (first-in-sorted-order wins). The generated
`go.work-70a6c73f6572` lists 6 modules.

**Correction to an earlier version of this document**, which claimed the dropped
module gets syntax only. It does not. gopls v0.22.0 builds a fallback module
view from a file's own `go.mod` when the file is outside the workspace, so
`wonderpush-handler` gets full type info too: hover on `rtlog.Open` returns
`func rtlog.Open(name string) *rtlog.Endpoint` with docs, and definition lands
in the module cache. The discriminator that proves the two modules resolve
independently is the SDK version — wonderpush resolves `compute-sdk-go@v1.3.3`,
its own requirement, while `html-scrubber`, which won the dedup, resolves
`v1.4.2`. Renaming the duplicate module path is still worth doing, but it buys
tidiness, not type information.

## GraphQL: rooting was the suspicion, and it was not enough

The stock server rooted directly at `src/js` returns exactly the same `null`
hover and empty completion as it does from the monorepo root. Three defects sit
behind it, each independently fatal and each completely silent:

1. **The config is named `.graphql.config.yml`.** graphql-config's cosmiconfig
   search places are `graphql.config.*`; the leading dot disables the file.
2. **Its `schema:` pointers name files that do not exist** —
   `./graphql-schema.graphql` and `./graphql-hygraph-schema.graphql`. The file
   on disk is `graphql.schema.graphql`, and the hygraph schema is absent.
3. **That schema fails SDL validation** on a duplicated
   `StayCategoryProductListInput.currency` (lines 14 and 23 of the input), which
   fails *every request* rather than only the schema load.

`bin/graphql-launch` finds the config — up from `${CLAUDE_PROJECT_DIR}`, then a
pruned depth-4 walk down, 0.019s from the monorepo root — and, only when
graphql-config genuinely cannot load it, writes a repaired config and
de-duplicated schema under `~/.cache/claude-lsp/`, the same out-of-repo trick as
`go.work`, passed via `--configDir`. It is stamped on file size and mtime so the
steady state is one `stat` per schema file.

Every failure path inside the repair falls through to the plain server, so a
broken repair degrades to the previous behaviour rather than taking the language
server down. A well-formed project takes the plain path and no config is
generated.

Verified from both the monorepo root and `src/js`: hover returns
`Currency.rate: String` with the schema's own docstring, and completion returns
`Currency`'s four fields with their declared types — strings that appear nowhere
in the query document. Negative controls (an unrelated empty root, and the
config renamed away) both return `null`.

**The monorepo still deserves the real three-line fix**: rename the config,
correct the schema pointer, delete the duplicate field. Codegen and editors
still see the broken version. Once it lands the repair branch stops firing by
itself.

## Sass: a second server, and why `.less` did not move

`vscode-css-language-server` is single-file. On two real monorepo files it
returned `null` definition, `null` hover and an empty completion list on a
`$variable` defined in a sibling file; `some-sass-language-server` v2.3.8
resolved all three at the same positions, naming the declaring file. All 137 of
the monorepo's SCSS imports are the legacy `@import` form — there is no `@use`
or `@forward` anywhere — which is exactly the case some-sass exists for.

`.less` and `.css` stayed with `vscode-css-language-server`. some-sass is
byte-identical to it on plain `.css` (same hover, same 55 completions in the
same order) but returns `null` for hover *and* documentSymbol on `.less` and
ships no `less` settings section at all. Splitting keeps every extension claimed
by exactly one server.

`unknownAtRules: "ignore"` is load-bearing on both, and both default to
`"warning"`: without it every `@tailwind` (in three real `.css` files) and every
SCSS at-rule is flagged, burying real diagnostics. some-sass spells it under its
own `somesass` section.

Known cost: at a wide workspace root some-sass resolves a duplicated filename to
the wrong copy — `Footer/responsive.scss`'s relative `./variables.scss` landed
on `src/js/web/src/styles/variables.scss`. That reaches 47 of 272 variable names
(17%), against `null` for all 272 before. The copies are near-identical
duplicates.

Performance is a non-issue: cross-file definition resolved at the full monorepo
root with a settle of 200ms, because imports resolve on demand rather than after
a workspace scan.

## Swift: the config file alone is inert

`itvlive` is Xcode-project-only — no `Package.swift`, no `compile_commands.json`
— so sourcekit-lsp had no compilation database and was syntax-only.

The fix is `xcode-build-server` plus a generated `buildServer.json`, **and one
real build**. This is the part worth remembering: generating `buildServer.json`
changed nothing on its own. Hover and cross-file definition returned `null`
before the fix, and still returned `null` with `buildServer.json` in place but
no build. Only after one `xcodebuild` succeeded — growing the DerivedData index
store from 0 to 2693 files — did the identical probes return
`@MainActor let player: PlayerController` and a correct cross-file definition
into `AppModel.swift`.

No manifest change: sourcekit-lsp auto-discovers `buildServer.json` in the
workspace root.

```sh
brew install xcode-build-server
cd ~/Work/itvlive
xcode-build-server config -project itvlive.xcodeproj -scheme ITVLive
xcodebuild -project itvlive.xcodeproj -scheme ITVLive -destination 'platform=macOS' build
```

`ITVLive` is a macOS-only scheme; it has no iOS destinations. Re-run the build
whenever the index goes stale.

**`buildServer.json` is left untracked in `~/Work/itvlive` and is not covered by
its `.gitignore`**, so it shows in `git status`. It embeds machine-specific
absolute paths — the DerivedData hash and `/opt/homebrew` — so it is a per-machine
file and should be gitignored rather than committed.

## Known limitations

- **Bash cannot see this repo's own scripts.** `extensionToLanguage` is
  extension-keyed and `kdiff`, `kjobs`, `kitty-session`, `wt-help`, `wt-ide`,
  `wt-link` and the three LSP wrappers have no extension. The server covers the
  monorepo's 84 `.sh` files and nothing here. Its oracle is cross-file
  `source`-graph name resolution, not types — shell has none.
- **Python's cross-file target is necessarily third-party.** None of the 14
  tracked `.py` files import each other, so resolution was proven through an
  installed package (`pymysql`, specialised as `Connection[Cursor]`) rather than
  a first-party import.
- **intelephense's exclusion mechanism is proven, its glob list mostly is not.**
  Temporarily excluding `src/php/service-stays` dropped a query from 77 symbols
  to 67, so `settings` reaches the server. But most listed globs target trees
  with essentially no PHP and are near-no-ops.
- **C# from a non-service root** answers zero symbols rather than erroring.

## A restored machine needs the binaries too

`sync` restores the manifest; it does not install the servers. On a new machine:

```bash
npm install -g typescript-language-server typescript intelephense \
  vscode-langservers-extracted some-sass-language-server \
  graphql-language-service-cli pyright bash-language-server
go install golang.org/x/tools/gopls@latest
curl -sSL https://dot.net/v1/dotnet-install.sh | bash -s -- --channel 10.0
dotnet tool install --global csharp-ls
brew install xcode-build-server
```
`sourcekit-lsp` ships with Xcode's toolchain at `/usr/bin/sourcekit-lsp`. Swift
also needs the per-repo `buildServer.json` and one build, per the Swift section.

## Still open

- README's language-servers section is updated in the working tree but **not
  committed** — that file also holds unrelated in-flight edits, so it is the
  user's to split and commit.
- The four monorepo defects below are all worth fixing at source.
- `lsp-settle`'s 500ms is a margin over measured thresholds, not a tuned value.
  If a server is ever added that needs longer, the symptom will be a
  first-call-only empty result.

## Four monorepo bugs found by this work

None is an LSP problem; all predate it.

1. `src/dotnet/GlobalSolution.sln` fails `MSB5023` for every MSBuild-based tool.
2. `src/go/fastly-wasm/html-scrubber` and `.../wonderpush-handler` declare the
   same module path, which breaks any Go workspace spanning both.
3. `src/js/.graphql.config.yml` is unreadable by graphql-config three times over
   — wrong filename, dead schema pointers, and a duplicated field in the schema
   it should point at. Codegen and editors see all three.
4. `src/go/fastly-wasm/html-scrubber/main.go:57` **does not parse**: a `case`
   listing four hostnames is missing the closing quote on the last one
   (`"guidetoeurope.eu:`). `gofmt -e` reports `string literal not terminated`.
   Committed in `d4042b8f94`, "Add GTE .eu to fastly-html-scrubber".
