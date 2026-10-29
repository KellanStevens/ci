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
- run: bunx wrangler deploy --secrets-file "${{ steps.secrets.outputs.file }}"
```

The file is JSON, so a value can hold any character. `file` is empty when
there are no secrets to upload.

### `actions/remove-domain` and `actions/delete-preview`

`remove-domain` detaches a Workers custom domain and its DNS record.
`delete-preview` detaches the domains of a preview and deletes its Worker.
Neither fails if there is nothing to delete, so they can run more than once.
`delete-preview` needs Wrangler, from `actions/setup`.

```yaml
- uses: KellanStevens/ci/actions/delete-preview@<sha> # v1.0.0
  with:
    worker-name: example-pr-12
    hosts: pr-12.example.com
    cloudflare-api-token: ${{ secrets.CLOUDFLARE_API_TOKEN }}
```

Without `account-id`, they find the account from the zone of the hostname,
which needs Zone Read on the token.
