#!/bin/sh
set -eu
[ -n "${REX_BLOCK:-}" ] || exit 0
case "$REX_BLOCK" in block:*) id=${REX_BLOCK#block:} ;; *) exit 1 ;; esac
case "$id" in ''|*[!a-zA-Z0-9-]*) exit 1 ;; esac
case "${1:-}" in claude|codex) kind=$1 ;; *) exit 1 ;; esac
dir=${XDG_STATE_HOME:-"$HOME/.local/state"}/rex-agent-relay/agents
mkdir -p "$dir"
tmp=$(mktemp "$dir/.${id}.XXXXXX")
trap 'rm -f "$tmp"' EXIT HUP INT TERM
{ printf '{"agent":"%s","block_id":"%s","hook":' "$kind" "$REX_BLOCK"; cat; printf '}'; } > "$tmp"
mv "$tmp" "$dir/$id.json"
