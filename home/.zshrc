
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion


# bun completions
[ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH:$HOME/bin"
eval "$(/opt/homebrew/bin/brew shellenv)"
# The next line updates PATH for the Google Cloud SDK.
if [ -f "$HOME/Downloads/google-cloud-sdk/path.zsh.inc" ]; then . "$HOME/Downloads/google-cloud-sdk/path.zsh.inc"; fi

# The next line enables shell command completion for gcloud.
if [ -f "$HOME/Downloads/google-cloud-sdk/completion.zsh.inc" ]; then . "$HOME/Downloads/google-cloud-sdk/completion.zsh.inc"; fi

# go
export GOPATH=$HOME/go
export PATH=$PATH:$GOPATH/bin


#gcloud
source "/opt/homebrew/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/path.zsh.inc"
source "/opt/homebrew/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/completion.zsh.inc"
export GOOGLE_CLOUD_PROJECT="prod-ts"
#export PATH="$(brew --prefix)/opt/curl/bin:$PATH"
export PATH="$HOME/.local/bin:$PATH"

# A terminal launched from inside a Claude Code session donates that session's
# markers to every shell it opens. The result is the warning
#
#   Transcript saving is off -- inherited CLAUDE_CODE_CHILD_SESSION marker
#
# plus new agents pointed at the parent's messaging socket.
#
# The test is the PARENT PROCESS, not the terminal. The previous version keyed
# off the terminal's own environment variable and the name of its binary, so it
# silently stopped working the moment the terminal changed -- and it failed open,
# so the leak was invisible. A shell Claude Code itself spawned (its Bash tool) has
# `claude` as its parent and must keep the markers; a shell a terminal opened
# has `login`, a shell, or the terminal binary as its parent and must not.
if [[ -o interactive ]]; then
  _cc_parent="$(ps -o comm= -p ${PPID} 2>/dev/null)"
  if [[ "${_cc_parent:t}" != claude ]]; then
    unset CLAUDE_CODE_CHILD_SESSION CLAUDE_CODE_SESSION_ID \
          CLAUDE_CODE_MESSAGING_SOCKET CLAUDE_CODE_MESSAGING_TOKEN \
          CLAUDE_CODE_ENTRYPOINT CLAUDECODE CLAUDE_CODE_EXECPATH
  fi
  unset _cc_parent
fi

# OSC 7 (the working directory report the IDE button relies on) is emitted by
# kitty's own shell integration, which is enabled by default. The hand-rolled
# hook that used to live here was only needed because the previous terminal did
# not emit it.

# Worktree-in-this-pane helper (wt)
[[ -f "$HOME/.config/wt/shell.zsh" ]] && source "$HOME/.config/wt/shell.zsh"

# Inline image viewing (icat / ilast / iclear)
[[ -f "$HOME/.config/wt/images.zsh" ]] && source "$HOME/.config/wt/images.zsh"

# .NET: `brew install --cask dotnet-sdk` needs interactive sudo (a GUI admin
# prompt), which isn't available non-interactively, so SDK 10 was installed
# user-local via Microsoft's dotnet-install.sh instead of the cask's
# /usr/local/share/dotnet. An old SDK 8.0.422 still sits in ~/.dotnet --
# DOTNET_ROOT is what decides which one `dotnet` finds.
export DOTNET_ROOT="$HOME/.local/share/dotnet"
export PATH="$DOTNET_ROOT:$PATH"
export PATH="$HOME/.dotnet/tools:$PATH"
