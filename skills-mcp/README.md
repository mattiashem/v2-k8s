# skills-mcp

Serves the shared Agent Skills registry over **MCP (streamable HTTP)** so agents that have no
skill system of their own can still load the runbooks.

Claude Code and openclaw both read the `SKILL.md` format natively and should install from the
registry repo directly — they do **not** need this service. This exists for everything else:
n8n, custom bots, and coding agents that only speak MCP.

## Endpoint

| | |
|---|---|
| MCP | `http://skills-mcp.v2.local/mcp` (POST, JSON-RPC) |
| Health | `http://skills-mcp.v2.local/healthz` → `{"status":"ok","skills":[...]}` |

`*.v2.local` is a wildcard pointing at the traefik LoadBalancer, so the host header does the routing.

## What it exposes

Each skill is offered three ways, because MCP clients differ in what they support:

| Primitive | Shape | Notes |
|---|---|---|
| **tools** | `list_skills`, `get_skill(name)` | The primary path — tools are the most widely supported primitive |
| resources | `skill://<slug>` | For clients that browse resources |
| prompts | one per skill | For clients that surface prompts as slash commands |

## Design notes

**Zero dependencies.** The server is stdlib-only Python, so it runs on a stock `python:3.12-slim`
image — no image to build, no registry to publish to, and nothing fetched from PyPI at startup.
The whole server is a ConfigMap.

**Skills are re-read on every request**, so updated content is picked up without a restart.

**Content is a snapshot, not a live mirror.** The registry lives in a separate private repo, so
`configmap-skills.yaml` is generated from it:

```bash
./generate-skills-configmap.sh [path-to-agent-skills-repo]
```

That script also stamps a content hash onto the Deployment's `checksum/skills` annotation, so a
skill change actually rolls the pod rather than waiting on kubelet's ConfigMap sync period.
Rerun it and commit after every skill change.

**Upgrading to live sync** is a small change once a read-only token exists: add a git-sync sidecar
writing into `/skills`, then delete `configmap-skills.yaml`, its volume, and the `expand-skills`
initContainer. The server needs no modification — it just reads whatever is in `SKILLS_DIR`.

## Layout

```
namespace.yaml            the skills namespace
configmap-server.yaml     the MCP server itself
configmap-skills.yaml     GENERATED — skill content
deployment.yaml           initContainer expands <slug>__SKILL.md into <slug>/SKILL.md
service.yaml              ClusterIP + traefik ingress
```

The flat `<slug>__SKILL.md` key naming exists because ConfigMap keys cannot contain `/`; the
initContainer expands them back into the directory tree the Agent Skills format expects.

## Security

The server is **read-only and unauthenticated** — it only ever hands out skill text, and the
registry contains no credentials by policy. It is reachable from the LAN and the routed internal
nets. Do not add anything sensitive to a skill on the assumption that this endpoint is private.
