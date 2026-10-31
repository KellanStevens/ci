#!/usr/bin/env bats

load helpers

setup() {
  setup_env
  script=$REPO_ROOT/scripts/pr-head-sha.sh
  export GH_TOKEN=t REPO=owner/site PR_NUMBER=7
}

@test "writes the head commit of the pull request" {
  route_gh "repos/owner/site/pulls/7" 0 '{"head": {"sha": "0123456789abcdef0123456789abcdef01234567"}, "state": "closed"}'
  run "$script"
  assert_success
  assert_output_file "sha=0123456789abcdef0123456789abcdef01234567"
}

@test "fails when the API fails, and writes no commit" {
  route_gh "repos/owner/site/pulls/7" 1
  run "$script"
  assert_failure 1
  assert_output_file ""
}
