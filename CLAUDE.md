# HRB v2-k8s — Claude Guide

This is a **GitOps repo** (`git@github.com:mattiashem/v2-k8s.git`). Plain Kubernetes manifests
and Helm values, deployed by ArgoCD — see "Deployment Model" below. There is no build/lint/test
step; the "tests" are `kubectl`/`argocd` reconciliation against a live cluster.

## ⚠️ Default cluster = LOCAL. HRB production is off-limits without approval.
**Default to the local cluster for everything.** The HRB cluster (`~/.kube/confighrb`, `admin@hrb`)
is **production mail** — do **not** run any command against it (not even reads) without the user's
**explicit, per-action approval**. Editing files under `hrb/` is fine; applying/exec'ing/restarting
against the live HRB cluster is not. When in doubt, ask first.

## Two Clusters — pick the right kubeconfig
Manifests in this repo target **two different clusters**. Most directories are the local cluster;
only `hrb/` is the production mail cluster.

| Cluster | Kubeconfig | Context | API server | Directories |
|---|---|---|---|---|
| Local (home automation) | `~/.kube/config` (default) | `admin@v2cluster` | — | `home/`, `code/`, `core/`, `logging/`, `pbx/`, `zoe/`, `runners/` |
| HRB (production mail) | `~/.kube/confighrb` | `admin@hrb` | `https://10.13.13.1:6443` (router proxy, skip TLS) | `hrb/`, `runners/` |

Both are **Talos Linux, k8s v1.32.5**. ARC runners (`runners/`) are installed on *both* clusters.
Always pass `--kubeconfig=~/.kube/confighrb` for anything mail-related; omit the flag for everything else.

```bash
kubectl --kubeconfig=~/.kube/confighrb get all -n hrb   # HRB cluster
kubectl get all -n home                                 # local cluster
```

## Deployment Model — ArgoCD App-of-Apps
**Do not `kubectl apply` to deploy.** Commit + push to `master`; ArgoCD reconciles `HEAD`.

- `argo-init.yaml` bootstraps ArgoCD: the repo SSH secret, the `core` AppProject, and the
  `argocd-seed` Application which syncs `path: core`.
- `core/*.yaml` are themselves ArgoCD `Application` resources (app-of-apps). Each points at a
  top-level directory (`core/home.yaml` → `path: home`, `core/code.yaml` → `path: code`,
  `core/logging-seed.yaml` → `path: logging`, etc.). Adding a new app = add a `core/<name>.yaml`
  Application pointing at its directory.
- Every other directory (`home/`, `code/`, `hrb/`, …) is a flat pile of manifests/Helm values
  that ArgoCD applies as a unit.
- ArgoCD admin password: `./getArgocdPassword.sh`. UI exposed via `argocd-server-lb` (see `argoc-node.yaml`).

`runners/` is the exception — installed imperatively via Helm, not ArgoCD. See `runners/CLAUDE.md`.

## Repo Structure
```
hrb/          # HRB cluster — mail stack (postfix/dovecot/amavis/opendkim/PostfixAdmin)
code/         # Local — code/dev namespace
core/         # Local — ArgoCD app-of-apps seeds + core infra (traefik, cert-manager, metallb)
home/         # Local — home automation (Frigate, HA, Plex, Ollama, n8n, pihole, …)
logging/      # Local — fluentbit / loki / vector / nats (see logging/README.md)
pbx/          # Local — PBX
zoe/          # Local — Zoe / OVOS voice assistant
runners/      # GitHub ARC self-hosted runners, both clusters (see runners/CLAUDE.md)
```
> Jetson (standalone, NOT k8s): Frigate removed 2026-07-05 — Jetson now only runs Ollama (gemma4b).
> Cluster Frigate lives in `home/frigate-inomhus.yaml` + `home/frigate-utomhus.yaml` (ns `frigate`).

> Nested guides exist — read them before touching those areas: `runners/CLAUDE.md`, `logging/README.md`.

## Mail Stack (namespace: hrb)
| Component    | Description                        |
|--------------|------------------------------------|
| postfix      | SMTP server                        |
| dovecot      | Runs inside postfix pod, SASL auth |
| amavisd      | Spam/virus filter                  |
| opendkim     | DKIM signing                       |
| mail-admin   | PostfixAdmin UI                    |
| mail-web     | Webmail                            |
| main-mysql   | MySQL StatefulSet (PostfixAdmin DB)|

### MySQL
- Root password in secret `mysql-cluster` → `ROOT_PASSWORD`
- PostfixAdmin DB: host `main-mysql-master`, db `postfixadmin`
- Shell: `kubectl --kubeconfig=~/.kube/confighrb exec -n hrb main-mysql-0 -c mysql -- mysql -uroot -p<password> postfixadmin`

### Dovecot password config
- Mounted via configmap `postfix-config-main` → key `dovecot-sql.conf`
- `default_pass_scheme = BLF-CRYPT`
- MD5-legacy hashes prefixed with `{MD5-CRYPT}` in DB

## Longhorn Storage (Local Cluster)

