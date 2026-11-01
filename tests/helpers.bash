# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154 # The test files use ACCOUNT; bats sets status and output.
# Shared by the tests. Load it with `load helpers` and call setup_env from
# setup(). Every test runs in its own temporary directory, with stubs for curl,
# gh, bun, bunx and sleep ahead of the real commands, so that no test reaches
# the network or runs a real Bun.

REPO_ROOT=$(cd "$BATS_TEST_DIRNAME/.." && pwd)

setup_env() {
  export STUB_DIR=$BATS_TEST_TMPDIR/stub
  mkdir -p "$STUB_DIR"
  PATH=$REPO_ROOT/tests/stubs:$PATH

  export GITHUB_OUTPUT=$BATS_TEST_TMPDIR/github_output
  export GITHUB_STEP_SUMMARY=$BATS_TEST_TMPDIR/step_summary
  export RUNNER_TEMP=$BATS_TEST_TMPDIR/runner
  : > "$GITHUB_OUTPUT"
  : > "$GITHUB_STEP_SUMMARY"
  mkdir -p "$RUNNER_TEMP"

  # The scripts read these from the runner. Start each test without them.
  unset CLOUDFLARE_ACCOUNT_ID CLOUDFLARE_API_TOKEN ACCESS_TEAM GH_TOKEN
  export CLOUDFLARE_API_TOKEN=test-token-123

  mkdir -p "$BATS_TEST_TMPDIR/work"
  cd "$BATS_TEST_TMPDIR/work" || return 1
}

# A valid Cloudflare account ID, and one more.
ACCOUNT=0123456789abcdef0123456789abcdef
OTHER_ACCOUNT=fedcba9876543210fedcba9876543210

# --- Stubs ---------------------------------------------------------------

# route_curl METHOD URL-PART CODE [BODY [REDIRECT-URL]]
#
# Answer a curl call whose method is METHOD (or *) and whose URL contains
# URL-PART. CODE 000 is a connection failure. With several routes for one call,
# they answer in turn, and the last one repeats.
route_curl() {
  local file
  file=$(mktemp "$STUB_DIR/body.XXXXXX")
  printf '%s' "${4:-}" > "$file"
  printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$file" "${5:-}" >> "$STUB_DIR/curl.routes"
}

# route_gh ARGS-PART EXIT [BODY]
#
# Answer a gh call whose arguments contain ARGS-PART. BODY is the JSON that the
# real API returns, before --jq.
route_gh() {
  local file
  file=$(mktemp "$STUB_DIR/body.XXXXXX")
  printf '%s' "${3:-}" > "$file"
  printf '%s\t%s\t%s\n' "$1" "$2" "$file" >> "$STUB_DIR/gh.routes"
}

# route_cmd NAME ARGS-PART EXIT
#
# Make bun, bunx or sleep exit with EXIT when its arguments contain ARGS-PART.
route_cmd() {
  printf '%s\t%s\n' "$2" "$3" >> "$STUB_DIR/$1.routes"
}

# calls NAME: what the stub NAME was called with, one call on each line.
# NAME is curl (METHOD URL), curl.argv, curl.config, curl.data, gh, bun, bunx or sleep.
calls() {
  local file=$STUB_DIR/$1.log
  [ -f "$STUB_DIR/$1" ] && file=$STUB_DIR/$1
  [ -f "$file" ] && cat "$file"
  return 0
}

call_count() {
  calls "$1" | grep -c . || true
}

# field NAME: the last value that gh got for -f NAME=value.
field() {
  cat "$STUB_DIR/gh.field.$1"
}

# --- Assertions ----------------------------------------------------------

fail() {
  printf '%s\n' "$*" >&2
  return 1
}

assert_status() {
  [ "$status" -eq "$1" ] || fail "expected exit status $1, got $status. Output:
$output"
}

assert_success() { assert_status 0; }

# assert_failure [STATUS]: any non-zero status, or exactly STATUS.
assert_failure() {
  if [ -n "${1:-}" ]; then
    assert_status "$1"
  else
    [ "$status" -ne 0 ] || fail "expected a failure, got exit status 0. Output:
$output"
  fi
}

# assert_output TEXT: the whole output is TEXT.
assert_output() {
  assert_equal "$output" "$1"
}

assert_output_has() {
  [[ "$output" == *"$1"* ]] || fail "expected the output to contain: $1
Output:
$output"
}

refute_output_has() {
  [[ "$output" != *"$1"* ]] || fail "expected the output not to contain: $1
Output:
$output"
}

assert_equal() {
  [ "$1" = "$2" ] || fail "expected: $2
actual:   $1"
}

# assert_has TEXT STRING: the text contains the string.
assert_has() {
  [[ "$1" == *"$2"* ]] || fail "expected to find: $2
in:
$1"
}

refute_has() {
  [[ "$1" != *"$2"* ]] || fail "expected not to find: $2
in:
$1"
}

# github_output: what the script wrote to GITHUB_OUTPUT.
github_output() { cat "$GITHUB_OUTPUT"; }

assert_output_file() {
  assert_equal "$(github_output)" "$1"
}
