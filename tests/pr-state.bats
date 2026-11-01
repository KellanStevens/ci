#!/usr/bin/env bats

load helpers

setup() {
  setup_env
  script=$REPO_ROOT/scripts/pr-state.sh
  export GH_TOKEN=t REPO=owner/site PR_NUMBER=7
}

@test "keeps the preview of an open pull request" {
  route_gh "repos/owner/site/pulls/7" 0 '{"state": "open"}'
  run "$script"
  assert_success
  assert_output_file "state=open"
  assert_output_has "The pull request is open. Keeping the preview."
}

@test "reports a pull request that closed" {
  route_gh "repos/owner/site/pulls/7" 0 '{"state": "closed"}'
  run "$script"
  assert_success
  assert_output_file "state=closed"
  assert_output_has "::notice::The pull request closed during the deploy. Deleting the preview."
}

@test "fails when the API fails, and writes no state" {
  route_gh "repos/owner/site/pulls/7" 1
  run "$script"
  assert_failure 1
  assert_output_file ""
}
