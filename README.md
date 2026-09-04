# Terminal setup

kitty → workmux. No tmux.

**One behavioural change to know first: there is no session server.** Panes do
not outlive the app. Quitting kitty kills every agent in it, and there is no
detach. kitty has no session concept and its author has declined to add one; the
old `⌘⌥D` is gone. `confirm_os_window_close 2` means closing a window with more
than one pane asks first, which is the only guard there is.

What you *can* get back is the **shape** of the workspace — `kitty-session
restore` rebuilds your tabs, panes and directories and resumes each agent with
`claude --continue`. See [Session snapshots](#session-snapshots).

## Opening the app

Launch kitty. `startup_session` builds tab `main` as a **2×2** and you land in
it. That is the whole mechanism — six lines in `~/.config/kitty/session.conf`:

```
new_tab main
layout grid
cd ~
launch zsh
launch zsh
launch zsh
launch zsh
```

The tab uses the **`grid`** layout, which derives every cell from the window size
with no split tree at all. There is no build order to get wrong, nothing to wait
for and nothing that can end up inconsistent — and it re-flows correctly when a
5th pane appears and back again when it closes.

## Keys

| Key | Does |
|---|---|
| `⌥O` | **IDE button** — opens WebStorm or PhpStorm on the current worktree |
| `⌥I` | opens the other IDE |
| `⌥H/J/K/L` | move between panes |
| `⌥Z` | zoom / unzoom the current pane (switches to the `stack` layout) |
| `⌘D` / `⌘⇧D` | split right / down |
| `⌘T` | new tab |
| `⌘W` | close this pane |
| `⌘N` | new window |
| `⌘K` | clear the screen **and** the scrollback |
| `⌘=` / `⌘-` / `⌘0` | **zoom** text in / out / back to normal |
| `⌘⌃F` | fullscreen — same as the green button in the titlebar |
| `⌥=` | **even out the grid** — see below |
| `⌘⇧G` | **diff** — every change in this repo, side by side, in its own window |
| `⌘⌥S` / `⌘⌥R` | **save / restore** the session snapshot |
| `⌃⇧G` / `⌃⇧H` | last command's output / full scrollback, in a pager |
| `⌃⇧Z` / `⌃⇧X` | jump to the previous / next **prompt** in this pane |
| `⌘⇧R` | reload config |
| `F1` or `⌥/` | **cheat sheet** — every shortcut and command; press again to close |
| `F2` | **what is running** — every command in every pane; press again to close |
| `F3` | **git** — lazygit over this pane, rooted where the pane is |
| `⌘⇧T` | **update project** — fetch, prune, merge upstream; autostashes |
| `⌘⇧K` | **commit and push** — lazygit, opened on the file list |

`⌘K` on its own would clear the scrollback and leave the visible screen alone,
so it looks like nothing happened. Terminal.app wipes both, so here it is
`clear_terminal reset active` followed by a `Ctrl+L` to make the shell or TUI
redraw its prompt.

`⌥` is the **left** Option/Alt key (`macos_option_as_alt left`) — right-Option is
left alone so it still types accented characters, which means right-Option+O
types `ø` instead of opening the IDE.

Gone from the old setup, with no kitty equivalent: `⌘⌥D` (detach), `⌘⇧P`
(command palette), `⌥⇧C` / `⌥⇧S` (live font and palette knobs — there is nothing
left to tune), and `⌥⇧R` (grid rebuild — nothing to rebuild).

## The grid

`⌥=` runs `layout_action equalize` and evens the grid out. Unlike the thing it
replaces it is a single action, it never fails, and it tears nothing down.
`equalize_on_window_close=y` is set on the `splits` layout as well, so closing a
pane re-evens the rest without pressing anything.

**The grid cannot get stuck.** kitty's layout state holds only fractional biases
and recomputes geometry from the real window size on every layout pass, so there
is no stored width to fall out of sync. Measured before committing to this:
12/12 clean when closing a pane 0 ms after opening one, 6/6 even across a 7×
window-resize range, even after 25 font-size changes 30 ms apart with no settle
time, and `equalize` restored a deliberately skewed grid exactly.

## From Claude Code

| Command | Does |
|---|---|
| `/worktree <name> [-p "prompt"]` | `workmux add` — worktree, branch, **tab**, agent. In a shell, `wt <name>` uses the current pane instead |
| `/ide [--other]` | seed and open WebStorm/PhpStorm on the current worktree |
| `/worktrees` | `workmux ls` |
| `/shortcuts` | the cheat sheet, inline |

They live in `~/.claude/commands/*.md`; the filename is the command name.

## Font rendering

Nothing to configure. kitty rasterises with **CoreText** on macOS — the same
engine Terminal.app uses — so Monaco 13 comes out the way it does in
Terminal.app without any tuning. There is no `wt-font`, no rendering mode, no
contrast dial and no stem darkening, because there is no FreeType in the path.

## Claude Code in a pane

A terminal launched from inside a Claude Code session donates that session's
markers to every shell it opens, and new agents then refuse to save transcripts:

```
⚠ Transcript saving is off — inherited CLAUDE_CODE_CHILD_SESSION marker
```

`.zshrc` strips them — `CLAUDE_CODE_CHILD_SESSION`, `CLAUDE_CODE_SESSION_ID`,
the messaging socket and token, `CLAUDE_CODE_ENTRYPOINT`, `CLAUDECODE` and
`CLAUDE_CODE_EXECPATH` (which otherwise pins an outdated version).

**The test is the parent process, not the terminal.** An interactive shell whose
parent is `claude` — Claude Code's own Bash tool — keeps the markers, because it
genuinely is inside a session. Anything else, which is what a pane the terminal
opened looks like, gets them stripped. The previous version of this guard keyed
off the terminal's own environment variable and the name of its binary, so it
silently stopped working the moment the terminal changed. Keying on the parent
means it cannot rot that way again.

Verified: a shell started with the markers forcibly set reports all of them
empty after sourcing `.zshrc`.

Two things this does not reach: a shell opened before the fix (run
`source ~/.zshrc` in it) and an agent already running (restart it).

## Reviewing a diff

`⌘⇧G`, or `kdiff` in a shell. Opens [diffnav](https://github.com/dlvhdr/diffnav):
a **file tree on the left**, GitHub style, and the syntax-highlighted diff for
the selected file on the right — so a large change set is navigated by jumping
between files rather than scrolling through one long buffer.

```bash
kdiff                  # everything on this branch - the pre-merge read
kdiff HEAD             # uncommitted only (working tree + index)
kdiff --staged         # the index
kdiff HEAD~3           # against an older commit
kdiff -k               # the kitten diff view instead (renders images)
kdiff -w               # in a new OS window (what ⌘⇧G does)
kdiff -t               # in a new tab
```

The windows `kdiff` opens are tinted `#1a1a24` rather than the usual black, so
the diff is recognisable among a screenful of terminals. `macos_titlebar_color`
is `background`, so the titlebar with the close buttons takes the shade too —
that is the only way to colour one window's titlebar, and it means the body
and the titlebar share it. A bare `kdiff` is left alone: it runs in a pane you
already own, and recolouring that would outlast the diff.

Bare `kdiff` diffs against the point where this branch left the base branch, so
**committed, staged and unstaged changes all show at once** and a local commit
does not empty the view. Base is `$KDIFF_BASE` if set, otherwise origin's
default branch, falling back to `origin/master`, `origin/main`, `master`,
`main`. On the base branch itself you get whatever is unpushed plus whatever is
uncommitted.

Inside diffnav, `?` or `F1` lists the keys — moving between files, toggling the
file tree, side-by-side vs unified, and search.

`kitten diff` is still there as the second viewer and is the one that **renders
images**: `kdiff -k`, or `KDIFF_VIEWER=kitten`. It is wired as git's difftool
too, so plain `git difftool -d` gets that view. Inside it: `j`/`k` scroll,
`n`/`p` next/previous change, `/` search, `a` all context, `q` quit.

If `diffnav` is not installed, `kdiff` silently falls back to `kitten diff`, so
a freshly restored machine still works — `brew install diffnav` to get the tree
back. Terminal diff viewers have no draggable scrollbar (kitty has none
anywhere); the file tree and `?`-listed jumps are what replace it.

Untracked files are not shown — `git diff` does not see them.

### Making it fit

Tab-indented files are the worst case: delta renders a tab as **eight** spaces
by default, so a method body in a `.cs` file starts three quarters of the way
across its pane. Two spaces is the setting, and it lives in delta rather than
diffnav — diffnav owns the frame, delta owns the diff body:

```gitconfig
[delta]
	tabs = 2
	hunk-header-decoration-style = none
```

`tabs = 2` is the readability fix. `hunk-header-decoration-style = none` drops
the box drawn around every hunk header while keeping the header itself, which
is the line that tells you *where* you are (`3: namespace Models`) — two rows
back per hunk, and a busy file has a lot of hunks.

`~/.config/diffnav/config.yml` hides the `DIFFNAV` banner, the one row of the
frame that carries no information. The breadcrumb and the search prompt are
hardcoded and stay.

The box around each **file** heading takes a wrapper. diffnav passes
`--file-decoration-style=box` on delta's own command line, and a command-line
flag beats every config file, so `~/.local/libexec/kdiff/delta` substitutes
the value in flight — delta rejects a repeated flag, so it cannot simply be
appended. `kdiff` puts that directory first on `PATH` for its diffnav
pipeline and nowhere else, and hands it the resolved path to the real delta;
run any other way the wrapper refuses. Plain `delta`, lazygit's pager and
`git difftool` all still get Homebrew's binary. Three rows per file heading
become one.

The bigger lever is the view itself, so `config.yml` sets **unified** rather
than diffnav's side-by-side default. Side-by-side splits the width in two
*and* spends a blank row opposite every insertion; on a monorepo diff of
deeply indented C# and long JSON lines that leaves very little of either line
readable. **`s`** toggles back for a rewrite that needs reading in parallel,
and **`e`** hides the file tree for the full width.

Note that a tab-indented file is the only thing `tabs` reaches. Most of the
leading whitespace in a C# or JSON diff is literal spaces in the source — four
per level — and nothing in delta or diffnav will narrow that.

`esc` closes diffnav too, but that one is a translation rather than a setting:
diffnav quits on `q` and its config file has no key bindings in it, so kitty
rewrites ESC to `q` while a window titled `diff: …` has focus. `kdiff`
sets that title before handing off. Rewriting the key rather than closing the
window matters for a bare `kdiff`, which runs in the pane you are already in —
closing that would take your shell with it. Two edges: with diffnav's search
prompt open, ESC types a `q` into it instead of quitting, and for a moment
after diffnav exits the title has not reverted, so an ESC lands a stray `q` at
your prompt.

## Doing something about it

`F3` opens [lazygit](https://github.com/jesseduffield/lazygit) as an overlay
over the current pane, rooted in that pane's directory. `kdiff` reads a change
set; this is the half that acts on one — stage, branch, fetch, pull, push,
rebase, stash, reflog, and hunk-level staging, which is the part of an IDE's git
panel that actually gets used.

```
space           stage / unstage the selected file
enter           drill into a file, then space stages one hunk or line
a               stage everything
c               commit          n   new branch (in Branches)
f / p / P       fetch / pull / push
r               rebase onto the selected branch      s   stash
o               open a PR for this branch (uses gh)
q or esc        close
```

`esc` closes it because `quitOnTopLevelReturn` is on. Inside a menu, a panel
or a diff, `esc` still means "return" — lazygit's own use of the key is
untouched; the setting only adds the top level, so the last `esc` closes the
whole thing the way every other overlay here does.

`?` lists every key in context. A second `F3` does nothing on purpose: it is
unmapped while lazygit has focus, so the key reaches lazygit rather than
stacking a second overlay — and it is a no-op rather than a kill, which matters
in the middle of a rebase.

The two WebStorm keys are shortcuts into the same two halves. `⌘⇧K` is that
lazygit again with the file list enlarged against the diff rather than the
four-panel dashboard — the commit dialog, one `c` and one `P` from pushed.
`⌘⇧T` is Update Project, and it runs `kpull`:

```
kpull                  # fetch --all --prune, then merge the upstream branch
kpull -f               # fetch and prune only
```

A dirty tree is not a reason to refuse — the merge autostashes, and git
reapplies that itself whether you go on to finish the merge or `git merge
--abort` it. A conflict is left exactly where it is, for `F3` to resolve.
WebStorm puts Update Project on `⌘T`; here that stays new-tab, so it moved one
modifier over.

Both lazygit maps set `PATH` before exec'ing. kitty's `launch` hands its child
only `/Applications/kitty.app/Contents/MacOS` and the system directories —
kitty resolves `lazygit` itself, but lazygit then cannot find `delta`, and the
diff pane renders `delta: command not found`. `kdiff` and `kpull` carry the
same fixup inside the scripts.

Two deliberate config choices in `~/.config/lazygit/config.yml`: diffs render
through `delta`, so they look the same here as in `git diff` and `kdiff`; and
Nerd Font icons are **off**, because `font_family` is Monaco and asking for
glyphs it does not have renders tofu boxes. Everything else is left at
lazygit's defaults, so upgrades keep bringing new ones — note that lazygit
rewrites the file in place when it renames a setting.

## What is running

`F2`, or `kjobs` in a shell. Every command running in every pane of this kitty
— not just the one you started, but everything running underneath it — what it
is costing, and a way to kill it:

```
 Running (10)  ·  21% cpu  ·  2.3G             2 agents  ·  sort: tab

  yarn dev · pane 1   ▾ yarn dev                  43m     ·   893M  ~/…/js/web
                        └ nodemon.js              43m     ·    13M  ~/…/js/web
                          └ node --max_old_spa…   43m   10%   865M  ~/…/js/web
  main · pane 1       ▾ claude ✳ Ancient otter…    1d   10%   1.3G  ~/…/ab-car-widget
                        └ npm exec chrome-devt…    1d     ·     7M  ~/…/ab-car-widget
                          └ chrome-devtools-mcp    1d     ·    22M  ~/…/ab-car-widget
                        └ caffeinate -i -t 300     1m     ·     1M  ~/…/ab-car-widget
  main · pane 2       ▾ claude ✳ Export and re…   23h  2.4%   190M  ~/Work/terminal
                        └ sh ./run_main.sh        24m     ·   800K  ~/Work/terminal
                          └ python http_run.py…   10m  1.7%    27M  ~/Work/terminal
                        └ tail -f -n 0 main-ru…   19m     ·   368K  ~/Work/terminal
                        └ intelephense --stdio    47m     ·    43M  ~/Work/terminal
```

`j`/`k` move, `space` marks, `tab` folds a row's children away, `s` cycles the
sort, `x` sends **SIGTERM**, `X` sends **SIGKILL**, `↵` focuses the pane it came
from and closes the overlay, `r` refreshes (it refreshes itself every 2s too),
`q` or a second `F2` closes. A single row is signalled without a prompt — you
opened a kill list on purpose — while killing several marked rows asks once and
names them, because marks survive a cancel.

**`F2` is a toggle**, and so is `F1`. `map f2` is a kitty-level binding, so it
fires before the overlay ever sees the key — press it twice and you used to get
two lists stacked on each other, each needing its own `q`. `kitty.conf` now
unmaps the key while the overlay is focused (`map --when-focus-on
title:^Running$ f2`), so the second press reaches `kjobs`, which closes on it.
The cheat sheet already closed on any key and needed nothing but the unmap.

**Every row is a real command, and every real command gets a row.** A top-level
row is what you typed in that pane; nested under it is everything that command
has running — a Claude Code pane shows the agent, its MCP servers, its language
server, its `caffeinate`, and each shell command the agent has going right now.
The list opens with all of it visible; `tab` folds a row away when you want less.

Two kinds of process are walked through rather than listed. One is the pane's
own plumbing: kitty starts panes as `login … kitten run-shell --shell /bin/zsh`,
and an idle shell is not a job. The other is a `shell -c …` standing in front of
the command it was given — Claude Code runs every Bash tool call as one, so
without this the tree would be a wall of `zsh -c source snapshot-….sh …` with
the command you care about hidden one level under each. A shell handed a script
(`sh ./run_main.sh`) is a command in its own right and stays. Interpreters are
stripped the same way: `node /Users/…/v24.11.0/bin/yarn dev` is displayed as
what you actually ran, `yarn dev`.

**CPU and memory on a top-level row cover the whole subtree**, because that is
what a kill takes down: the `claude` row counts the agent plus its MCP servers
and language server — including the wrapper shells that were too dull to list.
A nested row counts only itself and what is under it. CPU is measured as a delta
between refreshes rather than `ps`'s lifetime average, so it reflects the last
two seconds — the first frame drawn still shows the average, and `·` means under
half a percent.

**Agent rows carry their session name** from the pane title, so four panes
running Claude Code are told apart by what they are working on rather than by
their directory. They are dimmed, sorted last in the default order, and the
agent row itself is left out of both the header count and the tab bar's marker —
what an agent is running still counts, since that is the part you did not
already know about.

`tab` folds a row's children away when a busy agent is burying everything else,
and opens it again. Folds are remembered across refreshes; anything that starts
while the list is open arrives expanded. **Killing one of those children signals
only that process**: children share their job's process group, so signalling the
group there would take the whole job down with it.

Killing a job, by contrast, signals its **process group**, so `yarn dev` takes
its children with it. If that group turns out to be the pane's own shell group,
only the one process is signalled — a kill here can never take a pane's zsh down
with it. `x` leaves the row saying `terminating…` until it dies or the list
forgets; something that ignores SIGTERM sits there until you press `X`.

`s` cycles the sort: tab order, then CPU, memory and age, shown in the header.
The default groups by tab and keeps agents last; the other three sort purely by
the number, agents included, since finding the heaviest thing is the point.

The tab bar carries the short version as `▸N`: N panes in that tab running
something. **Agents are deliberately not counted** — nearly every pane holds one
all day, so counting them would pin the marker at `▸4` and say nothing, and the
per-pane `✳ ◐` glyphs already cover them.

`▸N` counts panes busy in the *foreground*. The F2 list is broader: it also
finds what you backgrounded with `&`, which kitty itself cannot see (it reports
only a pane's foreground process group, and a tab bar redraw cannot afford a
`ps`). So a forgotten `sleep 300 &` shows up under F2 with no marker on its tab.

Overlays — pagers, `kdiff`, the cheat sheet — are listed under the pane they are
stacked on, because they are running something too. The F2 list is the exception:
it leaves itself and its own shell out. kitty does not report which window of a
pane is the base one (it reorders them as they are focused), so nothing here
tries to guess — every window of a pane is walked, and they share its number.

One kitty instance is one list: `listen_on` is per kitty PID, so a second kitty
app has its own.

`kjobs --json` prints the same rows, children included, for scripts and for
checking the classifier without reading a curses screen.

## Language servers

Every language server this machine uses is defined in one file:
`~/.claude/skills/lsp/.claude-plugin/plugin.json`. It auto-loads as a plugin
(`lsp@skills-dir`) with no marketplace entry and no `enabledPlugins` line —
`MANIFEST` already mirrors `.claude/skills/`, so it is backed up with
everything else without a separate entry.

Ten servers, each owning a disjoint set of extensions: `typescript` (`.ts`,
`.tsx`, `.js`, `.jsx`, `.mts`, `.cts`, `.mjs`, `.cjs`), `gopls` (`.go`),
`intelephense` (`.php`), `sourcekit` (`.swift`), `csharp` (`.cs`), `css`
(`.css`, `.less`), `scss` (`.scss`, `.sass`), `graphql` (`.graphql`, `.gql`),
`pyright` (`.py`, `.pyi`) and `bash` (`.sh`, `.bash`). The official `*-lsp`
plugins are switched off in `enabledPlugins` — two plugins both claiming
`.ts` was never tested, and one file listing every server beats five. A
duplicate extension claim fails silently, so it is worth re-checking that
they stay disjoint after any edit.

**`lspServers` only works from a plugin manifest.** Put the same block in
`settings.json`, or hand it to `--settings`, and it is silently ignored — no
error, the server just never registers. This is the single most
time-wasting thing to rediscover later.

**Only `${CLAUDE_PROJECT_DIR}` and `${CLAUDE_PLUGIN_ROOT}` expand.** Nothing
else does. `${HOME}` in a config value is passed through verbatim, and the
server then creates a directory *literally called* `${HOME}` next to whatever
it is working on. That is why `intelephense` still indexes to
`/tmp/intelephense`, and why anything needing a real `$HOME` path goes through
a wrapper script in `bin/` instead.

**Servers spawn lazily and die with their session.** A session in the
monorepo that made no LSP call spawned zero servers — confirmed. Cost is one
server per (session × language actually touched), which cuts both ways: four
agents all editing TypeScript means four `tsserver`s, which is why the
`typescript` entry carries `--max-old-space-size=4096`.

Every server gets `workspaceFolder: "${CLAUDE_PROJECT_DIR}"`, so it roots at
the project rather than whichever pane the agent happened to start in.
Before this, a Go file opened from another repo's pane came back with every
import broken.

**TypeScript is told not to answer early.** `typescript-language-server` runs
a syntax-only server beside the semantic one and lets it reply first, which
on a cold session means a confidently wrong hover — a const whose real type
is `TravelshiftCustomHeader.DEBUG` came back as `any`, and was still `any`
three seconds in. `useSyntaxServer: "never"` trades a ~6s first hover for a
true one. An agent has no way to tell a cold answer from a settled one.

**Go needs a generated `go.work`**, built fresh under `~/.cache/claude-lsp/`
because the monorepo has 7 modules and no workspace file of its own. It lives
deliberately outside the repo: a shell `go build` never sees it, so an
LSP-only `BrokenImport` will not reproduce on the command line. Two of those
modules — `fastly-wasm/html-scrubber` and `fastly-wasm/wonderpush-handler` —
both declare `module compute-starter-kit-go`, which makes `go list` fail for
the whole workspace, so `gopls-launch` de-duplicates on the declared module
path and drops one. The dropped module still gets full type info: gopls
builds a fallback module view from a file's own `go.mod` when the file falls
outside the workspace.

**C# routes to the nearest per-service `.sln`**, walking up from the *file you
open* rather than from wherever the session started. csharp-ls loads one
solution and picks it before it starts, so rooted at the monorepo it used to
find none and answer every query empty — confidently, not as an error, and the
rule "start C# agents inside the service" is the kind nobody remembers. A proxy
now chooses late: the first `.cs` file opened says which service is in play, and
the server is restarted against that solution and the session replayed into it.
Costs one restart, about 3s, on the first C# file of a session.
`src/dotnet/GlobalSolution.sln` is deliberately never selected — it fails
`MSB5023` on a stale `NestedProjects` GUID and is rejected by every
MSBuild-based tool, including `dotnet build`. That's a pre-existing monorepo
defect, not an LSP one. `--features metadata-uris` is on the csharp server so
`goToDefinition` on a compiled-package symbol yields a decompiled location
instead of nothing.

**GraphQL routes to the nearest config, and repairs it if it cannot be
loaded.** Rooting alone fixed nothing: the monorepo's config is unreadable
three times over — named `.graphql.config.yml` when cosmiconfig looks for
`graphql.config.*`, pointing at two schema files that do not exist, and
naming one that fails SDL validation on a duplicated field. All three fail
identically and silently, every response `null`. `graphql-launch` finds the
config and, only when graphql-config genuinely cannot load it, writes a
repaired copy under `~/.cache/claude-lsp/` — the same out-of-repo trick as
`go.work`. Every failure path in there falls back to the plain server.

**Sass has its own server.** `vscode-css-language-server` is single-file: it
returns `null` on a `$variable` defined in a sibling file, and all 137 of the
monorepo's SCSS imports are the legacy `@import` form.
`some-sass-language-server` resolves them. `.css` and `.less` stayed behind,
because some-sass matches the old server byte-for-byte on `.css` but answers
`null` on `.less`. Both need `unknownAtRules: "ignore"`, or every `@tailwind`
and every SCSS at-rule is flagged and buries the real diagnostics.

**Swift needs a build, not just a config.** sourcekit-lsp is syntax-only
without a compilation database, and `itvlive` is Xcode-project-only.
`xcode-build-server config …` generates a `buildServer.json`, but that alone
changes nothing — hover stayed `null` until one real `xcodebuild` populated
the DerivedData index store, after which it resolves types and crosses files.
`buildServer.json` embeds machine-specific paths, so it belongs in
`.gitignore`, not in a commit.

`intelephense`'s exclusion list works — temporarily excluding
`src/php/service-stays` dropped a query from 77 symbols to 67 — though most
of the listed globs target trees with essentially no PHP in them.

## Images in a pane

kitty draws images in the terminal, so a screenshot or a chart needs no
external viewer:

```bash
icat shot.png          # show an image (also accepts piped image data)
ilast                  # the newest image here - handy after an agent writes one
ilast ~/Desktop        # ...or the newest screenshot
iclear                 # wipe images out of the pane (they survive clear)
```

⌘-clicking an image link in output previews it in an overlay instead of opening
Preview.app (`~/.config/kitty/open-actions.conf`).

## Notifications

Two kinds, both native:

- **Agents.** `~/.claude/hooks/kitty-notify.py` fires when Claude Code is
  blocked on you — a permission prompt, a question — and when a turn that took
  ≥ 2 min finishes. Claude's own idle ping, which arrives a minute after a turn
  ends and says nothing the finish notification did not, is dropped. The banner
  names the worktree, and **clicking it focuses that pane**.
- **Everything else.** `notify_on_cmd_finish unfocused 10.0` — any command that
  runs longer than 10s in a pane you are not watching.

Nothing fires while the pane is on your screen, and every pane of the 2×2
counts — not just the one holding the cursor. Another app in front, another tab,
or an overlay drawn over the pane all count as not looking. Delivery goes
through remote control, so the escape code never touches the pty a TUI is
drawing on.

Claude Code's own notifications are off — `preferredNotifChannel:
"notifications_disabled"` in `settings.json`. They were a second, unexpiring
copy of the same events, titled `Claude Code` rather than naming the pane, and
they stacked up in Notification Center. Hooks are unaffected by that setting.

Every banner self-dismisses after 10s and leaves nothing in Notification
Center, so none of them ever waits to be clicked. That matters more than it
sounds: delivering a notification does not move focus, but *clicking* one does,
and a banner parked over your work is a banner you end up clicking. See
development.md 13 for the audit -- 190 banners in a day, none of which took
focus on its own.

That holds for every sender, not just this setup's own. A notification is
given an expiry on the way out by `~/.config/kitty/notifications.py`, which
kitty consults before it dispatches one: kitty's own command-finish banners and
an OSC 99 from any program in any pane are both capped at 10s, whatever they
asked for. **Editing that file needs kitty restarted** — a config reload will
not pick it up. Cold-start straight into your own workspace instead of the
startup 2×2:

```bash
kitty-session export > ~/.config/kitty/restored.conf   # just before quitting
⌘Q
kitty --session ~/.config/kitty/restored.conf
```

`⌘⌥S`, quit, reopen, `⌘⌥R` gets there too, but restore is additive — see
Session snapshots. development.md 13.1 has the mechanism.

`kitty-notify "title" "body"` sends one by hand from any script; `-u critical`
brings back the sticky style. `-e never` is overridden by the hook above while
it is installed.

## Session snapshots

Quitting kitty still kills every agent. What survives is the layout:

```bash
kitty-session save [NAME]      # snapshot now (default: latest)
kitty-session restore [NAME]   # rebuild it, resuming agents
kitty-session restore --dry-run
kitty-session restore --no-agents
kitty-session list
kitty-session export [NAME]    # a kitty session.conf, for cold start
```

`latest` is written for you — `session_watcher.py` snapshots on focus change, at
most once every 20 seconds — so after a quit it holds the workspace you quit out
of. `⌘⌥S` forces one, `⌘⌥R` restores.

A snapshot holds each tab's title and layout, every pane's working directory,
and which panes had an agent running. Restore rebuilds the tabs and panes,
`cd`s each one, and types `claude --continue` into the panes that had agents —
so if `--continue` finds nothing, you are left at a prompt in the right
directory rather than an empty pane. Snapshots live in
`~/.local/state/kitty-sessions`.

**Restore adds, it does not replace.** A launch always builds `session.conf`'s
2×2 first — `startup_session` is a static file and knows nothing about snapshots
— and restore replays over remote control, which needs kitty already running.
So `⌘⌥R` leaves those four idle shells beside the tabs it rebuilt, for you to
close. `export` skips the detour by turning a snapshot into a session file kitty
can start *from*:

```bash
kitty-session export > ~/.config/kitty/restored.conf
kitty --session ~/.config/kitty/restored.conf
```

Agent panes come out as `launch claude --continue`. A Dock or Spotlight launch
ignores `--session` and uses `startup_session`, so this is a terminal-invoked
start. Either route, two panes saved in the same directory both continue the
most recent conversation there; the other one is still on disk under `claude
--resume`.

Not a detach: nothing keeps running, `--continue` resumes a conversation rather
than a process tree, and a snapshot can be up to 20 seconds stale.

## Worktrees

Run from anywhere inside a repo:

```bash
wt my-feature                   # worktree + branch + agent, in THIS pane
workmux add my-feature          # ...in a new tab instead
workmux ls                      # what's alive
workmux dashboard               # TUI of every agent and its status
workmux merge                   # merge, then clean up worktree/tab/branch
workmux remove my-feature       # drop it without merging
```

Worktrees land in `../<project>__worktrees/<name>`.

### Four worktrees in the four panes: `wt`

`workmux add` always opens a **new tab** — one worktree, one tab, that's its
data model. To fill the launch grid instead, type this in the pane you want:

```bash
wt my-feature                       # worktree + branch + agent, in THIS pane
wt my-feature fix the flaky test    # ...with a starting prompt
wt -                                # cd back to the main checkout
wt -l                               # list worktrees (tab-completion works too)
```

Four panes, four worktrees, one tab. `wt` still lets workmux create the
worktree — so naming, base branch and the `wt-link` seeding are identical — it
just closes the tab workmux insists on and runs the agent here.

The agent is tracked by **pane**, so a `wt` worktree shows up in
`workmux dashboard` exactly like a tab one, and `ls` / `merge` / `remove` work
unchanged. `remove` only kills tabs named `wm-<name>`, so it won't touch your
grid. Do `wt -` first though, or you're left in a directory that no longer
exists.

### When you do want a tab

`workmux add my-feature` still gives you one, now with a **single** agent pane
rather than a grid — one cell either way. `/worktree` from inside Claude Code
does the same, since an agent can't repurpose the pane it's running in. For a
grid inside worktree tabs, chain splits in the `panes:` block of
`~/.config/workmux/config.yaml` (`horizontal` puts a pane beside, `vertical`
starts the row below); the commented-out example there is the 2×2.

### Jumping around

In `workmux dashboard`, the **Agents** tab (the default) lists running agents and
`Enter` jumps to the pane — inside your grid, no new tab. The **Worktrees** tab
lists worktrees on disk, and `Enter` there *opens* one, which means a tab. Use
`wt` for that instead.

**Agent status now shows in the tab titles**, which the old setup could not do at
all. workmux writes a `workmux_status` user variable; `tab_bar.py` surfaces it
through the `{custom}` placeholder in `tab_title_template`, and
`workmux_watcher.py` repaints the tab bar when it changes and clears
*waiting* / *done* once you actually look at the pane.

## What happens automatically

`workmux add` runs `wt-link`, which seeds the new worktree from the main
checkout:

- **`.idea/`** copied, minus per-window state (`workspace.xml`, `shelf/`,
  `caches/`, `httpRequests/`, `$CACHE_FILE$`). Run configs marked *Store as
  project file* come along.
- **Every gitignored `node_modules`, `vendor`, `.env`, `.venv`** found anywhere
  in the tree — discovered from git, not a hardcoded list. `node_modules` is
  symlinked (instant, no duplicate indexing); `.env` files are copied so
  per-worktree edits don't leak back.

On the monorepo that's ~30 paths in about 9 seconds. `⌥O` re-runs it before
opening the IDE, so hand-made `git worktree add` checkouts get seeded too. It's
idempotent — re-run `wt-link` any time.

`workmux remove` does **not** follow the symlinks; the shared `node_modules` is
safe.

One thing that is *not* configuration, and worth knowing before hunting for a
setting: **creating a kitty window over remote control brings the app to the
front on macOS**, `--keep-focus` or not. So an agent that runs `kdiff`, `wt` or
`workmux add` in a pane pulls kitty forward while you are in another app.
Notifications do not do this — see development.md 13 for the measurements.

## Which IDE

`⌥O` decides from the repo, in this order:

1. `WT_IDE` in `<repo>/.wtrc`
2. `.idea/php.xml` exists → PhpStorm
3. `composer.json` or `artisan` → PhpStorm
4. a `*.php` file in the top two levels → PhpStorm
5. otherwise → WebStorm

So `~/Work/guide` opens PhpStorm, `~/Work/monorepo` opens WebStorm. `⌥I` flips it.

## Hooks and overrides

| Where | For |
|---|---|
| `~/.config/wt/config.sh` | global: `WT_LINK_NAMES`, `WT_CLONE_NAMES`, `WT_IDEA_EXCLUDES`, `WT_IDE` |
| `<repo>/.wtrc` | same knobs, per repository (see `~/.config/wt/wtrc.example`) |
| `~/.config/wt/hooks/pre-ide`, `post-ide` | run around IDE launch; get `$WT_IDE`, `$WT_PATH`, `$WT_MAIN`. Drop the `.example` suffix to arm |
| `~/.config/kitty/local.d/*.conf` | any kitty setting; loaded last via `globinclude`, so it wins |
| `<repo>/.workmux.yaml` | per-project panes and hooks — template at `~/.config/wt/workmux-project-template.yaml` |

## Files

```
~/.config/kitty/kitty.conf          keys, colours, font, remote control
~/.config/kitty/session.conf        the startup 2x2
~/.config/kitty/tab_bar.py          agent status + busy panes in tab titles
~/.config/kitty/workmux_watcher.py  repaint + auto-clear on focus
~/.config/kitty/session_watcher.py  rolling session snapshots
~/.config/kitty/open-actions.conf   what CMD+click does with a link
~/.config/kitty/notifications.py    caps how long any notification lives
~/.config/kitty/local.d/*.conf      your overrides, loaded last (not backed up)
~/.config/workmux/config.yaml       agent, rebase merges, post_create → wt-link
~/.local/bin/wt-link                worktree seeding
~/.local/bin/wt-ide                 IDE detection + launch
~/.local/bin/wt-help                the cheat sheet (--plain for pipes)
~/.local/bin/kdiff                  whole-change-set diff in kitten diff
~/.local/bin/kjobs                  every command running in every pane (F2)
~/.local/bin/kitty-session          save / restore the workspace shape
~/.local/bin/kitty-notify           desktop notification tied to a pane
~/.config/wt/images.zsh             icat / ilast / iclear
~/.claude/hooks/kitty-notify.py     agent notifications (Claude Code hooks)
~/.config/wt/shell.zsh              the `wt` function - worktree in this pane
~/.local/bin/{webstorm,phpstorm}    IDE launchers (Toolbox or /Applications)
~/.config/lazygit/config.yml        theme, delta as the diff renderer, ESC quits
~/.config/diffnav/config.yml        banner off, unified by default
~/.claude/settings.json             permissions, hooks, plugins, status line
~/.claude/skills/                   skills, plus the lsp plugin (see above)
~/.claude/statusline.sh             the status line
~/.zshrc                            the CLAUDE_CODE_* strip
~/.claude/commands/*.md             the slash commands
```

## Backup and restore

Every file in the list above lives in this repo under `home/`, which mirrors
`$HOME` path for path. `./sync` moves them across:

```
./sync export     home -> repo    then scrubs secrets and scans
./sync install    repo -> home    backs up anything it overwrites
./sync status     dry run: what differs, in which direction
./sync scan       secret scan over home/ on its own
```

`MANIFEST` is the whitelist of tracked paths — nothing else can enter the repo,
which is how Claude Code's runtime state (`history.jsonl`, `projects/`,
`sessions/`, `.credentials.json`, caches, logs) stays out. `~/.claude/plugins/`
is left out on purpose: `settings.json` already carries `enabledPlugins` and
`extraKnownMarketplaces`, so Claude Code reinstalls them itself.

`~/.config/kitty/local.d/*.conf` is deliberately *not* mirrored, in either
direction — it is the machine-local override point, so publishing it would
defeat its purpose and `install` would delete another machine's overrides.

**The loop.** Edit config where it normally lives, then `./sync export && git
diff` to see what you changed, commit, push. Export is not automatic — until you
run it, the repo is stale. `./sync status` tells you whether it is.

**On a new machine.** In order:

```bash
# 1. Homebrew, then everything this setup takes from it (Brewfile at the root)
git clone https://github.com/arturkin/kitty-terminal.git ~/Work/terminal
cd ~/Work/terminal && brew bundle

# 2. the configs themselves
./sync install

# 3. Claude Code (native install; lands in ~/.local/bin, which .zshrc has on PATH)
curl -fsSL https://claude.ai/install.sh | bash

# 4. node via nvm, then the language servers the lsp plugin expects on PATH
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh | bash
nvm install 24 && npm i -g typescript typescript-language-server intelephense \
  pyright bash-language-server vscode-langservers-extracted \
  some-sass-language-server graphql-language-service-cli
go install golang.org/x/tools/gopls@latest
dotnet tool install -g csharp-ls          # needs a .NET SDK; DOTNET_ROOT is set in .zshrc

# 5. credentials and IDE
gh auth login
```

What each step is for: `kitty` and `workmux` are the terminal and the worktree
manager; `lazygit` is `F3`; `git-delta` renders every diff body (lazygit's
diff pane prints `delta: command not found` without it); `diffnav` is the
file tree behind `kdiff` and is the one optional item — `kdiff` falls back to
`kitten diff`; `gh` is how git authenticates; `jq` is parsed by every Claude
Code hook and the status line, so without it the sensitive-files guard and
the `git push` confirmation silently stop firing. WebStorm and PhpStorm are
found in `~/Applications` (Toolbox) or `/Applications`, whichever exists.
`sourcekit-lsp` ships with Xcode's command line tools. Monaco is a system
font. `python3` is used by `kitty-session`, `kjobs` and the notify hook and
comes with the command line tools too.

Claude Code plugins (`superpowers`, `workmux-status`, the PhpStorm plugin)
reinstall themselves from `enabledPlugins` and `extraKnownMarketplaces` in
`settings.json` on first launch. The MCP servers are printed as
`claude mcp add-json` lines at the end of `./sync install`.

Anything it would have overwritten is moved to `~/.config-backup-<timestamp>/`
first, and it prints where. Directory entries (`kitty/`, `wt/`, `commands/`,
`skills/`, `hooks/`) are replaced **wholesale**: a file sitting at home that the
repo has no counterpart for is removed, recoverable only from that backup. Two things it deliberately does not do, and says so
when it finishes:

- **Git credentials.** The repo's `.gitconfig` has `token`, `password` and
  friends stripped on every export — that is the whole point of the scan — so
  the restored file authenticates nothing. Use `gh auth login`.
- **MCP servers.** They are recorded in `home/.claude/mcp-servers.json` but not
  merged back, because `~/.claude.json` is mostly machine state (OAuth account,
  project history). `install` prints ready-to-paste `claude mcp add-json` lines.

`export` refuses to finish if it finds a GitHub/AWS/Slack/Anthropic token or a
private key anywhere under `home/`.

One file still hardcodes this machine's username: `settings.json`, in about 30 places
— 22 `Read(...)` deny rules, six one-off `Bash(...)` allow entries left over
from past sessions, and one `autoMode` note. A restore under a different
username needs a pass over that file. The deny rules are the part that matters,
and `deny-sensitive-files.sh` already covers every path they name without
depending on a username — it normalises `~` and `$HOME` itself and matches on
the path text — so that protection survives a restore even before you edit
them. `.zshrc` is username-independent.

## Required kitty settings

workmux's kitty backend drives the terminal over its remote-control API, so
these are not optional:

```
allow_remote_control yes
listen_on unix:/tmp/kitty-{kitty_pid}
enabled_layouts splits:equalize_on_window_close=y,grid,stack
```

`splits` is what workmux creates panes with; `grid` is what the startup 2×2
uses; `stack` is the zoom target for `⌥Z`. Check it works with `kitten @ ls` —
if that fails, workmux will too.

## One-time, already done

Agent status tracking is installed as a Claude Code plugin
(`workmux-status@workmux`) — hooks *and* the 6 workmux skills. **You never need
to run `workmux setup`.** To verify: `claude plugin list | grep -A3 workmux`.

workmux's two first-run prompts (Nerd Font check, status-tracking offer) are
answered and persisted in `~/.config/workmux/config.yaml`.

## Worth doing once

Open `~/Work/monorepo` in WebStorm and set the Node interpreter, ESLint/Prettier,
and mark `node_modules` Excluded if indexing drags. Tick *Store as project file*
on run configs you want everywhere. Every future worktree inherits it.

See `development.md` for why it's built this way.
