#!/usr/bin/env bash
# Find the Worker and hostname of the preview of a pull request. Writes worker
# and host to GITHUB_OUTPUT.
#
# Reads PR_NUMBER, NAME and HOST (with {pr}).
set -euo pipefail

if ! [[ "$PR_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
  echo "::error::\"$PR_NUMBER\" is not a pull request number."
  exit 1
fi
if [[ "$HOST" != *"{pr}"* ]]; then
  echo "::error::\"$HOST\" has no {pr} in it."
  exit 1
fi
{
  echo "worker=$NAME-pr-$PR_NUMBER"
  echo "host=${HOST//\{pr\}/$PR_NUMBER}"
} >> "$GITHUB_OUTPUT"
