#!/usr/bin/env bats

load helpers

setup() {
  setup_env
  script=$REPO_ROOT/scripts/bundle-preview-worker.sh
}

@test "bundles the Worker of the preview environment into the runner temp directory" {
  PREVIEW_ENV=preview run "$script"
  assert_success
  assert_equal "$(calls bunx)" "--no-install wrangler deploy --dry-run --env preview --outdir $RUNNER_TEMP/worker"
}

@test "uses the environment that the caller names" {
  PREVIEW_ENV=staging run "$script"
  assert_has "$(calls bunx)" "--env staging"
}

@test "fails when Wrangler fails" {
  route_cmd bunx deploy 1
  PREVIEW_ENV=preview run "$script"
  assert_failure 1
}
