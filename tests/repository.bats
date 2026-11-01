#!/usr/bin/env bats

# Checks of the repository itself: that the workflows and the scripts agree.

load helpers

setup() {
  cd "$REPO_ROOT" || return 1
}

# scripts_called: the paths of the scripts that the workflows run.
scripts_called() {
  grep -rhoE '(\.ci/)?scripts/[a-z0-9-]+\.sh' .github/workflows | sed 's#^\.ci/##' | sort -u
}

@test "every script that a workflow runs exists and is executable" {
  [ -n "$(scripts_called)" ]
  for script in $(scripts_called); do
    [ -f "$script" ] || fail "$script is run by a workflow but does not exist."
    [ -x "$script" ] || fail "$script is not executable."
  done
}

@test "every script in scripts/ is run by a workflow" {
  for script in scripts/*.sh; do
    case $script in scripts/match-paths.sh) continue ;; esac # called by find-preview-pr.sh
    scripts_called | grep -qx "$script" || fail "$script is run by no workflow."
  done
}

@test "every script has a test file" {
  for script in scripts/*.sh actions/*/*.sh; do
    name=$(basename "$script" .sh)
    [ -f "tests/$name.bats" ] || fail "$script has no tests/$name.bats."
  done
}

@test "every script has a shebang and stops on errors" {
  for script in scripts/*.sh actions/*/*.sh; do
    case $script in actions/lib/*) continue ;; esac # sourced: see the next test
    [ "$(head -n 1 "$script")" = '#!/usr/bin/env bash' ] || fail "$script has no bash shebang."
    [ -x "$script" ] || fail "$script is not executable."
    grep -q '^set -euo pipefail$' "$script" || fail "$script does not set -euo pipefail."
  done
}

@test "the library is sourced, not run" {
  [ ! -x actions/lib/cloudflare.sh ]
  [ "$(head -n 1 actions/lib/cloudflare.sh)" = '# shellcheck shell=bash' ]
}

@test "workflows and actions keep no logic in run blocks: none is longer than 8 lines" {
  # Logic belongs in a script, where it can be tested.
  for file in .github/workflows/*.yml actions/*/action.yml; do
    run awk -v max=8 '
      { match($0, /^ */); indent = RLENGTH }
      in_run && $0 !~ /^ *$/ && indent <= run_indent {
        if (lines > max) print FILENAME ":" start " (" lines " lines)"
        in_run = 0
      }
      in_run { lines++ }
      /^ *run: [|>]/ { in_run = 1; run_indent = indent; start = NR; lines = 0 }
      END { if (in_run && lines > max) print FILENAME ":" start " (" lines " lines)" }
    ' "$file"
    [ -z "$output" ] || fail "Move this run block into a script: $output"
  done
}

@test "the check job names that release.yml requires are jobs of lint.yml" {
  required=$(sed -n 's/^ *REQUIRED: //p' .github/workflows/release.yml)
  [ -n "$required" ]
  for job in $required; do
    grep -qE "^    name: $job$" .github/workflows/lint.yml || fail "release.yml requires $job, which is not a job of lint.yml."
  done
}

@test "every action pins its steps to a commit" {
  # A mutable tag such as @v4 can change under the workflow.
  run grep -rnE 'uses: [^./][^@]*@' .github actions --include='*.yml'
  [ -n "$output" ]
  run bash -c "grep -rhE 'uses: [^./][^@ ]*@' .github actions --include='*.yml' | grep -vE '@[0-9a-f]{40}( |\$)'"
  [ -z "$output" ] || fail "Not pinned to a commit: $output"
}
