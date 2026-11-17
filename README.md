# .github

## Overview

This is the shared home for how my repos run on GitHub. GitHub treats a public repo named `.github` specially: the issue forms and PR template here become the defaults for every repo on this account that has none of its own. The workflows here are reusable: another repo calls them in one line instead of keeping its own copy, so a fix made here reaches every repo. Today it holds the release workflow, built on release-please, and the canonical issue labeler, issue forms and PR template. Repos pin it to a major tag (`@v1`), so a change here reaches them only when the tag moves. Conventions themselves (issue → commits → PR → review, Conventional Commits, merge commits) are described in my global agent instructions; this repo holds what GitHub runs.

## Table of Contents

- [Overview](#overview)
- [Reusable workflows](#reusable-workflows)
  - [Release (`release-please.yml`)](#release-release-pleaseyml)
- [Defaults for every repo](#defaults-for-every-repo)
- [This repo's own checks](#this-repos-own-checks)
- [Versioning](#versioning)

## Reusable workflows

### Release (`release-please.yml`)

It releases a repo from its commit titles. Each push to the default branch keeps one release PR up to date, holding the next version, the changelog and any marked version strings:

- `fix` bumps the patch version;
- `feat` bumps the minor version;
- `!` bumps the major version.

Merging the release PR tags the release and publishes it on GitHub.

To use it, a repo needs:

1. **`release-please-config.json` and `.release-please-manifest.json`.** The manifest holds the current version.
2. **A small caller workflow.** The comment at the top of `release-please.yml` shows it.
3. **Actions allowed to open PRs:** the repo's *Settings → Actions → General → "Allow GitHub Actions to create and approve pull requests"*. With `gh`: `gh api -X PUT repos/OWNER/REPO/actions/permissions/workflow -f default_workflow_permissions=read -F can_approve_pull_request_reviews=true`. None of these workflows ever approves a PR.

To mark version strings in other files, such as install links in a README, wrap them in `<!-- x-release-please-start-version -->` … `<!-- x-release-please-end -->`. Then list the file under `extra-files` with `"type": "generic"`.

**Release PRs and required checks.** release-please opens its PR with GitHub's own token, and GitHub starts no workflows for that token's events. So in a repo whose ruleset requires checks, a release PR's checks never run by themselves. To ship one, close and reopen it as yourself; that runs the checks. Then merge:

```sh
gh pr close N && gh pr reopen N && gh pr merge N --auto --merge --delete-branch
```

The alternative is a personal access token stored as a secret, which is a long-lived credential this setup avoids on purpose.

## Defaults for every repo

`.github/ISSUE_TEMPLATE/` (bug, feature and incident forms) and `.github/pull_request_template.md` apply to any repo on this account that has none of its own.

## This repo's own checks

- **`lint-pr-review.yml`:** runs actionlint on the workflows (including shellcheck on their scripts), shellcheck on the scripts, and the labeler's table tests. It posts the result as a comment review on each PR.
- **`issue-labeler.yml`:** labels issues from their Conventional Commits titles: `fix` → bug, `feat` → enhancement, and the scope → `area:<scope>`. The logic is in `.github/scripts/label-issue.sh`, and its tests are in `label-issue.test.sh`.

## Versioning

Callers pin a major tag, such as `@v1`. A compatible change moves `v1` forward. A change that would break a caller gets `v2`, and callers move when they choose to.
