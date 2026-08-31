#r### Code diagnostics

ALWAYS Prefer LSP over Grep/Read for code navigation
- `workspaceSymbol` to find where something is defined
- `findReferences` to see all usages across the codebase
- `goToDefinition` / `goToImplementation` to jump to source
- `hover` for type info without reading the file

Use Grep only when LSP isn't available or for text/pattern searches (comments, strings, config).

After writing or editing code, check LSP diagnostics and fix errors before proceeding.

### e2e testing
ALWAYS prefer chrome MCP when available when asked to e2e or visually test the changes. Chrome extension is not installed.

### Code comments
Only leave short and precise comments for the code which is not obvious, hacky by definition. 
Do not leave comments related to decision making, unless asked explicitly.


