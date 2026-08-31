# development.md

Why the terminal setup is built the way it is, and what was measured rather than
assumed. `README.md` is how to use it; this is why it looks like that.

Last verified: 2026-08-31, macOS 24.6.0 (Darwin), Apple Silicon. kitty 0.48.2,
workmux 0.1.248.

---

## 1. Component inventory

| Path | Role |
|---|---|
| `~/.config/kitty/kitty.conf` | keys, colours, font, remote control, tab bar |
| `~/.config/kitty/session.conf` | the startup 2×2 |
| `~/.config/kitty/tab_bar.py` | renders workmux's agent status into tab titles |
| `~/.config/kitty/workmux_watcher.py` | repaints the tab bar; clears status on focus |
| `~/.config/kitty/local.d/*.conf` | local overrides, loaded last via `globinclude` |
| `~/.config/workmux/config.yaml` | agent, rebase merges, `post_create` → `wt-link` |
| `~/.config/wt/shell.zsh` | the `wt` function — a worktree in the current pane |
| `~/.local/bin/wt-link` | worktree seeding (`.idea`, `node_modules`, `.env`) |
| `~/.local/bin/wt-ide` | IDE detection and launch |
| `~/.local/bin/wt-help` | the cheat sheet; `--plain` for pipes |
| `~/.zshrc` | strips inherited Claude Code session markers |

---

## 2. The layout model, and why this one cannot get stuck

This is the reason the setup is shaped the way it is, so it goes first.

**There are two ways a terminal can hold a pane layout.** It can store an
absolute size per node in a split tree, or it can store a *rule* — a fractional
bias, or nothing at all — and recompute geometry from the real window size on
every layout pass.

The setup this replaced stored absolute cell counts. That has a failure mode with
no recovery: corrupt one node's width and every row through it is wrong forever.
It was reproducible — closing a pane within ~350 ms of opening one assigned the
survivor the *tab's* width instead of its parent slot's — and it compounded,
283 → 425 → 638 columns in a 283-column tab. Because an inflated pane allocates
its grid at the inflated width, and scrollback was 200 000 lines, a corrupt tree
could also eat 20 GB of RAM. Nothing repaired it in place: resizing rescaled the
bad ratio along with everything else, `adjust-pane-size` only moved dividers
*inside* a node, and a surviving pane inherited its parent node's width rather
than the tab's.

kitty stores fractional biases only. Dump `layout_state` from `kitten @ ls` and
there are no cell counts in it — just `split_axis`, group ids and the biases. So
there is nothing to fall out of sync.

**Measured side by side before committing to the move**, same harness on both:

| Trigger | Previous setup | kitty |
|---|---|---|
| close a pane 0–300 ms after opening one | 5/5 corrupt at 50 ms; 2/2 at 150 ms | **12/12 clean, including 0 ms** |
| window resize, 60 → 430 columns and back | drift, then corruption | **6/6 perfectly even** |
| font-size cycling 6 → 24 pt (drives the same resize path) | breaks it | **7/7 even** |
| 25 font-size changes 30 ms apart, no settle | — | **even** |
| 40-cycle random split/close fuzz | 20 GB RAM, unresponsive | **105 → 125 MB** |
| deliberately skewed dividers | unfixable if the tree is inconsistent | **`layout_action equalize`, one action, exact** |
| reduce to one pane and rebuild | **impossible** — survivor inherits parent node width | **works** |

The consequence is that a large amount of machinery stopped being necessary and
was deleted: a script that polled until the window stopped resizing before
splitting, a divider re-centring script, a park-panes-into-tabs-and-rebuild
recovery tool, a 0.9 s cooldown guard on every pane-count change, and a
status-line widget that watched for grid corruption. All of it existed to work
around stored sizes.

### How to measure it again

`kitten @ ls` returns per-window `columns` and `lines` but no x/y, so the
invariant to check is the partition rather than positions: a healthy 2×2 has at
most two distinct column widths and two distinct heights, each appearing twice,
and the widths must sum with the dividers to the full tab width. ±1 on rows is
integer division, not a fault — 47 rows cannot split evenly in two.

