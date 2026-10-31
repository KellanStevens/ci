#!/usr/bin/env bash
# Find the open pull request that CI built, and the Worker and hostname of its
# preview. Its number comes from the GitHub API, never from the files of the
# run.
#
# Reads GH_TOKEN, REPO, OWNER, BRANCH, HEAD_SHA, NAME, HOST and PATHS. Writes
# number, host and worker to GITHUB_OUTPUT. The number is empty when there is
# nothing to deploy.
set -euo pipefail

if ! [[ "$HEAD_SHA" =~ ^[0-9a-f]{40}$ ]]; then
  echo "::error::\"$HEAD_SHA\" is not a commit SHA."
  exit 1
fi
# Skip a draft, and skip a run of an older commit. The run of the
# newest commit deploys that one.
number=$(gh api --method GET "repos/$REPO/pulls" -f state=open -f head="$OWNER:$BRANCH" \
  --jq "[.[] | select(.head.sha == \"$HEAD_SHA\" and (.draft | not))][0].number // empty")
if [ -z "$number" ]; then
  echo "::notice::No open pull request that is ready for review is at $HEAD_SHA. Nothing to deploy."
  echo "number=" >> "$GITHUB_OUTPUT"
  exit 0
fi

# Skip a pull request that changes none of the paths, for example
# one that edits only the README or the workflows. The file list
# comes from the API, not from the files of the run.
if [ -n "${PATHS//[[:space:]]/}" ]; then
  files=$(gh api --paginate "repos/$REPO/pulls/$number/files" --jq '.[] | .filename, (.previous_filename // empty)')
  if ! "$(dirname "$0")/match-paths.sh" <<< "$files"; then
    echo "::notice::Pull request #$number changes none of the preview paths. Nothing to deploy."
    echo "number=" >> "$GITHUB_OUTPUT"
    exit 0
  fi
fi

# shellcheck disable=SC2153 # HOST is the input, host the result.
host=${HOST//\{pr\}/$number}
worker="$NAME-pr-$number"
if ! [[ "$host" =~ ^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$ && "$HOST" == *"{pr}"* ]]; then
  echo "::error::\"$HOST\" is not a hostname with {pr} in it."
  exit 1
fi
if ! [[ "$worker" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]]; then
  echo "::error::\"$NAME\" is not a Worker name."
  exit 1
fi
{
  echo "number=$number"
  echo "host=$host"
  echo "worker=$worker"
} >> "$GITHUB_OUTPUT"
