#!/bin/sh
set -eu
if [ -z "${REX_BIN_DIR:-}" ]; then exit 0; fi
root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
state=$(mktemp -d)
trap 'rm -rf "$state"' EXIT
export XDG_STATE_HOME="$state" REX_BLOCK=block:rex-hook-test
output=$(printf '%s' '{"transcript_path":"/tmp/rex-transcript.jsonl","cwd":"/tmp/rex-project","session_id":"rex-session"}' |
  "$REX_BIN_DIR/rex" 'do' "$root/hooks/session-start.lua" agent=codex pid=$$)
[ -z "$output" ]
record=$state/rex-agent-relay/agents/rex-hook-test.json
[ -f "$record" ]
grep -F '"agent":"codex"' "$record" > /dev/null
grep -F '"pid":' "$record" > /dev/null
grep -F '"session_id":"rex-session"' "$record" > /dev/null
