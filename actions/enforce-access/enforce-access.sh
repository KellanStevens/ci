#!/usr/bin/env bash
# Check that Cloudflare Access protects a hostname, and take the site down if
# it does not.
#
# Usage: enforce-access.sh <hostname> <remove|keep> [<Worker name>
#        [<workers.dev Worker>]]
#
# With a Worker name, a failed check deletes that preview Worker and its
# domain (delete-preview). Without one, it detaches the domain only
# (remove-domain). Needs CLOUDFLARE_API_TOKEN. Reads CLOUDFLARE_ACCOUNT_ID.
#
# Access protects the hostname, not the workers.dev and preview URLs of the
# same Worker. With a workers.dev Worker, those are turned off first
# (workers-dev.sh), and the exit status is non-zero if either was on.
#
# A site that answers without a login is always taken down. When the site
# cannot be reached, so Access is neither proven nor disproven, <remove> takes
# it down too, and <keep> leaves it up. Either way, this exits non-zero
# unless Access protects the site: 1 if it is public, 2 if it cannot be
# reached.
set -euo pipefail

host=$1
on_unreachable=$2
worker=${3:-}
workers_dev_worker=${4:-}

if [ "$on_unreachable" != remove ] && [ "$on_unreachable" != keep ]; then
  echo "::error::on-unreachable must be \"remove\" or \"keep\", not \"$on_unreachable\"."
  exit 1
fi

actions=$(dirname "$0")/..

# First, so that a site that is taken down below is not left on workers.dev.
workers_dev_status=0
if [ -n "$workers_dev_worker" ]; then
  "$(dirname "$0")/workers-dev.sh" "$workers_dev_worker" "$host" || workers_dev_status=$?
else
  echo "::warning::No Worker to check for workers.dev, so $host is protected by Access only on its own hostname. Set the Worker name."
fi

status=0
"$actions/check-access/check-access.sh" "$host" || status=$?
if [ "$status" -eq 0 ]; then
  exit "$workers_dev_status"
fi

# check-access.sh exits 1 for a public site. Treat any other failure as not
# reachable.
if [ "$status" -ne 1 ]; then
  status=2
  if [ "$on_unreachable" = keep ]; then
    echo "::warning::Could not check Access on $host. Keeping the site, as on-unreachable is keep."
    exit "$status"
  fi
  echo "::warning::Could not check Access on $host. Taking the site down, as on-unreachable is remove."
fi

if [ -n "$worker" ]; then
  "$actions/delete-preview/delete-preview.sh" "$worker" "$host"
else
  "$actions/remove-domain/remove-domain.sh" "$host"
fi
exit "$status"
