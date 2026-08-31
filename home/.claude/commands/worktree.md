---
description: Create a git worktree in its own tab with an agent (workmux add)
argument-hint: <branch-name> [-p "starting prompt"]
allowed-tools: Bash(workmux:*)
---

!`workmux add $ARGUMENTS`

Report the result in one line: the branch, the worktree path, and whether seeding succeeded. Do not summarise the whole output.

This opens a new tab, because an agent cannot repurpose the pane it is itself
running in. To put a worktree in an existing pane of the grid, the user types
`wt <name>` in that pane's shell instead.
