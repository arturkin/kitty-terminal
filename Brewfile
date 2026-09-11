# Everything this setup needs from Homebrew. `brew bundle` from the repo root.
# Language servers, node and the .NET SDK are not brew packages -- see README,
# "On a new machine".
tap "raine/workmux"

cask "kitty"          # the terminal; key bindings assume /Applications/kitty.app
# 0.1.252 or newer. Below that, a shell left in a deleted directory makes
# `kitty @ ls` report "cwd": null, which older workmux cannot parse -- every
# workmux command fails then, `wt` included. Unversioned because brew has no
# minimum-version constraint; `brew bundle` upgrades by default, which is
# what clears it.
brew "raine/workmux/workmux"
brew "lazygit"        # F3, CMD+SHIFT+K
brew "git-delta"      # diff body for lazygit, diffnav and kdiff
brew "diffnav"        # the tree view behind kdiff / CMD+SHIFT+G (kdiff falls back without it)
brew "gh"             # git credentials and the open-pr skill
brew "jq"             # every Claude Code hook and the status line parse JSON with it
brew "go"             # `go install` for gopls
