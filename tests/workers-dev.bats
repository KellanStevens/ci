#!/usr/bin/env bats

load helpers

setup() {
  setup_env
  script=$REPO_ROOT/actions/enforce-access/workers-dev.sh
  api=https://api.cloudflare.com/client/v4
  export CLOUDFLARE_ACCOUNT_ID=$ACCOUNT
  subdomain="$api/accounts/$ACCOUNT/workers/scripts/site-pr-7/subdomain"
}

state() {
  route_curl GET "$subdomain" 200 "{\"success\": true, \"result\": {\"enabled\": $1, \"previews_enabled\": $2, \"extra\": 1}}"
}

@test "passes when workers.dev and the preview URLs are off, and changes nothing" {
  state false false
  run "$script" site-pr-7 pr-7.example.com
  assert_success
  assert_output_has "site-pr-7 is not on workers.dev or its preview URLs."
  assert_equal "$(calls curl)" "GET $subdomain"
}

@test "leaves no temporary file behind, on success or on failure" {
  export TMPDIR=$BATS_TEST_TMPDIR/tmp
  mkdir "$TMPDIR"
  state false false
  run "$script" site-pr-7 pr-7.example.com
  assert_success
  assert_equal "$(ls -A "$TMPDIR")" ""
  rm "$STUB_DIR/curl.routes"
  route_curl GET "$subdomain" 403 '{"errors": []}'
  run "$script" site-pr-7 pr-7.example.com
  assert_failure 1
  assert_equal "$(ls -A "$TMPDIR")" ""
}

@test "turns both off and fails when workers.dev was on" {
  state true false
  route_curl POST "$subdomain" 200 '{}'
  run "$script" site-pr-7 pr-7.example.com
  assert_failure 1
  assert_output_has "::error::site-pr-7 was public on workers.dev or its preview URLs"
  assert_output_has '"workers_dev": false'
  assert_equal "$(calls curl.data)" '{"enabled":false,"previews_enabled":false}'
}

@test "turns both off and fails when only the preview URLs were on" {
  state false true
  route_curl POST "$subdomain" 200 '{}'
  run "$script" site-pr-7 pr-7.example.com
  assert_failure 1
  assert_output_has '"previews_enabled":true'
  assert_equal "$(calls curl | sed -n 2p)" "POST $subdomain"
}

@test "turns both off when both were on, and shows the state it found" {
  state true true
  route_curl POST "$subdomain" 200 '{}'
  run "$script" site-pr-7 pr-7.example.com
  assert_failure 1
  assert_output_has '{"enabled":true,"previews_enabled":true}'
}

@test "fails, and says so, when the turn-off fails" {
  state true true
  route_curl POST "$subdomain" 500 '{}'
  run "$script" site-pr-7 pr-7.example.com
  assert_failure
  refute_output_has "Turned them off"
}

@test "fails with the messages of the API when it cannot read the settings" {
  route_curl GET "$subdomain" 403 '{"errors": [{"code": 10000, "message": "Authentication error"}]}'
  run "$script" site-pr-7 pr-7.example.com
  assert_failure 1
  assert_output_has "(HTTP 403)"
  assert_output_has "10000: Authentication error"
  assert_output_has "Workers Scripts Read"
  refute_has "$(calls curl)" "POST"
}

@test "fails and shows the body when the answer is not JSON" {
  route_curl GET "$subdomain" 404 'Not Found'
  run "$script" site-pr-7 pr-7.example.com
  assert_failure 1
  assert_output_has "Not Found"
}

@test "refuses what is not a Worker name, before any request" {
  for bad in "" Site site_pr -site "a b" 'a/b' 'a/../b'; do
    run "$script" "$bad" pr-7.example.com
    assert_failure 1
    assert_output_has "is not a Worker name."
  done
  assert_equal "$(call_count curl)" 0
}

@test "finds the account from the zone of the host when it is not given" {
  unset CLOUDFLARE_ACCOUNT_ID
  route_curl GET "$api/zones?name=pr-7.example.com" 200 "{\"result\": [{\"account\": {\"id\": \"$OTHER_ACCOUNT\"}}]}"
  route_curl GET "$api/accounts/$OTHER_ACCOUNT/workers/scripts/site-pr-7/subdomain" 200 '{"result": {"enabled": false, "previews_enabled": false}}'
  run "$script" site-pr-7 pr-7.example.com
  assert_success
}

@test "sends the token in a config on stdin, never in the arguments" {
  state false false
  run "$script" site-pr-7 pr-7.example.com
  assert_has "$(calls curl.config)" 'Bearer test-token-123'
  refute_has "$(calls curl.argv)" "test-token-123"
}
