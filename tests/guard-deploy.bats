#!/usr/bin/env bats

load helpers

setup() {
  setup_env
  script=$REPO_ROOT/scripts/guard-deploy.sh
}

@test "allows a push to the default branch" {
  EVENT=push REF=refs/heads/main DEFAULT_BRANCH=main run "$script"
  assert_success
}

@test "allows a run by hand on the default branch" {
  EVENT=workflow_dispatch REF=refs/heads/main DEFAULT_BRANCH=main run "$script"
  assert_success
}

@test "follows a default branch with another name" {
  EVENT=push REF=refs/heads/trunk DEFAULT_BRANCH=trunk run "$script"
  assert_success
  EVENT=push REF=refs/heads/main DEFAULT_BRANCH=trunk run "$script"
  assert_failure 1
}

@test "refuses every event but push and workflow_dispatch" {
  for event in pull_request pull_request_target workflow_run schedule release issue_comment; do
    EVENT=$event REF=refs/heads/main DEFAULT_BRANCH=main run "$script"
    assert_failure 1
    assert_output_has "Production deploys only on push or workflow_dispatch, not on $event."
  done
}

@test "refuses a push to another branch" {
  EVENT=push REF=refs/heads/feature DEFAULT_BRANCH=main run "$script"
  assert_failure 1
  assert_output_has "only from the default branch (main), not from refs/heads/feature."
}

@test "refuses a run by hand on another branch" {
  EVENT=workflow_dispatch REF=refs/heads/feature DEFAULT_BRANCH=main run "$script"
  assert_failure 1
}

@test "refuses a branch whose name starts with the default branch" {
  EVENT=push REF=refs/heads/main-evil DEFAULT_BRANCH=main run "$script"
  assert_failure 1
  EVENT=push REF=refs/heads/main/sub DEFAULT_BRANCH=main run "$script"
  assert_failure 1
}

@test "refuses a tag and a pull request ref" {
  for ref in refs/tags/main refs/pull/1/merge main; do
    EVENT=push REF=$ref DEFAULT_BRANCH=main run "$script"
    assert_failure 1
  done
}

@test "refuses when the default branch is unknown" {
  EVENT=push REF=refs/heads/ DEFAULT_BRANCH="" run "$script"
  assert_failure 1
  EVENT=push REF=refs/heads/main DEFAULT_BRANCH="" run "$script"
  assert_failure 1
}

@test "treats the default branch as text, not a pattern" {
  EVENT=push REF=refs/heads/main DEFAULT_BRANCH='*' run "$script"
  assert_failure 1
  EVENT=push REF=refs/heads/main DEFAULT_BRANCH='m*' run "$script"
  assert_failure 1
}
