#!/usr/bin/env bats

load helpers

setup() {
  setup_env
  script=$REPO_ROOT/actions/delete-preview/delete-preview.sh
  api=https://api.cloudflare.com/client/v4
  export CLOUDFLARE_ACCOUNT_ID=$ACCOUNT
  domains="$api/accounts/$ACCOUNT/workers/domains"
  worker_url="$api/accounts/$ACCOUNT/workers/scripts/site-pr-7?force=true"
  # A host with one domain, and a Worker that is deleted.
  route_curl GET "$domains?hostname=pr-7.example.com" 200 '{"result": [{"id": "dom-1"}]}'
  route_curl DELETE "$domains/dom-1" 200 '{}'
}

@test "detaches the domain, then deletes the Worker" {
  route_curl DELETE "$worker_url" 200 '{"success": true}'
  run "$script" site-pr-7 pr-7.example.com
  assert_success
  assert_output_has "Deleted the Worker site-pr-7."
  assert_equal "$(calls curl)" "GET $domains?hostname=pr-7.example.com
DELETE $domains/dom-1
DELETE $worker_url"
}

@test "leaves no temporary file behind, on success or on failure" {
  export TMPDIR=$BATS_TEST_TMPDIR/tmp
  mkdir "$TMPDIR"
  route_curl DELETE "$worker_url" 200 '{}'
  run "$script" site-pr-7 pr-7.example.com
  assert_success
  assert_equal "$(ls -A "$TMPDIR")" ""
  rm "$STUB_DIR/curl.routes"
  route_curl GET "$domains?hostname=pr-7.example.com" 200 '{"result": []}'
  route_curl DELETE "$worker_url" 500 '{"errors": []}'
  run "$script" site-pr-7 pr-7.example.com
  assert_failure 1
  assert_equal "$(ls -A "$TMPDIR")" ""
}

@test "forces the delete, even if another Worker binds to this one" {
  route_curl DELETE "$worker_url" 200 '{}'
  run "$script" site-pr-7 pr-7.example.com
  assert_has "$(calls curl)" "scripts/site-pr-7?force=true"
}

@test "detaches the domain of each host" {
  route_curl GET "$domains?hostname=pr-7.other.com" 200 '{"result": [{"id": "dom-2"}]}'
  route_curl DELETE "$domains/dom-2" 200 '{}'
  route_curl DELETE "$worker_url" 200 '{}'
  run "$script" site-pr-7 pr-7.example.com pr-7.other.com
  assert_success
  assert_has "$(calls curl)" "DELETE $domains/dom-1"
  assert_has "$(calls curl)" "DELETE $domains/dom-2"
}

@test "is not an error when the Worker is missing (code 10007)" {
  route_curl DELETE "$worker_url" 404 '{"errors": [{"code": 10007, "message": "workers.api.error.script_not_found"}]}'
  run "$script" site-pr-7 pr-7.example.com
  assert_success
  assert_output_has "::notice::No preview Worker site-pr-7 to delete."
}

@test "is an error when the 404 is for something else" {
  route_curl DELETE "$worker_url" 404 '{"errors": [{"code": 7003, "message": "No route for the URI"}]}'
  run "$script" site-pr-7 pr-7.example.com
  assert_failure 1
  assert_output_has "::error::Could not delete the Worker site-pr-7 (HTTP 404)."
  assert_output_has "7003: No route for the URI"
}

@test "is an error when a 404 has no JSON body, and shows the body" {
  route_curl DELETE "$worker_url" 404 'Not Found'
  run "$script" site-pr-7 pr-7.example.com
  assert_failure 1
  assert_output_has "(HTTP 404)"
  assert_output_has "Not Found"
}

@test "is an error for a failure of the API, and shows its messages" {
  route_curl DELETE "$worker_url" 403 '{"errors": [{"code": 10000, "message": "Authentication error"}]}'
  run "$script" site-pr-7 pr-7.example.com
  assert_failure 1
  assert_output_has "(HTTP 403)"
  assert_output_has "10000: Authentication error"
}

@test "is an error for a server error" {
  route_curl DELETE "$worker_url" 500 '{}'
  run "$script" site-pr-7 pr-7.example.com
  assert_failure 1
  assert_output_has "(HTTP 500)"
}

@test "does not delete the Worker when a domain cannot be detached" {
  rm "$STUB_DIR/curl.routes"
  route_curl GET "$domains?hostname=pr-7.example.com" 200 '{"result": [{"id": "dom-1"}]}'
  route_curl DELETE "$domains/dom-1" 500 '{}'
  run "$script" site-pr-7 pr-7.example.com
  assert_failure
  refute_has "$(calls curl)" "scripts/site-pr-7"
}

@test "refuses what is not a Worker name, before any request" {
  for bad in "" Site site_pr -site site- "a b" "a/b" 'a$(id)' "a?force=false"; do
    run "$script" "$bad" pr-7.example.com
    assert_failure 1
    assert_output_has "is not a Worker name."
  done
  assert_equal "$(call_count curl)" 0
}

@test "refuses a call with no host, before any request" {
  run "$script" site-pr-7
  assert_failure 1
  assert_output_has "::error::No hostname for site-pr-7."
  assert_equal "$(call_count curl)" 0
}

@test "finds the account once, from the zone of the first host" {
  unset CLOUDFLARE_ACCOUNT_ID
  route_curl GET "$api/zones?name=pr-7.example.com" 200 "{\"result\": [{\"account\": {\"id\": \"$ACCOUNT\"}}]}"
  route_curl DELETE "$worker_url" 200 '{}'
  run "$script" site-pr-7 pr-7.example.com
  assert_success
  assert_equal "$(calls curl | grep -c '/zones')" 1
}
