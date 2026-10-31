#!/usr/bin/env bash
# Tag the commit as the version, through the API, so that the job needs no
# checkout and no git credentials. An annotated tag, like the ones made by hand.
#
# Reads GH_TOKEN, REPO, VERSION and GITHUB_SHA.
set -euo pipefail

tag=$(gh api --method POST "repos/$REPO/git/tags" \
  -f tag="$VERSION" -f message="$VERSION" -f object="$GITHUB_SHA" -f type=commit --jq .sha)
gh api --method POST "repos/$REPO/git/refs" -f ref="refs/tags/$VERSION" -f sha="$tag" >/dev/null
echo "Tagged $GITHUB_SHA as $VERSION."
