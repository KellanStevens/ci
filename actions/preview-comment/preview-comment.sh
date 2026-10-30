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
updated=$(date -u '+%Y-%m-%d %H:%M UTC')
case "$STATUS" in
  deploying)
    title="🚀 Deploying preview…"
    rows="| **Status** | ⏳ Building and deploying |
| **Preview** | 🔗 $URL (not live yet) |
| **Commit** | $sha |
| **Logs** | [Workflow run]($RUN_URL) |"
    note="This comment updates when the deploy finishes."
    ;;
  deployed)
    title="✅ Preview ready"
    rows="| **Preview** | 🔗 $URL |
| **Commit** | $sha |
| **Updated** | 🕐 $updated |
| **Logs** | [Workflow run]($RUN_URL) |"
    note=""
    ;;
  failed)
    title="❌ Preview failed"
    rows="| **Status** | 💥 Deploy failed |
| **Commit** | $sha |
| **Logs** | [See what went wrong]($RUN_URL) |"
    note="Push a new commit or re-run the workflow to try again."
    ;;
  removed)
    title="🧹 Preview deleted"
    rows="| **Status** | 🗑️ Deleted after the pull request closed |
| **Preview** | 🧹 $URL (not accessible anymore) |
| **Commit** | $sha |
| **Updated** | 🕐 $updated |"
    note=""
    ;;
  *)
    echo "::error::\"$STATUS\" is not a preview status. Use deploying, deployed, failed or removed."
    exit 1
    ;;
esac

body=$(printf '%s\n### %s\n\n| | |\n|---|---|\n%s\n' "$tag" "$title" "$rows")
if [ -n "$note" ]; then
  body+=$(printf '\n\n%s\n' "$note")
fi

ids=$(gh api --paginate "repos/$REPO/issues/$PR_NUMBER/comments" \
  --jq ".[] | select(.user.login == \"github-actions[bot]\" and (.body | startswith(\"$tag\"))) | .id")
comment_id=${ids%%$'\n'*}

# A pull request with no preview comment never had a preview. Do not add one
# only to say that it is gone.
if [ -z "$comment_id" ] && [ "$STATUS" = removed ]; then
  echo "No preview comment to update."
elif [ -n "$comment_id" ]; then
  gh api --method PATCH "repos/$REPO/issues/comments/$comment_id" -f body="$body" >/dev/null
  echo "Updated comment $comment_id."
else
  gh api --method POST "repos/$REPO/issues/$PR_NUMBER/comments" -f body="$body" >/dev/null
  echo "Added a comment."
fi
