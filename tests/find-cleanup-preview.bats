#!/usr/bin/env bats

load helpers

setup() {
  setup_env
  script=$REPO_ROOT/scripts/find-cleanup-preview.sh
  export NAME=site HOST='pr-{pr}.example.com'
}

@test "writes the Worker and host of the preview" {
  PR_NUMBER=12 run "$script"
  assert_success
  assert_output_file "worker=site-pr-12
host=pr-12.example.com"
}

@test "puts the number into every {pr}" {
  PR_NUMBER=3 HOST='{pr}.pr{pr}.example.com' run "$script"
  assert_has "$(github_output)" "host=3.pr3.example.com"
}

@test "accepts large pull request numbers" {
  PR_NUMBER=123456 run "$script"
  assert_success
  assert_has "$(github_output)" "worker=site-pr-123456"
}

@test "refuses what is not a pull request number" {
  for bad in "" 0 01 -1 abc 1.5 "1 2" "1;id" "1
2" '$(id)'; do
    PR_NUMBER=$bad run "$script"
    assert_failure 1
    assert_output_has "is not a pull request number."
  done
  assert_output_file ""
}

@test "refuses a host with no {pr}" {
  PR_NUMBER=12 HOST='preview.example.com' run "$script"
  assert_failure 1
  assert_output_has '"preview.example.com" has no {pr} in it.'
  assert_output_file ""
}
