#!/usr/bin/env bats

load helpers

setup() {
  setup_env
  script=$REPO_ROOT/actions/preview-comment/preview-comment.sh
  sha=0123456789abcdef0123456789abcdef01234567
  export GH_TOKEN=t REPO=owner/site PR_NUMBER=7 URL=https://pr-7.example.com
  export STATUS=deployed HEAD_SHA=$sha MARKER=site-preview AUTHOR='github-actions[bot]'
  export RUN_URL=https://github.com/owner/site/actions/runs/99
  list="--paginate repos/owner/site/issues/7/comments"
  post="--method POST repos/owner/site/issues/7/comments"
}

# existing JSON: the comments of the pull request.
existing() {
  route_gh "$list" 0 "$1"
}

none() { existing '[]'; }

# A comment by the bot, with the marker of the site at the start.
mine() {
  printf '{"id": %s, "user": {"login": "github-actions[bot]"}, "body": "<!-- site-preview -->\\n### old"}' "$1"
}

# --- finding the comment ---

@test "adds a comment when the pull request has none" {
  none
  route_gh "$post" 0
  run "$script"
  assert_success
  assert_output_has "Added a comment."
  assert_has "$(calls gh)" "$post"
}

@test "updates the comment of the bot that has the marker" {
  existing "[$(mine 55)]"
  route_gh "--method PATCH repos/owner/site/issues/comments/55" 0
  run "$script"
  assert_success
  assert_output_has "Updated comment 55."
  refute_has "$(calls gh)" "--method POST"
}

@test "does not update a comment of another user, also with the marker" {
  existing '[{"id": 55, "user": {"login": "someone"}, "body": "<!-- site-preview -->\n### fake"}]'
  route_gh "$post" 0
  run "$script"
  assert_output_has "Added a comment."
  refute_has "$(calls gh)" "PATCH"
}

@test "does not update a comment that has the marker only further down" {
  existing '[{"id": 55, "user": {"login": "github-actions[bot]"}, "body": "quote: <!-- site-preview -->"}]'
  route_gh "$post" 0
  run "$script"
  assert_output_has "Added a comment."
}

@test "does not update the comment of another marker" {
  existing '[{"id": 55, "user": {"login": "github-actions[bot]"}, "body": "<!-- other-preview -->\n### x"}]'
  route_gh "$post" 0
  run "$script"
  assert_output_has "Added a comment."
}

@test "does not take a longer marker for its own" {
  existing '[{"id": 55, "user": {"login": "github-actions[bot]"}, "body": "<!-- site-preview-2 -->\n### x"}]'
  route_gh "$post" 0
  run "$script"
  assert_output_has "Added a comment."
}

@test "updates the first of several comments of the bot" {
  existing "[$(mine 55), $(mine 66)]"
  route_gh "--method PATCH repos/owner/site/issues/comments/55" 0
  run "$script"
  assert_output_has "Updated comment 55."
}

@test "finds the comment on a later page" {
  existing "[{\"id\": 1, \"user\": {\"login\": \"x\"}, \"body\": \"hi\"}][$(mine 77)]"
  route_gh "--method PATCH repos/owner/site/issues/comments/77" 0
  run "$script"
  assert_output_has "Updated comment 77."
}

@test "finds the comment of another author when AUTHOR names it" {
  existing '[{"id": 88, "user": {"login": "my-app[bot]"}, "body": "<!-- site-preview -->\n### x"}]'
  route_gh "--method PATCH repos/owner/site/issues/comments/88" 0
  AUTHOR='my-app[bot]' run "$script"
  assert_output_has "Updated comment 88."
}

@test "takes the marker and the author as values, not as part of the jq filter" {
  existing '[{"id": 9, "user": {"login": "a\"b"}, "body": "<!-- x\" or true -->\n### y"}]'
  route_gh "--method PATCH repos/owner/site/issues/comments/9" 0
  AUTHOR='a"b' MARKER='x" or true' run "$script"
  assert_success
  assert_output_has "Updated comment 9."
}

@test "fails when the comments cannot be read" {
  route_gh "$list" 1
  run "$script"
  assert_failure
}

@test "fails when the comment cannot be written" {
  none
  route_gh "$post" 1
  run "$script"
  assert_failure
}

# --- the text ---

@test "starts the body with the hidden marker" {
  none
  route_gh "$post" 0
  run "$script"
  body=$(field body)
  assert_equal "${body%%$'\n'*}" "<!-- site-preview -->"
}

