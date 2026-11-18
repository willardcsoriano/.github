# .github

## Overview

This is the shared home for how my repos run on GitHub. GitHub treats a public repo named `.github` specially: the issue forms and PR template here become the defaults for every repo on this account that has none of its own. The workflows here are reusable: another repo calls them in one line instead of keeping its own copy, so a fix made here reaches every repo. Today it holds the release, lint-review and issue-labeling workflows, plus the issue forms and PR template every repo inherits. Repos pin an exact release tag (`@v1.1.0`), so a change here reaches a repo only when that repo moves its pin. Conventions themselves (issue → commits → PR → review, Conventional Commits, merge commits) are described in my global agent instructions; this repo holds what GitHub runs.

## Table of Contents

- [Overview](#overview)
- [Reusable workflows](#reusable-workflows)
  - [Release (`release-please.yml`)](#release-release-pleaseyml)
  - [Lint review (`lint-review.yml`)](#lint-review-lint-reviewyml)
  - [Label issues (`label-issues.yml`)](#label-issues-label-issuesyml)
- [Defaults for every repo](#defaults-for-every-repo)
- [This repo's own checks](#this-repos-own-checks)
- [Auditing every repo](#auditing-every-repo)
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

### Lint review (`lint-review.yml`)

It lints what a PR changes and posts the result as a COMMENT review from github-actions[bot]. Findings are a record: the job succeeds either way, so a ruleset that requires the check requires only that it ran.

What it runs:

- **Always:** shellcheck on changed shell files. The `shell-paths` input takes one pathspec per line; the default is `*.sh` and `*.bash`. claude-config adds `.githooks/*`.
- **With `ruff-version` set:** ruff, at that version, on changed Python.
- **With `actionlint-version` set:** actionlint on all workflows, after a checksum-verified download. Its own shellcheck pass covers their `run:` steps.

The check reports as **`lint / review`** when the caller's job is named `lint`. That is the name a ruleset must require. The caller is in the file's header comment.

### Label issues (`label-issues.yml`)

It labels each issue from its Conventional Commits title:

- `fix` → `bug`;
- `feat` → `enhancement`;
- the scope → `area:<scope>`;
- a title that doesn't parse → `needs-triage`.

The script and its table tests live only here, in `.github/scripts/`. The workflow fetches them at `scripts-ref`, which defaults to the release tag the workflow itself ships in, so callers keep no copy. The caller is in the file's header comment.

## Defaults for every repo

`.github/ISSUE_TEMPLATE/` (bug, feature and incident forms) and `.github/pull_request_template.md` apply to any repo on this account that has none of its own.

## This repo's own checks

This repo uses its own shared workflows, run from the same commit (`uses: ./…`), so a change is exercised on its own PR before any tag moves:

- **`lint-pr-review.yml`:** `lint-review.yml` with actionlint on, plus a `labeler-tests` job that runs `label-issue.test.sh`.
- **`issue-labeler.yml`:** `label-issues.yml`, with the script taken from the triggering commit.

## Auditing every repo

`bash scripts/audit-repos.sh` checks every active repo on the account against these conventions, private ones included, and prints one row per repo. It only reads, through your `gh` login, and exits non-zero when something needs fixing. Pass repo names to check only those. For each repo it checks:

- **lint:** it calls the shared lint review;
- **labeler:** it calls the shared labeler;
- **pin:** its pins name the newest release tag;
- **copies:** it keeps no local copy of what this repo shares;
- **merge:** merge commits are allowed;
- **public repos only:** a default-branch ruleset (PR-only, no force-push, no deletion, required checks), and secret scanning with push protection.

## Versioning

Releases are immutable tags: `v1.1.0`, `v1.2.0` and so on. Callers pin one exactly (`uses: …/lint-review.yml@v1.1.0`) and move by editing the pin, which is a one-line, reviewable change in each repo. A tag never moves. `v1` is the first release and stays where it is; `v1.1.0` is the first under this rule.

To release:

1. Merge the change.
2. Set `label-issues.yml`'s `scripts-ref` default to the new tag, through a PR.
3. Tag the merge commit, for example: `git tag -a v1.2.0 -m v1.2.0 && git push origin v1.2.0`.
4. Bump the pins in the repos that should get it.

Use a minor bump for a compatible change and a major bump when callers must change too.
