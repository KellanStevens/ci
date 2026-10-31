#!/usr/bin/env bats

load helpers

setup() {
  setup_env
  script=$REPO_ROOT/scripts/audit.sh
}

@test "audits with no flags when nothing is ignored" {
  IGNORE="" run "$script"
  assert_success
  assert_equal "$(calls bun)" "audit"
}

@test "ignores a GHSA advisory" {
  IGNORE="GHSA-gcqx-w48m-w2h4" run "$script"
  assert_success
  assert_equal "$(calls bun)" "audit --ignore=GHSA-gcqx-w48m-w2h4"
}

@test "ignores a CVE" {
  IGNORE="CVE-2024-12345" run "$script"
  assert_success
  assert_equal "$(calls bun)" "audit --ignore=CVE-2024-12345"
}

@test "ignores several advisories, separated by spaces or new lines" {
  IGNORE=$'GHSA-gcqx-w48m-w2h4  CVE-2024-1\nGHSA-2222-3333-4444' run "$script"
  assert_success
  assert_equal "$(calls bun)" "audit --ignore=GHSA-gcqx-w48m-w2h4 --ignore=CVE-2024-1 --ignore=GHSA-2222-3333-4444"
}

@test "refuses what is not an advisory ID, before it audits" {
  for bad in --registry=evil GHSA-xxxx GHSA-gcqx-w48m CVE-24-1 cve-2024-1 'CVE-2024-1;id' GHSA-gcqx-w48m-w2h4-extra GHSA-aaaa-bbbb-cccc; do
    IGNORE="$bad" run "$script"
    assert_failure 1
    assert_output_has "is not an advisory ID."
  done
  assert_equal "$(call_count bun)" 0
}

@test "does not expand a glob into file names" {
  touch GHSA-gcqx-w48m-w2h4
  IGNORE='*' run "$script"
  assert_failure 1
  assert_output_has '"*" is not an advisory ID.'
  assert_equal "$(call_count bun)" 0
}

@test "does not audit when one of several IDs is bad" {
  IGNORE="CVE-2024-1 nope" run "$script"
  assert_failure 1
  assert_equal "$(call_count bun)" 0
}

@test "fails when bun audit finds a vulnerability" {
  route_cmd bun audit 1
  IGNORE="" run "$script"
  assert_failure 1
}
