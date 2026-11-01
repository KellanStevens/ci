#!/usr/bin/env bats

load helpers

setup() {
  setup_env
  script=$REPO_ROOT/scripts/run-checks.sh
}

@test "runs each script with bun run, in order" {
  SCRIPTS="lint typecheck build" run "$script"
  assert_success
  assert_equal "$(calls bun)" "run lint
run typecheck
run build"
}

@test "groups the log of each script" {
  SCRIPTS="lint" run "$script"
  assert_output_has "::group::bun run lint"
  assert_output_has "::endgroup::"
}

@test "runs every script even if an earlier one failed, then fails and lists them" {
  route_cmd bun "run lint" 1
  route_cmd bun "run build" 2
  SCRIPTS="lint typecheck build" run "$script"
  assert_failure 1
  assert_equal "$(calls bun)" "run lint
run typecheck
run build"
  assert_output_has "::error::bun run lint failed."
  assert_output_has "::error::bun run build failed."
  refute_output_has "bun run typecheck failed"
  assert_output_has "Failed: lint build"
}

@test "succeeds when every script passes" {
  SCRIPTS="lint build" run "$script"
  assert_success
  refute_output_has "Failed:"
}

@test "splits the list on new lines too" {
  SCRIPTS=$'lint\ntypecheck\n  build' run "$script"
  assert_success
  assert_equal "$(call_count bun)" 3
}

@test "accepts the names that scripts use: colons, dashes and underscores" {
  SCRIPTS="test:unit build-prod check_types 2fa" run "$script"
  assert_success
  assert_equal "$(call_count bun)" 4
}

@test "does nothing for an empty list" {
  SCRIPTS="" run "$script"
  assert_success
  assert_equal "$(call_count bun)" 0
}

@test "refuses a name that is not a script name, before it runs" {
  for bad in 'lint;whoami' 'a&b' '$(id)' 'a/b' 'a.b' '`id`' "a'b"; do
    SCRIPTS="$bad" run "$script"
    assert_failure 1
    assert_output_has "is not a script name."
  done
  assert_equal "$(call_count bun)" 0
}

@test "refuses a name that bun would read as a flag" {
  for bad in --version -h --silent; do
    SCRIPTS="$bad" run "$script"
    assert_failure 1
    assert_output_has "is not a script name."
  done
  assert_equal "$(call_count bun)" 0
}

@test "does not expand a glob into file names" {
  touch lint build
  SCRIPTS='*' run "$script"
  assert_failure 1
  assert_output_has '"*" is not a script name.'
  assert_equal "$(call_count bun)" 0
}

@test "stops at a bad name, after the scripts before it" {
  SCRIPTS="lint bad;name build" run "$script"
  assert_failure 1
  assert_equal "$(calls bun)" "run lint"
}

@test "fails when SCRIPTS is not set" {
  unset SCRIPTS
  run "$script"
  assert_failure
}
