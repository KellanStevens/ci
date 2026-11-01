#!/usr/bin/env bats

load helpers

setup() {
  setup_env
  script=$REPO_ROOT/scripts/release-draft.sh
  sha=0123456789abcdef0123456789abcdef01234567
  export GH_TOKEN=t REPO=owner/ci VERSION=v1.2.3 GITHUB_SHA=$sha
}

@test "drafts a release of the existing tag with generated notes" {
  route_gh "release create" 0 "https://github.com/owner/ci/releases/tag/untagged-abc"
  run "$script"
  assert_success
  assert_equal "$(calls gh)" "release create v1.2.3 --repo owner/ci --verify-tag --draft --title v1.2.3 --generate-notes"
}

@test "links the draft in the summary of the run" {
  route_gh "release create" 0 "https://github.com/owner/ci/releases/tag/untagged-abc"
  run "$script"
  summary=$(cat "$GITHUB_STEP_SUMMARY")
  assert_equal "$summary" "Tagged \`$sha\` as v1.2.3.

Edit the notes and publish the draft: https://github.com/owner/ci/releases/tag/untagged-abc
Breaking changes and known issues go at the top."
  assert_has "$summary" "Tagged \`$sha\` as v1.2.3."
  assert_has "$summary" "Edit the notes and publish the draft: https://github.com/owner/ci/releases/tag/untagged-abc"
  assert_has "$summary" "Breaking changes and known issues go at the top."
}

@test "writes no summary when the release fails" {
  route_gh "release create" 1
  run "$script"
  assert_failure 1
  assert_equal "$(cat "$GITHUB_STEP_SUMMARY")" ""
}
