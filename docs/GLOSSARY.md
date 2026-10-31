# Glossary

## Rex

**Rex session**: A group of windows listed in the Rex sidebar. It is distinct from an agent conversation. Avoid using "session" alone.

**Pane**: One terminal in a Rex window, identified by its block ID. Avoid "block" outside API references.

## Agents

**Agent**: A coding AI CLI process running in a pane.

**Agent kind**: A type of agent, such as Claude Code or Codex.

**Target-only agent kind**: An agent kind that can receive a relay but cannot be a source because its conversation cannot be read.

**Conversation**: A continuous exchange with an agent. Starting or clearing an agent begins a new conversation.

## Relay

**Relay**: The part of the source conversation after the last relay point, its changed files, and a note, sent together to the target.

**Note**: The instruction sent with a relay. A user writes it today. An agent may write it in a future auto mode.

**Auto mode**: A future mode in which an agent decides when to relay and writes the note. This project currently provides only the `peek` and `deliver` entry points. The `by` attribute distinguishes a human decision from an agent decision.

**Source**: The pane and agent sending a relay. Avoid "origin".

**Target**: The pane and agent receiving a relay.

**Pair**: Two panes that can relay to each other. A pane belongs to at most one pair. The panes may belong to different Rex sessions.

**Relay point**: The last position in a conversation included in a relay.

**Relay file**: A file containing the full relay when it is too long to paste into the target.

**Shared worktree**: A working directory used by both agents in a pair. A new target starts in the source's shared worktree.
