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
Use coderabbit CLI for code reviews after changes are completed from your end before handing over

## Delegation
Delegate to the `scout` agent for "where is X defined/used/configured" sweeps
that span 5+ files, when only the conclusion is needed and not the file
contents. Do not delegate a lookup you can answer in one or two reads — a
subagent pays its own system prompt, so delegating a small search costs more
than doing it.

## e2e testing
ALWAYS prefer chrome MCP when available when asked to e2e or visually test the changes. Chrome extension is not installed.

## Code comments
Only leave short and precise comments for the code which is not obvious, hacky by definition. 
Do not leave comments related to decision making, unless asked explicitly.

@RTK.md
