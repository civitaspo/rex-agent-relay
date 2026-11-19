#!/bin/sh
set -eu
if [ -z "${REX_BIN_DIR:-}" ]; then exit 0; fi
: "${REX_SESSION:?Run this test in a Rex terminal}"
: "${REX_BLOCK:?Run this test in a Rex terminal}"
root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
state=$(mktemp -d)
trap 'rm -rf "$state"' EXIT
export XDG_STATE_HOME="$state"
pid=$("$REX_BIN_DIR/rex" 'do' --json -e '
  local terminal = assert(rex.call("com.superlogical.terminal.process", {
    session_id = os.getenv("REX_SESSION"), block_id = os.getenv("REX_BLOCK"), args = {}
  }))
  return assert(terminal.foreground).pid
')
record=$state/rex-agent-relay/agents/${REX_BLOCK#block:}.json
output=$(printf '%s' '{"transcript_path":"/tmp/rex-transcript.jsonl","cwd":"/tmp/rex-project","session_id":"rex-session"}' |
  "$REX_BIN_DIR/rex" 'do' "$root/hooks/session-start.lua" agent=claude pid="$pid")
[ -z "$output" ]
cp "$record" "$state/expected.json"
output=$(printf '%s' '{"transcript_path":"/tmp/nested.jsonl","cwd":"/tmp/rex-project","session_id":"nested-session"}' |
  "$REX_BIN_DIR/rex" 'do' "$root/hooks/session-start.lua" agent=codex pid="$((pid + 1))")
[ -z "$output" ]
cmp "$state/expected.json" "$record"
grep -F '"agent":"claude"' "$record" > /dev/null
grep -F '"session_id":"rex-session"' "$record" > /dev/null
