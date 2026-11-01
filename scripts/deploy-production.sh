#!/usr/bin/env bash
# Deploy the site to production with Wrangler.
#
# Reads WRANGLER_ENV, SECRETS_FILE (may be empty) and GITHUB_SHA. Needs
# CLOUDFLARE_API_TOKEN.
set -euo pipefail

# Name the environment, even the top level: wrangler warns when a
# config has environments and none is given.
args=(--env "$WRANGLER_ENV" --tag "$GITHUB_SHA" --message "main @ ${GITHUB_SHA::7}")
if [ -n "$SECRETS_FILE" ]; then
  args+=(--secrets-file "$SECRETS_FILE")
fi
# --no-install: this step holds the Cloudflare token, so run only the
# Wrangler that bun.lock pins, never the latest one from the registry.
bunx --no-install wrangler deploy "${args[@]}"
