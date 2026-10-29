#!/usr/bin/env bash
# Delete a preview Worker and its custom domains.
#
# Usage: delete-preview.sh <Worker name> <hostname>...
# Needs CLOUDFLARE_API_TOKEN, and Wrangler from the setup action. Reads
# CLOUDFLARE_ACCOUNT_ID.
#
# A missing domain or Worker is not an error, so this can run more than once
# for the same pull request.
set -euo pipefail

name=$1
shift
if ! [[ "$name" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]]; then
  echo "::error::\"$name\" is not a Worker name."
  exit 1
fi

# Detach the domains first, so that no hostname points at a deleted Worker.
for host in "$@"; do
  "$(dirname "$0")/../remove-domain/remove-domain.sh" "$host"
done

# A draft pull request never gets a preview, so the Worker can be missing.
if output=$(bunx wrangler delete --name "$name" --force 2>&1); then
  echo "$output"
elif grep -qiE "does not exist|not found|10007" <<<"$output"; then
  echo "$output"
  echo "::notice::No preview Worker $name to delete."
else
  echo "$output"
  exit 1
fi
