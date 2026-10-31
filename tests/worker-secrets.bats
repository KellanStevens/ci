#!/usr/bin/env bats

load helpers

setup() {
  setup_env
  script=$REPO_ROOT/actions/worker-secrets/worker-secrets.sh
  file=$RUNNER_TEMP/worker-secrets.json
  export REQUIRED="" OPTIONAL="" SECRETS_JSON='{}' VARS_JSON='{}' HELP="See README."
}

# json_has FILTER: the secrets file satisfies the jq filter.
json_has() {
  jq -e "$1" "$file" > /dev/null
}

@test "writes a required secret to the file and its path to the output" {
  REQUIRED="API_KEY" SECRETS_JSON='{"API_KEY": "abc"}' run "$script"
  assert_success
  assert_output_has "Added API_KEY."
  assert_output_file "file=$file"
  json_has '. == {"API_KEY": "abc"}'
}

@test "writes several secrets" {
  REQUIRED="A B" OPTIONAL="C" SECRETS_JSON='{"A": "1", "B": "2", "C": "3"}' run "$script"
  assert_success
  json_has '. == {"A": "1", "B": "2", "C": "3"}'
}

@test "splits the lists on new lines too" {
  REQUIRED=$'A\nB' SECRETS_JSON='{"A": "1", "B": "2"}' run "$script"
  assert_success
  json_has '. == {"A": "1", "B": "2"}'
}

@test "reads NAME=SOURCE: the value of SOURCE under the name NAME" {
  REQUIRED="ACCESS_AUD=ACCESS_AUD_PREVIEW" SECRETS_JSON='{"ACCESS_AUD_PREVIEW": "aud123", "ACCESS_AUD": "wrong"}' run "$script"
  assert_success
  json_has '. == {"ACCESS_AUD": "aud123"}'
}

@test "reads a variable when there is no secret of that name" {
  REQUIRED="TEAM" SECRETS_JSON='{}' VARS_JSON='{"TEAM": "myteam"}' run "$script"
  assert_success
  json_has '. == {"TEAM": "myteam"}'
}

@test "a secret wins over a variable of the same name" {
  REQUIRED="TEAM" SECRETS_JSON='{"TEAM": "from-secret"}' VARS_JSON='{"TEAM": "from-var"}' run "$script"
  json_has '. == {"TEAM": "from-secret"}'
}

@test "an empty secret does not hide a variable" {
  REQUIRED="TEAM" SECRETS_JSON='{"TEAM": ""}' VARS_JSON='{"TEAM": "from-var"}' run "$script"
  assert_success
  json_has '. == {"TEAM": "from-var"}'
}

@test "stops when a required secret is missing, and says how to fix it" {
  REQUIRED="API_KEY" HELP="Set it in the preview environment." run "$script"
  assert_failure 1
  assert_output_has "::error::Set the API_KEY secret or variable. Set it in the preview environment."
  [ ! -e "$file" ]
  assert_output_file ""
}

@test "stops when a required secret is empty" {
  REQUIRED="API_KEY" SECRETS_JSON='{"API_KEY": ""}' run "$script"
  assert_failure 1
  [ ! -e "$file" ]
}

@test "reports every missing required secret, not only the first" {
  REQUIRED="A B C" SECRETS_JSON='{"B": "2"}' run "$script"
  assert_failure 1
  assert_output_has "Set the A secret"
  assert_output_has "Set the C secret"
  refute_output_has "Set the B secret"
}

@test "warns about a missing optional secret and leaves it out" {
  REQUIRED="A" OPTIONAL="B" SECRETS_JSON='{"A": "1"}' HELP="Fix it." run "$script"
  assert_success
  assert_output_has "::warning::B is empty, so the Worker runs without B. Fix it."
  json_has '. == {"A": "1"}'
}

@test "names the name, not the source, in the warning of an optional NAME=SOURCE" {
  OPTIONAL="NAME=SOURCE" run "$script"
  assert_output_has "SOURCE is empty, so the Worker runs without NAME."
}

@test "writes no file and an empty output when there is nothing to upload" {
  run "$script"
  assert_success
  assert_output_has "No Worker secrets to upload."
  assert_output_file "file="
  [ ! -e "$file" ]
}

@test "writes no file when every secret is optional and missing" {
  OPTIONAL="A B" run "$script"
  assert_success
  assert_output_file "file="
  [ ! -e "$file" ]
}

@test "makes the file readable by its owner only" {
  REQUIRED="A" SECRETS_JSON='{"A": "1"}' run "$script"
  assert_equal "$(stat -c %a "$file")" 600
}

