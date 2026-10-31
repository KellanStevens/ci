#!/usr/bin/env bash
# Deploy the preview Worker of a pull request with Wrangler.
#
# Reads WRANGLER_ENV, WORKER_NAME, PREVIEW_HOST, HEAD_SHA, PR_NUMBER,
# SECRETS_FILE (may be empty), WORKER (true or false) and, for a Worker,
# WORKER_SRC. Needs CLOUDFLARE_API_TOKEN. Writes url to GITHUB_OUTPUT and the
# link to GITHUB_STEP_SUMMARY.
set -euo pipefail

args=()
if [ "$WORKER" = true ]; then
  # Given a script, Wrangler looks for its config next to the
  # script, so name the config of main.
  config=
  for f in wrangler.jsonc wrangler.json wrangler.toml; do
    if [ -f "$f" ]; then config=$f; break; fi
  done
  if [ -z "$config" ]; then
    echo "::error::No Wrangler config in the repository root."
    exit 1
  fi
  args+=("$WORKER_SRC/index.js" --no-bundle --config "$config")
fi
args+=(
  --env "$WRANGLER_ENV"
  --name "$WORKER_NAME"
  --domain "$PREVIEW_HOST"
  --tag "$HEAD_SHA"
  --message "PR #$PR_NUMBER @ ${HEAD_SHA::7}"
)
if [ -n "$SECRETS_FILE" ]; then
  args+=(--secrets-file "$SECRETS_FILE")
fi
# --no-install: this step holds the Cloudflare token, so run only the
# Wrangler that bun.lock pins, never the latest one from the registry.
bunx --no-install wrangler deploy "${args[@]}"
echo "url=https://$PREVIEW_HOST" >> "$GITHUB_OUTPUT"
echo "Preview: https://$PREVIEW_HOST" >> "$GITHUB_STEP_SUMMARY"
