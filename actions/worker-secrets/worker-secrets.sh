#!/usr/bin/env bash
# Write the Worker secrets to a JSON file for `wrangler deploy --secrets-file`.
#
# Reads REQUIRED, OPTIONAL, SECRETS_JSON, VARS_JSON and HELP. See action.yml.
#
# JSON, not .env, so that a value can hold any character.
set -euo pipefail
# The lists are split on spaces, so stop "*" from matching files.
set -f

file="$RUNNER_TEMP/worker-secrets.json"
out='{}'
missing=0

# add <NAME or NAME=SOURCE> <required|optional>
add() {
  local entry=$1 kind=$2 name source value
  name=${entry%%=*}
  source=${entry#*=}
  for part in "$name" "$source"; do
    if ! [[ "$part" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
      echo "::error::\"$part\" is not a secret name."
      exit 1
    fi
  done

  value=$(jq -r --arg k "$source" '.[$k] // empty' <<<"$SECRETS_JSON")
  if [ -z "$value" ]; then
    value=$(jq -r --arg k "$source" '.[$k] // empty' <<<"$VARS_JSON")
  fi

  if [ -z "$value" ]; then
    if [ "$kind" = required ]; then
      echo "::error::Set the $source secret or variable. $HELP"
      missing=1
    else
      echo "::warning::$source is empty, so the Worker runs without $name. $HELP"
    fi
    return
  fi

  out=$(jq -c --arg k "$name" --arg v "$value" '. + {($k): $v}' <<<"$out")
  echo "Added $name."
}

for entry in $REQUIRED; do add "$entry" required; done
for entry in $OPTIONAL; do add "$entry" optional; done

if [ "$missing" -ne 0 ]; then
  exit 1
fi

if [ "$out" = '{}' ]; then
  echo "No Worker secrets to upload."
  echo "file=" >> "$GITHUB_OUTPUT"
  exit 0
fi

(umask 077 && printf '%s\n' "$out" > "$file")
echo "file=$file" >> "$GITHUB_OUTPUT"
