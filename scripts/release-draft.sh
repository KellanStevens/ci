#!/usr/bin/env bash
# Draft the GitHub Release of a tag with generated notes, and link the draft in
# the summary of the run.
#
# Reads GH_TOKEN, REPO, VERSION and GITHUB_SHA. Writes to GITHUB_STEP_SUMMARY.
set -euo pipefail

url=$(gh release create "$VERSION" --repo "$REPO" --verify-tag --draft \
  --title "$VERSION" --generate-notes)
{
  echo "Tagged \`$GITHUB_SHA\` as $VERSION."
  echo
  echo "Edit the notes and publish the draft: $url"
  echo "Breaking changes and known issues go at the top."
} >> "$GITHUB_STEP_SUMMARY"
