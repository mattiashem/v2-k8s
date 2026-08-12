# kube-foundry — AI software factory

Operator watches `SoftwareTask` resources → spawns a sandbox pod running an AI coding agent →
the agent clones the repo, does the work, pushes a branch and opens a pull request.

- **Namespace:** `kubefoundry` (local cluster)
- **ArgoCD apps:** `kubefoundry` (the Helm chart) and `kubefoundry-config` (this directory).
  Both are **manual sync** on purpose — every task spends real LLM credits.
- **Agent:** `open-code` (OpenCode) routed to [berget.ai](https://berget.ai), EU-sovereign.

First working PR: [elino-apps/elino.se#1](https://github.com/elino-apps/elino.se/pull/1),
2026-08-12.

---

## Wire up a new service — the short version

Three things per project: a **credentials Secret**, a **SoftwareTask**, and a repo the token
can write to.

```bash
# 1. Per-project credentials (never commit these — see "Credentials" below)
kubectl create secret generic factory-creds-myproject -n kubefoundry \
  --from-literal=ANTHROPIC_API_KEY='<berget-api-key>' \
  --from-literal=GITHUB_TOKEN='<github-pat-for-that-org>'

# 2. Describe the work
cp examples/softwaretask.yaml /tmp/my-task.yaml
$EDITOR /tmp/my-task.yaml          # set name, repo, secretRef, task text
kubectl apply -f /tmp/my-task.yaml

# 3. Watch it
kubectl get st -n kubefoundry -w
kubectl logs -f -n kubefoundry <task-name>-sandbox
kubectl get st <task-name> -n kubefoundry -o jsonpath='{.status.pullRequestURL}'
```

There is a helper that does steps 1–2 for you: `examples/new-project.sh`.

> **Do not put SoftwareTasks in this directory.** ArgoCD syncs `kubefoundry/` and would
> recreate every task forever, re-running the agent each time. Tasks are one-shot work items —
> apply them from `examples/` or `/tmp`. The `examples/` subdirectory is safe because the
> ArgoCD app does not recurse into subdirectories.

---

## Credentials — one Secret per project

Each `SoftwareTask` names its own Secret, so different projects can use different GitHub
tokens (different orgs, different scopes) and even different LLM keys. Nothing is shared
implicitly.

| Convention | Value |
|---|---|
| Secret name | `factory-creds-<project>` |
| Namespace | same namespace as the SoftwareTask (`kubefoundry` by default) |
| Referenced by | `spec.credentials.secretRef` |

Two keys are required:

| Key | Contents |
|---|---|
| `ANTHROPIC_API_KEY` | **The berget API key.** Not a typo — see the naming trap below. |
| `GITHUB_TOKEN` | A GitHub PAT with write access to the target repo. |

```bash
kubectl create secret generic factory-creds-<project> -n kubefoundry \
  --from-literal=ANTHROPIC_API_KEY='<llm-key>' \
  --from-literal=GITHUB_TOKEN='<github-pat>'
```

Updating one (`create` is not idempotent):

```bash
kubectl create secret generic factory-creds-<project> -n kubefoundry \
  --from-literal=ANTHROPIC_API_KEY='<llm-key>' \
  --from-literal=GITHUB_TOKEN='<github-pat>' \
  --dry-run=client -o yaml | kubectl apply -f -
```

### ⚠️ The berget key goes in `ANTHROPIC_API_KEY`

The operator picks the env var name via `agentAPIKeyName()`, which returns `ANTHROPIC_API_KEY`
for every agent except `codex`. The OpenCode provider config reads `{env:ANTHROPIC_API_KEY}`.
So whatever LLM you route to, its key lives in the `ANTHROPIC_API_KEY` field. Badly named
upstream, but it means nothing has to be patched.

### GitHub token requirements

Fine-grained PATs are fiddly. What the agent actually needs on the target repo:

| Permission | Level | Needed for |
|---|---|---|
| Contents | **Read and write** | clone, commit, push the branch |
| Pull requests | **Read and write** | `gh pr create` |
| Issues | Read and write | only for ticket-driven work |
| Metadata | Read | mandatory, auto-selected |

Hard-won specifics:

- **Resource owner is chosen at creation and is immutable.** A token owned by your personal
  account cannot be granted access to an org's repos by editing permissions — the org must
  either allow personal fine-grained PATs or you create the token with the org as owner.
- **403 vs 404 tells you which problem you have.** `403` = the token sees the repo but lacks
  the permission. `404` = the repo is outside the token's repository-access list, or org
  approval is still pending.
- **Widening an approved token re-triggers org approval.** Newly added repos stay ungranted
  (403) while previously approved ones keep working — that mixed state is normal and means
  someone needs to approve it in *Org → Settings → Personal access tokens → Pending requests*.
- **The repo's `permissions` field lies.** `GET /repos/{owner}/{repo}` reports *your* role, not
  the token's grants. Probe the real thing instead:

```bash
TOK=$(kubectl get secret factory-creds-<project> -n kubefoundry \
        -o jsonpath='{.data.GITHUB_TOKEN}' | base64 -d)
curl -s -o /dev/null -w 'contents=%{http_code}\n' \
  -H "Authorization: Bearer $TOK" https://api.github.com/repos/<org>/<repo>/contents/
git ls-remote "https://x-access-token:$TOK@github.com/<org>/<repo>" >/dev/null && echo "git OK"
```

### 🔴 Tokens leak into pod logs

The entrypoint embeds the token in the git remote URL. Any agent that runs `git remote -v`
prints it, and the sandbox log is shipped to Loki. Treat every token used here as exposed and
rotate on a schedule. This is an upstream design flaw, not something config can fix.

---

## Isolating projects further

The default is one namespace (`kubefoundry`) with a Secret per project, which is enough to keep
credentials separate. If a project needs stronger isolation — its own quota, its own RBAC, no
chance of reading another project's Secret — give it a namespace:

```bash
kubectl create namespace factory-myproject
kubectl create secret generic factory-creds-myproject -n factory-myproject ...
# ...and set metadata.namespace on the SoftwareTask to match
```

The operator's ClusterRole is cluster-wide, so it can reconcile tasks and create sandbox pods
in any namespace. The Secret must live in the **same namespace as the task** — `secretRef` does
not cross namespaces. Note the Skills in this directory are namespaced to `kubefoundry`; a task
in another namespace needs its own copies.

---

## Writing a SoftwareTask

```yaml
apiVersion: factory.factory.io/v1alpha1
kind: SoftwareTask
metadata:
  name: myproject-add-healthcheck
  namespace: kubefoundry
spec:
  repo: https://github.com/<org>/<repo>     # HTTPS only, pattern-enforced
  branch: main                              # base branch to clone
  agent: open-code                          # open-code | claude-code | codex
  skills:
    - berget                                # provider + default model
  credentials:
    secretRef: factory-creds-myproject
  gitAuthorName: kube-foundry
  gitAuthorEmail: you@example.com
  resources:
    cpu: "2"
    memory: 4Gi
    timeoutMinutes: 30                      # max 120
  task: |
    Natural-language description of the work.
```

The agent creates branch `factory/<task-name>` and opens a PR against `spec.branch`.

### Writing good task text

The agent has no context beyond what you write and what it can read in the repo. What worked:

- Tell it to **read before editing** — it will otherwise guess at file locations.
- **Bound the scope explicitly** ("styling for the menu logo only, do not restructure the
  page"). Without this the diff sprawls.
- Name the **constraints that matter** (don't break the mobile layout, keep the public API).
- Ask it to **explain the change in the PR description**, which files and why.

### Model selection

| Skill | Model | Use for |
|---|---|---|
| `berget` | `zai-org/GLM-5.2` | default; strong tool-calling |
| `berget` (small) | `mistralai/Mistral-Small-3.2-24B-Instruct-2506` | title generation, incidental calls |
| `berget-large` | `moonshotai/Kimi-K3` | harder tasks, higher cost |
| `berget-fast` | `mistralai/Mistral-Small-3.2-24B-Instruct-2506` | simple mechanical edits |

Override per task by listing an override skill **after** `berget`:

```yaml
skills: [berget, berget-large]
```

Order matters. The operator appends skill env in list order and Kubernetes resolves duplicate
env names to the **last** occurrence — reversed, the default silently wins.

List available models:

```bash
KEY=$(kubectl get secret factory-creds-<project> -n kubefoundry \
        -o jsonpath='{.data.ANTHROPIC_API_KEY}' | base64 -d)
curl -s https://api.berget.ai/v1/models -H "Authorization: Bearer $KEY" | jq -r '.data[].id'
```

Every model id you use must also appear in the provider `models` map in
`skill-berget-opencode.yaml` — the top-level `model` field *selects* from that map, it does not
register a model.

---

## Watching a task

```bash
kubectl get st -n kubefoundry                       # phase, agent, repo, PR
kubectl get st <name> -n kubefoundry -o jsonpath='{.status.pullRequestURL}'
kubectl logs -f -n kubefoundry <name>-sandbox       # live agent output
kubectl logs -n kubefoundry deploy/kube-foundry-operator --tail=50   # if nothing happens at all
```

The sandbox log is the real diagnostic. It prints `[1/6]`…`[6/6]`:

| Step | Meaning | Fails when |
|---|---|---|
| 1/6 | git credentials | — |
| 2/6 | clone | token lacks Contents, or repo outside its access list |
| 3/6 | create work branch | branch already exists from a previous run |
| skills | inject config files | — |
| 4/6 | run the agent | model id wrong, key invalid, binary missing |
| 5/6 | commit and push | token is read-only, or branch diverged |
| 6/6 | `gh pr create` | token lacks Pull requests: write |

**A task stuck with an empty status and no pod is always an operator-side problem** — check the
operator log, not the task. That symptom has meant missing RBAC every time so far.

---

## Gotchas

Ordered by how much time each one costs when you hit it cold.

### The agent images are mostly broken upstream

v0.1.0 publishes three agent images. Two do not work:

| Image | State |
|---|---|
| `agent-claude-code` | Works — `claude` 2.1.86 |
| `agent-codex` | **Broken** — ships codex-cli 0.117.0 but the entrypoint calls `--approval-mode`, removed in that version |
| `agent-open-code` | **Broken upstream** — the image contains no `opencode` binary at all |

We build a repaired `open-code` image in
[elino-apps/cloudbilder](https://github.com/elino-apps/cloudbilder) and point the chart at it
via `agent.openCode.image` in `core/kubefoundry.yaml`. Re-check `command -v opencode` before
assuming any future upstream image is fixed.

`open-code` is the agent we need because it is the only one that can be pointed at an
OpenAI-compatible endpoint through its `config.json` provider block. Claude Code speaks the
Anthropic Messages API, which berget does not serve (`POST /v1/messages` → 404).

### The chart's RBAC is incomplete

The chart's ClusterRole grants `softwaretasks`, pods, secrets, configmaps, events and leases —
but **not** `skills` (a CRD it does not ship) and **not** `serviceaccounts`. Both gaps produce
the same silent symptom: task sits at empty status, no pod, cause visible only in the operator
log. Fixed in `rbac-skills.yaml`. Expect more gaps if upstream adds informers.

### The chart's CRD is stale relative to its own operator

`spec.skills` is **silently pruned** by the API server on the packaged CRD — skills look
configured and do nothing. `crd-softwaretask.yaml` vendors upstream's own generated CRD for the
same tag, and the chart app has `ignoreDifferences` on `/spec/versions` with
`RespectIgnoreDifferences=true` so a Helm sync cannot revert it.

### Skill file paths must be absolute

Skill files are written **after** the entrypoint does `cd /workspace/repo`. A relative path
writes into the cloned repo, and step 5 runs `git add -A` — so it gets committed into the PR.
Always use absolute paths like `/home/opencode/.config/opencode/config.json`.

### No Node toolchain in the sandbox

The base image has `git`, `jq`, `gh`, `curl` — but no `node`/`npm`. On a JS/TS repo the agent
can edit but cannot lint, build or test its own work, and will say so. Add Node to the
`cloudbilder` image before trusting this on anything non-trivial.

### The operator can race with itself

Two reconciles can create the same sandbox pod name, lose the status write with
`the object has been modified`, and discard a pod that has **already finished and opened the
PR** — then retry from scratch, burning a second full agent run and colliding with the branch
the first run pushed. If a task looks stuck retrying, check GitHub before assuming it failed.

### Other chart notes

- `networkPolicy.enabled` **must stay false**: the `core` AppProject blacklists NetworkPolicy,
  and the chart's default egress list has no DNS rule, so sandboxes could not resolve github.com.
- `credentials.secretName` in `values.yaml` is dead — it appears in zero templates. Credentials
  are per-task via `secretRef`.
- The chart's `namespace:` value is stamped into every rendered object, so it must match
  `spec.destination.namespace` or the sync splits across two namespaces.
- **amd64 only.** The upstream agent base image is `linux/amd64`, so sandbox pods must land on
  an amd64 node.

---

## Syncing changes

Both apps are manual. `core/kubefoundry.yaml` defines the Applications, so a change there needs
the **seed** to sync first — scoped, so the seed's heavy pre-existing drift is not swept in:

```bash
FULL=$(git rev-parse HEAD)
kubectl patch app argocd-seed -n argocd --type merge \
  -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'
kubectl patch app argocd-seed -n argocd --type merge -p "{\"operation\":{\"sync\":{
  \"revision\":\"$FULL\",
  \"resources\":[{\"group\":\"argoproj.io\",\"kind\":\"Application\",
                  \"name\":\"kubefoundry\",\"namespace\":\"argocd\"}]}}}"
```

Then sync the app itself (`kubefoundry` for chart/values changes, `kubefoundry-config` for the
CRDs, RBAC and Skills in this directory). `kubefoundry-config` needs `ServerSideApply=true` —
the generated CRDs exceed the annotation size limit a client-side apply would need.

Changing the operator's args (e.g. a new agent image) requires a rollout:

```bash
kubectl rollout restart deployment/kube-foundry-operator -n kubefoundry
```

The new pod waits for the old leader lease to expire before reconciling — roughly a minute of
apparent silence is normal. It is ready once the log shows `Starting workers`.

---

## Files here

| File | Purpose |
|---|---|
| `crd-softwaretask.yaml` | Upstream's generated CRD, replacing the chart's stale copy |
| `crd-skill.yaml` | Skill CRD — the chart ships none, the operator implements it fully |
| `rbac-skills.yaml` | ClusterRole for `skills` + `serviceaccounts`, missing from the chart |
| `skill-berget-opencode.yaml` | Routes OpenCode to berget.ai; provider block + default model |
| `skill-berget-models.yaml` | `berget-large` / `berget-fast` model overrides |
| `examples/softwaretask.yaml` | Template for a new task — **do not commit real tasks here** |
| `examples/new-project.sh` | Creates a project Secret and scaffolds its first task |
