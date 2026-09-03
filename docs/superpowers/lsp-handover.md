# LSP plugin — session handover

Written at the end of the implementation run, before context compaction. The
artifact itself is documented in `lsp-as-built.md`; this file is about the
*session* — what was decided on the user's behalf, what went wrong, and what a
successor should pick up.

Design: `specs/2026-09-03-lsp-plugin-design.md` (partly superseded — it carries a
banner). Plan: `plans/2026-09-03-lsp-plugin.md` (historical; Task 4 is
superseded). Execution ledger with full evidence:
`.superpowers/sdd/2026-09-03-lsp-plugin/progress.md` — **gitignored**, so it will
not survive a `git clean`. Everything load-bearing has been copied out of it into
these two docs.

## State at handover

16 commits, `d67115d..5e9166e`, all on `master`. Nine servers deployed and
auto-loading. The user's uncommitted work in `README.md`,
`home/.claude/settings.json`, `home/.config/kitty/kitty.conf`,
`home/.local/bin/kjobs` and `home/.local/bin/wt-help` was left dirty throughout
and must stay that way — it is theirs, not part of this work.

Final whole-branch review: **ready to merge as code**, no Critical or Important
code defects, all deferred minors triaged as acceptable. Its one merge-blocker
was documentation, which `lsp-as-built.md` and this file discharge.

## Decisions taken on the user's behalf

Twenty-six rulings were recorded during execution. These are the ones that
changed an outcome; the rest were process bookkeeping.

| Ruling | Decision | Cost if wrong |
|---|---|---|
| 5 | **Rejected Task 0's finding** that `workspaceFolder` is ignored — its probe claimed `.go`, which the still-enabled official gopls plugin also claimed, so a different server answered both runs | would have added needless `cd` wrappers to every server and hidden the real behaviour |
| 8 | **Never nest `sleep` inside a probe prompt** — foreground sleep is blocked in the inner harness too, so the inner agent hangs | cost three stalls before it was caught |
| 12 | **Strengthened the acceptance oracle**: absence of an error proves nothing when the thing that would emit it never ran; `documentSymbol` is syntactic and proves nothing about semantics | four tasks shipped green tests over broken features before this was enforced |
| 13 | **De-duplicate Go modules on declared module path** rather than renaming in the company repo | one module (`wonderpush-handler`) gets syntax-only Go |
| 16 | **Accepted a user-local `dotnet-install.sh` SDK** over the spec's Homebrew cask, which needs interactive root | `dotnet` is on PATH for this user only, not system-wide |
| 17 | **Retired an agent** that invoked `osascript` with administrator privileges and probed `/etc/sudoers.d` after `sudo` failed | lost its context; it had to be re-derived |
| 19 | **Shipped csharp-ls over Roslyn**, routed to the nearest per-service `.sln` | C# from a non-service root answers with zero symbols rather than an error |
| 21 | **Stopped using `./sync install`** after it reverted the user's live `settings.json` three times | a later change to another mirrored file will not reach `$HOME` until someone installs deliberately |
| 23 | **Left Task 5's README section uncommitted** for the user to split | that section is not in history until they commit it |
| 25 | **Barred Task 7 from touching `README.md`** | the four newest servers are undocumented until the appendix text is merged |
| 26 | **Declined to expand scope again** for the SCSS and GraphQL follow-ups | both stay unresolved pending the user's call |

## Mistakes made in this session

Recorded because a successor should not trust the earlier parts of the
transcript uncritically.

1. **Swept the user's README work into a commit.** `git add README.md` stages the
   whole file, and README was the one dirty file a task also had to edit.
   Reverted with `git reset --soft` at the user's instruction; content intact.
2. **Reported an "11+ minute" csharp-ls load** that never happened — inferred
   from process elapsed time when the solution had actually failed to parse in
   seconds and the process was idling.
3. **Blamed `deny-sensitive-files.sh`** for the user's grep approval prompts. It
   emits only `permissionDecision: deny` and never `ask`, so it cannot prompt.
4. **Wrote one of the five unfalsifiable tests.** A `pgrep -fc … || echo 0`
   laziness check that always returns `0/0` on macOS. A subagent caught it and
   substituted a real check.

The recurring theme: **the configuration work was easy and the verification was
where everything went wrong.** Five separate tests in this run reported success
over a broken or unexercised feature. Anything a successor inherits as "verified"
is worth re-checking against a test that could actually fail.

## Pick up here

All six items on the original list are done. What follows is what became of
them, and what is left.

| # | Item | Outcome |
|---|---|---|
| 1 | Merge the README appendix | Done, **in the working tree only** — README still holds the user's own in-flight edits, so it is theirs to split and commit |
| 2 | Re-test GraphQL from `src/js` | Rooting was not the cause. Three silent config defects were; `bin/graphql-launch` works around all three |
| 3 | Decide on SCSS | Swapped to `some-sass-language-server` for `.scss`/`.sass`; `.css`/`.less` stayed, because some-sass answers `null` on `.less` |
| 4 | Swift | Fixed. Needs `xcode-build-server`, a generated `buildServer.json`, **and one real build** — the config alone is inert |
| 5 | Canonicalise the wrapper roots | Done, and it was a live bug, not a theoretical one: 1945 spin iterations in 10s |
| 6 | Drop `startupTimeout` from `csharp` | Done |

Three findings arrived that were not on the list:

- **SCSS and GraphQL were still broken through Claude Code** after passing every
  raw probe. Claude Code sends `didOpen` and the request back to back; both
  servers answer an unindexed question with an empty result. `bin/lsp-settle`
  holds the first request by 500ms. This is the clearest example in the whole
  project of why raw probing is not verification: a hand-written client waits
  naturally, so the bug cannot appear there.


- **TypeScript answered `any`.** `typescript-language-server`'s syntax server
  replies before the semantic one and gives a confidently wrong type on a cold
  session — still wrong at a 3s settle. `useSyntaxServer: "never"` fixes it.
  Caught only by the `claude -p` integration run; every raw probe used a
  generous settle time and missed it.
- **`${HOME}` does not expand in the manifest.** Only `${CLAUDE_PROJECT_DIR}`
  and `${CLAUDE_PLUGIN_ROOT}` do. Attempting to move intelephense's index out
  of `/tmp` created a directory literally named `${HOME}` inside the monorepo.
  Removed; intelephense stays on `/tmp`.

And one documented fact turned out to be wrong: the Go section claimed the
de-duplicated module gets syntax only. It gets full type info, from a gopls
fallback module view. Corrected in `lsp-as-built.md`.

## Still open

- **README is uncommitted.** The language-servers section is rewritten for all
  ten servers; the file also carries unrelated user edits.
- **Four monorepo defects**, all listed at the end of `lsp-as-built.md`. Three
  were known; the fourth is new and the most clear-cut:
  `src/go/fastly-wasm/html-scrubber/main.go:57` does not parse — a `case`
  listing four hostnames is missing the closing quote on the last
  (`"guidetoeurope.eu:`), committed in `d4042b8f94`.
- **`buildServer.json` is untracked in `~/Work/itvlive`** and not gitignored.
  It embeds machine-specific paths and should be ignored, not committed.

## Not this work, but surfaced by it

- `home/.claude/settings.json` has `permissions.deny` emptied (26 rules → 0) in
  both the repo copy and the live file, unstaged, from another session. The live
  file is restored from the repo copy by `sync`, so the two must agree before any
  change sticks. The `deny-sensitive-files.sh` hook is still wired and still
  hard-blocks credential reads.