```bash
kitten @ ls | python3 -c "import json,sys; d=json.load(sys.stdin); \
  print([(w['columns'],w['lines']) for w in d[0]['tabs'][0]['windows']])"
```

---

## 3. Startup: `session.conf`, and why `grid` rather than `splits`

`startup_session` declares the layout, so there is no script, no poll and no
retry. The tab uses the **`grid`** layout deliberately:

- `grid` has no tree at all. It arranges N windows into the nearest grid and
  derives every cell from the window size, so it re-flows correctly when a 5th
  pane appears and back again when it closes. Verified: 4 → 5 → 6 → 4 windows,
  each step a correct arrangement.
- `splits` is a binary tree (of biases, so still safe) and is what **workmux**
  creates panes with, which is why it stays in `enabled_layouts`.

A session file has no way to move focus mid-build, so it cannot construct a
particular *splits* shape — with `splits` you would get a 3-way T from four
`launch` lines, not a 2×2. `grid` makes the question moot. This is also why
`enabled_layouts` lists all three: layout is per-tab, so the startup tab can be
`grid` while workmux's tabs are `splits`.

One trap worth recording: building a 2×2 as *vsplit, then split each column
separately* creates two independent column trees whose horizontal dividers drift
apart on their own — a visibly misaligned middle line. A shared divider needs the
horizontal split at the top level. `grid` avoids the whole class of mistake.

`equalize_on_window_close=y` is set on `splits` so closing a pane re-evens the
rest without pressing anything; `⌥=` (`layout_action equalize`) is the manual
version.

---

## 4. Fonts

**Nothing to configure, and that is the point.** kitty rasterises with CoreText
on macOS — the same engine Terminal.app uses — so Monaco 13 comes out matching
the reference with no settings at all.

The reference is Terminal.app's **Pro** profile, read out of
`/System/Applications/Utilities/Terminal.app/Contents/Resources/Initial Settings/Pro.terminal`
rather than eyeballed: Monaco 13, `FontAntialias` true, background `NSWhite: 0 0.85`
(black at 85%), text `0.94758`, blur `0.0`. Neither `Pro` nor `Basic` defines any
`ANSIColor` key, so Terminal.app renders ANSI from its own built-in palette.

The setup this replaced used FreeType, and getting near CoreText took three
findings, none of which apply any more but all of which cost time:

- Monaco ships **embedded bitmap strikes** at 12/13/16/19 px. At 72 dpi 13 pt is
  exactly 13 px, so FreeType served a hand-tuned bitmap and ignored every
  antialiasing setting until `NO_BITMAP` forced the outline path.
- **Subpixel antialiasing was a mistake.** macOS has not done subpixel AA since
  Mojave, so `HorizontalLcd` could not match the reference by construction — it
  fringes every stem orange on one side and blue on the other. Measured as
  mean(|R−G| + |G−B|) over inked pixels: Terminal.app **1.0**, subpixel **105.8**,
  greyscale **0.0**. Edge softness (fraction of inked pixels between 15% and 85%
  coverage): Terminal.app 0.358, subpixel 0.624, greyscale 0.354.
- **FreeType stem darkening does nothing to a TrueType font.** It is implemented
  for the CFF, Type 1 and CID drivers only. Total glyph coverage was 47.741 with
  darkening off, at level 1, at level 4, and with the darkening amounts cranked
  to 10× — identical every time.

---

## 5. Colours

Background and text are Terminal.app's *Pro* values; opacity is 0.92 by
preference.

**Two separate causes of washed-out colour, and the bigger one is not the
palette.**

`inactive_text_alpha` dims inactive panes' text. The previous equivalent also cut
*saturation* to 0.9 alongside brightness 0.7 — and since three of four panes in a
2×2 are inactive, that was desaturating and darkening **75% of the screen**.
Catppuccin red `#f38ba8` arrived as `#aa697b`, a muddy mauve. Never desaturate;
dim only enough to mark focus. It is 0.88 now, brightness only.

