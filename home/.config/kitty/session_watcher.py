# Keeps ~/.local/state/kitty-sessions/latest.json in step with the workspace,
# so `kitty-session restore` after a quit rebuilds the tabs, panes, working
# directories and agents you had. Snapshots on focus change (which is when the
# layout has usually just changed), no more than once every SNAPSHOT_INTERVAL.
#
# --guard makes kitty-session drop a snapshot that is losing panes seconds
# after a fuller one, so the cascade of closes at quit cannot erode the file.
import os
import subprocess
import time

from kitty.boss import Boss
from kitty.window import Window

SAVE = os.path.expanduser('~/.local/bin/kitty-session')
SNAPSHOT_INTERVAL = 20
_last = 0.0


def _snapshot() -> None:
    global _last
    now = time.monotonic()
    if now - _last < SNAPSHOT_INTERVAL or not os.access(SAVE, os.X_OK):
        return
    _last = now
    # listen_on is unix:/tmp/kitty-{kitty_pid}, and we are in the kitty process
    env = dict(os.environ, KITTY_LISTEN_ON=f'unix:/tmp/kitty-{os.getpid()}')
    subprocess.Popen([SAVE, 'save', 'latest', '--guard'], env=env,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def on_focus_change(boss: Boss, window: Window, data: dict) -> None:
    if data.get('focused'):
        _snapshot()
