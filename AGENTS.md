# AGENTS.md

- Write repository text in English.
- Use signed commits and Conventional Commit pull request titles.
- End each commit message with a `Co-authored-by` trailer for the agent that wrote it, such as `Co-authored-by: Codex <noreply@openai.com>` or `Co-authored-by: Claude <noreply@anthropic.com>`. These addresses link to the agents' GitHub accounts.
- Squash merges use the pull request description as the commit message. End the description with one such trailer for every agent that has committed to the pull request, and add trailers as new agents commit.
- Use pull requests for changes to the default branch.
- Request a squash merge with `/merge` after required checks and approval pass.
- Add project checks to CI when the project gains tooling or source code.
- Install tools with `mise install`; run `mise run lint` and `mise run test` before submitting changes.
- Run `mise run fix` to apply supported automatic fixes.
- Before changing GitHub Actions, read [docs/github-actions.md](docs/github-actions.md).
