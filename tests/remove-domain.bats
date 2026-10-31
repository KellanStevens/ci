#!/usr/bin/env bats

load helpers

setup() {
  setup_env
  script=$REPO_ROOT/actions/remove-domain/remove-domain.sh
  api=https://api.cloudflare.com/client/v4
  export CLOUDFLARE_ACCOUNT_ID=$ACCOUNT
  domains="$api/accounts/$ACCOUNT/workers/domains"
}

@test "detaches the custom domain of the host" {
  route_curl GET "$domains?hostname=pr-7.example.com" 200 '{"result": [{"id": "dom-1"}]}'
  route_curl DELETE "$domains/dom-1" 200 '{}'
  run "$script" pr-7.example.com
  assert_success
  assert_output_has "Removed pr-7.example.com (dom-1)."
  assert_equal "$(calls curl)" "GET $domains?hostname=pr-7.example.com
DELETE $domains/dom-1"
}

@test "detaches every domain that the lookup returns" {
  route_curl GET "$domains?hostname=" 200 '{"result": [{"id": "dom-1"}, {"id": "dom-2"}]}'
  route_curl DELETE "$domains/dom-" 200 '{}'
  run "$script" pr-7.example.com
  assert_success
  assert_has "$(calls curl)" "DELETE $domains/dom-1"
  assert_has "$(calls curl)" "DELETE $domains/dom-2"
}

@test "is not an error when there is no such domain, and deletes nothing" {
  route_curl GET "$domains?hostname=" 200 '{"result": []}'
  run "$script" pr-7.example.com
  assert_success
  assert_output_has "No custom domain for pr-7.example.com."
  refute_has "$(calls curl)" "DELETE"
}

@test "can run twice for the same host" {
  route_curl GET "$domains?hostname=" 200 '{"result": [{"id": "dom-1"}]}'
  route_curl GET "$domains?hostname=" 200 '{"result": []}'
  route_curl DELETE "$domains/dom-1" 200 '{}'
  run "$script" pr-7.example.com
  assert_success
  run "$script" pr-7.example.com
  assert_success
  assert_output_has "No custom domain"
}

@test "fails when the lookup fails" {
  route_curl GET "$domains?hostname=" 403 '{"errors": [{"code": 10000, "message": "Authentication error"}]}'
  run "$script" pr-7.example.com
  assert_failure
  refute_has "$(calls curl)" "DELETE"
}

@test "fails when a delete fails, and does not say it removed the domain" {
  route_curl GET "$domains?hostname=" 200 '{"result": [{"id": "dom-1"}]}'
  route_curl DELETE "$domains/dom-1" 500 '{}'
  run "$script" pr-7.example.com
  assert_failure
  refute_output_has "Removed"
}

@test "refuses what is not a hostname, before any request" {
  for bad in "" PR-7.example.com "pr 7.example.com" "-a.example.com" "a.example.com-" ".example.com" "a/b" 'a$(id).com' "a.com?x=1" "a.com;id" "a.com
b.com"; do
    run "$script" "$bad"
    assert_failure 1
    assert_output_has "is not a hostname."
  done
  assert_equal "$(call_count curl)" 0
}

@test "accepts a hostname with digits, dashes and dots" {
  route_curl GET "$domains?hostname=" 200 '{"result": []}'
  run "$script" a-1.b2.example.co.za
  assert_success
}

@test "needs a hostname" {
  run "$script"
  assert_failure
  assert_equal "$(call_count curl)" 0
}

@test "finds the account from the zone when the account is not given" {
  unset CLOUDFLARE_ACCOUNT_ID
  route_curl GET "$api/zones?name=pr-7.example.com" 200 "{\"result\": [{\"account\": {\"id\": \"$OTHER_ACCOUNT\"}}]}"
  route_curl GET "$api/accounts/$OTHER_ACCOUNT/workers/domains" 200 '{"result": []}'
  run "$script" pr-7.example.com
  assert_success
  assert_has "$(calls curl)" "GET $api/accounts/$OTHER_ACCOUNT/workers/domains?hostname=pr-7.example.com"
}

@test "sends the token in a config on stdin, never in the arguments" {
  route_curl GET "$domains?hostname=" 200 '{"result": []}'
  run "$script" pr-7.example.com
  assert_has "$(calls curl.config)" 'header = "Authorization: Bearer test-token-123"'
  refute_has "$(calls curl.argv)" "test-token-123"
}