@test "shows the preview as ready, with the link and the short commit" {
  none
  route_gh "$post" 0
  run "$script"
  body=$(field body)
  assert_has "$body" "### ✅ Preview ready"
  assert_has "$body" "| **Preview** | 🔗 https://pr-7.example.com |"
  assert_has "$body" '| **Commit** | `0123456` |'
  refute_has "$body" "$sha"
  assert_has "$body" "| **Logs** | [Workflow run](https://github.com/owner/site/actions/runs/99) |"
  assert_has "$body" "UTC"
}

@test "shows a deploy under way, and says the link is not live" {
  none
  route_gh "$post" 0
  STATUS=deploying run "$script"
  body=$(field body)
  assert_has "$body" "### 🚀 Deploying preview…"
  assert_has "$body" "(not live yet)"
  assert_has "$body" "This comment updates when the deploy finishes."
}

@test "shows a failed deploy with a link to the logs and what to do" {
  none
  route_gh "$post" 0
  STATUS=failed run "$script"
  body=$(field body)
  assert_has "$body" "### ❌ Preview failed"
  assert_has "$body" "[See what went wrong](https://github.com/owner/site/actions/runs/99)"
  assert_has "$body" "Push a new commit or re-run the workflow to try again."
}

@test "shows a removed preview as not accessible" {
  existing "[$(mine 55)]"
  route_gh "--method PATCH repos/owner/site/issues/comments/55" 0
  STATUS=removed run "$script"
  body=$(field body)
  assert_has "$body" "### 🧹 Preview deleted"
  assert_has "$body" "(not accessible anymore)"
}

@test "shows a preview that could not be deleted as maybe live" {
  none
  route_gh "$post" 0
  STATUS=delete-failed run "$script"
  body=$(field body)
  assert_has "$body" "### ⚠️ Preview not deleted"
  assert_has "$body" "(may still be live)"
  assert_has "$body" "Re-run the workflow to try again."
}

@test "adds no note to a ready preview" {
  none
  route_gh "$post" 0
  run "$script"
  body=$(field body)
  refute_has "$body" "to try again"
  refute_has "$body" "updates when"
}

# --- removed and delete-failed ---

@test "a removed preview with no comment adds none" {
  none
  STATUS=removed run "$script"
  assert_success
  assert_output_has "No preview comment to update."
  refute_has "$(calls gh)" "--method"
}

@test "a preview that could not be deleted adds a comment if there is none" {
  none
  route_gh "$post" 0
  STATUS=delete-failed run "$script"
  assert_success
  assert_output_has "Added a comment."
}

# --- input ---

@test "refuses a status it does not know" {
  for bad in "" Deployed ready 'deployed;id'; do
    STATUS=$bad run "$script"
    assert_failure 1
    assert_output_has "is not a preview status."
  done
  assert_equal "$(call_count gh)" 0
}

@test "refuses what is not a pull request number, before it calls the API" {
  for bad in "" 0 01 abc "1/../2" "7;id" -1; do
    PR_NUMBER=$bad run "$script"
    assert_failure 1
    assert_output_has "is not a pull request number."
  done
  assert_equal "$(call_count gh)" 0
}

@test "shows the short commit on every status" {
  for status in deploying deployed failed delete-failed; do
    none
    route_gh "$post" 0
    STATUS=$status run "$script"
    assert_success
    assert_has "$(field body)" '| **Commit** | `0123456` |'
    rm -f "$STUB_DIR/gh.routes"
  done
  existing "[$(mine 55)]"
  route_gh "--method PATCH repos/owner/site/issues/comments/55" 0
  STATUS=removed run "$script"
  assert_has "$(field body)" '| **Commit** | `0123456` |'
}

@test "shows when it was updated on the statuses that are final" {
  for status in deployed delete-failed; do
    none
    route_gh "$post" 0
    STATUS=$status run "$script"
    assert_has "$(field body)" "| **Updated** | 🕐 "
    rm -f "$STUB_DIR/gh.routes"
  done
}

@test "does not show a time on a deploy under way or a failed one" {
  for status in deploying failed; do
    none
    route_gh "$post" 0
    STATUS=$status run "$script"
    refute_has "$(field body)" "**Updated**"
    rm -f "$STUB_DIR/gh.routes"
  done
}

@test "links the logs on the statuses that have a run to look at" {
  for status in deploying deployed failed delete-failed; do
    none
    route_gh "$post" 0
    STATUS=$status run "$script"
    assert_has "$(field body)" "https://github.com/owner/site/actions/runs/99"
    rm -f "$STUB_DIR/gh.routes"
  done
}
