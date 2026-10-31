#!/usr/bin/env bats

load helpers

setup() {
  setup_env
  script=$REPO_ROOT/scripts/deploy-preview.sh
  sha=0123456789abcdef0123456789abcdef01234567
  export WRANGLER_ENV=preview WORKER_NAME=site-pr-7 PREVIEW_HOST=pr-7.example.com
  export HEAD_SHA=$sha PR_NUMBER=7 SECRETS_FILE="" WORKER=false
  export WORKER_SRC=$RUNNER_TEMP/worker
}

@test "deploys the site as its own Worker on its own domain" {
  run "$script"
  assert_success
  assert_equal "$(calls bunx)" "--no-install wrangler deploy --env preview --name site-pr-7 --domain pr-7.example.com --tag $sha --message PR #7 @ 0123456"
}

@test "writes the URL to the output and the link to the summary" {
  run "$script"
  assert_output_file "url=https://pr-7.example.com"
  assert_equal "$(cat "$GITHUB_STEP_SUMMARY")" "Preview: https://pr-7.example.com"
}

@test "uploads the secrets file when there is one" {
  SECRETS_FILE=/tmp/s.json run "$script"
  assert_has "$(calls bunx)" "--secrets-file /tmp/s.json"
}

@test "leaves out --secrets-file when there is none" {
  run "$script"
  refute_has "$(calls bunx)" "--secrets-file"
}

@test "runs only the Wrangler that is installed" {
  run "$script"
  assert_has "$(calls bunx)" "--no-install wrangler deploy"
}

@test "writes nothing when the deploy fails" {
  route_cmd bunx deploy 1
  run "$script"
  assert_failure 1
  assert_output_file ""
  assert_equal "$(cat "$GITHUB_STEP_SUMMARY")" ""
}

# --- Worker ---

@test "deploys the bundle without bundling it again, with the config of main" {
  touch wrangler.jsonc
  WORKER=true run "$script"
  assert_success
  assert_equal "$(calls bunx)" "--no-install wrangler deploy $WORKER_SRC/index.js --no-bundle --config wrangler.jsonc --env preview --name site-pr-7 --domain pr-7.example.com --tag $sha --message PR #7 @ 0123456"
}

@test "finds wrangler.json and wrangler.toml too" {
  touch wrangler.json
  WORKER=true run "$script"
  assert_has "$(calls bunx)" "--config wrangler.json "
  rm wrangler.json "$STUB_DIR/bunx.log"
  touch wrangler.toml
  WORKER=true run "$script"
  assert_has "$(calls bunx)" "--config wrangler.toml "
}

@test "prefers wrangler.jsonc, then wrangler.json, then wrangler.toml" {
  touch wrangler.toml wrangler.json wrangler.jsonc
  WORKER=true run "$script"
  assert_has "$(calls bunx)" "--config wrangler.jsonc "
  rm wrangler.jsonc "$STUB_DIR/bunx.log"
  WORKER=true run "$script"
  assert_has "$(calls bunx)" "--config wrangler.json "
}

@test "fails when a Worker has no Wrangler config" {
  WORKER=true run "$script"
  assert_failure 1
  assert_output_has "::error::No Wrangler config in the repository root."
  assert_equal "$(call_count bunx)" 0
}

@test "does not need a config for a site with no Worker" {
  run "$script"
  assert_success
  refute_has "$(calls bunx)" "--config"
  refute_has "$(calls bunx)" "--no-bundle"
}
