#!/usr/bin/env bats

load helpers

setup() {
  setup_env
  script=$REPO_ROOT/scripts/add-noindex.sh
  mkdir dist
}

@test "creates _headers with the noindex rule" {
  SITE_PATH=dist run "$script"
  assert_success
  assert_equal "$(cat dist/_headers)" "
/*
  X-Robots-Tag: noindex, nofollow"
}

@test "adds the rule after the headers that are there" {
  printf '/assets/*\n  Cache-Control: max-age=31536000\n' > dist/_headers
  SITE_PATH=dist run "$script"
  assert_success
  assert_equal "$(cat dist/_headers)" "/assets/*
  Cache-Control: max-age=31536000

/*
  X-Robots-Tag: noindex, nofollow"
}

@test "starts the rule on its own line when the file has no final new line" {
  printf '/a\n  X-A: 1' > dist/_headers
  SITE_PATH=dist run "$script"
  grep -qx '/\*' dist/_headers
  grep -qx '  X-A: 1' dist/_headers
}

@test "fails when the site directory is missing" {
  SITE_PATH=nope run "$script"
  assert_failure
}
