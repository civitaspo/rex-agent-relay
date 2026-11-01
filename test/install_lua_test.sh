#!/bin/sh
set -eu

root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
name=lua-5.1.5-lunajson-1.2.3-1
mkdir -p "$root/.mise/$name"

for archive in lua.tar.gz lunajson.src.rock; do
  cp "$MISE_PROJECT_ROOT/.mise/$name/"*.tar.gz "$root/.mise/$name/"
  cp "$MISE_PROJECT_ROOT/.mise/$name/"*.rock "$root/.mise/$name/"
  printf 'corrupt' >> "$root/.mise/$name/$archive"
  if MISE_PROJECT_ROOT="$root" sh mise-tasks/install-lua >"$root/output" 2>&1; then
    printf 'Corrupted %s was accepted.\n' "$archive" >&2
    exit 1
  fi
  if ! grep -F 'FAILED' "$root/output" >/dev/null; then
    cat "$root/output" >&2
    exit 1
  fi
done
printf '%s\n' 'Archive integrity tests passed.'
