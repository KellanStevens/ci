#!/usr/bin/env bats

load helpers

setup() {
  setup_env
  script=$REPO_ROOT/scripts/release-check-version.sh
  export GH_TOKEN=t REPO=owner/ci
}

# tags NAME...: the tags that the repository has.
tags() {
  local json='[' sep=''
  for name in "$@"; do
    json+="$sep{\"name\": \"$name\"}"
    sep=,
  done
  route_gh "repos/owner/ci/tags" 0 "$json]"
}

@test "allows the first release" {
  tags
  VERSION=v1.0.0 run "$script"
  assert_success
  assert_output_has "Releasing v1.0.0 after no release."
}

@test "allows a newer patch, minor and major version" {
  tags v1.2.3
  for next in v1.2.4 v1.3.0 v2.0.0 v1.2.10; do
    VERSION=$next run "$script"
    assert_success
    assert_output_has "Releasing $next after v1.2.3."
  done
}

@test "refuses the version that is the latest" {
  tags v1.2.3
  VERSION=v1.2.3 run "$script"
  assert_failure 1
  assert_output_has "::error::v1.2.3 is not newer than the latest release, v1.2.3."
}

@test "refuses an older version" {
  tags v1.2.3
  for old in v1.2.2 v1.1.9 v0.9.9; do
    VERSION=$old run "$script"
    assert_failure 1
    assert_output_has "is not newer than the latest release, v1.2.3."
  done
}

@test "compares the parts as numbers, not as text" {
  tags v1.9.0
  VERSION=v1.10.0 run "$script"
  assert_success
  tags v1.10.0
  VERSION=v1.9.0 run "$script"
  assert_failure 1
}

@test "compares with the newest tag, whatever the order of the tags" {
  tags v1.0.0 v1.10.0 v1.2.0 v1.9.0
  VERSION=v1.10.1 run "$script"
  assert_success
  assert_output_has "after v1.10.0."
  VERSION=v1.9.1 run "$script"
  assert_failure 1
}

@test "ignores tags that are not versions" {
  tags latest v2 v1.0.0-rc1 nightly v3.0 v1.0.0
  VERSION=v1.0.1 run "$script"
  assert_success
  assert_output_has "after v1.0.0."
}

@test "allows the first release when the only tags are not versions" {
  tags latest v2
  VERSION=v0.1.0 run "$script"
  assert_success
  assert_output_has "after no release."
}

@test "refuses a version that is not vX.Y.Z, before it calls the API" {
  for bad in "" 1.2.3 v1 v1.2 v1.2.3.4 v1.2.3-rc1 v01.2.3 v1.02.3 v1.2.03 " v1.2.3" "v1.2.3 " V1.2.3 'v1.2.3;id' v1.2.x; do
    VERSION=$bad run "$script"
    assert_failure 1
    assert_output_has "is not a version like v1.2.3."
  done
  assert_equal "$(call_count gh)" 0
}

@test "accepts zero parts" {
  tags
  VERSION=v0.0.1 run "$script"
  assert_success
  VERSION=v0.0.0 run "$script"
  assert_success
}

@test "reads all the pages of tags" {
  tags v1.0.0
  VERSION=v1.0.1 run "$script"
  assert_has "$(calls gh)" "api --paginate repos/owner/ci/tags"
}

@test "fails when the API fails" {
  route_gh "repos/owner/ci/tags" 1
  VERSION=v1.0.0 run "$script"
  assert_failure
}
