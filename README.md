# ci

Shared CI/CD for Astro sites that run on Cloudflare Workers.

Each site keeps its own settings (hostnames, checks, Worker secrets) in short
caller workflows. This repository holds the steps that are the same
everywhere, so a fix lands once and reaches every site as a Renovate pull
request.

There are two layers:

- **Actions** (`actions/`): composite actions that a workflow calls step by
  step. Use these when a site needs a job that the reusable workflows do not
  cover, such as a database migration.
- **Reusable workflows** (`.github/workflows/`): whole jobs for the common
  case, called with `uses:` from a job of the site.

## Pinning

Pin every reference to a full commit SHA, with the release tag as a comment,
as for any third-party action:

```yaml
uses: KellanStevens/ci/.github/workflows/check.yml@<sha> # v1.0.0
```

Renovate updates the SHA and the comment when a new tag is released. A
reusable workflow checks out this repository at its own commit
(`job.workflow_sha`) to run the actions, so a workflow and the actions it uses
always come from the same commit.

## Wrangler

A site must list `wrangler` in its `package.json`, so that `bun.lock` pins it.
`check.yml`, `deploy.yml` and `preview.yml` run `bunx --no-install wrangler`,
which uses only the installed copy and fails if there is none. Without
`--no-install`, `bunx` would download the latest Wrangler from the registry
into a step that holds the Cloudflare token. Renovate then updates Wrangler
like any other dependency.

## Secrets

This repository holds no secrets. A caller passes each secret by name, which
works across GitHub accounts and organisations (`secrets: inherit` does not)
and for secrets that exist only in an environment:

```yaml
secrets:
  CLOUDFLARE_API_TOKEN: ${{ secrets.CLOUDFLARE_API_TOKEN }}
```

The reusable workflows set `environment: production` or `environment: preview`
on their deploy jobs, so the environment secrets and protection rules of the
site apply.

## Development