The palette itself is pale by design. Measured with a colour library rather than
guessed, Catppuccin Mocha's ANSI slots sit at HSL lightness **0.73–0.86**:

| slot | hex | lightness |
|---|---|---|
| red | `#f38ba8` | 0.75 |
| green | `#a6e3a1` | 0.76 |
| yellow | `#f9e2af` | 0.83 |
| blue | `#89b4fa` | 0.76 |
| magenta | `#f5c2e7` | 0.86 |
| cyan | `#94e2d5` | 0.73 |

A hue carries its maximum chroma at l = 0.50, so at 0.8 every colour is most of
the way to white. That is what "washed out" is — nothing is wrong with the
rendering, the palette is pale. Raising *saturation* barely helps, because at
l = 0.8 there is no headroom for chroma. **Lightness is the knob.**

Mocha also ships `brights` **byte-identical** to `ansi`, so bold text gained
nothing at all.

`kitty.conf` therefore carries an explicit 16-colour palette rather than a theme
name: each chromatic slot pulled toward l = 0.50, brights toward 0.62 so bold
still reads as the brighter of the two, and black and white left alone since they
are greys with no hue to intensify.

| level | red | green | blue |
|---|---|---|---|
| as shipped | `#f38ba8` | `#a6e3a1` | `#89b4fa` |
| 0.35 | `#f25f88` | `#7de075` | `#5b97f9` |
| **0.60 (in use)** | `#f23f71` | `#5de152` | `#3a83f9` |
| 0.85 | `#f41d59` | `#3ce42e` | `#186efa` |

---

## 6. Window chrome, and the one thing that got worse

The native titlebar is **kept**, coloured to the background:

```
hide_window_decorations no
macos_titlebar_color background
```

This is a genuine regression and there is no way around it. The previous setup
drew real macOS traffic lights *inside the tab bar*, so it had close/minimise/
zoom and a draggable window without spending a row on chrome. kitty has exactly
two options and no third: decorations on (buttons and drag, ~28 px row) or
`titlebar-only` (no row, but **no buttons and no way to drag the window** — kitty
has no drag-by-body). Colouring the titlebar to the background is what fixes the
light-slab look that made it objectionable in the first place.

---

## 7. workmux on kitty

Detected automatically from `$KITTY_WINDOW_ID`. The backend drives kitty over its
remote-control API, so three settings are load-bearing:

```
allow_remote_control yes
listen_on unix:/tmp/kitty-{kitty_pid}
enabled_layouts splits:equalize_on_window_close=y,grid,stack
```

kitty exports `KITTY_LISTEN_ON` into every pane, which is how a bare `kitten @`
finds the socket without `--to`. If `kitten @ ls` fails, workmux will too — check
that first.

Verified working: `workmux ls` from a real repo returns the worktree table with
the kitty backend active.

**What this backend cannot do**, from its own source and guide:

- **Session mode is refused outright** — `create_session`, `switch_to_session`
  and friends all return *"Kitty does not have a session concept like tmux. Use
  the default window mode instead."* `~/.config/workmux/config.yaml` uses window
  mode (`panes:`), so this does not bite, but `--session` is not available.
- **No insert-after for tabs** — new tabs always append.
- **Scope is the OS window**, not a session: tabs in other OS windows are
  untouched by workmux commands.
- **Pane sizing is percentage only**; absolute cell sizes are unsupported because
  kitty has no fixed-cell splits.
- The backend is flagged **experimental**. tmux remains workmux's mature backend.

**Agent status in tab titles now works**, which the previous backend could not do
at all. workmux writes a `workmux_status` user variable per window;
`tab_bar.py` surfaces it through the `{custom}` placeholder in
`tab_title_template`, and `workmux_watcher.py` marks the tab bar dirty when the
variable changes and clears *waiting* / *done* when the pane takes focus.

