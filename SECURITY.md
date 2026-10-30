# Security

The workflows and actions in this repository deploy every site, with the
Cloudflare tokens and Worker secrets of each one. A flaw here can reach all of
them.

## Reporting a vulnerability

Do not open a public issue or pull request. Report it privately from the
**Security** tab of this repository, with **Report a vulnerability**.

Say which workflow or action is affected, how to reproduce the problem, and
what an attacker could do with it, for example read a secret or publish a
preview that Access does not protect.

## Supported versions

Only the latest release gets fixes. Sites pin a commit, and Renovate moves
them to the fixed release.
