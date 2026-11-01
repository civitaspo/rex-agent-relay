# rex-agent-relay

Install the tools with `mise install`, then use these commands:

- `mise run lint` checks workflows and source files.
- `mise run fix` applies supported automatic fixes.
- `mise run test` runs the project tests.

The lint task uses ast-grep to flag direct Lua shell execution and dynamic code
loading. These syntax-based rules do not trace data flow or calls through aliases.
