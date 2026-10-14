#!/usr/bin/env bash
# Push openclaw credentials from a local env file into the instance's Kubernetes
# Secret, then restart the instance so it picks them up.
#
#   ./apply-secrets.sh openclaw          # dobby  -> Secret openclaw/openclaw-secrets
#   ./apply-secrets.sh openclaw-zoe      # zoe    -> Secret openclaw-zoe/openclaw-zoe-secrets
#   ./apply-secrets.sh openclaw --dry-run   # show which keys would change, apply nothing
#
# The env file defaults to ~/.config/openclaw/<instance>.env (override with ENV_FILE=...).
# Format: KEY=value, one per line; '#' comments and blank lines are ignored.
#
# Only keys that HAVE a value are written, and they are merged into the Secret, so
# an empty line never wipes a working key and keys missing from the file are kept.
# To delete a key: kubectl -n <ns> patch secret <ns>-secrets --type=json \
#                    -p '[{"op":"remove","path":"/data/KEY"}]'
#
# NEVER commit the env file: this repo is public. It lives outside the repo on purpose.
set -euo pipefail

NS=${1:?usage: $0 <openclaw|openclaw-zoe> [--dry-run]}
DRY=${2:-}
case "$NS" in openclaw|openclaw-zoe) ;; *) echo "unknown instance: $NS" >&2; exit 1;; esac
ENV_FILE=${ENV_FILE:-$HOME/.config/openclaw/$NS.env}
CTX=${KUBE_CONTEXT:-admin@v2cluster}
K="kubectl --context $CTX -n $NS"

[ -f "$ENV_FILE" ] || { echo "env file not found: $ENV_FILE" >&2; exit 1; }
case "$(realpath "$ENV_FILE")" in "$(realpath "$(dirname "$0")/../..")"/*)
  echo "refusing: $ENV_FILE is inside the (public) git repo" >&2; exit 1;; esac

umask 077
PATCH=$(mktemp); trap 'shred -u "$PATCH" 2>/dev/null || rm -f "$PATCH"' EXIT

# Build a {"stringData":{...}} merge patch from the non-empty KEY=value lines and
# report which keys are new / changed / unchanged versus the live Secret.
LIVE_SECRET=$($K get secret "$NS-secrets" -o json) \
python3 - "$ENV_FILE" "$PATCH" <<'EOF'
import json, os, re, sys, base64
env_file, patch_file = sys.argv[1], sys.argv[2]
live = {k: base64.b64decode(v).decode() for k, v in (json.loads(os.environ["LIVE_SECRET"]).get("data") or {}).items()}
out = {}
for n, line in enumerate(open(env_file), 1):
    line = line.strip()
    if not line or line.startswith("#"):
        continue
    if line.startswith("export "):
        line = line[7:].lstrip()
    m = re.match(r'^([A-Z_][A-Z0-9_]*)=(.*)$', line)
    if not m:
        sys.exit(f"{env_file}:{n}: not KEY=value (keys must be UPPER_CASE)")
    k, v = m.group(1), m.group(2).strip()
    if len(v) >= 2 and v[0] == v[-1] and v[0] in "'\"":
        v = v[1:-1]
    if not v:
        continue
    out[k] = v
    print(f"  {'new      ' if k not in live else 'changed  ' if live[k] != v else 'unchanged'}  {k}")
if not out:
    sys.exit("no keys with values in the file - nothing to apply")
json.dump({"stringData": out}, open(patch_file, "w"))
EOF

if [ "$DRY" = "--dry-run" ]; then echo "dry run - nothing applied"; exit 0; fi

$K patch secret "$NS-secrets" --type=merge --patch-file "$PATCH" >/dev/null
echo "Secret $NS/$NS-secrets updated. Restarting $NS ..."
$K rollout restart "statefulset/$NS"
$K rollout status "statefulset/$NS" --timeout=300s
echo
echo "Check it came up (allow ~1 min for channels):"
echo "  kubectl --context $CTX -n $NS exec $NS-0 -- openclaw channels status --probe"
echo "  kubectl --context $CTX -n $NS exec $NS-0 -- openclaw secrets audit"
