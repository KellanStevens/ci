#!/usr/bin/env bash
# Tell whether any file matches one of the paths.
#
# Usage: match-paths.sh < files
# Reads PATHS: one path on each line. A path is a file, a directory (it matches
# everything below it), or a glob where * also matches /. Spaces are ignored,
# and so is a leading "./". The file names come on stdin, one on each line.
#
# Exit 0 if a file matches, 1 if none does. Empty PATHS matches nothing: the
# caller decides what no paths means.
set -euo pipefail

while IFS= read -r file || [ -n "$file" ]; do
  while IFS= read -r path; do
    path=${path//[[:space:]]/}
    path=${path#./}
    [ -n "$path" ] || continue
    # shellcheck disable=SC2053
    if [[ "$file" == "$path" || "$file" == "${path%/}/"* || "$file" == $path ]]; then
      exit 0
    fi
  done <<< "$PATHS"
done
exit 1
