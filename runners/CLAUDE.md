# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This directory manages GitHub Actions self-hosted runners deployed via the **Actions Runner Controller (ARC) v2** (`gha-runner-scale-set`) Helm chart.

- **Controller namespace:** `arc-systems`
- **Runner namespace:** `arc-runners`
- **Controller Helm release name:** `arc`
- **Controller service account:** `arc-gha-rs-controller` (in `arc-systems`)
- **Helm chart:** `oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set`
- **Container mode:** `dind` (Docker-in-Docker) for all runner sets

## Two Clusters

ARC runs on two separate clusters. Use the correct kubeconfig:

| Cluster | Kubeconfig | Context |
|---|---|---|
| hrb (Talos) | `~/.kube/confighrb` | `admin@hrb` |
| v2cluster | `~/.kube/config` | `admin@v2cluster` |

```bash
# hrb cluster
kubectl --kubeconfig=/home/mattias/.kube/confighrb get pods -n arc-systems
# v2cluster
kubectl --kubeconfig=/home/mattias/.kube/config get pods -n arc-systems
```

## Runner Sets

Each `github-runner-<name>.yaml` is a Helm values file for a runner scale set:

| Values file | GitHub org/user | Architecture |
|---|---|---|
| `github-runner.yaml` | `ollebo` | amd64 |
| `github-runner-arm.yaml` | `ollebo` | arm64 |
| `github-runner-hrb.yaml` | `Hacking-Robots-and-Beer` | amd64 |
| `github-runner-mantiser.yaml` | `mantiser-com` | amd64 |
| `github-runner-arm-mantiser.yaml` | `mantiser-com` | arm64 |
| `github-runner-samma.yaml` | `samma-io` | amd64 |
| `github-runner-viodlar.yaml` | `viodlar` | amd64 |

## Required Config in Every Values File

Every values file **must** include the `controllerServiceAccount` block. Without it, listener pods crash because they can't locate the controller across namespaces:

```yaml
controllerServiceAccount:
  namespace: arc-systems
  name: arc-gha-rs-controller   # must match actual SA name, NOT just "arc"
```

## Install / Upgrade

Run from within the `runners/` directory. The script installs the controller first, then all runner sets:

```bash
# hrb cluster
KUBECONFIG=~/.kube/confighrb bash install_github_runner.sh

# v2cluster
KUBECONFIG=~/.kube/config bash install_github_runner.sh
```

**If the controller install fails with a CRD conflict** (old CRDs left over from a previous install):
```bash
kubectl --kubeconfig=<kubeconfig> delete crd \
  autoscalinglisteners.actions.github.com \
  autoscalingrunnersets.actions.github.com \
  ephemeralrunners.actions.github.com \
  ephemeralrunnersets.actions.github.com
# Then re-run the controller install only:
helm --kubeconfig <kubeconfig> upgrade --install arc \
    --namespace arc-systems --create-namespace \
    oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller
```

## Verifying Health

```bash
# Controller + all listener pods (expect 1 controller + 7 listeners, all 1/1 Running)
kubectl --kubeconfig=<kubeconfig> get pods -n arc-systems

# Runner sets registered with GitHub (STATE column should populate when jobs run)
kubectl --kubeconfig=<kubeconfig> get autoscalingrunnersets -n arc-runners

# Listener objects (shows which GitHub URL each set connects to)
kubectl --kubeconfig=<kubeconfig> get autoscalinglisteners -n arc-systems
```

## Uninstalling

```bash
KUBECONFIG=<kubeconfig>
for release in arc-runner-set arc-runner-set-arm arc-runner-set-hrb arc-runner-set-mantiser \
               arc-runner-set-arm-mantiser arc-runner-set-samma arc-runner-set-viodlar; do
  helm --kubeconfig $KUBECONFIG uninstall $release -n arc-runners
done
helm --kubeconfig $KUBECONFIG uninstall arc -n arc-systems
```

**If namespaces are stuck Terminating** (ARC uses finalizers on CRDs — they must be stripped manually):
```bash
# Strip finalizers from all ARC custom resources
for rs in arc-runner-set arc-runner-set-arm arc-runner-set-arm-mantiser arc-runner-set-hrb \
          arc-runner-set-mantiser arc-runner-set-samma arc-runner-set-viodlar; do
  kubectl --kubeconfig=$KUBECONFIG patch autoscalingrunnerset $rs -n arc-runners \
    --type=merge -p '{"metadata":{"finalizers":[]}}'
done
# Also strip rolebindings, roles, serviceaccounts, secrets in arc-runners
for type in rolebindings roles serviceaccounts secrets; do
  for r in $(kubectl --kubeconfig=$KUBECONFIG get $type -n arc-runners -o name 2>/dev/null | grep gha-rs); do
    kubectl --kubeconfig=$KUBECONFIG patch $r -n arc-runners --type=merge -p '{"metadata":{"finalizers":[]}}'
  done
done
# Strip listeners in arc-systems
for l in $(kubectl --kubeconfig=$KUBECONFIG get autoscalinglisteners -n arc-systems -o name 2>/dev/null); do
  kubectl --kubeconfig=$KUBECONFIG patch $l -n arc-systems --type=merge -p '{"metadata":{"finalizers":[]}}'
done
```

## Troubleshooting

### Listener pods crash immediately (Error status)

Check logs: `kubectl --kubeconfig=<kubeconfig> logs -n arc-systems <listener-pod>`

| Error | Cause | Fix |
|---|---|---|
| `failed to get kubernetes secret` | `controllerServiceAccount.name` is wrong (e.g. `arc` instead of `arc-gha-rs-controller`) | Fix the name in all values files and `helm upgrade` |
| `409 Conflict: already has an active session` | Stale GitHub broker session from previous install | Delete and reinstall the affected `AutoscalingRunnerSet`: `helm uninstall <name> -n arc-runners && helm upgrade --install ...` |
| `404 Not Found: No runner scale set found` | Old scale-set-id annotation points to deleted GitHub registration | Remove annotation: `kubectl annotate autoscalingrunnerset <name> -n arc-runners actions.github.com/scale-set-id-` then reinstall |
| `401 Unauthorized: Bad credentials` | GitHub PAT has expired | Generate a new PAT with `manage_runners:org` scope, update the token in the values file, `helm upgrade` |

### PAT Token Requirements

Each GitHub PAT needs the `manage_runners:org` scope. Both `ollebo` (amd64 + arm64) and `mantiser-com` (amd64 + arm64) share the same token per org. PATs expire — when they do, all runner sets for that org fail with 401.

## Adding a New Runner Set

1. Copy an existing values file to `github-runner-<name>.yaml`
2. Set `githubConfigUrl`, `githubConfigSecret.github_token`, `nodeSelector` arch
3. Keep the `controllerServiceAccount` block (required)
4. Add a `helm upgrade --install arc-runner-set-<name>` block in `install_github_runner.sh`
