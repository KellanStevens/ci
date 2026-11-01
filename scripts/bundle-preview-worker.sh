#!/usr/bin/env bash
# Bundle the Worker script of a site, for the preview, without deploying it.
#
# Reads PREVIEW_ENV and RUNNER_TEMP. The bundle lands in $RUNNER_TEMP/worker.
set -euo pipefail

# --no-install: run only the Wrangler that bun.lock pins, never the latest one
# from the registry.
bunx --no-install wrangler deploy --dry-run --env "$PREVIEW_ENV" --outdir "$RUNNER_TEMP/worker"
