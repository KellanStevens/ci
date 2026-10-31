#!/usr/bin/env bash
# Write the head commit of a pull request to the output "sha".
#
# Reads GH_TOKEN, REPO and PR_NUMBER.
set -euo pipefail

sha=$(gh api "repos/$REPO/pulls/$PR_NUMBER" --jq .head.sha)
echo "sha=$sha" >> "$GITHUB_OUTPUT"
