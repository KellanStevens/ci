#!/usr/bin/env bash
# Run the package.json scripts of a site with Bun, in order. Each one runs even
# if an earlier one failed, so that one run reports all failures.
#
# Reads SCRIPTS: script names separated by spaces or new lines.
set -euo pipefail
# The list is split on spaces, so stop "*" from matching files.
set -f

failed=()
for script in $SCRIPTS; do
  # Not a leading "-", so that a name cannot be a flag of bun.
  if ! [[ "$script" =~ ^[A-Za-z0-9:_][A-Za-z0-9:_-]*$ ]]; then
    echo "::error::\"$script\" is not a script name."
    exit 1
  fi
  echo "::group::bun run $script"
  status=0
  bun run "$script" || status=$?
  echo "::endgroup::"
  if [ "$status" -ne 0 ]; then
    echo "::error::bun run $script failed."
    failed+=("$script")
  fi
done
if [ "${#failed[@]}" -ne 0 ]; then
  echo "Failed: ${failed[*]}"
  exit 1
fi