### Dead Nodes
- **node2** and **node3** — `NotReady` and cordoned since late 2025. Do not expect them to come back.
- Only active Longhorn targets: `turing1` (ssd2/nvme1/ssd1), `node1`, `talos-wyx-ktb` (default disk only)

### Disabled Disks
- **talos-wyx-ktb USB** (`/var/mnt/usb-storage`) — scheduling disabled, over-committed. Do **not** re-enable.
- **node1 default disk** — nearly full (~1 Gi schedulable headroom). Existing replicas OK, expansions will fail.

### PVC Expansion — Known Pitfalls
Longhorn blocks expansion if any replica's disk lacks headroom OR replicas are unscheduled. Safe procedure:
1. Delete replicas on over-committed disks, disable those disks for scheduling
2. If volumes show `degraded`, set `numberOfReplicas: 2` via `kubectl patch volume.longhorn.io`
3. Wait for `ROBUSTNESS: healthy`, then patch the PVC

### Volumes at 2 Replicas
`openclaw` and `openclaw-zoe` volumes run at `numberOfReplicas: 2` (turing1 + node1) — intentional, 3rd replica target doesn't exist.

## OpenClaw (AI Agent Gateway)

Two instances, both in the local cluster, both on **node1**, both StatefulSets.

| Instance | Namespace | Ingress | Telegram bot | WhatsApp |
|---|---|---|---|---|
| `openclaw` | `openclaw` | `openclaw.v2.local` | `@openclaw_bot` (open DM policy) | not configured |
| `openclaw-zoe` | `openclaw-zoe` | `openclaw-zoe.v2.local` | `@zoe_bot` (allowlist) | disabled |

### LLM Model Config (both instances)
- **Primary:** `google/gemini-2.5-flash`
- **Fallback:** `ollama/qwen2.5:7b-instruct` (Ollama at `http://10.0.0.20:11434/v1`)
- **Image model:** `google/gemini-2.5-flash-image`
- **Google API key** stored in `models.providers.google.apiKey` in `openclaw.json`

### Resources (both instances — Guaranteed QoS)
```yaml
resources:
  requests:
    cpu: "2000m"
    memory: "2Gi"
  limits:
    cpu: "2000m"
    memory: "2Gi"
```

### Config Location
- Live config: `/home/node/.openclaw/openclaw.json` (on the `openclaw[-zoe]-config` PVC)
- Edit via exec: `kubectl exec -n <ns> <pod> -- python3 -c "import json; ..."`
- Restart to apply: `kubectl rollout restart statefulset/<name> -n <ns>`

### Known Issues
- `gemini-3-pro-preview` caused 131s timeouts in openclaw — switched to `gemini-2.5-flash`
- `ollama/qwen2.5:7b-instruct` fallback can crash with `llama runner process has terminated` (OOM on Ollama host)

## Agent IRC Bus (Ergo, `chat.robots.beer`)

Agents report what they are doing into IRC and can be driven back from it. The server is
**Ergo** (`ghcr.io/ergochat/ergo:stable`), deploy `irc` in ns `hrb` on the **HRB cluster** —
its config is a ConfigMap there and is in **no git repo**. Public endpoint
`chat.robots.beer:6697`, TLS only.

| Channel | Purpose | Registered |
|---|---|---|
| `#agents` | shared "what I'm doing now" | ❌ — `emst` is present and nobody has op, so the relay uses its `<agent>` prefix fallback there |
| `#agents-work` | finished work: PRs, results | ✅ founder `agentrelay` |
| `#claude` | control Claude Code sessions | ✅ |
| `#dobby` / `#zoe` | control each openclaw instance | ✅ |

| Account | Used by |
|---|---|
| `agentrelay` | the `irc-relay` service, on behalf of `cc/*`, `arc/*`, `kf/*` |
| `dobby` / `zoe` | the two openclaw instances, native `@openclaw/irc` plugin |
| `mahe` | **your admin account — the ONLY sender dobby and zoe accept commands from** |
| `matte` | registered 2026-09-06, but NOT on any agent allowlist |

**🔒 Account registration is DISABLED** (2026-09-06 — `accounts.registration.enabled: false`
+ `allow-before-connect: false` in the `irc-config` ConfigMap on HRB). All 11 accounts:
`agentrelay dobby zoe matte binja emst gg kemani mahe nvkv nvkv2`. To add an agent later,
re-enable it, `kubectl rollout restart deployment/irc -n hrb`, register, then disable again —
or use an oper with the `accreg` capability and `NICKSERV SAREGISTER` (the configured `admin`
oper password looks like the stock placeholder hash, so that path is untested). Anonymous
clients can still *connect* and chat; they just cannot create accounts. Channel registration
is still open.

List accounts without a client — the datastore is BoltDB, **not** the MySQL history db:
```bash
kubectl --kubeconfig=~/.kube/confighrb exec -n hrb deploy/irc -- \
  sh -c 'strings /ircd-data/ircd.db | grep -oE "^account\.exists [[:graph:]]+" | cut -d" " -f2 | sort -u'
```

