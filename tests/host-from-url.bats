#!/usr/bin/env bats

load helpers

setup() {
  setup_env
  script=$REPO_ROOT/scripts/host-from-url.sh
}

@test "writes the host of a URL with a trailing slash" {
  URL=https://www.example.com/ run "$script"
  assert_success
  assert_output_file "host=www.example.com"
}

@test "writes the host of a URL with no path" {
  URL=https://www.example.com run "$script"
  assert_output_file "host=www.example.com"
}

@test "drops the path" {
  URL=https://www.example.com/a/b/c run "$script"
  assert_output_file "host=www.example.com"
}

@test "keeps every label of the host" {
  URL=https://pr-12.preview.example.co.za/ run "$script"
  assert_output_file "host=pr-12.preview.example.co.za"
}

@test "appends to the output file" {
  echo "other=1" > "$GITHUB_OUTPUT"
  URL=https://a.example.com/ run "$script"
  assert_output_file "other=1
host=a.example.com"
}
