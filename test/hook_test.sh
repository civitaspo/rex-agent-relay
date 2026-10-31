set -eu
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
printf '{"session_id":"test","transcript_path":"/tmp/log","cwd":"/tmp"}' | XDG_STATE_HOME="$root" REX_BLOCK=block:test-123 ./session-start.sh claude
grep -F '"agent":"claude","block_id":"block:test-123"' "$root/rex-agent-relay/agents/test-123.json" > /dev/null
grep -F '"transcript_path":"/tmp/log"' "$root/rex-agent-relay/agents/test-123.json" > /dev/null
printf '{}' | env -u REX_BLOCK XDG_STATE_HOME="$root" ./session-start.sh codex
