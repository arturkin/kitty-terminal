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
| `F1` or `⌥/` | **cheat sheet** — every shortcut and command, as an overlay |
| `F2` | **what is running** — every pane's jobs; kill them or jump to one |

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

## What is running

`F2`, or `kjobs` in a shell. Every command running in every pane of this kitty,
what it is costing, and a way to kill it:

```
 Running (1)  ·  11% cpu  ·  2.3G              2 agents  ·  sort: tab

  yarn dev · pane 1   ▾ yarn dev                  43m     ·   893M  ~/…/js/web
                        └ nodemon.js              43m     ·    13M  ~/…/js/web
                          └ node --max_old_spa…   43m   10%   865M  ~/…/js/web
  main · pane 1       ▸ claude ✳ Ancient otter…    1d   10%   1.3G  ~/…/ab-car-widget
  main · pane 2       ▸ claude ✳ Export and re…   23h  2.4%   190M  ~/Work/terminal
```

`j`/`k` move, `space` marks, `tab` opens a row's children, `s` cycles the sort,
`x` sends **SIGTERM**, `X` sends **SIGKILL**, `↵` focuses the pane that row came
from and closes the overlay, `r` refreshes (it also refreshes itself every 2s),
`q` closes. A single row is signalled without a prompt — you opened a kill list
on purpose — while killing several marked rows asks once and names them, because
marks survive a cancel.

Rows are the command you typed, not the process tree under it. A pane running
Claude Code holds five processes — the agent, two MCP servers, a language
server, a `caffeinate` — and this shows one row: `claude`. It gets there by
walking down from the pane's child treating shells as transparent (kitty starts
panes as `login … kitten run-shell --shell /bin/zsh`, so those are plumbing too)
and stopping at the first real command. `node /Users/…/v24.11.0/bin/yarn dev` is
displayed as what you actually ran, `yarn dev`.

**CPU and memory cover the whole subtree**, because that is what a kill takes
down: the `claude` row counts the agent plus its MCP servers and language
server. CPU is measured as a delta between refreshes rather than `ps`'s
lifetime average, so it reflects the last two seconds — the first frame drawn
still shows the average, and `·` means under half a percent.

**Agent rows carry their session name** from the pane title, so four panes
running Claude Code are told apart by what they are working on rather than by
their directory. They are dimmed, sorted last in the default order, and left
out of both the header count and the tab bar's marker.

`tab` opens a row to show what is under it, which is how you find out that the
865M in a `yarn dev` row is one `node` child, or which MCP server an agent is
leaking. **Killing one of those children signals only that process**: children
share their job's process group, so signalling the group there would take the
whole job down with it.

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

Overlays — pagers, `kdiff`, the F2 list itself — are not panes and hold no jobs,
so they never appear as rows. One kitty instance is one list: `listen_on` is per
kitty PID, so a second kitty app has its own.

`kjobs --json` prints the same rows, children included, for scripts and for
checking the classifier without reading a curses screen.

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

- **Agents.** `~/.claude/hooks/kitty-notify.py` fires when Claude Code asks for
  input or permission, and when a turn that took ≥ 20s finishes. The banner
  names the worktree, and **clicking it focuses that pane**.
- **Everything else.** `notify_on_cmd_finish unfocused 10.0` — any command that
  runs longer than 10s in a pane you are not watching.

Nothing fires while you are actually looking at the pane: kitty reports
per-window focus, and being in another app counts as not looking. Delivery goes
through remote control, so the escape code never touches the pty a TUI is
drawing on.

`kitty-notify "title" "body"` sends one by hand from any script.

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
~/.config/kitty/local.d/*.conf      your overrides, loaded last
~/.config/workmux/config.yaml       agent, rebase merges, post_create → wt-link
~/.local/bin/wt-link                worktree seeding
~/.local/bin/wt-ide                 IDE detection + launch
~/.local/bin/wt-help                the cheat sheet (--plain for pipes)
~/.local/bin/kdiff                  whole-change-set diff in kitten diff
~/.local/bin/kjobs                  what is running in every pane (F2)
~/.local/bin/kitty-session          save / restore the workspace shape
~/.local/bin/kitty-notify           desktop notification tied to a pane
~/.config/wt/images.zsh             icat / ilast / iclear
~/.claude/hooks/kitty-notify.py     agent notifications (Claude Code hooks)
~/.config/wt/shell.zsh              the `wt` function - worktree in this pane
~/.local/bin/{webstorm,phpstorm}    launchers
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

**On a new machine.** Install kitty, workmux, Claude Code and `diffnav`
(`brew install diffnav`, optional — `kdiff` falls back without it), then:

```
git clone https://github.com/arturkin/kitty-terminal.git ~/Work/terminal
cd ~/Work/terminal && ./sync install
```

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
private key anywhere under `home/`. Paths are absolute and user-specific
(`/Users/arturkin/...` appears in `.zshrc` and `settings.json`), so a restore
under a different username needs a pass over those two files.

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
