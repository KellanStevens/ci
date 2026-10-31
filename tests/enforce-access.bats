#!/usr/bin/env bats

# enforce-access.sh decides what to do with the exit codes of the scripts next
# to it. These tests copy the actions and replace those scripts with fakes that
# log the call and exit with the status in FAKE_<NAME>.

load helpers

setup() {
  setup_env
  cp -R "$REPO_ROOT/actions" "$BATS_TEST_TMPDIR/actions"
  actions=$BATS_TEST_TMPDIR/actions
  script=$actions/enforce-access/enforce-access.sh
  fake "$actions/check-access/check-access.sh" check-access FAKE_CHECK_ACCESS
  fake "$actions/enforce-access/workers-dev.sh" workers-dev FAKE_WORKERS_DEV
  fake "$actions/delete-preview/delete-preview.sh" delete-preview FAKE_DELETE_PREVIEW
  fake "$actions/remove-domain/remove-domain.sh" remove-domain FAKE_REMOVE_DOMAIN
}

# fake PATH NAME VARIABLE: a script that logs "NAME ARGS (team=...)" and exits
# with the value of VARIABLE, or 0.
fake() {
  cat > "$1" <<FAKE
#!/usr/bin/env bash
echo "$2 \$* team=\${ACCESS_TEAM:-}" >> "\$STUB_DIR/enforce.log"
exit "\${$3:-0}"
FAKE
  chmod +x "$1"
}

@test "does nothing more when Access protects the site" {
  run "$script" pr-7.example.com remove site-pr-7 site-pr-7
  assert_success
  assert_equal "$(calls enforce)" "workers-dev site-pr-7 pr-7.example.com team=
check-access pr-7.example.com team="
}

@test "turns off workers.dev before it checks Access" {
  run "$script" pr-7.example.com remove site-pr-7 site-pr-7
  assert_equal "$(calls enforce | sed -n 1p | cut -d' ' -f1)" workers-dev
  assert_equal "$(calls enforce | sed -n 2p | cut -d' ' -f1)" check-access
}

@test "warns and skips workers.dev when no Worker is named for it" {
  run "$script" pr-7.example.com remove site-pr-7
  assert_success
  assert_output_has "::warning::No Worker to check for workers.dev"
  refute_has "$(calls enforce)" "workers-dev"
}

@test "passes the team to the check" {
  ACCESS_TEAM=myteam run "$script" pr-7.example.com remove site-pr-7 site-pr-7
  assert_has "$(calls enforce)" "check-access pr-7.example.com team=myteam"
}

@test "refuses on-unreachable other than remove and keep, before any check" {
  for bad in "" Remove delete true; do
    run "$script" pr-7.example.com "$bad" site-pr-7
    assert_failure 1
    assert_output_has "on-unreachable must be \"remove\" or \"keep\""
  done
  assert_equal "$(call_count enforce)" 0
}

@test "refuses a team that is not a team name, before any check" {
  ACCESS_TEAM=Not_A_Team run "$script" pr-7.example.com remove site-pr-7 site-pr-7
  assert_failure 1
  assert_output_has "is not an Access team name."
  assert_equal "$(call_count enforce)" 0
}

# --- workers.dev ---

@test "fails, and keeps the site, when workers.dev was on but Access protects it" {
  FAKE_WORKERS_DEV=1 run "$script" pr-7.example.com remove site-pr-7 site-pr-7
  assert_failure 1
  refute_has "$(calls enforce)" "delete-preview"
  refute_has "$(calls enforce)" "remove-domain"
}

@test "fails with the status of workers.dev when it cannot check" {
  FAKE_WORKERS_DEV=2 run "$script" pr-7.example.com remove site-pr-7 site-pr-7
  assert_failure 2
}

@test "still takes a public site down when workers.dev also failed" {
  FAKE_WORKERS_DEV=1 FAKE_CHECK_ACCESS=1 run "$script" pr-7.example.com remove site-pr-7 site-pr-7
  assert_failure 1
  assert_has "$(calls enforce)" "delete-preview site-pr-7 pr-7.example.com"
}

@test "turns off workers.dev even when the site is going to be taken down" {
  FAKE_CHECK_ACCESS=1 run "$script" pr-7.example.com remove site-pr-7 site-pr-7
  assert_equal "$(calls enforce | sed -n 1p | cut -d' ' -f1)" workers-dev
}

# --- a public site ---

@test "deletes the preview Worker and its domain when the site is public" {
  FAKE_CHECK_ACCESS=1 run "$script" pr-7.example.com remove site-pr-7 site-pr-7
  assert_failure 1
  assert_has "$(calls enforce)" "delete-preview site-pr-7 pr-7.example.com team="
  refute_has "$(calls enforce)" "remove-domain"
}

@test "detaches only the domain when there is no preview Worker" {
  FAKE_CHECK_ACCESS=1 run "$script" example.com remove ""
  assert_failure 1
  assert_has "$(calls enforce)" "remove-domain example.com"
  refute_has "$(calls enforce)" "delete-preview"
}

@test "takes a public site down whatever on-unreachable says" {
  for mode in remove keep; do
    rm -f "$STUB_DIR/enforce.log"
    FAKE_CHECK_ACCESS=1 run "$script" pr-7.example.com "$mode" site-pr-7 site-pr-7
    assert_failure 1
    assert_has "$(calls enforce)" "delete-preview"
  done
}

# --- a site that cannot be reached ---

@test "takes an unreachable site down when on-unreachable is remove, and fails with 2" {
  FAKE_CHECK_ACCESS=2 run "$script" pr-7.example.com remove site-pr-7 site-pr-7
  assert_failure 2
  assert_output_has "::warning::Could not check Access on pr-7.example.com. Taking the site down, as on-unreachable is remove."
  assert_has "$(calls enforce)" "delete-preview site-pr-7 pr-7.example.com"
}

@test "keeps an unreachable site when on-unreachable is keep, and fails with 2" {
  FAKE_CHECK_ACCESS=2 run "$script" pr-7.example.com keep site-pr-7 site-pr-7
  assert_failure 2
  assert_output_has "Keeping the site, as on-unreachable is keep."
  refute_has "$(calls enforce)" "delete-preview"
  refute_has "$(calls enforce)" "remove-domain"
}

@test "treats any other failure of the check as unreachable" {
  for code in 3 64 126 127 255; do
    rm -f "$STUB_DIR/enforce.log"
    FAKE_CHECK_ACCESS=$code run "$script" pr-7.example.com keep site-pr-7 site-pr-7
    assert_failure 2
    refute_has "$(calls enforce)" "delete-preview"
  done
}

@test "takes the domain down for an unreachable production site when asked to remove" {
  FAKE_CHECK_ACCESS=2 run "$script" example.com remove ""
  assert_failure 2
  assert_has "$(calls enforce)" "remove-domain example.com"
}

# --- the takedown fails ---

@test "fails with the status of the takedown when it cannot delete the preview" {
  FAKE_CHECK_ACCESS=1 FAKE_DELETE_PREVIEW=7 run "$script" pr-7.example.com remove site-pr-7 site-pr-7
  assert_failure 7
}

@test "fails with the status of the takedown when it cannot detach the domain" {
  FAKE_CHECK_ACCESS=1 FAKE_REMOVE_DOMAIN=9 run "$script" example.com remove ""
  assert_failure 9
}
