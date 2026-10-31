#!/usr/bin/env bats

load helpers

setup() {
  setup_env
  lib=$REPO_ROOT/actions/lib/cloudflare.sh
  api=https://api.cloudflare.com/client/v4
}

# find_account HOST: run cf_find_account, then print the account.
find_account() {
  run bash -c 'source "$1"; cf_find_account "$2"; echo "ID=$CLOUDFLARE_ACCOUNT_ID"' _ "$lib" "$1"
}

zone() {
  route_curl GET "$api/zones?name=$1" 200 "{\"result\": [{\"account\": {\"id\": \"$2\"}}]}"
}

no_zone() {
  route_curl GET "$api/zones?name=$1" 200 '{"result": []}'
}

# --- cf_curl ---

@test "cf_curl sends the token in a config on stdin" {
  route_curl GET "$api/x" 200 '{}'
  run bash -c 'source "$1"; cf_curl "$2"' _ "$lib" "$api/x"
  assert_success
  assert_equal "$(calls curl.config)" 'header = "Authorization: Bearer test-token-123"'
}

@test "cf_curl keeps the token out of the arguments" {
  route_curl GET "$api/x" 200 '{}'
  run bash -c 'source "$1"; cf_curl "$2"' _ "$lib" "$api/x"
  refute_has "$(calls curl.argv)" "test-token-123"
  assert_has "$(calls curl.argv)" "-K -"
}

@test "cf_curl is quiet, has a timeout and retries" {
  route_curl GET "$api/x" 200 '{}'
  run bash -c 'source "$1"; cf_curl "$2"' _ "$lib" "$api/x"
  assert_has "$(calls curl.argv)" "--silent --show-error --max-time 30 --retry 3"
}

@test "cf_curl passes its arguments on, and prints the body" {
  route_curl POST "$api/y" 200 '{"ok": true}'
  run bash -c 'source "$1"; cf_curl -f -X POST --data "{}" "$2"' _ "$lib" "$api/y"
  assert_success
  assert_output '{"ok": true}'
  assert_equal "$(calls curl)" "POST $api/y"
}

@test "cf_curl fails on an HTTP error with -f" {
  route_curl GET "$api/x" 403 '{}'
  run bash -c 'source "$1"; cf_curl -f "$2"' _ "$lib" "$api/x"
  assert_failure 22
}

@test "cf_curl does not fail on an HTTP error without -f" {
  route_curl GET "$api/x" 403 '{"err": 1}'
  run bash -c 'source "$1"; cf_curl "$2"' _ "$lib" "$api/x"
  assert_success
  assert_output '{"err": 1}'
}

# --- cf_find_account ---

@test "keeps the account that is set, without a request" {
  CLOUDFLARE_ACCOUNT_ID=$ACCOUNT find_account pr-7.example.com
  assert_success
  assert_output "ID=$ACCOUNT"
  assert_equal "$(call_count curl)" 0
}

@test "finds the account from the zone of the host" {
  zone pr-7.example.com "$ACCOUNT"
  find_account pr-7.example.com
  assert_success
  assert_output "ID=$ACCOUNT"
}

@test "walks up to the parent until one is a zone" {
  no_zone pr-1.example.co.za
  zone example.co.za "$ACCOUNT"
  find_account pr-1.example.co.za
  assert_success
  assert_output "ID=$ACCOUNT"
  assert_equal "$(calls curl)" "GET $api/zones?name=pr-1.example.co.za
GET $api/zones?name=example.co.za"
}

@test "stops at the first zone" {
  zone pr-1.example.com "$ACCOUNT"
  zone example.com "$OTHER_ACCOUNT"
  find_account pr-1.example.com
  assert_output "ID=$ACCOUNT"
  assert_equal "$(call_count curl)" 1
}

@test "tries the last name with a dot, and no further" {
  no_zone a.b.c
  no_zone b.c
  find_account a.b.c
  assert_failure 1
  assert_equal "$(call_count curl)" 2
}

@test "fails, and says what to do, when no parent is a zone" {
  no_zone pr-1.example.com
  no_zone example.com
  find_account pr-1.example.com
  assert_failure 1
  assert_output_has "::error::The Cloudflare token cannot read the zone of pr-1.example.com. Set the account ID, or give the token Zone Read."
}

@test "shows the same message when the token lacks Zone Read (403)" {
  route_curl GET "$api/zones" 403 '{"errors": [{"code": 9109, "message": "Unauthorized"}]}'
  find_account pr-1.example.com
  assert_failure 1
  assert_output_has "The Cloudflare token cannot read the zone of pr-1.example.com."
}

@test "asks for each zone by name, as a query" {
  zone pr-1.example.com "$ACCOUNT"
  find_account pr-1.example.com
  assert_equal "$(calls curl)" "GET $api/zones?name=pr-1.example.com"
}

@test "exports the account for the scripts that it starts" {
  zone pr-1.example.com "$ACCOUNT"
  run bash -c 'source "$1"; cf_find_account "$2"; bash -c "echo CHILD=\$CLOUDFLARE_ACCOUNT_ID"' _ "$lib" pr-1.example.com
  assert_success
  assert_output "CHILD=$ACCOUNT"
}

@test "refuses an account ID of the wrong shape" {
  for bad in short 0123456789abcdef0123456789abcdeg 0123456789ABCDEF0123456789ABCDEF 0123456789abcdef0123456789abcdef0 "../../x" "0123456789abcdef0123456789abcde/" "$ACCOUNT?x=1"; do
    CLOUDFLARE_ACCOUNT_ID=$bad find_account pr-1.example.com
    assert_failure 1
    assert_output_has "is not a Cloudflare account ID."
  done
}

@test "refuses an account ID of the wrong shape that the API returned" {
  zone pr-1.example.com "../../evil"
  find_account pr-1.example.com
  assert_failure 1
  assert_output_has "is not a Cloudflare account ID."
}

@test "treats an empty account as not set" {
  zone pr-1.example.com "$ACCOUNT"
  CLOUDFLARE_ACCOUNT_ID="" find_account pr-1.example.com
  assert_success
  assert_output "ID=$ACCOUNT"
}
