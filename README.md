# rex-agent-relay

Relay the new part of a Claude Code or Codex conversation to another agent in Rex, together with changed file paths and a note. Both agents work in the same directory. See the [glossary](docs/GLOSSARY.md) for the terms used here.

## Requirements

- Rex Beta. Its terminals provide `REX_BIN_DIR`, which the input window uses to find `rex`. To run the examples from another terminal, add the `rex` CLI to your `PATH` or use its absolute path.
- Claude Code and Codex with SessionStart hooks enabled. Start Codex sources with `codex --no-daemon` so the hook receives the pane environment.
- `fzf`, or another fuzzy finder that reads candidates from stdin and writes the selected line to stdout.

## Install

1. Clone the repository, for example with `ghq get civitaspo/rex-agent-relay`.
2. Add the repository directory to `package.path` in `~/.config/rex/init.lua` and register the actions. Replace the path if your clone is elsewhere.

   ```lua
   package.path = os.getenv("HOME") .. "/src/github.com/civitaspo/rex-agent-relay/?.lua;" .. package.path
   require("rex-agent-relay").setup{ key = "cmd+shift+r" }
   ```

3. Run `rex config reload`.
4. Add a SessionStart command hook to `~/.claude/settings.json` and `~/.codex/hooks.json`. Keep any existing hooks. Replace the path with the path to your clone.

   Claude Code:

   ```json
   {"type":"command","timeout":5,"command":"$HOME/src/github.com/civitaspo/rex-agent-relay/session-start.sh claude"}
   ```

   Codex:

   ```json
   {"type":"command","timeout":5,"command":"$HOME/src/github.com/civitaspo/rex-agent-relay/session-start.sh codex"}
   ```

   Place each command in a `hooks.SessionStart` entry's `hooks` array. Approve the Codex hook with `/hooks` if required. Restart the agent in Rex so that the hook registers its conversation. Codex runs SessionStart when its first prompt starts a conversation. Outside Rex, the hook does nothing.

The hook stores the agent's SessionStart data under `${XDG_STATE_HOME:-~/.local/state}/rex-agent-relay/agents`. Relay points and pairs are stored in the same state directory. Configure these files and the outbox with permissions appropriate for conversation data.

To update, pull the repository and run `rex config reload`. You can manage the clone, Rex configuration, and hooks with home-manager.

## Send a relay

Focus an agent pane and press `cmd+shift+r`, or run **Agent Relay: Send** from the command palette. If no live pair exists, select an agent kind to start beside the source. Enter a one-line note and press Enter. An empty note is allowed when the conversation has changed.

Use **Agent Relay: Change Pair** to pair the source with an existing agent pane, including one in another Rex session. Each pane belongs to one pair. A new pair replaces each pane's old pair.

The target receives the conversation in an `<agent-relay>` tag, followed by the note. The `by` attribute identifies who chose the relay. Changed files appear at the end of each turn as `[refs: edited path; wrote path]`. A relayed conversation is not sent back to its source, though its note remains visible as a relayed note.

If the target is no longer running its agent, the relay does not write to its shell. A new target starts in the source's latest working directory. Codex targets start with `--no-daemon` so their SessionStart hook can register the pane. Both agents can edit the same files.

## Peek and deliver

`peek` prints the next conversation delta without changing the relay point or pair:

```sh
rex do /path/to/rex-agent-relay/relay.lua mode=peek source=block:...
```

```text
source: claude ~/src/foo (…a1b2c3)
target: codex ~/src/foo (…d4e5f6)
until: 123456
2 messages, 1 files since last relay

user: Compare the designs.

claude: I compared them.

[refs: edited src/a.ts]
```

`target: none` means there is no live pair. The first four lines are the header. The remainder is the same conversation text included in the relay. `until` is the byte position after the last complete transcript line read.

`deliver` reads a plain-text note from stdin and sends without opening a window or fuzzy finder:

```sh
printf '%s\n' 'Review the design and list the risks.' |
  rex do /path/to/rex-agent-relay/relay.lua mode=deliver source=block:... until=123456 kind=codex by=auto
```

`source` is required. `until` is optional. Pass the value from `peek` to exclude later transcript entries. `kind` selects the agent to start if no pair exists. It defaults to the other agent kind. `by` is `auto` by default and can be `human` or `auto`. To send without a note, redirect stdin from `/dev/null`.

Both commands exit with `0` when there is content to peek or a relay was sent, `2` when there is nothing to relay, and `1` on error. Errors go to stderr. `send` uses the same exit codes.

## Configuration

Set these variables in your login shell's startup files.

| Variable | Default | Purpose |
| --- | --- | --- |
| `REX_AGENT_RELAY_FUZZY_FINDER` | `fzf` | Command used to select a kind or pane. Arguments are allowed. |
| `REX_AGENT_RELAY_INLINE_MAX` | `20000` | Maximum relay size in bytes before writing a relay file. |
| `REX_AGENT_RELAY_OUTBOX_DIR` | `<state directory>/outbox` | Directory for relay files. |

For long relays, the target receives the file path and a summary of changed files. The file contains the full relay. Relay files are not deleted automatically. Claude Code may ask permission to read the outbox outside its working directory. Add the outbox to `permissions.additionalDirectories` if appropriate.

## Limitations

- Changed files come from Claude's editing tools and Codex `FileChange` records. Shell commands that change files are not included.
- The relay reads complete JSONL lines only. Transcript formats and Rex Beta APIs may change.
- Only panes on the same Rex server are supported. Rex cannot move a pane between sessions.
- The input window accepts a single-line note. `deliver` accepts multiple lines.
- Do not run concurrent relays against the same state directory. Pair and relay point updates are not synchronized across processes.
- Rex queues terminal writes. The agent may exit between a foreground check and receipt of the text. Check the target before retrying a failed relay because a failed submission may already have pasted text.
- A new pane receives the relay at startup, so its relay point advances when Rex creates the pane. If the agent fails to start, inspect the pane and retry manually; a pane waiting for registration blocks further relays until it registers or is closed.

## Verification

The transcript and hook checks run in CI. With Rex installed, run `rex do test/transcript_test.lua` and `sh test/hook_test.sh` from the repository root.

Verified locally with Rex Beta: piped stdin and exit code 2, `peek`, cross-session pairing with fzf, floating-layer note input, and bracketed-paste delivery to Claude Code and Codex. Claude Code 2.1.305 and Codex 0.163.0 SessionStart hooks and new target startup were tested in isolated workspaces. Codex must use `--no-daemon`: the shared daemon does not pass the pane environment to its hooks.

## Future auto mode

A future caller can trigger on an agent turn ending, run `peek`, ask a judge agent whether to relay and what note to write, and call `deliver` with the returned `until`. It can use `by="auto"` to count automatic relays and stop after a configured number of round trips. This repository does not implement the trigger, judge, or loop prevention.
