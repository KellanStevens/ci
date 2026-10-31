#!/usr/bin/env bats

load helpers

setup() {
  setup_env
  script=$REPO_ROOT/scripts/release-tag.sh
  sha=0123456789abcdef0123456789abcdef01234567
  export GH_TOKEN=t REPO=owner/ci VERSION=v1.2.3 GITHUB_SHA=$sha
}

@test "makes an annotated tag for the commit, then a ref that points at the tag" {
  route_gh "git/tags" 0 '{"sha": "tagobjectsha"}'
  route_gh "git/refs" 0 '{}'
  run "$script"
  assert_success
  assert_output_has "Tagged $sha as v1.2.3."
  assert_equal "$(calls gh | sed -n 1p | cut -d' ' -f1-4)" "api --method POST repos/owner/ci/git/tags"
  assert_equal "$(calls gh | sed -n 2p | cut -d' ' -f1-4)" "api --method POST repos/owner/ci/git/refs"
}

@test "tags the commit of the run with the version as name and message" {
  route_gh "git/tags" 0 '{"sha": "tagobjectsha"}'
  route_gh "git/refs" 0 '{}'
  run "$script"
  assert_equal "$(field tag)" "v1.2.3"
  assert_equal "$(field message)" "v1.2.3"
  assert_equal "$(field object)" "$sha"
}

@test "points refs/tags/<version> at the tag object, not at the commit" {
  route_gh "git/tags" 0 '{"sha": "tagobjectsha"}'
  route_gh "git/refs" 0 '{}'
  run "$script"
  assert_equal "$(field ref)" "refs/tags/v1.2.3"
  assert_equal "$(field sha)" "tagobjectsha"
}

@test "makes no ref when the tag object fails" {
  route_gh "git/tags" 1
  run "$script"
  assert_failure 1
  assert_equal "$(call_count gh)" 1
  refute_output_has "Tagged"
}

@test "fails when the ref exists already" {
  route_gh "git/tags" 0 '{"sha": "tagobjectsha"}'
  route_gh "git/refs" 1
  run "$script"
  assert_failure 1
  refute_output_has "Tagged"
}
