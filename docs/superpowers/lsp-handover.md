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

Ordered by value.

1. **Merge the README appendix** from the end of `lsp-as-built.md` into the
   language-servers section, and change "Five servers" to nine. The section
   itself is currently uncommitted in the working tree, mixed with the user's own
   revision — they are splitting that by hand.
2. **Re-test GraphQL rooted at `src/js`.** Its config exists at
   `src/js/.graphql.config.yml`; a monorepo-root session never sees it. This is
   probably a rooting fix, not a dead end.
3. **Decide on SCSS.** `vscode-css-language-server` is single-file;
   `some-sass-language-server` v2.3.8 handles cross-file `@use`/`@import`, which
   was the reason SCSS was worth adding at 1,122 files.
4. **Swift** needs `xcode-build-server` and a generated `buildServer.json` in
   `~/Work/itvlive` to get past syntax-only.
5. **Canonicalise the wrapper roots** — one line in each of `gopls-launch` and
   `csharp-ls-launch`. Harmless today because `CLAUDE_PROJECT_DIR` is always
   absolute, but a relative value makes the C# upward walk spin forever.
6. **Drop `startupTimeout: 180000` from the `csharp` entry.** A Roslyn vestige;
   csharp-ls loads in 2.7s, so it only makes a wedged server take three minutes
   to give up.

## Not this work, but surfaced by it

- `home/.claude/settings.json` has `permissions.deny` emptied (26 rules → 0) in
  both the repo copy and the live file, unstaged, from another session. The live
  file is restored from the repo copy by `sync`, so the two must agree before any
  change sticks. The `deny-sensitive-files.sh` hook is still wired and still
  hard-blocks credential reads.
- Two monorepo defects, described in `lsp-as-built.md`: the corrupt
  `GlobalSolution.sln`, and the duplicate `module compute-starter-kit-go`.
