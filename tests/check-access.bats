#!/usr/bin/env bats

load helpers

setup() {
  setup_env
  script=$REPO_ROOT/actions/check-access/check-access.sh
  url=https://pr-7.example.com/
  login=https://myteam.cloudflareaccess.com/cdn-cgi/access/login/pr-7.example.com
}

@test "passes when the site redirects to the Access login" {
  route_curl GET "$url" 302 "" "$login"
  run "$script" pr-7.example.com
  assert_success
  assert_output_has "Access protects $url."
}

@test "passes for every kind of redirect" {
  for code in 301 302 303 307 308; do
    rm -f "$STUB_DIR/curl.routes"
    route_curl GET "$url" "$code" "" "$login"
    run "$script" pr-7.example.com
    assert_success
  done
}

@test "asks for the root of the host, once, when the answer is clear" {
  route_curl GET "$url" 302 "" "$login"
  run "$script" pr-7.example.com
  assert_equal "$(calls curl)" "GET $url"
  assert_equal "$(call_count sleep)" 0
}

@test "fails with 1 when the site answers with a page and no login" {
  for code in 200 204 404 403 401; do
    rm -f "$STUB_DIR/curl.routes"
    route_curl GET "$url" "$code" "<html>"
    run "$script" pr-7.example.com
    assert_failure 1
    assert_output_has "::error::$url answered $code without a login."
  done
}

@test "fails with 1 when the site redirects somewhere else" {
  route_curl GET "$url" 302 "" "https://pr-7.example.com/login"
  run "$script" pr-7.example.com
  assert_failure 1
  assert_output_has "redirects to https://pr-7.example.com/login, not to the Access login."
}

@test "fails with 1 at once, without trying again" {
  route_curl GET "$url" 200 ""
  run "$script" pr-7.example.com
  assert_equal "$(call_count curl)" 1
  assert_equal "$(call_count sleep)" 0
}

# --- the team ---

@test "without a team, a redirect to any team passes" {
  route_curl GET "$url" 302 "" "https://anyone.cloudflareaccess.com/cdn-cgi/access/login/x"
  run "$script" pr-7.example.com
  assert_success
}

@test "with a team, a redirect to that team passes" {
  route_curl GET "$url" 302 "" "$login"
  ACCESS_TEAM=myteam run "$script" pr-7.example.com
  assert_success
}

@test "with a team, a redirect to another team fails" {
  route_curl GET "$url" 302 "" "https://evil.cloudflareaccess.com/cdn-cgi/access/login/x"
  ACCESS_TEAM=myteam run "$script" pr-7.example.com
  assert_failure 1
  assert_output_has "not to the Access login."
}

@test "with a team, a team whose name ends with it fails" {
  route_curl GET "$url" 302 "" "https://notmyteam.cloudflareaccess.com/login"
  ACCESS_TEAM=myteam run "$script" pr-7.example.com
  assert_failure 1
}

@test "a team name is text, not a pattern" {
  route_curl GET "$url" 302 "" "https://myXteam.cloudflareaccess.com/login"
  ACCESS_TEAM=my-team run "$script" pr-7.example.com
  assert_failure 1
}

@test "a redirect to a look-alike domain fails, with or without a team" {
  for location in \
    "https://myteam.cloudflareaccess.com.evil.com/" \
    "https://myteam.cloudflareaccess.com@evil.com/" \
    "http://myteam.cloudflareaccess.com/login" \
    "https://evil.com/?https://myteam.cloudflareaccess.com/" \
    "https://myteam.cloudflareaccess.org/login" \
    "https://myteam-cloudflareaccess.com/login"; do
    rm -f "$STUB_DIR/curl.routes"
    route_curl GET "$url" 302 "" "$location"
    run "$script" pr-7.example.com
    assert_failure 1
    ACCESS_TEAM=myteam run "$script" pr-7.example.com
    assert_failure 1
  done
}

@test "refuses a team that is not a team name, before any request" {
  for bad in Not_A_Team MyTeam -team team- "my.team" "a b" 'a.*' 'a|b' '(a)' 'a$'; do
    ACCESS_TEAM=$bad run "$script" pr-7.example.com
    assert_failure 64
    assert_output_has "is not an Access team name."
  done
  assert_equal "$(call_count curl)" 0
}

@test "accepts a team with digits and dashes" {
  route_curl GET "$url" 302 "" "https://my-team-2.cloudflareaccess.com/login"
  ACCESS_TEAM=my-team-2 run "$script" pr-7.example.com
  assert_success
}

# --- waiting for a new domain ---

@test "tries again after an error of the server, and passes when Access answers" {
  route_curl GET "$url" 503 ""
  route_curl GET "$url" 502 ""
  route_curl GET "$url" 302 "" "$login"
  run "$script" pr-7.example.com
  assert_success
  assert_equal "$(call_count curl)" 3
  assert_equal "$(calls sleep)" "10
10"
  assert_output_has "Attempt 1: $url gave 503"
}

@test "tries again when the host cannot be reached" {
  route_curl GET "$url" 000 ""
  route_curl GET "$url" 302 "" "$login"
  run "$script" pr-7.example.com
  assert_success
  assert_equal "$(call_count curl)" 2
}

@test "fails with 1 when the site is public after a retry" {
  route_curl GET "$url" 503 ""
  route_curl GET "$url" 200 ""
  run "$script" pr-7.example.com
  assert_failure 1
}

@test "gives up after 10 attempts with 2" {
  route_curl GET "$url" 503 ""
  run "$script" pr-7.example.com
  assert_failure 2
  assert_equal "$(call_count curl)" 10
  assert_equal "$(call_count sleep)" 10
  assert_output_has "::error::Could not reach $url to check Access."
}

@test "gives up with 2 when the host never answers" {
  route_curl GET "$url" 000 ""
  run "$script" pr-7.example.com
  assert_failure 2
  assert_equal "$(call_count curl)" 10
}

@test "needs a hostname" {
  run "$script"
  assert_failure
  assert_equal "$(call_count curl)" 0
}
