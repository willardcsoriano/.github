#!/usr/bin/env bash
# audit-repos: check every repo on the account against the conventions this
# repo holds, and print one row per repo. Read-only: it only queries GitHub
# through gh (your login), so it sees private repos too and changes nothing.
#
#   bash scripts/audit-repos.sh               # active repos (not archived, not forks)
#   bash scripts/audit-repos.sh REPO [REPO..] # just these
#
# Columns (ok, or what is wrong):
#   lint     .github/workflows/lint-pr-review.yml calls the shared lint-review.yml
#   labeler  .github/workflows/issue-labeler.yml calls the shared label-issues.yml
#   pin      every shared workflow it calls is pinned to the newest release tag
#   copies   no local copy of what the shared repo provides (forms, template,
#            labeler script, the old shellcheck workflow)
#   merge    merge commits allowed (the merge method the workflow uses)
#   rules    public only: a ruleset on the default branch with PR-only,
#            no force-push, no deletion and required checks
#   secrets  public only: secret scanning and push protection on
# Exits 1 when any row has a problem, so it can gate a script.
set -uo pipefail

OWNER=willardcsoriano
SHARED="$OWNER/.github"

# A file's raw content, or nothing (and status 1) when it doesn't exist.
raw() { gh api -H "Accept: application/vnd.github.raw" "repos/$1/contents/$2" 2>/dev/null; }
exists() { gh api "repos/$1/contents/$2" --silent 2>/dev/null; }

# The newest vX.Y.Z tag of the shared repo: what callers should pin.
latest=$(gh api "repos/$SHARED/tags" --paginate --jq '.[].name' |
    grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1)
if [ -z "$latest" ]; then
    echo "audit-repos: no vX.Y.Z tag on $SHARED" >&2
    exit 2
fi

if [ "$#" -gt 0 ]; then
    repos=("$@")
else
    mapfile -t repos < <(gh repo list "$OWNER" --limit 500 --no-archived --source \
        --json name --jq '.[].name' | sort)
fi

check_repo() {
    local name=$1 full="$OWNER/$1" meta vis lint labeler pin copies merge rules secrets
    meta=$(gh api "repos/$full" --jq '[.visibility, .allow_merge_commit,
        (.security_and_analysis.secret_scanning.status // "n/a"),
        (.security_and_analysis.secret_scanning_push_protection.status // "n/a"),
        .default_branch] | @tsv' 2>/dev/null) || { printf '%s\tnot found\n' "$name"; return 1; }
    local mc ss pp branch
    IFS=$'\t' read -r vis mc ss pp branch <<< "$meta"

    if [ "$full" = "$SHARED" ]; then
        # The shared repo runs its own workflows from the same commit (uses: ./).
        lint=ok labeler=ok pin=n/a copies=n/a
    else
        local lw lb
        lw=$(raw "$full" .github/workflows/lint-pr-review.yml)
        lb=$(raw "$full" .github/workflows/issue-labeler.yml)
        if grep -q "uses: $SHARED/.github/workflows/lint-review.yml@" <<< "$lw"; then lint=ok; else lint=MISSING; fi
        if grep -q "uses: $SHARED/.github/workflows/label-issues.yml@" <<< "$lb"; then labeler=ok; else labeler=MISSING; fi
        # Every pin in every workflow that calls the shared repo.
        local pins wf
        pins=$(for wf in $(gh api "repos/$full/contents/.github/workflows" --jq '.[].path' 2>/dev/null); do
            raw "$full" "$wf" | grep -oE "uses: $SHARED/\.github/workflows/[a-z-]+\.yml@[^[:space:]]+" | sed 's/.*@//'
        done | sort -u)
        if [ -z "$pins" ]; then pin=n/a
        elif [ "$pins" = "$latest" ]; then pin=ok
        else pin="OLD($(paste -sd, <<< "$pins"))"; fi
        copies=ok
        local p
        for p in .github/ISSUE_TEMPLATE .github/pull_request_template.md .github/scripts/label-issue.sh \
                 .github/workflows/shellcheck-pr-review.yml; do
            if exists "$full" "$p"; then copies="HAS(${p#.github/})"; break; fi
        done
    fi

    if [ "$mc" = true ]; then merge=ok; else merge=OFF; fi

    if [ "$vis" = public ]; then
        local types
        types=$(gh api "repos/$full/rules/branches/$branch" --jq '[.[].type] | sort | join(",")' 2>/dev/null)
        rules=ok
        local t
        for t in deletion non_fast_forward pull_request required_status_checks; do
            case ",$types," in *",$t,"*) ;; *) rules="MISSING($t)"; break ;; esac
        done
        if [ "$ss" = enabled ] && [ "$pp" = enabled ]; then secrets=ok; else secrets="OFF"; fi
    else
        rules=n/a secrets=n/a
    fi

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$name" "$vis" "$lint" "$labeler" "$pin" "$copies" "$merge" "$rules" "$secrets"
    case "$lint$labeler$pin$copies$merge$rules$secrets" in
        *MISSING* | *OLD* | *HAS* | *OFF*) return 1 ;;
    esac
    return 0
}

echo "Shared workflows: $SHARED, newest release $latest"
rows=$(mktemp)
trap 'rm -f "$rows"' EXIT
printf 'repo\tvisibility\tlint\tlabeler\tpin\tcopies\tmerge\trules\tsecrets\n' > "$rows"
failed=0
for r in "${repos[@]}"; do
    check_repo "$r" >> "$rows" || failed=$((failed + 1))
done
column -t -s $'\t' "$rows"
echo
if [ "$failed" -eq 0 ]; then
    echo "All ${#repos[@]} repos conform."
    exit 0
fi
echo "$failed of ${#repos[@]} repos have something to fix."
exit 1
