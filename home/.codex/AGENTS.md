## Code diagnostics

ALWAYS Prefer LSP over Grep/Read for code navigation
- `workspaceSymbol` to find where something is defined
- `findReferences` to see all usages across the codebase
- `goToDefinition` / `goToImplementation` to jump to source
- `hover` for type info without reading the file

Use Grep only when LSP isn't available or for text/pattern searches (comments, strings, config).

After writing or editing code, check LSP diagnostics and fix errors before proceeding.

## Tools
use gh CLI for github 
Use CodeRabbit CLI for code reviews after changes are completed from your end before handing over

## e2e testing
ALWAYS prefer chrome MCP when available when asked to e2e or visually test the changes. Chrome extension is not installed.

## Code comments
Only leave short and precise comments for the code which is not obvious, hacky by definition. 
Do not leave comments related to decision making, unless asked explicitly.

## RTK

Prefix every shell command with `rtk`: `rtk git status`, `rtk cargo test`,
`rtk npm run build`, `rtk ls src/`. Keep the prefix inside chains:
`rtk git add . && rtk git commit -m "msg"`. Commands RTK has no filter for
run as-is, so the prefix is always safe.

Command output is condensed to save tokens while retaining failures and other
actionable signals. Treat it as the complete result unless it is empty when
output was expected, contradicts its exit code, or is garbled. In those cases,
run `rtk recall <hash>` or repeat the command as `rtk proxy <cmd>`.

- `rtk gain` / `rtk gain --history` shows measured token savings.
- `RTK_DISABLED=1 <cmd>` bypasses RTK once.
- `rtk discover` finds prior commands RTK could have condensed.
