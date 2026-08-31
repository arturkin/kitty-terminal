#!/usr/bin/env python3
"""Desktop notifications for Claude Code agents, via kitty.

Wired to three hook events in ~/.claude/settings.json:

  UserPromptSubmit  stamps the turn's start time (no output, so no context)
  Notification      Claude is asking for input or permission -> notify
  Stop              the turn ended -> notify only if it was a long one

A notification is suppressed when you are already looking at the pane the
agent runs in (kitty reports per-window focus, so another app being in front
still counts as not looking). Clicking one focuses that pane.
"""
import json
import os
import re
import subprocess
import sys
import tempfile
import time

MIN_TURN_SECONDS = 20  # below this, a finished turn is not worth interrupting for
NOTIFY = os.path.expanduser("~/.local/bin/kitty-notify")


def stamp_path(session_id: str) -> str:
    safe = re.sub(r"[^A-Za-z0-9_-]", "", session_id) or "unknown"
    return os.path.join(tempfile.gettempdir(), f"claude-turn-{safe}")


def label(cwd: str) -> str:
    """Worktree name when we are in one, else the directory name."""
    m = re.search(r"([^/]+)__worktrees/([^/]+)", cwd or "")
    return f"{m.group(1)}/{m.group(2)}" if m else os.path.basename(cwd or "") or "claude"


def looking_at_pane() -> bool:
    win = os.environ.get("KITTY_WINDOW_ID")
    if not win:
        return False
    cmd = ["kitten", "@"]
    if os.environ.get("KITTY_LISTEN_ON"):
        cmd += ["--to", os.environ["KITTY_LISTEN_ON"]]
    try:
        out = subprocess.run(cmd + ["ls"], capture_output=True, text=True, timeout=5)
        if out.returncode != 0:
            return False
        for osw in json.loads(out.stdout):
            for tab in osw["tabs"]:
                for w in tab["windows"]:
                    if str(w["id"]) == win:
                        return bool(w.get("is_focused"))
    except Exception:
        return False
    return False


def notify(title: str, body: str, session_id: str, urgency: str = "normal") -> None:
    subprocess.run([NOTIFY, "-i", f"claude-{session_id}", "-u", urgency, title, body],
                   capture_output=True)


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
        return

    if looking_at_pane():
        return

    if event == "Notification":
        notify(f"Claude needs you · {where}", data.get("message", "waiting for input"),
               session_id, urgency="critical")
    elif event == "Stop":
        try:
            elapsed = time.time() - float(open(stamp).read())
            os.unlink(stamp)
        except (OSError, ValueError):
            elapsed = MIN_TURN_SECONDS  # unknown: treat as worth reporting
        if elapsed >= MIN_TURN_SECONDS:
            mins, secs = divmod(int(elapsed), 60)
            took = f"{mins}m {secs}s" if mins else f"{secs}s"
            notify(f"Claude finished · {where}", f"turn took {took}", session_id)


if __name__ == "__main__":
    main()