`wt` itself is backend-agnostic: it lets workmux create the worktree in a
background tab, closes that tab, and runs the agent in the current pane. Status
tracking is keyed on the terminal's own pane id, which workmux resolves itself.

---

## 8. The Claude Code marker guard

A terminal launched from inside a Claude Code session donates that session's
markers to every shell it opens. New agents then print

```
⚠ Transcript saving is off — inherited CLAUDE_CODE_CHILD_SESSION marker
```

and point at the parent's messaging socket. `CLAUDE_CODE_EXECPATH` additionally
pins an outdated `claude` build.

**The guard keys on the parent process, not on the terminal.** The previous
version tested the terminal's own environment variable *and* the name of its
binary, which meant it silently stopped working the moment the terminal changed —
that is exactly how the leak reappeared during this migration, and it was
invisible because the guard failed open.

```zsh
if [[ -o interactive ]]; then
  _cc_parent="$(ps -o comm= -p ${PPID} 2>/dev/null)"
  if [[ "${_cc_parent:t}" != claude ]]; then
    unset CLAUDE_CODE_CHILD_SESSION CLAUDE_CODE_SESSION_ID ...
  fi
fi
```

An interactive shell whose parent is `claude` is Claude Code's own Bash tool and
genuinely is inside a session, so it keeps the markers. A pane the terminal
opened has `login`, a shell, or the terminal binary as its parent, so it does
not. Verified both ways: markers forcibly set on a shell whose parent is a shell
come back empty, and `ps -o comm= -p $PPID` inside Claude Code's Bash tool
returns exactly `claude`.

Two things it cannot reach: a shell opened before the fix (`source ~/.zshrc`) and
an agent already running (restart it).

OSC 7 — the working-directory report `⌥O` relies on — is emitted by kitty's own
shell integration, on by default. The hand-rolled `chpwd` hook that used to do it
is gone.

---

## 9. What the move cost

Recorded so nobody rediscovers these as bugs:

| Lost | Detail |
|---|---|
| **Session persistence / detach** | The big one. Panes do not outlive the app; quitting kills every agent. kitty has no session server and its author has declined to add one. tmux or `abduco` inside kitty is the only route back. `kitty-session` (§12.4) restores the *shape* — tabs, panes, directories — and resumes agents with `claude --continue`, which is not the same thing as a detach. |
| **Command palette** | No kitty equivalent. `kitten @` is scripting, not an interactive searchable action list. |
| **Right status line** | No per-window status area. The tab bar is templatable in Python, which is where agent status goes instead. |
| **Integrated title buttons** | §6. A titlebar row, or no buttons and no drag. |
| **Live font/palette knobs** | Nothing left to tune (§4), so the chords were dropped rather than ported. |

---

## 10. Known gaps

| Gap | Detail |
|---|---|
| workmux's kitty backend is experimental | Its own guide says "expect rough edges". Tab ordering appends only; session mode unsupported; scope is the OS window. tmux is the mature backend if this becomes a problem. |
| Wording | workmux still prints "created worktree and tmux window" under a non-tmux backend. Cosmetic. |
| Closing ≠ detaching, and there is no detaching | `confirm_os_window_close 2` asks before closing a multi-pane window. That is the only guard; there is no way to leave agents running. §12.4 rebuilds the layout afterwards; it cannot keep anything alive. |
| Session snapshots are up to 20s stale | `session_watcher.py` debounces to one snapshot per 20s, and only on focus change. A tab opened and quit inside that window is not in the file. `CMD+ALT+S` forces one. |
| `wt` depends on workmux internals | It leans on `add -b -C` + `close` keeping the worktree, and on cleanup matching tabs by name rather than worktree path. Verified against v0.1.248; an upstream refactor could change either. Source is cloned at `~/.claude/plugins/marketplaces/workmux` — re-check `src/workflow/cleanup.rs`, `src/command/close.rs` and `src/multiplexer/kitty.rs` after a `workmux update`. |
| A tab flickers when `wt` creates a worktree | `workmux add -b` builds a background tab that `workmux close` immediately removes. Harmless, briefly visible. |
| Orphaned dev servers | Four `yarn dev` processes were found reparented to PID 1, surviving days after their shells died. Not caused by any of this, but nothing reaps them either. |

