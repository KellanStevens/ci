#!/usr/bin/env bats

load helpers

setup() {
  setup_env
  script=$REPO_ROOT/scripts/match-paths.sh
}

# matches PATHS FILE...: run the script with the files on stdin.
matches() {
  local paths=$1
  shift
  printf '%s\n' "$@" | PATHS=$paths "$script"
}

@test "matches a file by its name" {
  run matches "package.json" "package.json"
  assert_success
}

@test "does not match another file" {
  run matches "package.json" "README.md" "docs/package.json"
  assert_failure 1
}

@test "matches everything below a directory" {
  run matches "src" "src/pages/index.astro"
  assert_success
}

@test "matches a directory written with a trailing slash" {
  run matches "public/" "public/logo.svg"
  assert_success
}

@test "does not match a directory that only starts with the same letters" {
  run matches "src" "srcfoo/index.astro" "source.txt"
  assert_failure 1
}

@test "matches a glob where * also matches /" {
  run matches '**/*.astro' "src/pages/index.astro"
  assert_success
  run matches '*.md' "docs/guide/intro.md"
  assert_success
}

@test "a glob does not match another extension" {
  run matches '**/*.astro' "src/pages/index.ts"
  assert_failure 1
}

@test "a ? in a glob matches one character" {
  run matches 'src/?.ts' "src/a.ts"
  assert_success
  run matches 'src/?.ts' "src/ab.ts"
  assert_failure 1
}

@test "ignores a leading ./" {
  run matches "./src" "src/a.ts"
  assert_success
  run matches "./package.json" "package.json"
  assert_success
}

@test "ignores spaces around a path" {
  run matches "   src   " "src/a.ts"
  assert_success
}

@test "skips blank lines" {
  paths=$'\n\n  \nsrc\n\n'
  run matches "$paths" "src/a.ts"
  assert_success
}

@test "tries every path, one on each line" {
  paths=$'docs\npublic/\n**/*.astro'
  run matches "$paths" "public/logo.svg"
  assert_success
  run matches "$paths" "src/index.astro"
  assert_success
  run matches "$paths" "docs/a.md"
  assert_success
  run matches "$paths" "package.json"
  assert_failure 1
}

@test "matches when any one of several files matches" {
  run matches "src" "README.md" ".github/workflows/ci.yml" "src/a.ts"
  assert_success
}

@test "matches a last file that has no new line after it" {
  run bash -c "printf 'README.md\nsrc/a.ts' | PATHS=src '$script'"
  assert_success
}

@test "matches nothing when there are no paths" {
  run matches "" "src/a.ts"
  assert_failure 1
  run matches $'  \n  ' "src/a.ts"
  assert_failure 1
}

@test "matches nothing when there are no files" {
  run bash -c "printf '' | PATHS=src '$script'"
  assert_failure 1
}

@test "does not expand a glob into the files of the working directory" {
  touch a.ts b.ts
  run matches '*' "c/d.ts"
  assert_success
}

@test "a dot in a path is a dot, not any character" {
  run matches "package.json" "packageXjson"
  assert_failure 1
}

@test "a blank path does not match a file that starts with a slash" {
  run matches $'\n  \n' "/etc/passwd"
  assert_failure 1
  run matches $'\nsrc\n' "/etc/passwd"
  assert_failure 1
}