`lint.yml` runs [actionlint](https://github.com/rhysd/actionlint) on the
workflows, and shellcheck on the scripts of the actions. To run them locally:

```sh
nix shell nixpkgs#actionlint nixpkgs#shellcheck -c sh -c \
  'actionlint && shellcheck --external-sources $(git ls-files "*.sh")'
```

## Actions

### `actions/setup`

Install Bun and Node at the versions in `.bun-version` and `.nvmrc`, restore
`node_modules`, and, with `build-cache: true`, the Astro build cache.

```yaml
- uses: KellanStevens/ci/actions/setup@<sha> # v1.0.0
  with:
    build-cache: true # in jobs that run `bun run build`
```

### `actions/worker-secrets`

Write the Worker secrets for `wrangler deploy --secrets-file`. A required
secret that is empty stops the job, and an optional one gives a warning. A
name can read another secret or a variable, as `NAME=SOURCE`.

```yaml
- id: secrets
  uses: KellanStevens/ci/actions/worker-secrets@<sha> # v1.0.0
  with:
    required: ACCESS_AUD=ACCESS_AUD_PREVIEW TURNSTILE_SECRET_KEY
    optional: RESEND_API_KEY
    secrets: ${{ toJSON(secrets) }}
    vars: ${{ toJSON(vars) }}
- run: bunx --no-install wrangler deploy --secrets-file "${{ steps.secrets.outputs.file }}"
```

The file is JSON, so a value can hold any character. `file` is empty when
there are no secrets to upload. `CLOUDFLARE_API_TOKEN` and `GITHUB_TOKEN`
cannot be a source: they belong to the deploy, and a preview Worker runs the
code of the pull request.

### `actions/remove-domain` and `actions/delete-preview`

`remove-domain` detaches a Workers custom domain and its DNS record.
`delete-preview` detaches the domains of a preview and deletes its Worker.
Neither fails if there is nothing to delete, so they can run more than once.
Any other error fails the step. Both call the Cloudflare API, so they need no
Wrangler and no `actions/setup`.

```yaml
- uses: KellanStevens/ci/actions/delete-preview@<sha> # v1.0.0
  with:
    worker-name: example-pr-12
    hosts: pr-12.example.com
    cloudflare-api-token: ${{ secrets.CLOUDFLARE_API_TOKEN }}
```

Without `account-id`, they find the account from the zone of the hostname,
which needs Zone Read on the token.

### `actions/check-access`

Fail unless Cloudflare Access protects a hostname. Output `public` is `"true"`
when the site answered without a login, so that the job can take it down. To
check and take it down in one step, use `enforce-access`.

### `actions/enforce-access`

Check that Cloudflare Access protects a hostname, and take the site down if it
does not. The step fails unless Access protects the site. Use it for previews
and production alike.

- A site that answers without a login is always taken down.
- When the site cannot be reached, Access is neither proven nor disproven.
  `on-unreachable` decides: `remove` (the default) takes the site down, so a
  site that cannot be proven safe is not served. `keep` leaves it up. This
  suits production, where a flaky check should not cause an outage.
- With `worker-name`, it deletes the preview Worker and its domain, like
  `delete-preview`. Without it, it detaches the domain only, like
  `remove-domain`.

```yaml
- uses: KellanStevens/ci/actions/enforce-access@<sha> # v1.0.0
  with:
    host: pr-12.example.com
    worker-name: example-pr-12 # leave out for production
    on-unreachable: remove # or keep
    cloudflare-api-token: ${{ secrets.CLOUDFLARE_API_TOKEN }}
```

Without `account-id`, it finds the account from the zone of the hostname,
which needs Zone Read on the token.

### `actions/preview-comment`

Keep one comment with the state of the preview on a pull request, and edit it
on each push and each state. `status` is `deploying`, `deployed` (the default,
with the link), `failed`, `removed` or `delete-failed`. The comment is a table
with an emoji title for each state. Needs `pull-requests: write`. Keep the
`marker` of the comments a site already has, or the next push adds a second
comment. With a `token` other than the default, set `author` to the login it
comments as, for example `my-app[bot]`. Only a comment by that login is
edited.

## Reusable workflows

A job that calls a reusable workflow shows in the checks as
`<caller job> / <job>`, for example `check / check`.

### `audit.yml`

Check `bun.lock` for known vulnerabilities. Do not make a deploy wait for it.

```yaml
audit:
  uses: KellanStevens/ci/.github/workflows/audit.yml@<sha> # v1.0.0
  with:
    # GHSA-gcqx-w48m-w2h4: deepmerge, no fix yet. Only the shadcn CLI uses it.
    ignore: GHSA-gcqx-w48m-w2h4
```

### `check.yml`

Run the package scripts of a site in one job, then upload the build as the
`site` artifact for `deploy.yml` and `preview.yml`. Each script runs even if an
earlier one failed, so one run reports all failures. Drafts and forks upload
nothing. With `worker-bundle: true`, it also bundles the Worker script of a
pull request for its preview.

```yaml
check:
  uses: KellanStevens/ci/.github/workflows/check.yml@<sha> # v1.0.0
  with:
    scripts: lint typecheck test build
```

### `deploy.yml`

Deploy the `site` artifact to production, in the `production` environment.
Never cancelled once it starts. With `require-access: true`, it checks that
Cloudflare Access protects the site, and removes the domain if not. If it
cannot reach the site to check, the site stays up and the job fails.

A `guard` job runs first and fails unless the run is a push to the default
branch, or a run by hand (`workflow_dispatch`) from it. A pull request that
reaches this workflow by mistake fails there, before the `production`
environment and its secrets. Keep the `if:` on the caller anyway, so that
other runs skip the job instead of failing.

```yaml
deploy:
  needs: check
  if: ${{ github.event_name == 'push' && github.ref == 'refs/heads/main' }}
  uses: KellanStevens/ci/.github/workflows/deploy.yml@<sha> # v1.0.0
  with:
    url: https://www.example.com
  secrets:
    CLOUDFLARE_API_TOKEN: ${{ secrets.CLOUDFLARE_API_TOKEN }}
```

A reusable workflow receives only the secrets that it names. To upload a new
Worker secret, add it to `on.workflow_call.secrets` of `deploy.yml` and
`preview.yml` first.

### `preview.yml`

Deploy each pull request to its own Worker, `<name>-pr-<number>`, on its own
hostname, after CI passes, and comment on the pull request when the deploy
starts, then with the link, or that it failed. Call it from a workflow that
runs on `workflow_run` of CI, so that it runs from main with the secrets, and
the code of the pull request never runs where the secrets are. See the comment
at the top of the file. With `require-access: true`, it deletes a preview that
Access does not protect, or that it cannot check.

With `paths`, a pull request gets a preview only if it changes a file under
one of the paths, so a pull request that edits only the README, `CLAUDE.md` or
the workflows deploys nothing and adds no comment. One path for each line: a
file, a directory (everything below it), or a glob where `*` also matches `/`.
The check covers the whole pull request, not the last push, so once a pull
request touches a path, every later push previews. Without `paths`, every
pull request previews.

```yaml
name: Preview
on:
  workflow_run:
    workflows: [CI]
    types: [completed]
permissions:
  contents: read
jobs:
  preview:
    uses: KellanStevens/ci/.github/workflows/preview.yml@<sha> # v1.0.0
    # A called workflow cannot have more permissions than its caller.
    permissions:
      contents: read
      actions: read
      pull-requests: write
    with:
      name: example
      host: pr-{pr}.example.com
      paths: |
        src
        public
        package.json
        bun.lock
    secrets:
      CLOUDFLARE_API_TOKEN: ${{ secrets.CLOUDFLARE_API_TOKEN }}
```

A site with a Worker script sets `worker: true` here and `worker-bundle: true`
in `check.yml`. The preview then runs the Worker code of the pull request with
the `wrangler.jsonc` of main.

### `preview-cleanup.yml`

Delete the Worker and domain of a preview when its pull request closes, or by
hand from the Actions tab. It then edits the preview comment: the link stays,
marked 🧹 and "(not accessible anymore)". It adds no comment to a pull request
that has none, and skips the comment if it cannot look up the pull request. If
the delete fails, the job fails and the comment says ⚠️ "Preview not deleted",
with a link to the run, because the preview may still be live. `preview.yml`
does the same when the pull request closes during a deploy.

```yaml
name: Preview cleanup
on:
  pull_request_target:
    types: [closed]
  workflow_dispatch:
    inputs:
      pr_number:
        description: Pull request number of the preview to delete
        required: true
        type: number
permissions:
  contents: read
jobs:
  cleanup:
    permissions:
      contents: read
      pull-requests: write
    uses: KellanStevens/ci/.github/workflows/preview-cleanup.yml@<sha> # v1.0.0
    with:
      pr-number: ${{ github.event.pull_request.number || inputs.pr_number }}
      name: example
      host: pr-{pr}.example.com
    secrets:
      CLOUDFLARE_API_TOKEN: ${{ secrets.CLOUDFLARE_API_TOKEN }}
```

## Renovate

`renovate/default.json` holds the shared settings: weekly updates after three
days, grouped minor and patch updates, Bun, GitHub Actions, and updates of
this repository as soon as they are released. `renovate/astro.json` and
`renovate/react.json` group packages that release together.

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": [
    "github>KellanStevens/ci//renovate/default",
    "github>KellanStevens/ci//renovate/astro"
  ]
}
```

Add the rules that only one site needs to that site's `renovate.json`.

## Releases

Run the **Release** workflow from the Actions tab, on main, with the new
version as `vX.Y.Z`. It tags the commit and drafts a GitHub Release with
generated notes. Edit the notes, with breaking changes and known issues at the
top, and publish the draft.

Renovate opens a pull request in each site that moves its pins to the new tag
as soon as the tag exists, before the draft is published. The
`protect-release-tags` ruleset stops a `v*` tag from moving or being deleted,
so fix a bad release with the next version.
