#!/usr/bin/env bash
# Write the state of a pull request, open or closed, to the output "state".
#
# Reads GH_TOKEN, REPO and PR_NUMBER.
set -euo pipefail

state=$(gh api "repos/$REPO/pulls/$PR_NUMBER" --jq .state)
echo "state=$state" >> "$GITHUB_OUTPUT"
if [ "$state" = "open" ]; then
  echo "The pull request is open. Keeping the preview."
else
  echo "::notice::The pull request closed during the deploy. Deleting the preview."
fi
