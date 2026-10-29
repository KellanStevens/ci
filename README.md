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
