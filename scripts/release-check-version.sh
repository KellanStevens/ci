#!/usr/bin/env bash
# Check that a version is vX.Y.Z and newer than every release tag.
#
# Reads GH_TOKEN, REPO and VERSION.
set -euo pipefail

if ! [[ "$VERSION" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  echo "::error::\"$VERSION\" is not a version like v1.2.3."
  exit 1
fi
# Not in the pipeline below: its || true is for a repository with no version tags,
# and must not hide a failed API call, which would let any version through.
tags=$(gh api --paginate "repos/$REPO/tags" --jq '.[].name')
latest=$(grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' <<<"$tags" | sort -V | tail -n 1 || true)
if [ -n "$latest" ]; then
  newest=$(printf '%s\n%s\n' "$latest" "$VERSION" | sort -V | tail -n 1)
  if [ "$VERSION" = "$latest" ] || [ "$newest" != "$VERSION" ]; then
    echo "::error::$VERSION is not newer than the latest release, $latest."
    exit 1
  fi
fi
echo "Releasing $VERSION after ${latest:-no release}."
