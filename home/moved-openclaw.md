# Migrating / Cloning an OpenClaw Instance

Steps used to clone the `openclaw` instance into a new `openclaw-zoe` namespace with existing data.

---

## 1. Copy and update the YAML file

Copy `openclaw.yaml` to `openclaw-zoe.yaml` and replace all references:

- Namespace: `openclaw` → `openclaw-zoe`
- Resource names: `openclaw` → `openclaw-zoe`
- Secret ref: `openclaw-secrets` → `openclaw-zoe-secrets`
- PVC claims: `openclaw-config/home/workspace` → `openclaw-zoe-config/home/workspace`
- Ingress host: `openclaw.v2.local` → `openclaw-zoe.v2.local`

---

## 2. Temporarily replace the start command

Before deploying, change the container command so the pod stays running without crashing
(the app would fail on first boot without correct config):

```yaml
# Comment out the real command:
#command: ["node", "dist/index.js", "gateway", "--bind", "lan", "--port", "18789", "--allow-unconfigured"]

# Use this idle command instead:
command: ["tail", "-f", "/dev/null"]
```

Deploy it:

```bash
kubectl apply -f openclaw-zoe.yaml
kubectl rollout status statefulset/openclaw-zoe -n openclaw-zoe --timeout=120s
```

---

## 3. Copy data into the pod

Use `tar` piped through `kubectl exec` to copy the data. Do config and workspace separately
since they are on different PVCs mounted at different paths.

> **Note:** tar will print errors like `Cannot utime` and `Cannot change mode` on the root
> directory — these are harmless and the files are copied successfully.

### Config (everything except workspace):

```bash
tar -C /home/mattias/.openclaw -cf - --exclude=./workspace . | \
  kubectl exec -i -n openclaw-zoe openclaw-zoe-0 -- \
  tar -xf - -C /home/node/.openclaw/ --no-same-permissions --no-same-owner
```

### Workspace:

```bash
tar -C /home/mattias/.openclaw/workspace -cf - . | \
  kubectl exec -i -n openclaw-zoe openclaw-zoe-0 -- \
  tar -xf - -C /home/node/.openclaw/workspace/ --no-same-permissions --no-same-owner
```

Verify files landed:

```bash
kubectl exec -n openclaw-zoe openclaw-zoe-0 -- ls /home/node/.openclaw/
kubectl exec -n openclaw-zoe openclaw-zoe-0 -- ls /home/node/.openclaw/workspace/
```

---

## 4. Patch openclaw.json inside the pod

The copied config needs two fixes before the gateway will start:

1. **`gateway.controlUi.dangerouslyAllowHostHeaderOriginFallback`** — required when binding to `lan` without explicit `allowedOrigins`
2. **`agents.defaults.workspace`** — the path is copied from the local machine and must point to the container path

Run this inside the pod:

```bash
kubectl exec -n openclaw-zoe openclaw-zoe-0 -- sh -c '
cat /home/node/.openclaw/openclaw.json | python3 -c "
import json, sys
cfg = json.load(sys.stdin)
cfg[\"gateway\"][\"controlUi\"] = {\"dangerouslyAllowHostHeaderOriginFallback\": True}
cfg[\"agents\"][\"defaults\"][\"workspace\"] = \"/home/node/.openclaw/workspace\"
print(json.dumps(cfg, indent=2))
" > /tmp/openclaw.json.new && mv /tmp/openclaw.json.new /home/node/.openclaw/openclaw.json
'
```

---

## 5. Restore the real command and redeploy

In the YAML, swap the commands back:

```yaml
command: ["node", "dist/index.js", "gateway", "--bind", "lan", "--port", "18789", "--allow-unconfigured"]
#command: ["tail", "-f", "/dev/null"]
```

Apply and verify:

```bash
kubectl apply -f openclaw-zoe.yaml
kubectl rollout status statefulset/openclaw-zoe -n openclaw-zoe --timeout=90s
kubectl get pod openclaw-zoe-0 -n openclaw-zoe
kubectl logs -n openclaw-zoe openclaw-zoe-0 --tail=30
```

Pod should show `1/1 Running` with no fatal errors in the logs.

---

## Known warnings (non-fatal)

- `[DEP0040] punycode module is deprecated` — Node.js version warning, ignore
- `channels.telegram.groupPolicy is "allowlist" but groupAllowFrom is empty` — telegram group messages will be dropped until sender IDs are added to `channels.telegram.groupAllowFrom`
