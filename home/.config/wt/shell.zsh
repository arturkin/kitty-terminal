# Worktrees in the pane you are standing in, instead of a new tab.
#
# workmux always creates a window (a kitty tab) for a worktree -- `mode`
# accepts only `window` or `session`, and session mode is rejected outright by
# the kitty backend. So `wt` lets workmux create the worktree in a background
# tab, closes that tab again, and runs the agent right here. Status tracking is
# keyed on the terminal's own pane id ($KITTY_WINDOW_ID here), which workmux
# detects itself, so the agent still shows up in `workmux dashboard`.
#
# Locals are wt_-prefixed on purpose: zsh ties `path` to $PATH and `prompt` to
# the shell prompt, so `local path` silently empties $PATH inside the function.

wt() {
  emulate -L zsh
  setopt local_options no_nomatch

  local wt_agent=${WT_AGENT:-claude}
  local wt_name=$1
  shift 2>/dev/null

  if [[ -z $wt_name || $wt_name == (-h|--help) ]]; then
    print -r -- "usage: wt <name> [prompt ...]   run a worktree's agent in this pane"
    print -r -- "       wt -                     cd back to the main checkout"
    print -r -- "       wt -l                    list worktrees"
    return 1
  fi

  local wt_common wt_main
  wt_common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || {
    print -u2 -- "wt: not inside a git repository"
    return 1
  }
  wt_main=${wt_common:h}

  case $wt_name in
    -)  cd -- "$wt_main"; return ;;
    -l) workmux ls; return ;;
  esac

  local wt_prompt="$*"
  local wt_dir
  wt_dir=$(workmux path "$wt_name" 2>/dev/null)

  if [[ -z $wt_dir || ! -d $wt_dir ]]; then
    local -a wt_add=("$wt_name" -b -C)   # background window, no pane commands
    [[ -n $wt_prompt ]] && wt_add+=(-p "$wt_prompt")
    workmux add "${wt_add[@]}" || return 1
    workmux close "$wt_name" >/dev/null 2>&1
    wt_dir=$(workmux path "$wt_name" 2>/dev/null)
    [[ -d $wt_dir ]] || { print -u2 -- "wt: could not resolve worktree '$wt_name'"; return 1 }
  fi

  cd -- "$wt_dir" || return 1
  if [[ -n $wt_prompt ]]; then
    "$wt_agent" "$wt_prompt"
  else
    "$wt_agent"
  fi
}

_wt() {
  local -a wt_names
  wt_names=(${(f)"$(workmux ls 2>/dev/null | awk 'NR>1 && $1 != "main" {print $1}')"})
  _describe 'worktree' wt_names
}
compdef _wt wt 2>/dev/null
