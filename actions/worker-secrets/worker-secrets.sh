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

  # The secrets context also holds the tokens of the deploy itself. A preview
  # Worker runs the code of the pull request, so it must never get them.
  case "${source^^}" in
    CLOUDFLARE_API_TOKEN | GITHUB_TOKEN)
      echo "::error::$source is a token of the deploy, not a Worker secret."
      exit 1
      ;;
  esac

  # Keep the value as a JSON string, not raw: $(...) would drop its trailing
  # new lines, as at the end of a PEM key.
  value=$(jq -c --arg k "$source" '.[$k] // empty | select(. != "")' <<<"$SECRETS_JSON")
  if [ -z "$value" ]; then
    value=$(jq -c --arg k "$source" '.[$k] // empty | select(. != "")' <<<"$VARS_JSON")
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

  # Through the environment, not an argument: any process on the runner can
  # read the arguments of another.
  out=$(VALUE=$value jq -c --arg k "$name" '. + {($k): (env.VALUE | fromjson)}' <<<"$out")
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
