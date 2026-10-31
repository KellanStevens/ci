#!/usr/bin/env bash
# Keep a preview out of search engines. The build is shared with production,
# which may allow search engines, so add the rule to the copy for the preview.
#
# Reads SITE_PATH.
set -euo pipefail

printf '\n/*\n  X-Robots-Tag: noindex, nofollow\n' >> "$SITE_PATH/_headers"
