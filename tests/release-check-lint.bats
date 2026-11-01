#!/usr/bin/env bats

load helpers

setup() {
  setup_env
  script=$REPO_ROOT/scripts/release-check-lint.sh
  sha=0123456789abcdef0123456789abcdef01234567
  export GH_TOKEN=t REPO=owner/ci GITHUB_SHA=$sha REQUIRED="lint actions test"
}

# checks "NAME CONCLUSION"...: the check runs of the commit.
checks() {
  local json='{"check_runs": [' sep='' line
  for line in "$@"; do
    local name=${line% *} conclusion=${line##* }
    if [ "$conclusion" = null ]; then
      json+="$sep{\"name\": \"$name\", \"conclusion\": null}"
    else
      json+="$sep{\"name\": \"$name\", \"conclusion\": \"$conclusion\"}"
    fi
    sep=,
  done
  route_gh "commits/$sha/check-runs" 0 "$json]}"
}

@test "passes when every required check succeeded" {
  checks "lint success" "actions success" "test success"
  run "$script"
  assert_success
}

@test "asks for the check runs of the commit" {
  checks "lint success" "actions success" "test success"
  run "$script"
  assert_has "$(calls gh)" "repos/owner/ci/commits/$sha/check-runs?per_page=100"
}

@test "ignores other checks, passed or failed" {
  checks "lint success" "actions success" "test success" "deploy failure" "other cancelled"
  run "$script"
  assert_success
}

@test "fails when a required check is missing" {
  checks "lint success" "actions success"
  run "$script"
  assert_failure 1
  assert_output_has "::error::The test check has not passed on $sha."
}

@test "fails when a required check failed" {
  checks "lint success" "actions failure" "test success"
  run "$script"
  assert_failure 1
  assert_output_has "::error::The actions check has not passed on $sha."
}

@test "fails when a required check was cancelled, skipped or is not finished" {
  for result in cancelled skipped timed_out null; do
    checks "lint success" "actions success" "test $result"
    run "$script"
    assert_failure 1
    assert_output_has "The test check has not passed"
    rm -f "$STUB_DIR/gh.routes"
  done
}

@test "names every check that did not pass" {
  checks "lint failure"
  run "$script"
  assert_failure 1
  assert_output_has "The lint check has not passed"
  assert_output_has "The actions check has not passed"
  assert_output_has "The test check has not passed"
}

@test "does not take a check with a longer name for the one it needs" {
  checks "lint-extra success" "pre-actions success" "test success"
  run "$script"
  assert_failure 1
  assert_output_has "The lint check has not passed"
  assert_output_has "The actions check has not passed"
}

@test "does not take a check that only has success in its name" {
  checks "lint not success" "actions success" "test success"
  run "$script"
  assert_failure 1
  assert_output_has "The lint check has not passed"
}

@test "passes when the same check ran twice and one run succeeded" {
  checks "lint failure" "lint success" "actions success" "test success"
  run "$script"
  assert_success
}

@test "passes when nothing is required" {
  checks
  REQUIRED="" run "$script"
  assert_success
}

@test "does not expand a glob in the list of required checks" {
  touch lint
  checks "lint success"
  REQUIRED='*' run "$script"
  assert_failure 1
  assert_output_has "The * check has not passed"
}

@test "fails when the API fails" {
  route_gh "commits/$sha/check-runs" 1
  run "$script"
  assert_failure
}
