# Logging Stack for Kubernetes (Talos Linux)

A self-contained logging pipeline using Fluent Bit, NATS, Vector, and Loki. Designed for Talos Linux clusters but works on any standard Kubernetes distribution.

## Architecture

```
K8s Pods → stdout/stderr
    │
    ▼
Fluent Bit (DaemonSet)
  tails /var/log/containers/*.log on every node
  enriches with K8s metadata (namespace, pod, container)
    │ Fluent Forward protocol :24224
    ▼
Vector Collector (Deployment)
  normalises fields, adds source_type label
    │ NATS JetStream  subject: logs.k8s
    ▼
NATS (StatefulSet, JetStream enabled)
  durable stream LOGS — 24h retention, file storage
    │ NATS consumer queue: vector-aggregator
    ▼
Vector Aggregator (Deployment)
  ensures required Loki label fields exist
    │ HTTP :3100
    ▼
Loki (SingleBinary, Helm)
  stores logs on a PVC — queryable via LogQL
    │
    ▼
Grafana  (add Loki as datasource — see below)
```

## Files in this Directory

| File | Purpose |
|------|---------|
| `ns.yaml` | `logging` namespace — privileged PSA required for DaemonSet hostPath mounts |
| `nats.yaml` | Single-node NATS StatefulSet with JetStream (self-contained) |
| `nats-stream-setup.yaml` | One-time Job that creates the `LOGS` JetStream stream |
| `loki-values.yaml` | Helm values for Loki SingleBinary |
| `vector.yaml` | Vector Collector + Vector Aggregator deployments |
| `fluentbit.yaml` | Fluent Bit DaemonSet + RBAC |

The Loki ArgoCD Application lives at `../core/loki.yaml` (uses the same `loki-values.yaml` values).

## Prerequisites

- `kubectl` configured for your cluster
- Helm 3 with the Grafana chart repo: `helm repo add grafana https://grafana.github.io/helm-charts`
- For this cluster: `export KUBECONFIG=~/.kube/confighrb`

## Talos-Specific Notes

Fluent Bit runs as a DaemonSet and mounts host paths (`/var/log/containers`, `/var/log/pods`, `/run`). Talos enforces Pod Security Admission — the `logging` namespace must have the `privileged` enforcement label. `ns.yaml` already sets this.

No Talos machine config changes are needed. Container logs land at `/var/log/containers/` on each node exactly as on any other K8s distribution.

## Deploy

Apply in this order — each step depends on the previous.

```bash
export KUBECONFIG=~/.kube/confighrb

# 1. Namespace (must exist before everything else)
kubectl apply -f logging/ns.yaml

# 2. NATS with JetStream
kubectl apply -f logging/nats.yaml
kubectl rollout status statefulset/nats -n logging

# 3. Create the LOGS stream
kubectl apply -f logging/nats-stream-setup.yaml

# 4a. Loki via Helm (standalone)
helm upgrade --install loki grafana/loki \
  --version 6.7.4 \
  --namespace logging \
  -f logging/loki-values.yaml

# 4b. Loki via ArgoCD (if you use ArgoCD)
# kubectl apply -f core/loki.yaml

kubectl rollout status statefulset/loki -n logging

# 5. Vector Collector + Aggregator
kubectl apply -f logging/vector.yaml
kubectl rollout status deployment/vector-collector -n logging
kubectl rollout status deployment/vector-aggregator -n logging

# 6. Fluent Bit (last — nothing to collect until the pipeline is ready)
kubectl apply -f logging/fluentbit.yaml
kubectl rollout status daemonset/fluent-bit -n logging
```

### Using the code-namespace NATS instead

The live cluster already has a 3-node NATS in the `code` namespace. If you prefer that over the standalone one above, skip step 2 and edit `vector.yaml` — change both occurrences of:

```
nats://nats.logging.svc.cluster.local:4222
```

to:

```
nats://nats.code.svc.cluster.local:4222
```

The `nats-stream-setup.yaml` server flag needs the same change.

## Verify

```bash
K=~/.kube/confighrb

# All pods running
kubectl --kubeconfig=$K get pods -n logging

# Fluent Bit — should show logs being read
kubectl --kubeconfig=$K logs -n logging -l app=fluent-bit --tail=30

# Vector Collector — should show events forwarded to NATS
kubectl --kubeconfig=$K logs -n logging -l app=vector-collector --tail=30

# Vector Aggregator — should show events written to Loki
kubectl --kubeconfig=$K logs -n logging -l app=vector-aggregator --tail=30

# NATS stream info (requires nats-box)
kubectl --kubeconfig=$K run nats-test --rm -it --restart=Never \
  --image=natsio/nats-box:0.14.5 -- \
  nats stream info LOGS --server nats://nats.logging.svc.cluster.local:4222

# Loki ready check
kubectl --kubeconfig=$K port-forward -n logging svc/loki-headless 3100:3100 &
curl -s localhost:3100/ready
# → ready

# Labels present means logs arrived
curl -s 'localhost:3100/loki/api/v1/labels' | jq .
```

## Grafana Integration

Add Loki as a datasource in Grafana:

- **Type:** Loki
- **URL:** `http://loki.logging.svc.cluster.local:3100`
- **Auth:** none (auth_enabled: false)

Sample LogQL queries:

```logql
# All logs from a namespace
{namespace="kube-system"}

# Logs from a specific pod
{pod=~"coredns.*"}

# Error lines across the cluster
{namespace=~".+"} |= "error"

# Logs from a container, last 5 minutes
{container="vector"} | json
```

## SIEM Integration

The NATS stream `logs.k8s` is the integration point for the Samma SIEM. The SIEM subscribes to this subject, evaluates events against YAML rules, and publishes alerts to `samma.alerts.*`.

When connecting the SIEM:

1. The SIEM's `SIEM_NATS_URL` should point to `nats://nats.logging.svc.cluster.local:4222` (or `nats.code.svc.cluster.local:4222` if using the shared NATS).
2. Set `SIEM_NATS_SUBSCRIBE=logs.k8s` to match the subject Vector publishes to.
3. The SIEM publishes alerts to `samma.alerts.<severity>` — wire a second Vector sink to forward those to Loki or Elasticsearch for dashboards.

See `samma/siem` repository for the SIEM deployment manifests and rule configuration.
