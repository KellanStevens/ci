#!/usr/bin/env bats

load helpers

setup() {
  setup_env
  script=$REPO_ROOT/scripts/find-preview-pr.sh
  sha=0123456789abcdef0123456789abcdef01234567
  other=fedcba9876543210fedcba9876543210fedcba98

  export GH_TOKEN=t REPO=owner/site OWNER=owner BRANCH=feature
  export HEAD_SHA=$sha NAME=site HOST='pr-{pr}.example.com' PATHS=""
}

# One open pull request at $sha.
open_pr() {
  route_gh "repos/owner/site/pulls -f" 0 "[{\"number\": ${1:-7}, \"draft\": false, \"head\": {\"sha\": \"$sha\"}}]"
}

@test "finds the pull request and the Worker and host of its preview" {
  open_pr 7
  run "$script"
  assert_success
  assert_output_file "number=7
host=pr-7.example.com
worker=site-pr-7"
}

@test "asks for the open pull requests of the branch of the run" {
  open_pr 7
  run "$script"
  assert_has "$(calls gh)" "api --method GET repos/owner/site/pulls -f state=open -f head=owner:feature"
}

@test "does not look at the files when there are no paths" {
  open_pr 7
  run "$script"
  refute_has "$(calls gh)" "/files"
}

@test "deploys nothing when no pull request is open at the branch" {
  route_gh "repos/owner/site/pulls -f" 0 "[]"
  run "$script"
  assert_success
  assert_output_has "::notice::No open pull request that is ready for review is at $sha. Nothing to deploy."
  assert_output_file "number="
}

@test "skips a draft" {
  route_gh "repos/owner/site/pulls -f" 0 "[{\"number\": 7, \"draft\": true, \"head\": {\"sha\": \"$sha\"}}]"
  run "$script"
  assert_success
  assert_output_file "number="
}

@test "skips a run of an older commit" {
  route_gh "repos/owner/site/pulls -f" 0 "[{\"number\": 7, \"draft\": false, \"head\": {\"sha\": \"$other\"}}]"
  run "$script"
  assert_success
  assert_output_file "number="
}

@test "picks the pull request that is at the commit and not a draft" {
  route_gh "repos/owner/site/pulls -f" 0 "[
    {\"number\": 5, \"draft\": true,  \"head\": {\"sha\": \"$sha\"}},
    {\"number\": 6, \"draft\": false, \"head\": {\"sha\": \"$other\"}},
    {\"number\": 8, \"draft\": false, \"head\": {\"sha\": \"$sha\"}},
    {\"number\": 9, \"draft\": false, \"head\": {\"sha\": \"$sha\"}}
  ]"
  run "$script"
  assert_success
  assert_has "$(github_output)" "number=8"
}

@test "refuses a head commit that is not a full SHA, before it calls the API" {
  for bad in "" abc123 "${sha:0:39}" "${sha}0" "${sha^^}" 'x";id;"' "${sha:0:39}g"; do
    HEAD_SHA=$bad run "$script"
    assert_failure 1
    assert_output_has "is not a commit SHA."
  done
  assert_equal "$(call_count gh)" 0
}

@test "passes the branch as a field, not as part of the jq filter" {
  open_pr 7
  BRANCH='x" or true or "' run "$script"
  assert_success
  assert_has "$(calls gh)" 'head=owner:x" or true or "'
  assert_output_file "number=7
host=pr-7.example.com
worker=site-pr-7"
}

@test "fails when the API fails" {
  route_gh "repos/owner/site/pulls -f" 1
  run "$script"
  assert_failure 1
  assert_output_file ""
}

# --- paths ---

@test "deploys when the pull request changes a file under a path" {
  open_pr 7
  route_gh "pulls/7/files" 0 '[{"filename": "README.md"}, {"filename": "src/pages/index.astro"}]'
  PATHS="src" run "$script"
  assert_success
  assert_has "$(github_output)" "number=7"
}

@test "asks for all the files of the pull request" {
  open_pr 7
  route_gh "pulls/7/files" 0 '[{"filename": "src/a.ts"}]'
  PATHS="src" run "$script"
  assert_has "$(calls gh)" "api --paginate repos/owner/site/pulls/7/files"
}

@test "deploys nothing when the pull request changes none of the paths" {
  open_pr 7
  route_gh "pulls/7/files" 0 '[{"filename": "README.md"}, {"filename": ".github/workflows/ci.yml"}]'
  PATHS=$'src\npublic/' run "$script"
  assert_success
  assert_output_has "::notice::Pull request #7 changes none of the preview paths. Nothing to deploy."
  assert_output_file "number="
}

@test "counts the old name of a renamed file" {
  open_pr 7
  route_gh "pulls/7/files" 0 '[{"filename": "archive/page.astro", "previous_filename": "src/page.astro"}]'
  PATHS="src" run "$script"
  assert_success
  assert_has "$(github_output)" "number=7"
}

@test "counts a file with the same path as a glob" {
  open_pr 7
  route_gh "pulls/7/files" 0 '[{"filename": "src/pages/index.astro"}]'
  PATHS='**/*.astro' run "$script"
  assert_success
  assert_has "$(github_output)" "number=7"
}

@test "treats paths of only spaces as no paths" {
  open_pr 7
  PATHS=$'  \n ' run "$script"
  assert_success
  assert_has "$(github_output)" "number=7"
  refute_has "$(calls gh)" "/files"
}

@test "fails when the list of files cannot be read" {
  open_pr 7
  route_gh "pulls/7/files" 1
  PATHS="src" run "$script"
  assert_failure
}

# --- names ---

@test "puts the number into every {pr} of the host" {
  open_pr 12
  HOST='pr-{pr}.preview-{pr}.example.com' run "$script"
  assert_success
  assert_has "$(github_output)" "host=pr-12.preview-12.example.com"
}

@test "refuses a host with no {pr}" {
  open_pr 7
  HOST='preview.example.com' run "$script"
  assert_failure 1
  assert_output_has "is not a hostname with {pr} in it."
  assert_output_file ""
}

@test "refuses a host that is not a hostname" {
  open_pr 7
  for bad in 'PR-{pr}.example.com' 'pr-{pr}.example.com/path' 'pr {pr}.example.com' '-pr-{pr}.example.com' 'pr-{pr}.example.com;id'; do
    HOST=$bad run "$script"
    assert_failure 1
    assert_output_has "is not a hostname with {pr} in it."
  done
  assert_output_file ""
}

@test "refuses a site name that is not a Worker name" {
  open_pr 7
  for bad in Site my_site -site 'a b' 'a/b'; do
    NAME=$bad run "$script"
    assert_failure 1
    assert_output_has "is not a Worker name."
  done
  assert_output_file ""
}
