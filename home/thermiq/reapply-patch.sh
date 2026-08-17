#!/usr/bin/env bash
# Re-apply the thermiq_mqtt input_number.py patch after a HACS update reverts it.
#
# Why this exists: thermiq_mqtt 3.1.0 subclasses Home Assistant's InputNumber but
# calls the *Number* entity API, so all 48 numeric controls die on startup AND the
# MQTT write hook sits on a method HA never calls. A HACS update overwrites our
# patched file and silently takes all heat-pump control away again — reads keep
# working, so nothing looks broken. See ../THERMIQ.md section 6.
#
# Idempotent: safe to run when already patched (it will say so and exit 0).
# Local cluster only — never touches the HRB cluster.
set -euo pipefail

NS=home
CC=/config/custom_components/thermiq_mqtt
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/input_number.py"
STAMP=$(date +%Y%m%d-%H%M%S)

echo "==> locating Home Assistant pod in ns/$NS"
POD=$(kubectl get pod -n "$NS" -l app=homeassistant \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
[ -n "$POD" ] || POD=$(kubectl get pod -n "$NS" --no-headers \
        | awk '$1 ~ /^homeassistant-/ && $3=="Running" {print $1; exit}')
[ -n "$POD" ] || { echo "!! no running homeassistant pod found"; exit 1; }
echo "    pod: $POD"

VER=$(kubectl exec -n "$NS" "$POD" -- \
        python3 -c "import json;print(json.load(open('$CC/manifest.json'))['version'])")
echo "    thermiq_mqtt version: $VER"
[ "$VER" = "3.1.0" ] || cat <<EOF
    !! WARNING: this patch was written against 3.1.0. Upstream may have fixed the
       bug (check async_set_value / _current_value in the new input_number.py).
       Diff before trusting: kubectl exec -n $NS $POD -- cat $CC/input_number.py
EOF

if kubectl exec -n "$NS" "$POD" -- grep -q '_current_value' "$CC/input_number.py"; then
  echo "==> already patched — nothing to do"
  exit 0
fi

echo "==> backing up the reverted file to input_number.py.hacs-$STAMP"
kubectl exec -n "$NS" "$POD" -- \
  cp "$CC/input_number.py" "$CC/input_number.py.hacs-$STAMP"

echo "==> copying patched input_number.py in"
kubectl cp "$SRC" "$NS/$POD:$CC/input_number.py"
kubectl exec -n "$NS" "$POD" -- grep -q '_current_value' "$CC/input_number.py" \
  || { echo "!! copy did not take"; exit 1; }

echo "==> restarting Home Assistant via its API (NOT a pod restart — the PVC is RWO)"
kubectl exec -n "$NS" "$POD" -- python3 - <<'PY'
import json, datetime, time, urllib.request, urllib.error
BASE = "http://127.0.0.1:8123"

def token(minutes=20):
    import jwt
    auth = json.load(open("/config/.storage/auth"))
    toks = [t for t in auth["data"]["refresh_tokens"]
            if t.get("token_type") == "long_lived_access_token"]
    rt = next((t for t in toks if t.get("client_name") == "migrate"), None) or toks[0]
    now = datetime.datetime.now(datetime.timezone.utc)
    return jwt.encode({"iss": rt["id"], "iat": now,
                       "exp": now + datetime.timedelta(minutes=minutes)},
                      rt["jwt_key"], algorithm="HS256")

def req(tok, path, data=None):
    r = urllib.request.Request(
        BASE + path, data=(json.dumps(data).encode() if data is not None else None),
        headers={"Authorization": "Bearer " + tok,
                 "Content-Type": "application/json"})
    return json.loads(urllib.request.urlopen(r, timeout=30).read().decode())

t = token()
cc = req(t, "/api/config/core/check_config", {})
print("    check_config:", cc["result"], cc.get("errors") or "")
if cc["result"] != "valid":
    raise SystemExit("!! config invalid, refusing to restart")
try:
    req(t, "/api/services/homeassistant/restart", {})
except urllib.error.HTTPError:
    pass
print("    restarting…")
time.sleep(20)
for _ in range(40):
    try:
        req(t, "/api/"); break
    except Exception:
        time.sleep(5)
else:
    raise SystemExit("!! HA did not come back within 220 s")

# The 48 controls hold state, but the 102 read-only sensors need the pump's next
# MQTT frame (~30 s) before they leave 'unknown'.
for i in range(20):
    time.sleep(15)
    st = {s["entity_id"]: s["state"] for s in req(t, "/api/states")}
    ctl = {k: v for k, v in st.items()
           if k.startswith("input_number.thermiq_mqtt_vp1")}
    bad = [k for k, v in ctl.items() if v in ("unavailable", "unknown")]
    sens = [k for k, v in st.items()
            if k.startswith("sensor.thermiq_mqtt_vp1") and v in ("unavailable", "unknown")]
    print(f"    t+{20+(i+1)*15:3d}s  controls={len(ctl)} bad={len(bad)}  sensors_pending={len(sens)}")
    if len(ctl) == 48 and not bad and not sens:
        print("    ✅ all 48 controls available, all sensors reporting")
        break
else:
    raise SystemExit("!! did not reach a clean state — inspect manually")
PY

echo "==> done. Verify in the UI: http://ha.v2.local/heat-pump (Styrning view)"
