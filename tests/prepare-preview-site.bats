#!/usr/bin/env bats

load helpers

setup() {
  setup_env
  script=$REPO_ROOT/scripts/prepare-preview-site.sh
  export SRC=$BATS_TEST_TMPDIR/download/site
  export WORKER_SRC=$BATS_TEST_TMPDIR/download/worker
  export SITE_PATH=dist WORKER=false
  mkdir -p "$SRC" "$WORKER_SRC"
  echo secret > "$BATS_TEST_TMPDIR/outside.txt"
}

@test "copies the site to the site path" {
  mkdir -p "$SRC/assets"
  echo '<h1>hi</h1>' > "$SRC/index.html"
  echo 'body{}' > "$SRC/assets/app.css"
  run "$script"
  assert_success
  assert_equal "$(cat dist/index.html)" '<h1>hi</h1>'
  assert_equal "$(cat dist/assets/app.css)" 'body{}'
}

@test "fails when the site is empty" {
  run "$script"
  assert_failure 1
  assert_output_has "::error::The site is empty."
  [ ! -e dist ]
}

@test "fails when the site has only hidden files, and copies nothing" {
  touch "$SRC/.env"
  run "$script"
  assert_success
  [ -d dist ]
  [ -z "$(ls -A dist)" ]
}

@test "replaces what was at the site path" {
  mkdir dist
  echo old > dist/old.html
  echo new > "$SRC/index.html"
  run "$script"
  assert_success
  [ ! -e dist/old.html ]
  [ -f dist/index.html ]
}

@test "removes links, so that they cannot point Wrangler at a file of the runner" {
  echo ok > "$SRC/index.html"
  ln -s "$BATS_TEST_TMPDIR/outside.txt" "$SRC/link.txt"
  ln -s /etc "$SRC/etc"
  ln -s index.html "$SRC/alias.html"
  mkdir "$SRC/sub"
  ln -s "$BATS_TEST_TMPDIR/outside.txt" "$SRC/sub/deep.txt"
  run "$script"
  assert_success
  [ -f dist/index.html ]
  [ ! -e dist/link.txt ] && [ ! -L dist/link.txt ]
  [ ! -e dist/etc ] && [ ! -L dist/etc ]
  [ ! -e dist/alias.html ] && [ ! -L dist/alias.html ]
  [ ! -L dist/sub/deep.txt ]
  [ -f "$BATS_TEST_TMPDIR/outside.txt" ]
}

@test "removes broken links too" {
  echo ok > "$SRC/index.html"
  ln -s /nonexistent/file "$SRC/broken"
  run "$script"
  assert_success
  [ ! -L dist/broken ]
}

@test "removes pipes" {
  echo ok > "$SRC/index.html"
  mkfifo "$SRC/pipe"
  run "$script"
  assert_success
  [ ! -p dist/pipe ]
}

@test "removes hidden files and directories" {
  echo ok > "$SRC/index.html"
  echo KEY=1 > "$SRC/.env"
  mkdir "$SRC/.git"
  echo x > "$SRC/.git/config"
  mkdir "$SRC/sub"
  echo x > "$SRC/sub/.secret"
  run "$script"
  assert_success
  [ ! -e dist/.env ]
  [ ! -e dist/.git ]
  [ ! -e dist/sub/.secret ]
  [ -f dist/index.html ]
}

@test "keeps .well-known and .assetsignore" {
  echo ok > "$SRC/index.html"
  mkdir "$SRC/.well-known"
  echo '{}' > "$SRC/.well-known/security.txt"
  echo '_worker.js' > "$SRC/.assetsignore"
  run "$script"
  assert_success
  [ -f dist/.well-known/security.txt ]
  [ -f dist/.assetsignore ]
}

@test "keeps _headers and _redirects, which do not start with a dot" {
  echo ok > "$SRC/index.html"
  echo '/* ' > "$SRC/_headers"
  echo '/a /b 301' > "$SRC/_redirects"
  run "$script"
  assert_success
  [ -f dist/_headers ]
  [ -f dist/_redirects ]
}

@test "removes a link inside .well-known" {
  mkdir "$SRC/.well-known"
  echo '{}' > "$SRC/.well-known/ok.txt"
  ln -s "$BATS_TEST_TMPDIR/outside.txt" "$SRC/.well-known/link.txt"
  run "$script"
  assert_success
  [ -f dist/.well-known/ok.txt ]
  [ ! -L dist/.well-known/link.txt ]
}

@test "copies to a site path with more than one level" {
  echo ok > "$SRC/index.html"
  mkdir -p build
  SITE_PATH=build/public run "$script"
  assert_success
  [ -f build/public/index.html ]
}

@test "leaves the Worker bundle alone when there is no Worker" {
  echo ok > "$SRC/index.html"
  echo wasm > "$WORKER_SRC/module.wasm"
  run "$script"
  assert_success
  [ -f "$WORKER_SRC/module.wasm" ]
}

# --- Worker ---

@test "fails when the Worker bundle has no index.js" {
  echo ok > "$SRC/index.html"
  echo x > "$WORKER_SRC/other.js"
  WORKER=true run "$script"
  assert_failure 1
  assert_output_has "::error::The Worker bundle has no index.js."
}

@test "keeps JavaScript and source maps of the Worker bundle" {
  echo ok > "$SRC/index.html"
  echo 1 > "$WORKER_SRC/index.js"
  echo 2 > "$WORKER_SRC/chunk.mjs"
  echo 3 > "$WORKER_SRC/index.js.map"
  WORKER=true run "$script"
  assert_success
  [ -f "$WORKER_SRC/index.js" ]
  [ -f "$WORKER_SRC/chunk.mjs" ]
  [ -f "$WORKER_SRC/index.js.map" ]
}

@test "deletes the other files of the Worker bundle, and names them" {
  echo ok > "$SRC/index.html"
  echo 1 > "$WORKER_SRC/index.js"
  echo '#!/bin/sh' > "$WORKER_SRC/run.sh"
  echo x > "$WORKER_SRC/README.md"
  mkdir "$WORKER_SRC/sub"
  echo x > "$WORKER_SRC/sub/data.json"
  WORKER=true run "$script"
  assert_success
  [ ! -e "$WORKER_SRC/run.sh" ]
  [ ! -e "$WORKER_SRC/README.md" ]
  [ ! -e "$WORKER_SRC/sub/data.json" ]
  assert_output_has "$WORKER_SRC/run.sh"
  assert_output_has "$WORKER_SRC/README.md"
}

@test "removes links from the Worker bundle" {
  echo ok > "$SRC/index.html"
  echo 1 > "$WORKER_SRC/index.js"
  ln -s "$BATS_TEST_TMPDIR/outside.txt" "$WORKER_SRC/evil.js"
  WORKER=true run "$script"
  assert_success
  [ ! -L "$WORKER_SRC/evil.js" ]
  [ -f "$BATS_TEST_TMPDIR/outside.txt" ]
}

@test "does not accept an index.js that is a link" {
  echo ok > "$SRC/index.html"
  ln -s "$BATS_TEST_TMPDIR/outside.txt" "$WORKER_SRC/index.js"
  WORKER=true run "$script"
  # [ -f ] follows the link, so this passes the check; the cleanup then removes it.
  [ ! -L "$WORKER_SRC/index.js" ]
}
