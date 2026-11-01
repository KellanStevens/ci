#!/usr/bin/env bash
# Check bun.lock for known vulnerabilities with `bun audit`.
#
# Reads IGNORE: advisory IDs to skip, separated by spaces or new lines. Only
# GHSA and CVE IDs are accepted, so that the value cannot add a flag.
set -euo pipefail
# The list is split on spaces, so stop "*" from matching files.
set -f

args=()
for id in $IGNORE; do
  if ! [[ "$id" =~ ^(GHSA(-[23456789cfghjmpqrvwx]{4}){3}|CVE-[0-9]{4}-[0-9]+)$ ]]; then
    echo "::error::\"$id\" is not an advisory ID."
    exit 1
  fi
  args+=("--ignore=$id")
done
bun audit "${args[@]}"
