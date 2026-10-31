#!/usr/bin/env bash
# Stop a production deploy that does not run on the default branch, from a
# push or a run by hand.
#
# Reads EVENT, REF and DEFAULT_BRANCH.
set -euo pipefail

if [ "$EVENT" != push ] && [ "$EVENT" != workflow_dispatch ]; then
  echo "::error::Production deploys only on push or workflow_dispatch, not on $EVENT."
  exit 1
fi
if [ -z "$DEFAULT_BRANCH" ] || [ "$REF" != "refs/heads/$DEFAULT_BRANCH" ]; then
  echo "::error::Production deploys only from the default branch ($DEFAULT_BRANCH), not from $REF."
  exit 1
fi
