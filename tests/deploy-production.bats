#!/usr/bin/env bats

load helpers

setup() {
  setup_env
  script=$REPO_ROOT/scripts/deploy-production.sh
  sha=0123456789abcdef0123456789abcdef01234567
}

@test "deploys with the environment, the commit as tag and a message" {
  WRANGLER_ENV=production SECRETS_FILE="" GITHUB_SHA=$sha run "$script"
  assert_success
  assert_equal "$(calls bunx)" "--no-install wrangler deploy --env production --tag $sha --message main @ 0123456"
}

@test "names the environment even when it is empty" {
  WRANGLER_ENV="" SECRETS_FILE="" GITHUB_SHA=$sha run "$script"
  assert_success
  assert_has "$(calls bunx)" "deploy --env  --tag $sha"
}

@test "uploads the secrets file when there is one" {
  WRANGLER_ENV=production SECRETS_FILE=/tmp/secrets.json GITHUB_SHA=$sha run "$script"
  assert_success
  assert_has "$(calls bunx)" "--secrets-file /tmp/secrets.json"
}

@test "leaves out --secrets-file when there is none" {
  WRANGLER_ENV=production SECRETS_FILE="" GITHUB_SHA=$sha run "$script"
  refute_has "$(calls bunx)" "--secrets-file"
}

@test "runs only the Wrangler that is installed, never one from the registry" {
  WRANGLER_ENV=production SECRETS_FILE="" GITHUB_SHA=$sha run "$script"
  assert_has "$(calls bunx)" "--no-install wrangler"
}

@test "fails when Wrangler fails" {
  route_cmd bunx deploy 3
  WRANGLER_ENV=production SECRETS_FILE="" GITHUB_SHA=$sha run "$script"
  assert_failure 3
}