---

## 11. How to verify a change

Nothing here has automated tests. What was actually run:

```bash
# kitty config parses (empty output = clean; bad keys DO surface here)
kitty --config ~/.config/kitty/kitty.conf 2>&1 | grep -iE 'unknown|invalid|bad '

# the startup 2x2 really is a 2x2, and stays one across a resize
kitten @ ls | python3 -c "import json,sys; d=json.load(sys.stdin); \
  print([(w['columns'],w['lines']) for w in d[0]['tabs'][0]['windows']])"
kitten @ resize-os-window --width 220 --height 70 --unit cells   # re-check

# no session markers leak into a pane
env | grep -c '^CLAUDE_CODE'            # expect 0 in a fresh pane
CLAUDE_CODE_CHILD_SESSION=x zsh -i -c 'echo [$CLAUDE_CODE_CHILD_SESSION]'  # expect []

# remote control, which workmux needs
kitten @ ls >/dev/null && echo ok

# workmux sees the right backend
workmux ls                               # from inside a git repo

# the cheat sheet renders and its keys match kitty.conf
wt-help --plain

# diff plumbing (should print the kitten diff command)
git config --global --get difftool.kitty.cmd

# images really render in a pane, not just in theory
kitten icat --detect-support && echo graphics ok

# a notification actually reaches the desktop, tied to this pane
kitty-notify -u low "probe" "if you can see this, the RC path works"

# snapshot round trip, without touching the live workspace
kitty-session save probe && kitty-session restore probe --dry-run
```

Test destructively in a **throwaway instance**, never the one you are working in:

```bash
kitty --listen-on unix:/tmp/kt-test.sock --instance-group kttest &
kitten @ --to unix:/tmp/kt-test.sock ls
```

Scrub `CLAUDE_CODE_*` from its environment first (`env -u ...`) or every pane it
opens inherits your session markers — §8, and it is how the leak happened.

---

## 12. Layered on top: diff, images, notifications, session snapshots

Four kitty capabilities the base setup did not use. Each is a thin wrapper over
something kitty already does, so there is little to rot.

### 12.1 `kdiff` — a whole change set in one view

`kitten diff` takes two **directories** as well as two files, and `git difftool
--dir-diff` hands it exactly that: two trees. One invocation therefore shows
every changed file in a single scrollable, syntax-highlighted, side-by-side
view, each file under its own heading — the file list and the diff are the same
surface, navigated with `n`/`p`.

```
git config --global diff.tool kitty
git config --global difftool.kitty.cmd 'kitten diff "$LOCAL" "$REMOTE"'
git config --global difftool.prompt false
```

`kdiff` adds three things worth having: it refuses outside a repo and *pauses*
so the message survives (a window spawned by a key binding would otherwise
close before you could read it), it short-circuits when the change set is empty
for the same reason, and `-w` / `-t` re-exec it in a new OS window or tab via
remote control. `CMD+SHIFT+G` is the `-w` path with the pane's cwd.

Untracked files never appear — `git diff` does not see them. That is git, not
kitty.

### 12.2 Images: `icat`, `ilast`

kitty's graphics protocol needs no setup, so this is only ergonomics:
`~/.config/wt/images.zsh` defines `icat`, `ilast` (newest image in a directory —
screenshots, charts, whatever an agent just wrote) and `iclear`, all guarded on
`$KITTY_WINDOW_ID` so a non-kitty shell sources the file harmlessly.

`open-actions.conf` makes a CMD+clicked image link preview in an overlay
instead of launching Preview.app. Verified with `kitten icat --detect-support`
in a real pane.

### 12.3 Notifications that know which pane