Passwords are **not in git** — `~/.config/irc-relay/*.pass` (mode 600) and the
`irc-relay-secrets` Secret in ns `irc-relay`. `matte` is the human account.

### Two ways in
- **Persistent agents** (dobby, zoe) hold their own IRC connection via openclaw's native
  plugin. Config lives in `openclaw.json` on the PVC, not in git.
- **Ephemeral agents** (Claude Code sessions, ARC runners, KubeFoundry tasks) POST to
  **`irc-relay`** (`irc-relay/`, app `core/irc-relay.yaml`, ns `irc-relay`), which owns one
  shared connection. LAN: `http://irc-relay.v2.local`. In-cluster:
  `http://irc-relay.irc-relay.svc.cluster.local` — **`*.v2.local` does not resolve in pods**.
  Claude Code wiring: `~/.claude/hooks/irc.sh` + hooks in `~/.claude/settings.json`.

### Traps
- 🔴 **Changing an agent's IRC allowlist needs a full pod restart.**
  `openclaw gateway call channels.stop` + `channels.start` reports success and reconnects,
  but the old provider survives with its old config still handling messages — dobby kept
  obeying a removed account through four stop/start cycles, and the ircd showed 7 sessions
  for one account (`multiclient` permits them). Always
  `kubectl rollout restart statefulset/<name>` and re-verify.
- 🔴 **Verify an allowlist change with a replay-aware test.** Ergo's `autoreplay-on-join`
  re-sends up to 30 past lines *with the original sender's prefix*, so a stale reply from
  the agent looks exactly like a live one. Join, drain for ~8s, then send a unique nonce and
  only count what arrives after it. Confirm against the agent's own log, which prints
  `[irc] drop group sender <nick>!… (policy=allowlist)` for a rejected sender.
- 🔴 **An allowlisted nick is only trustworthy if that nick is registered.** The whole
  "a nick *is* an authenticated account" argument holds for reserved nicks only. dobby and
  zoe briefly trusted `matte` while `matte` was unregistered — anyone could have taken the
  nick and commanded both agents. Registering it closed that. Check `/msg NickServ INFO
  <nick>` before putting any nick in an allowlist.
- 🔴 **Agent-to-agent loops.** Two LLM agents in one channel will answer each other forever
  and burn API tokens. Guards: mode `+B` on every bot account, `requireMention: true` in
  shared channels, and `allowFrom`/`groupAllowFrom` limited to `mahe`. Test with both bots idle before
  enabling anything chatty.
- 🔴 **~2 msg/s, server-wide per connection** (`fakelag`: burst 5, 2 per 1s window). This is
  the hard ceiling. **Do not narrate tool use** — publish session start, permission-needed,
  errors, PR links, session end. The relay throttles at 1.5/s and drops the oldest
  low-priority events, reporting `(+N events suppressed)`.
- ⚠️ **32 connections per 10 minutes per /32, 16 concurrent**, and the whole LAN plus
  cluster shares one NAT address (`155.4.221.50`). This is why ephemeral agents share one
  relay connection instead of each opening their own. (Configured limit; not observed being
  hit in practice.)
- ✏️ **Ergo sends nothing until you register.** A probe that connects and waits for a
  banner hangs forever and looks exactly like a block — it isn't. Send `NICK`/`USER` first.
  Equally, always run probe scripts with `python3 -u`: killed by `timeout`, a buffered
  script loses all its output and looks like a silent failure.
- ✏️ Only `:6697` (TLS) and `:8097` (websocket) listeners exist. The Service maps
  `6667:32695` but **nothing is bound to it** — plaintext IRC will hang, not refuse.
- ✏️ `nick-reservation` is **strict** with `force-nick-equals-account`: a nick *is* its
  account, and a 433 on a registered nick means **SASL did not run**, not that a ghost holds
  it. `IRC_DEBUG=true` on the relay logs the raw protocol.
- ✏️ `CAP LS 302` is **multiline** (continuations marked `*`) and advertises values
  (`sasl=PLAIN,EXTERNAL,...`). Match capability *names*, and do not send `CAP END` until
  every `CAP REQ` is answered.
- ✏️ History is MySQL-backed with `autoreplay-on-join: 30`, so rejoining replays old lines.
  The relay ignores anything at or before a per-channel server-time high-water mark;
  without that a restart re-runs old commands.

## Cert-Manager
- ClusterIssuer: `http` (HTTP-01 via Traefik)
- Traefik runs on NodePort — needs router portforward 80→NodePort for cert renewal
- Known issue: `chat.robots.beer` cert stuck pending (port 80 not reachable externally)

## Common Commands
```bash
# List all in hrb namespace
kubectl --kubeconfig=~/.kube/confighrb get all -n hrb

# Check cert issues
kubectl --kubeconfig=~/.kube/confighrb get certificates,challenges -n hrb

# Restart postfix
kubectl --kubeconfig=~/.kube/confighrb rollout restart deployment/postfix -n hrb

# MySQL shell
kubectl --kubeconfig=~/.kube/confighrb exec -n hrb main-mysql-0 -c mysql -- mysql -uroot -pasyd5675ahskdhka postfixadmin
```
