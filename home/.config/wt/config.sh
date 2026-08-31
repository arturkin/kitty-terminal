# Sourced by wt-link and wt-ide before they do anything. Global overrides.
# A repo can override any of these again in <repo>/.wtrc.

# Basenames pulled from the main checkout into every new worktree.
# WT_LINK_NAMES="node_modules vendor .env .env.local .venv"

# Which of those get a real (reflink) copy instead of a symlink.
# Copies are isolated but cost ~4s per 20k files, so keep big trees symlinked.
# WT_CLONE_NAMES=".env .env.local"

# .idea entries that must not be inherited (per-window state).
# WT_IDEA_EXCLUDES='workspace.xml shelf/ caches/ sonarlint* httpRequests/ $CACHE_FILE$ .gitignore'

# Force one IDE everywhere, bypassing auto-detection.
# WT_IDE=webstorm
