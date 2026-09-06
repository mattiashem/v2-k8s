# irc-relay

One IRC connection shared by many short-lived agents.

Claude Code sessions, ARC runner pods and KubeFoundry task pods cannot each hold an
IRC socket open — they are ephemeral, and they all leave the cluster through a single
NAT address that the ircd rate-limits. They POST events here over HTTP instead; this
process owns the one connection and attributes each message to its originating agent
with `RELAYMSG`, so `#agents` shows `cc/workstation-664f93` rather than one bot nick.

The reverse direction is the point of the whole thing: you type a reply in `#agents`
minutes after an agent went quiet, and it is parked in a per-agent inbox that the agent
collects on its next poll.

Persistent agents do **not** use this. `dobby` and `zoe` are openclaw instances with the
native `@openclaw/irc` plugin and their own accounts — see the repo `CLAUDE.md`.

```
Claude Code hooks (LAN) ─┐
ARC runner pods         ─┼─► HTTP :8080 ──► outbox ──token bucket──┐
KubeFoundry pods        ─┘        ▲                                ▼
                                inbox ◄── IRC ──TLS 1.3──► chat.robots.beer:6697
```

## Server facts that shaped this

The ircd is Ergo (`ghcr.io/ergochat/ergo:stable`), in ns `hrb` on the **HRB cluster**,
not this one. Its config is a ConfigMap on that cluster and is in no git repo.

| Constraint | Consequence here |
|---|---|
| Only `:6697` TLS and `:8097` websocket listeners exist | `IRC_TLS=true` is not optional. The Service maps `6667:32695` but nothing is bound to it |
| `fakelag`: 1s window, burst 5, 2 msg/window | Token bucket: capacity 4, refill 1.5/s. **This is the ceiling on the whole design** |
| `ip-limits`: 16 concurrent, 32 per 10 min per /32 | One shared connection, and reconnect backoff is jittered up to 300s |
| `relaymsg` enabled, separator `/`, chanop only | Agent ids must contain exactly one `/`; without op we fall back to `<agent> text` |
| `nick-reservation: strict`, `force-nick-equals-account` | The relay's nick **is** its account name |
| History is MySQL-backed, `autoreplay-on-join: 30` | Rejoining replays old lines. The relay ignores anything at or before its per-channel high-water mark, so an old command is never re-delivered as new |

## Files

| File | Role |
|---|---|
| `irc_relay.py` | **Source of truth.** Stdlib only — no image build, it ships as a ConfigMap |
| `generate-configmap.sh` | Regenerates `configmap-server.yaml` and stamps `checksum/relay` on the Deployment. **Run and commit after every code change** |
| `configmap-server.yaml` | GENERATED — never edit by hand |
| `deployment.yaml` | `replicas: 1`, `strategy: Recreate` (two pods = two connections = duplicate posts) |
| `service.yaml` | ClusterIP + ingress `irc-relay.v2.local` |

Deployed by `core/irc-relay.yaml`. `argocd-seed` is manual-sync, so a new app needs
`argocd-seed` synced first, then `irc-relay`.

## Bootstrap

Credentials are deliberately **not** in git. Passwords live in `~/.config/irc-relay/`
(mode 600) on the workstation and in the `irc-relay-secrets` Secret.

```bash
# accounts (already done — registration is open, no email verification)
#   /msg NickServ REGISTER <password>       as agentrelay, dobby, zoe
# channels, as agentrelay:
#   /msg ChanServ REGISTER #agents-work
#   /msg ChanServ AMODE #agents-work +o agentrelay

kubectl create namespace irc-relay
kubectl create secret generic irc-relay-secrets -n irc-relay \
  --from-literal=irc-account=agentrelay \
  --from-literal=irc-password="$(cat ~/.config/irc-relay/agentrelay.pass)" \
  --from-literal=relay-token="$(cat ~/.config/irc-relay/relay.token)"
```

A cluster rebuild will not recreate that Secret and ArgoCD will not complain — the pod
will just log `SASL FAILED`. There is no sealed-secrets controller in this repo yet.

## API

`Authorization: Bearer <relay-token>` on everything except `/healthz`.

| Endpoint | Notes |
|---|---|
| `POST /v1/publish` | `{agent, channel, event, text}`. Always `202`, even when dropped — a hook must never see an error it might retry or show you |
| `GET /v1/commands?agent=&wait=&peek=` | Long-poll up to 55s. Destructive read unless `peek=1` |
| `GET /v1/agents` | Queue depths per agent |
| `GET /healthz` | Unauthenticated. **200 whenever the process lives, even with IRC down** — otherwise an ircd outage would pull the pod from the Service and hang every hook. IRC state is in the body |

`event` is one of `notify stop error question pr start` (high priority) or anything
else (low). `channel` must be in `IRC_CHANNELS`; a leaked token must not let anyone
make the bot spam `#home`. Agent ids are normalised server-side to something
`RELAYMSG` accepts (`weird name!!` → `cc/weird-name`), and text is truncated to 400
bytes on a UTF-8 codepoint boundary — the server enforces `UTF8ONLY` and a split
codepoint closes the connection.

```bash
curl -sX POST http://irc-relay.v2.local/v1/publish \
  -H "Authorization: Bearer $TOK" -H 'Content-Type: application/json' \
  -d '{"agent":"cc/test","channel":"#agents","event":"log","text":"hello"}'
```

**In-cluster clients must use `http://irc-relay.irc-relay.svc.cluster.local`** —
`*.v2.local` does not resolve inside pods, it is a pihole-only zone.

## Addressing an agent from IRC

Type `agent/id: text` (or `agent/id, text`) in any channel the relay is in, or DM the
relay. It is parked for that agent and delivered on its next poll. The address prefix
is stripped; the agent receives just the text.

## Ops

```bash
kubectl logs -n irc-relay deploy/irc-relay -f
curl -s http://irc-relay.v2.local/healthz | jq
```

- `channels.<name>.op: false` → not a chanop there, so it is using the `<agent>` text
  prefix instead of RELAYMSG. Fix with `/msg ChanServ AMODE <chan> +o agentrelay`.
  Nothing is broken; only the per-agent nick rendering is lost.
- `dropped` climbing → an agent is publishing faster than 1.5 msg/s sustained. The
  oldest low-priority entries go first and a `(+N events suppressed)` note is appended
  once that agent's backlog clears.
- `irc: reconnecting` with `last_error` set → check `last_error`. A TCP connect that
  succeeds but receives no banner means the ircd is rate-limiting this IP; back off and
  wait out the 10-minute window.
- Editing `irc_relay.py` without running `generate-configmap.sh` changes nothing: the
  pod serves the ConfigMap.
