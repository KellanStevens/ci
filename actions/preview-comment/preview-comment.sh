#!/usr/bin/env bash
# Add or update the preview comment of a pull request.
#
# Reads GH_TOKEN, REPO, PR_NUMBER, URL, STATUS, HEAD_SHA, RUN_URL and MARKER.
# See action.yml.
set -euo pipefail

if ! [[ "$PR_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
  echo "::error::\"$PR_NUMBER\" is not a pull request number."
  exit 1
fi

tag="<!-- $MARKER -->"
sha="\`${HEAD_SHA::7}\`"
case "$STATUS" in
  deploying)
    body=$(printf '%s\n**Preview:** deploying to %s ...\n\nBuilding %s. [Workflow run](%s)\n' \
      "$tag" "$URL" "$sha" "$RUN_URL")
    ;;
  deployed)
    body=$(printf '%s\n**Preview:** %s\n\nBuilt from %s. [Workflow run](%s)\n' \
      "$tag" "$URL" "$sha" "$RUN_URL")
    ;;
  failed)
    body=$(printf '%s\n**Preview:** failed\n\nNo preview for %s. [Workflow run](%s)\n' \
      "$tag" "$sha" "$RUN_URL")
    ;;
  *)
    echo "::error::\"$STATUS\" is not a preview status. Use deploying, deployed or failed."
    exit 1
    ;;
esac

ids=$(gh api --paginate "repos/$REPO/issues/$PR_NUMBER/comments" \
  --jq ".[] | select(.user.login == \"github-actions[bot]\" and (.body | startswith(\"$tag\"))) | .id")
comment_id=${ids%%$'\n'*}

if [ -n "$comment_id" ]; then
  gh api --method PATCH "repos/$REPO/issues/comments/$comment_id" -f body="$body" >/dev/null
  echo "Updated comment $comment_id."
else
  gh api --method POST "repos/$REPO/issues/$PR_NUMBER/comments" -f body="$body" >/dev/null
  echo "Added a comment."
fi