@test "never prints the value of a secret" {
  REQUIRED="A" OPTIONAL="B" SECRETS_JSON='{"A": "super-secret-value", "B": "other-secret-value"}' run "$script"
  refute_output_has "super-secret-value"
  refute_output_has "other-secret-value"
  refute_has "$(github_output)" "secret-value"
}

# --- values ---

@test "keeps the new lines of a value, also at the end, as in a PEM key" {
  REQUIRED="KEY" SECRETS_JSON='{"KEY": "-----BEGIN-----\nabc\n-----END-----\n"}' run "$script"
  assert_success
  json_has '.KEY == "-----BEGIN-----\nabc\n-----END-----\n"'
}

@test "keeps quotes, backslashes, dollar signs and unicode" {
  REQUIRED="A" SECRETS_JSON='{"A": "q\"uote \\ back $(id) `x` é ✓ {\"j\":1}"}' run "$script"
  assert_success
  json_has '.A == "q\"uote \\ back $(id) `x` é ✓ {\"j\":1}"'
}

@test "keeps a value that is only spaces" {
  REQUIRED="A" SECRETS_JSON='{"A": "  "}' run "$script"
  assert_success
  json_has '.A == "  "'
}

@test "keeps a very long value" {
  long=$(head -c 50000 /dev/zero | tr '\0' 'x')
  REQUIRED="A" SECRETS_JSON="{\"A\": \"$long\"}" run "$script"
  assert_success
  json_has '.A | length == 50000'
}

# --- names ---

@test "refuses a name that is not a secret name" {
  for bad in 1BAD A-B 'A;id' '$(id)' 'A.B' '=A' 'A=' 'A=B=C'; do
    REQUIRED="$bad" run "$script"
    assert_failure 1
    assert_output_has "is not a secret name."
  done
}

@test "refuses a name before it reads any secret" {
  REQUIRED="OK 1BAD" SECRETS_JSON='{"OK": "1"}' run "$script"
  assert_failure 1
  [ ! -e "$file" ]
}

@test "does not expand a glob into file names" {
  touch API_KEY
  REQUIRED='*' run "$script"
  assert_failure 1
  assert_output_has '"*" is not a secret name.'
}

@test "accepts names with lower case, digits and underscores" {
  REQUIRED="my_Key2 _x" SECRETS_JSON='{"my_Key2": "1", "_x": "2"}' run "$script"
  assert_success
}

# --- tokens of the deploy ---

@test "refuses the Cloudflare token as a source, whatever its case" {
  for bad in CLOUDFLARE_API_TOKEN cloudflare_api_token Cloudflare_Api_Token; do
    REQUIRED="LEAK=$bad" SECRETS_JSON="{\"$bad\": \"tok\"}" run "$script"
    assert_failure 1
    assert_output_has "is a token of the deploy, not a Worker secret."
    [ ! -e "$file" ]
  done
}

@test "refuses the GitHub token as a source, whatever its case" {
  for bad in GITHUB_TOKEN github_token; do
    REQUIRED="LEAK=$bad" SECRETS_JSON="{\"$bad\": \"tok\"}" run "$script"
    assert_failure 1
    assert_output_has "is a token of the deploy, not a Worker secret."
  done
}

@test "refuses a token of the deploy given by its own name" {
  REQUIRED="CLOUDFLARE_API_TOKEN" SECRETS_JSON='{"CLOUDFLARE_API_TOKEN": "tok"}' run "$script"
  assert_failure 1
}

@test "refuses a token of the deploy in the optional list too" {
  OPTIONAL="GITHUB_TOKEN" SECRETS_JSON='{"GITHUB_TOKEN": "tok"}' run "$script"
  assert_failure 1
  [ ! -e "$file" ]
}

@test "never writes the token of the deploy to the file" {
  REQUIRED="A" SECRETS_JSON='{"A": "1", "CLOUDFLARE_API_TOKEN": "tok", "GITHUB_TOKEN": "gh"}' run "$script"
  assert_success
  json_has '. == {"A": "1"}'
}

@test "refuses a bad name even when a secret of that name exists, and writes no file" {
  for bad in 1BAD A-B; do
    REQUIRED="$bad" SECRETS_JSON="{\"$bad\": \"value\"}" run "$script"
    assert_failure 1
    assert_output_has "is not a secret name."
    [ ! -e "$file" ]
    assert_output_file ""
  done
}

@test "refuses a bad source even when a secret of that name exists, and writes no file" {
  REQUIRED="GOOD=1BAD" SECRETS_JSON='{"1BAD": "value"}' run "$script"
  assert_failure 1
  [ ! -e "$file" ]
}
