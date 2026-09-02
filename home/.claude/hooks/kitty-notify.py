#!/usr/bin/env python3
"""Desktop notifications for Claude Code agents, via kitty.

Wired to three hook events in ~/.claude/settings.json:

  UserPromptSubmit  stamps the turn's start time (no output, so no context)
  Notification      Claude is blocked on you -> notify
  Stop              the turn ended -> notify only if it was a long one

A notification is suppressed when the pane is on your screen: kitty frontmost,
the pane's tab current, nothing drawn over the pane. Every pane you can see in
a split counts as looked at, not only the one holding the cursor. Clicking a
notification focuses its pane.

Not every Notification event is a question for you - the idle ping arrives a
minute after a turn ends, which Stop already reported - so those stay quiet.

Urgency stays normal on purpose: critical makes macOS present the banner with
the legacy alert options instead of a self-dismissing banner, which leaves a
toast sitting over your work until you click it - and the click is what moves
focus to kitty.
"""
import json
import os
import re
import subprocess
import sys
import tempfile
import time

MIN_TURN_SECONDS = 120  # below this, a finished turn is not worth interrupting for
NOTIFY = os.path.expanduser("~/.local/bin/kitty-notify")

# Notification types that do not mean Claude is waiting on you. `idle_prompt`
# is the one that matters: Claude Code sends it messageIdleNotifThresholdMs
# (60s) after a turn completes if you have not typed since, so it is a second
# banner for the turn Stop just reported. The others are progress reports.
QUIET_NOTIFICATIONS = frozenset({
    "idle_prompt",
    "agent_completed",
    "auth_success",
    "computer_use_enter",
    "computer_use_exit",
    "elicitation_complete",
})


def stamp_path(session_id: str) -> str:
    safe = re.sub(r"[^A-Za-z0-9_-]", "", session_id) or "unknown"
    return os.path.join(tempfile.gettempdir(), f"claude-turn-{safe}")


def label(cwd: str) -> str:
    """Worktree name when we are in one, else the directory name."""
    m = re.search(r"([^/]+)__worktrees/([^/]+)", cwd or "")
    return f"{m.group(1)}/{m.group(2)}" if m else os.path.basename(cwd or "") or "claude"


def kitty_ls():
    """`kitten @ ls`, or None when kitty cannot be asked."""
    if not os.environ.get("KITTY_WINDOW_ID"):
        return None
    cmd = ["kitten", "@"]
    if os.environ.get("KITTY_LISTEN_ON"):
        cmd += ["--to", os.environ["KITTY_LISTEN_ON"]]
    try:
        out = subprocess.run(cmd + ["ls"], capture_output=True, text=True, timeout=5)
        return json.loads(out.stdout) if out.returncode == 0 else None
    except Exception:
        return None


def looking_at_pane() -> bool:
    """Whether this pane is on screen right now.

    kitty's per-window `is_focused` answers a different question: it means "the
    active window of its tab, and kitty is in front", so it is true for a pane
    in a background tab, and false for the three panes you can plainly see
    beside the cursor in a 2x2. Tab focus is the dependable half - kitty clears
    it when another app comes forward - so visibility is derived from the tab:
    it must be the focused one, this pane must be the top of its window group
    (an overlay hides what is under it), and under `stack`, where only one pane
    is drawn, it must be the focused window.
    """
    win = os.environ.get("KITTY_WINDOW_ID")
    tree = kitty_ls()
    if not win or tree is None:
        return False
    for osw in tree:
        for tab in osw.get("tabs", []):
            for group in tab.get("groups", []):
                ids = [str(w) for w in group.get("windows", [])]
                if win not in ids:
                    continue
                if not tab.get("is_focused") or ids[-1] != win:
                    return False
                if not tab.get("layout", "").startswith("stack"):
                    return True
                return any(str(w.get("id")) == win and w.get("is_focused")
                           for w in tab.get("windows", []))
    return False


def turn_length(stamp: str) -> str:
    """How long the turn took, or "" when it is not worth interrupting for.

    A missing stamp means this Stop belongs to no turn we timed - most often a
    second Stop for a turn already reported - so it stays quiet rather than
    inventing a duration.
    """
    try:
        with open(stamp) as f:
            elapsed = time.time() - float(f.read())
    except (OSError, ValueError):
        return ""
    try:
        os.unlink(stamp)
    except OSError:
        pass
    if elapsed < MIN_TURN_SECONDS:
        return ""
    mins, secs = divmod(int(elapsed), 60)
    return f"{mins}m {secs}s" if mins else f"{secs}s"


def notify(title: str, body: str, session_id: str) -> None:
    subprocess.run([NOTIFY, "-i", f"claude-{session_id}", title, body], capture_output=True)


def main() -> None:
    try:
        data = json.load(sys.stdin)
    except Exception:
        return
    event = data.get("hook_event_name", "")
    session_id = data.get("session_id", "")
    where = label(data.get("cwd", ""))
    stamp = stamp_path(session_id)

    if event == "UserPromptSubmit":
        try:
            with open(stamp, "w") as f:
                f.write(str(time.time()))
        except OSError:
            pass
    elif event == "Notification":
        if data.get("notification_type") in QUIET_NOTIFICATIONS:
            return
        if not looking_at_pane():
            notify(f"Claude needs you · {where}",
                   data.get("message", "waiting for input"), session_id)
    elif event == "Stop":
        took = turn_length(stamp)
        if took and not looking_at_pane():
            notify(f"Claude finished · {where}", f"turn took {took}", session_id)


if __name__ == "__main__":
    main()
