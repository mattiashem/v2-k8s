#!/usr/bin/env bash
#
# Wire up a new project for kube-foundry: create its credentials Secret and
# scaffold its first SoftwareTask.
#
# Each project gets its own Secret so different repos can use different GitHub
# tokens (different orgs, different scopes) and different LLM keys. Nothing is
# shared implicitly — a task only ever sees the Secret it names.
#
#   ./new-project.sh myproject https://github.com/some-org/some-repo
#
# Keys are read interactively so they never land in shell history or argv.
# Re-running for an existing project updates the Secret in place.
#
set -euo pipefail

NAMESPACE="${NAMESPACE:-kubefoundry}"

PROJECT="${1:-}"
REPO="${2:-}"

if [ -z "$PROJECT" ] || [ -z "$REPO" ]; then
    echo "usage: $0 <project-name> <https-repo-url>" >&2
    echo "example: $0 elino https://github.com/elino-apps/elino.se" >&2
    exit 1
fi

case "$REPO" in
    https://*) ;;
    *) echo "error: repo must be an https:// URL (the CRD enforces this)" >&2; exit 1 ;;
esac

SECRET="factory-creds-${PROJECT}"

echo "Project:   ${PROJECT}"
echo "Repo:      ${REPO}"
echo "Secret:    ${SECRET} (namespace ${NAMESPACE})"
echo

# --------------------------------------------------------------------------
# Credentials
# --------------------------------------------------------------------------
# ANTHROPIC_API_KEY holds the *berget* key. Not a typo: the operator picks the
# env var name via agentAPIKeyName(), which returns ANTHROPIC_API_KEY for every
# agent except codex, and the OpenCode provider config reads {env:ANTHROPIC_API_KEY}.
if kubectl get secret "$SECRET" -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "Secret ${SECRET} already exists."
    read -r -p "Replace its keys? [y/N] " REPLACE
    [ "$REPLACE" = "y" ] || [ "$REPLACE" = "Y" ] || SKIP_SECRET=1
fi

if [ -z "${SKIP_SECRET:-}" ]; then
    read -r -s -p "berget API key (stored as ANTHROPIC_API_KEY): " LLM_KEY; echo
    read -r -s -p "GitHub PAT with Contents+PR write on the repo:  " GH_TOKEN; echo

    [ -n "$LLM_KEY" ] || { echo "error: LLM key is empty" >&2; exit 1; }
    [ -n "$GH_TOKEN" ] || { echo "error: GitHub token is empty" >&2; exit 1; }

    # create is not idempotent; this pattern updates in place.
    kubectl create secret generic "$SECRET" -n "$NAMESPACE" \
        --from-literal=ANTHROPIC_API_KEY="$LLM_KEY" \
        --from-literal=GITHUB_TOKEN="$GH_TOKEN" \
        --dry-run=client -o yaml | kubectl apply -f -

    # ----------------------------------------------------------------------
    # Verify both credentials before anyone wastes an agent run on a 403.
    # The repo's `permissions` field reports YOUR role, not the token's grants,
    # so probe the endpoints the agent actually uses.
    # ----------------------------------------------------------------------
    echo
    echo "Verifying credentials..."

    LLM_CODE=$(curl -s -o /dev/null -w '%{http_code}' \
        -H "Authorization: Bearer ${LLM_KEY}" https://api.berget.ai/v1/models || echo 000)
    if [ "$LLM_CODE" = "200" ]; then
        echo "  berget API key: OK"
    else
        echo "  berget API key: FAILED (HTTP ${LLM_CODE})" >&2
    fi

    OWNER_REPO=$(echo "$REPO" | sed -E 's#^https://github.com/##; s#\.git$##')
    GH_CODE=$(curl -s -o /dev/null -w '%{http_code}' \
        -H "Authorization: Bearer ${GH_TOKEN}" \
        "https://api.github.com/repos/${OWNER_REPO}/contents/" || echo 000)
    case "$GH_CODE" in
        200) echo "  GitHub read:    OK" ;;
        403) echo "  GitHub read:    FORBIDDEN — token sees the repo but lacks Contents" >&2 ;;
        404) echo "  GitHub read:    NOT FOUND — repo is outside the token's access list," >&2
             echo "                  or org approval is still pending" >&2 ;;
        *)   echo "  GitHub read:    unexpected HTTP ${GH_CODE}" >&2 ;;
    esac

    # Read access does not imply write. This is the check that catches a
    # read-only token before the agent does all the work and fails at push.
    if GIT_TERMINAL_PROMPT=0 git ls-remote \
        "https://x-access-token:${GH_TOKEN}@github.com/${OWNER_REPO}" >/dev/null 2>&1; then
        echo "  git access:     OK"
    else
        echo "  git access:     FAILED — the agent will not be able to clone" >&2
    fi
    echo
    echo "  NOTE: push/PR permissions cannot be verified without writing to the"
    echo "        repo. Confirm the token shows Contents and Pull requests as"
    echo "        'Read and write', or the first task will do all the work and"
    echo "        then fail at step 5/6."
fi

# --------------------------------------------------------------------------
# Scaffold the first task
# --------------------------------------------------------------------------
OUT="/tmp/softwaretask-${PROJECT}.yaml"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

sed -e "s#CHANGE-ME-project-what-it-does#${PROJECT}-CHANGE-ME#" \
    -e "s#https://github.com/CHANGE-ME-org/CHANGE-ME-repo#${REPO}#" \
    -e "s#factory-creds-CHANGE-ME-project#${SECRET}#" \
    "${HERE}/softwaretask.yaml" > "$OUT"

echo
echo "Wrote ${OUT}"
echo
echo "Next:"
echo "  1. \$EDITOR ${OUT}        # set the task name and write the task text"
echo "  2. kubectl apply -f ${OUT}"
echo "  3. kubectl get st -n ${NAMESPACE} -w"
echo "     kubectl logs -f -n ${NAMESPACE} <task-name>-sandbox"
