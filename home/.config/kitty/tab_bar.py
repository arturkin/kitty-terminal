# Draws the {custom} part of tab_title_template: workmux's agent status, plus
# a marker for panes running a non-agent command. See README, "What is running".
#
# Reads kitty's in-process window objects only -- a subprocess in the render
# path would stall the tab bar on every redraw.
import os

from kitty.fast_data_types import get_boss

# A pane's own plumbing rather than a job: kitty starts panes as
# `login -f -l -p USER kitten run-shell --shell /bin/zsh`.
SHELLS = {
    'zsh', '-zsh', 'bash', '-bash', 'sh', '-sh', 'fish', '-fish', 'dash',
    'login', '-login', 'kitten', 'kitty',
}
AGENTS = {'claude'}
BUSY_MARKER = ' ▸'


def busy_panes(tab):
    """Panes in this tab running a command that is not a shell or an agent."""
    count = 0
    for window in tab:
        try:
            # Overlays report the underlying pane's processes, not their own.
            if window.overlay_parent is not None or window.at_prompt:
                continue
            # `(zsh)` is what a shell still exec'ing reports as its argv.
            names = {
                os.path.basename(p['cmdline'][0]).strip('()')
                for p in window.child.foreground_processes if p.get('cmdline')
            }
        except Exception:
            continue  # a pane whose child died mid-redraw is not a job
        if not names - SHELLS or names & AGENTS:
            continue
        count += 1
    return count


def draw_title(data):
    tab = get_boss().tab_for_id(data['tab'].tab_id)
    if not tab:
        return ''
    out = ''
    for window in tab:
        status = window.user_vars.get('workmux_status', '')
        if status:
            out = ' ' + status
            break
    busy = busy_panes(tab)
    if busy:
        out += f'{BUSY_MARKER}{busy}'
    return out
