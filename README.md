# spec-sync-action

@fohte's personal reusable GitHub Action to regenerate code from a producer's OpenAPI spec and open a PR when it changes

## Why this action exists

When one repo (the producer) publishes an OpenAPI spec and other repos (consumers) generate code from it, each consumer needs the same reaction to a producer update: regenerate code, and open (or update) a pull request if the output changed. The only things that differ between consumers are the producer repo and the command that does the regeneration.

This action covers that common part — token federation, checkout, diff detection, committing, force-pushing to a reused branch, and creating/updating the pull request — so each consumer only needs a workflow with a sha-pinned `uses:` and its own generate command.

## Inputs

| name                | required | description                                                                                                                  |
| ------------------- | -------- | ---------------------------------------------------------------------------------------------------------------------------- |
| `producer-repo`     | yes      | Producer repo in `owner/repo` form. Drives the sync branch name and the pull request title/body/link.                        |
| `generate-command`  | yes      | Shell command that regenerates and formats code. Runs at the repository root; include any toolchain setup it needs.          |
| `octo-sts-identity` | yes      | octo-sts identity used to federate a token (`domain: octo-sts.fohte.net`) with `contents: write` and `pull_requests: write`. |

There's no branch/PR-title/PR-body input: all three are derived from `producer-repo` so a repeat run for the same producer reuses the same branch and pull request instead of any caller having to keep them in sync themselves.

- branch: `spec-sync/<producer-repo>`
- PR title (and the sync commit message): `chore: sync generated code from <producer-repo> OpenAPI spec`
- PR body: `Regenerated code from the latest [<producer-repo> OpenAPI spec](https://github.com/<producer-repo>/blob/main/openapi.json).`

## Outputs

| name               | type                   | description                                 |
| ------------------ | ---------------------- | ------------------------------------------- |
| `changed`          | `'true'` \| `'false'`  | Whether `generate-command` produced a diff. |
| `pull-request-url` | string (empty if none) | URL of the created or updated pull request. |

## Usage

```yaml
name: Sync producer-repo spec

on:
  repository_dispatch:
    types: [producer-repo-spec-updated]
  workflow_dispatch:

permissions:
  id-token: write

concurrency:
  group: sync-producer-repo-spec
  cancel-in-progress: false

jobs:
  sync:
    runs-on: ubuntu-latest
    steps:
      - uses: fohte/spec-sync-action@<sha> # vN
        with:
          producer-repo: your-org/producer-repo
          generate-command: |
            corepack enable
            pnpm install --frozen-lockfile
            pnpm run generate:producer-repo-contract
          octo-sts-identity: consumer-repo-sync-producer-repo-spec
```

### Caller responsibilities (out of scope for this action)

- Triggering the workflow (`repository_dispatch` from the producer, `workflow_dispatch`, etc.)
- Job-level `permissions: id-token: write`, needed for the octo-sts token federation this action performs
- `concurrency` control, if the same sync could otherwise run twice in parallel
- An octo-sts trust policy that grants `octo-sts-identity` a token with `contents: write` and `pull_requests: write`

## Security considerations

- **`generate-command` runs with a token that has `contents: write` and `pull_requests: write` on this repo.** Only pass a command you trust; it runs before the diff/commit/push steps with no sandboxing beyond the GitHub Actions runner itself.
- **The federated token's scope comes from the octo-sts trust policy for `octo-sts-identity`, not from this action.** Review the trust policy in the caller repo to confirm it grants only the permissions this action needs.
- **`git push --force` unconditionally overwrites the `spec-sync/<producer-repo>` branch.** This is required, not incidental: the branch is rebuilt from the default branch's current tip on every run (so a stale PR never lingers behind a moved-forward default branch), which means it shares no history with its previous push and a non-force push would be rejected as non-fast-forward. Don't push to that branch from anywhere else.

## Development

This is a composite (bash) action — no build step. Checked by the same hooks as the rest of the repo (`lefthook run pre-commit --all-files`): `pinact` for pinned `uses:` refs and `prettier` for YAML formatting. A smoke-test job in `.github/workflows/test.yml` runs the action against itself on every push.