The naive route — a hook writing `kitten notify`'s escape code to `/dev/tty` —
puts raw bytes into a pty that a TUI (Claude Code) is drawing on, and
`--wait-till-closed` additionally *reads* the tty, competing with that TUI for
stdin. Both are avoided by going through remote control instead:

```
kitten @ kitten --match id:$KITTY_WINDOW_ID notify TITLE BODY
```

kitty itself handles the notification for that window, so nothing touches the
pty (checked with `kitten @ get-text` on the target pane: no leaked escapes),
and because the notification belongs to a window, clicking it focuses that
pane. `kitty-notify` wraps this, falling back to `/dev/tty` and then
`osascript` outside kitty.

`~/.claude/hooks/kitty-notify.py` is wired to three Claude Code hook events:

| Event | What it does |
|---|---|
| `UserPromptSubmit` | writes a start timestamp; prints nothing, because this event's stdout is injected into the model's context |
| `Notification` | Claude wants input or permission → notify, `critical` |
| `Stop` | turn ended → notify only if it ran ≥ 20s |

Both notifying events first ask kitty whether you are already looking at the
pane (`is_focused` on the window in `kitten @ ls`, which is false whenever kitty
is not the frontmost app) and stay silent if you are. `--identifier
claude-<session_id>` means a busy agent replaces its own banner rather than
stacking them.

`notify_on_cmd_finish unfocused 10.0` covers everything that is not an agent:
builds, installs, test runs.

### 12.4 `kitty-session` — the shape, not the processes

This does **not** undo §9's first row. Processes still die with kitty. What is
recoverable is the *shape*: tabs, their layout, every pane's working directory,
and which panes were running an agent — and an agent, unlike a shell, can be
put back with `claude --continue`.

Snapshots come from `kitten @ ls`, where the useful cwd is
`foreground_processes[].cwd` (the pane's own `cwd` is where it was *launched*,
which is `~` for the startup 2x2 and therefore useless). A pane counts as an
agent only if a `claude` process is running *now*; `last_reported_cmdline` still
says `claude` long after the agent exited, so it is not used.

Restore replays through remote control, which has two sharp edges:

- `@ launch --match` selects the **tab**, not the window, and `--next-to`
  selects the window inside it to split. There is no `--match-tab`.
- panes are recreated with `--keep-focus` and the saved active pane focused at
  the end, so a restore does not scatter focus while it builds.

Agents are resumed with `@ send-text "claude --continue\r"` into a freshly
launched shell rather than by launching `claude` as the pane's process. Two
reasons: typed-ahead input survives — zsh consumes it once it starts, so there
is no race to wait out — and if `--continue` finds no conversation you are left
at a prompt in the right directory instead of watching the pane close.

Snapshotting is driven by `session_watcher.py` on focus change, debounced to
20s. No daemon, no launchd, nothing to leak: `watcher` accepts multiple lines
and both watchers were confirmed to fire on the same window (workmux's
auto-clear still cleared its user vars while the snapshot was written).

The one real hazard is **erosion at quit**: closing a window changes focus,
which would snapshot a workspace that is halfway torn down. Hence `--guard`,
which refuses a snapshot with fewer panes than one written less than 60s
earlier. Verified by inflating `latest.json` to eight panes and re-saving: the
write was skipped.

`latest.json` records the kitty pid, so `restore` can say when a snapshot came
from the instance you are still sitting in. Named snapshots (`kitty-session
save before-refactor`) never expire.

---

## 13. Reference

- kitty config: <https://sw.kovidgoyal.net/kitty/conf/>
- kitty layouts: <https://sw.kovidgoyal.net/kitty/layouts/>
- kitty remote control: <https://sw.kovidgoyal.net/kitty/remote-control/>
- workmux kitty guide: `~/.claude/plugins/marketplaces/workmux/docs/src/content/docs/guide/kitty.mdx`
- workmux kitty backend: `~/.claude/plugins/marketplaces/workmux/src/multiplexer/kitty.rs`
