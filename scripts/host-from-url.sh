#!/usr/bin/env bash
# Write the hostname of a URL to the output "host".
#
# Reads URL, for example https://www.example.com/. Needs GITHUB_OUTPUT.
set -euo pipefail

host=${URL#https://}
host=${host%%/*}
echo "host=$host" >> "$GITHUB_OUTPUT"
