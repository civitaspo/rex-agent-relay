---
status: accepted
date: 2026-11-01
---

# Register sources with SessionStart hooks

A relay must know which conversation the agent in the source pane is having. Rex knows the pane and its foreground process, but nothing about agent conversations. We find the source conversation from a registration that the agent's SessionStart hook writes, and we decide whether a pane is a target from its foreground process alone. We chose hooks over discovering conversations without them because hooks fail loudly, rely on documented interfaces, and keep the code small. Discovery would work with any agent but can pick the wrong conversation without anyone noticing.

## Context

- Rex can report a pane's foreground process (`pid`, `cwd`, executable path, `argv0`, and `script` for interpreters), its terminal title, and its screen text. It keeps no mapping from panes to agent conversations.
- Each agent kind stores conversations in its own undocumented format. Claude Code and Codex write JSONL transcripts. The relay already reads these transcripts, so it already depends on one undocumented format per agent kind.
- The first scope is Claude Code and Codex. pi and OpenCode are planned for later.
- The relay sends conversation text to another agent. Sending the wrong conversation is worse than refusing to send, because the receiving agent acts on it.

## Decision

1. **A source needs a registration.** When an agent starts a conversation in Rex, its SessionStart hook writes `agents/<pane>.json` under the state directory. The file records the pane's block ID from `REX_BLOCK`, the agent kind, and the hook payload, including `transcript_path` and `cwd`. The relay finds the source conversation only through this file.
2. **The registration file is the contract, not the hook.** The relay does not care what writes the file. Claude Code and Codex use the shell hook in this repository. A later agent kind can write the same file from its own extension mechanism.
3. **A target needs no registration.** A target only has to be running a supported agent. The relay decides whether a pane is a target, and which agent kind it runs, from the pane's foreground process name. Each agent kind lists the process names it can appear as.
4. **Codex sources run with `--no-daemon`.** The shared Codex daemon runs hooks without the pane's environment, so `REX_BLOCK` is missing and the hook cannot register the pane. A Codex pane started through the daemon can still be a target.
5. **A registration must belong to the agent now running in the pane.** The relay accepts a registration only when it names the same agent kind as the pane's foreground process and was written after that process started. Otherwise it stops with an error. This keeps a registration left behind by an earlier agent in the same pane from relaying an old conversation.

## Considered options

### SessionStart hooks (chosen)

Claude Code and Codex both document SessionStart hooks. The hook receives `transcript_path` on stdin and inherits `REX_BLOCK` from the pane, which together give an exact mapping from pane to conversation. Claude Code runs SessionStart again after `/clear`, so the registration follows the new conversation.

### Discovering conversations without hooks (rejected)

We prototyped discovery against Rex Beta (API revision 7), Claude Code 2.1.305, Codex 0.163.0 with daemon 0.166.0, and OpenCode 2.0.30. We ran one Claude Code, two Codex agents, and one OpenCode agent in the same directory. Discovery resolved a pane's conversation in up to five steps, stopping at the first step that found exactly one candidate:

1. **Process ID.** Claude Code writes `~/.claude/sessions/<pid>.json`, whose `sessionId` names the transcript. `/clear` updated `sessionId`. No other agent kind has a mapping like this.
2. **Directory and time.** Filter the agent's conversation store by the process's `cwd` and keep conversations updated after the process started. Exclude conversations already assigned to other live panes. Codex has `threads` in `~/.codex/state_5.sqlite`, with `cwd`, `originator = 'codex-tui'`, and `rollout_path`. OpenCode has `session_v2` in `~/.local/share/opencode/opencode.db`, with `directory` and `title`. pi writes `~/.pi/agent/sessions/--<cwd with separators replaced by ->--/<timestamp>_<id>.jsonl`.
3. **Terminal title.** Codex sets the title to `<threads.name> | <cwd basename>`. OpenCode sets it to `OC | <session_v2.title>`. pi shows a conversation name only after the user names the conversation.
4. **Screen text.** Strip whitespace from the pane's screen text and from each candidate's recent user messages, then look for the messages on screen. This step works with any agent kind.
5. **Ask the user.** Show the remaining candidates in the fuzzy finder and remember the choice for the pane.

What we observed:

- The two Codex conversations in the same directory had the same `created_at_ms`, and their `updated_at_ms` values differed by 1 ms, so time could not tell them apart. Titles and screen text could.
- For about three seconds after the first prompt, Codex shows a spinner in the title while it generates the conversation name.
- Immediately after `/new`, Codex shows only the directory name in the title and has no `threads` row until the first prompt. A rule that picks the most recently updated conversation in the directory would pick the previous conversation here.
- A Codex agent started through the daemon was found without any configuration, which hooks cannot do.
- Rex Lua has no `io.popen`. `rex.exec{...}` runs a command from an argument list, and `/usr/bin/sqlite3` on macOS could read both databases from it.
- One of several read-only `sqlite3` opens of the Codex database failed with `unable to open database file (14)` while Codex was running. A later run of 180 opens had no failures.
- OpenCode's foreground process is named `opencode.exe`.

We rejected discovery for these reasons:

- **Wrong results are silent.** When a clue stops matching, discovery falls through to a weaker step instead of failing. A changed title format or schema lowers accuracy without an error, and the relay may send another conversation from the same directory. A missing registration produces an error.
- **More undocumented interfaces.** Discovery depends on the transcript, the conversation store (`sessions/<pid>.json`, `state_5.sqlite`, `session_v2`), and the title format of each agent kind. Version numbers in `state_5` and `session_v2` suggest that these names change with migrations. Hooks are documented by the agents.
- **More code.** A five-step resolver with a store reader and title parser per agent kind needs far more code and tests than a short hook script. CI cannot run real agents to catch format changes.
- **Its main advantage is not needed yet.** Discovery supports agents without any extension point. The first scope has hooks, and pi offers a documented `session_start` extension event with `ctx.sessionManager.getSessionFile()`, so it can write the same registration.

## Consequences

- Users configure a hook for each agent kind. Codex sources must be started with `codex --no-daemon`. A source without a registration fails with an error that says how to register it.
- The relay keeps reading undocumented transcript formats. Registration does not reduce that dependency.
- Agents that run behind another program in the pane, such as tmux, ssh, or a container, are not supported. Their foreground process is not the agent, and their hook does not see `REX_BLOCK` or writes to another machine.
- Adding a target-only agent kind needs only its process names and start command. Adding a source-capable agent kind also needs a registrar and a transcript reader.

## When to revisit

Revisit this decision if any of these become true:

- We need a source agent kind that has no conversation-start extension point.
- Claude Code or Codex removes SessionStart hooks or stops passing `transcript_path`.
- The Codex daemon starts passing the pane environment to hooks, which would remove the `--no-daemon` requirement but not change this decision.

If discovery is reconsidered, keep these rules from the prototype:

- Never guess in auto mode. If steps 1 to 4 do not settle on one conversation, exit with an error instead of asking or picking one.
- Treat a Codex title without a conversation name as a new, empty conversation, and report nothing to relay.
- Pass values into SQL as hex literals, such as `CAST(X'...' AS TEXT)`, and run `sqlite3 -readonly -safe` through `rex.exec` with an argument list. Retry a failed open once or twice.
- Compare `procStart` in `~/.claude/sessions/<pid>.json` with the process start time, because process IDs are reused.
- Use screen text only in memory. Never write it to state, relay files, or logs.
- Record the agent versions each locator was verified against, and keep a manual smoke test to rerun after agent upgrades.
