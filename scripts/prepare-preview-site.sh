#!/usr/bin/env bash
# Make the files that CI built safe to deploy. Keep only regular files and
# directories, so that no link points Wrangler at a file of this runner. Drop
# hidden files except .well-known/ and .assetsignore, then copy the site to
# SITE_PATH in the working directory.
#
# Reads SRC (the downloaded site), SITE_PATH, WORKER (true or false) and, for a
# Worker, WORKER_SRC (the downloaded bundle).
set -euo pipefail

if [ -z "$(ls -A "$SRC")" ]; then
  echo "::error::The site is empty."
  exit 1
fi
find "$SRC" -mindepth 1 ! -type f ! -type d -delete
find "$SRC" -mindepth 1 -name '.*' \
  ! -path "$SRC/.well-known" ! -path "$SRC/.assetsignore" -prune -exec rm -rf {} +
rm -rf "$SITE_PATH"
cp -R "$SRC" "$SITE_PATH"

# Wrangler uploads the bundle as it is, with --no-bundle. Keep only
# JavaScript and source maps.
if [ "$WORKER" = true ]; then
  if [ ! -f "$WORKER_SRC/index.js" ]; then
    echo "::error::The Worker bundle has no index.js."
    exit 1
  fi
  find "$WORKER_SRC" -mindepth 1 \( ! -type f ! -type d \) -delete
  find "$WORKER_SRC" -type f ! -name '*.js' ! -name '*.mjs' ! -name '*.map' -print -delete
fi
