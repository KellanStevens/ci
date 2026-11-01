#!/usr/bin/env bash
# Check that the required checks have passed on the commit. A tag cannot be
# moved, so do not tag a commit that lint.yml has not passed.
#
# Reads GH_TOKEN, REPO, GITHUB_SHA and REQUIRED: the names of the jobs, separated
# by spaces. Keep them in step with the jobs of lint.yml.
set -euo pipefail
# The list is split on spaces, so stop "*" from matching files.
set -f

results=$(gh api --paginate "repos/$REPO/commits/$GITHUB_SHA/check-runs?per_page=100" \
  --jq '.check_runs[] | "\(.name) \(.conclusion // "not finished")"')
failed=0
for check in $REQUIRED; do
  result=$(grep -F -x -m1 -e "$check success" <<<"$results" || true)
  if [ -z "$result" ]; then
    echo "::error::The $check check has not passed on $GITHUB_SHA. Wait for it, or fix it, and run again."
    failed=1
  fi
done
exit "$failed"
