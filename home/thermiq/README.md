# ThermIQ / Thermia — recovery kit

Everything in this directory exists because **Home Assistant's config lives on a
PVC, not in git**. If that volume is lost, or if HACS updates the integration,
the heat-pump setup is gone with no trace in the repo. This is the copy that
survives.

The register map, control paths and traps are documented in
[`../THERMIQ.md`](../THERMIQ.md). This directory is only the *artifacts*.

| File | What it is |
|---|---|
| `input_number.py` | The **patched** file we actually run. Copy this into `/config/custom_components/thermiq_mqtt/`. |
| `input_number.py.orig-3.1.0` | Pristine upstream 3.1.0, kept so the patch can be re-derived or diffed against a newer release. |
| `input_number.patch` | The change as a unified diff — three hunks. Use this to reason about whether a newer upstream release still needs it. |
| `reapply-patch.sh` | Idempotent re-apply: backs up, copies, validates config, restarts HA via its API, waits for all 48 controls. |
| `templates.yaml` | The Δ-T + patch-guard template sensors. Lives at `/config/templates.yaml`, included from `configuration.yaml` as `template: !include templates.yaml`. |
| `automation-varmepump-styrning-borta.yaml` | The guard automation. Appended to `/config/automations.yaml`. |
| `scripts-varmepump-profiler.yaml` | The Sommar/Vinter/Semester profile scripts — **the whole of** `/config/scripts.yaml`, which was empty before this. |
| `automation-varmepump-profil.yaml` | Applies the selected profile on change and re-asserts on HA start. Appended to `/config/automations.yaml`. |

## The bug

`thermiq_mqtt` 3.1.0 subclasses Home Assistant's `InputNumber` but uses the
*Number* entity API, which that base class does not have:

| Component uses | HA's `InputNumber` actually has |
|---|---|
| `_attr_native_value` | `_current_value` |
| `native_min_value` / `native_max_value` | `_minimum` / `_maximum` |
| `async_set_native_value()` | `async_set_value()` |

Two independent defects: every control raises on startup, **and** the MQTT write
hook is attached to `async_set_native_value()`, a method HA never calls — so even
if the entities had loaded, edits would never have reached the pump. Present in
3.1.0 and in master as of 2026-08-16.

Applied 2026-08-16. Verified end-to-end 2026-08-17 — see "Write path" below.

## Why it needs guarding

A HACS update overwrites `input_number.py` and **silently** reverts all of this.
Reading keeps working — 102 sensors, 38 binary sensors, graphs, history, all
fine — so nothing looks broken. Only the 48 controls go, and only if you try to
change something do you notice.

Two layers catch it:

1. `sensor.varmepump_styrningar_otillgangliga` (in `templates.yaml`) counts
   thermiq `input_number` entities that are `unavailable`/`unknown`. Healthy = `0`
   of `48`. Shown on the dashboard under **Diagnostik → System**.
2. `automation.varmepump_styrning_borta` sends Telegram after the count has been
   above 0 for 15 min, then nags every 12 h until it is fixed.

An MQTT link drop does **not** trigger this — `input_number` entities keep their
last value when MQTT goes quiet. A non-zero count means the patch, not WiFi.

## Recovery

```bash
# after a HACS update, or on a fresh /config volume:
./reapply-patch.sh
```

Then, if `/config` was rebuilt from scratch, also restore the HA-side config:

```bash
POD=$(kubectl get pod -n home -l app=homeassistant -o jsonpath='{.items[0].metadata.name}')

kubectl cp templates.yaml "home/$POD:/config/templates.yaml"
# configuration.yaml needs:  template: !include templates.yaml
kubectl exec -n home "$POD" -- sh -c \
  'grep -q "^template:" /config/configuration.yaml \
   || printf "\ntemplate: !include templates.yaml\n" >> /config/configuration.yaml'

# append the guard automation
kubectl cp automation-varmepump-styrning-borta.yaml "home/$POD:/tmp/a.yaml"
kubectl exec -n home "$POD" -- sh -c \
  'grep -q varmepump_styrning_borta /config/automations.yaml \
   || cat /tmp/a.yaml >> /config/automations.yaml'

# profile scripts (this IS the whole of scripts.yaml) + its automation
kubectl cp scripts-varmepump-profiler.yaml "home/$POD:/config/scripts.yaml"
kubectl cp automation-varmepump-profil.yaml "home/$POD:/tmp/p.yaml"
kubectl exec -n home "$POD" -- sh -c \
  'grep -q varmepump_profil_applicera /config/automations.yaml \
   || cat /tmp/p.yaml >> /config/automations.yaml'
```

The profile **selector is a UI helper**, so it is not in any YAML file and must be recreated via
the WebSocket API — `input_select/create` with name `Värmepump profil` and options
`Sommar` / `Vinter` / `Semester`. `configuration.yaml` defines no helpers at all in this setup.

Then `script.reload` + `automation.reload`, and pick a profile to push the registers back into the
pump. The scripts are idempotent and write only what differs, so re-running is free.

`template:` is a **new domain** the first time it is added — `homeassistant.reload_all`
will not pick it up, it needs a real restart. Once loaded, `template.reload` is
enough for later edits.

The dashboard itself is Lovelace *storage* mode (`/config/.storage/lovelace.heat_pump`),
so it is not reproducible from YAML here. It was generated by a script; if it is
ever lost, rebuild it rather than hand-editing.

## Write path — verified 2026-08-17

Confirmed end to end, not just by reading the code. Setpoint `d50` driven
21 → 20 → 21 while sniffing the broker:

```
ThermIQ/ThermIQ-room2/write  {"d050": 20}     <- HA published
ThermIQ/ThermIQ-room2/data   d50=20  d3=20    <- pump echoed, recomputed börvärde
ThermIQ/ThermIQ-room2/write  {"d050": 21}     <- restored
ThermIQ/ThermIQ-room2/data   d50=21  d3=21
```

`d3` (`indoor_target_t`) is a *different*, read-only register that the pump
computes itself, and it lagged the restore by ~20 s. That lag is the proof the
round-trip is real rather than an optimistic local update.

To repeat it:

```bash
kubectl exec -n home mosquitto-... -- \
  timeout 120 mosquitto_sub -h 127.0.0.1 -v -t 'ThermIQ/ThermIQ-room2/#'
```

…then nudge `input_number.thermiq_mqtt_vp1_indoor_requested_t` and watch. Move it
**down**, never up: lowering the setpoint cannot start the compressor.

## Δ-T sensors and the flow gate

`templates.yaml` defines two Δ-T sensors, both **deliberately `unavailable` when
their circulation pump is off**:

| Sensor | Formula | Gate | Normal under load |
|---|---|---|---|
| `sensor.varmepump_dt_varmebarare` | `supplyline_t − returnline_t` | `supply_pump_on` | +5…+13 K |
| `sensor.varmepump_dt_koldbarare` | `brine_in_t − brine_out_t` | `brine_pump_on` | +2…+2.5 K |

A Δ-T is undefined without flow. With the pumps idle the sensors drift apart and
produce nonsense — measured 2026-08-17 on a stagnant system: **−3 K** on the
brine circuit and **+28 K** on the heat-carrier circuit. Gating leaves gaps in
the graph, which is the point: an unflowing reading written into long-term
statistics would corrupt min/max/mean permanently, and gaps are honest.

**On the brine direction.** The integration's own calibration registers are
cross-labelled in its source (`brine_in_sensor_offset_t` is described as
"Calibration brine out sensor" and vice versa), which invites the conclusion that
`brine_in`/`brine_out` are swapped. They are **not**. Checked against **all 36
compressor runs** in the recorder database: `brine_in_t` is the warmer side in
**36 of 36** (median +2.50 K, range +1.5…+3.0), i.e. genuinely the fluid arriving
from the borehole. Do not "fix" the sign from an idle reading — with the brine
pump off the two sensors drift apart and can read the other way round.

## Profiles

`input_select.varmepump_profil` → `script.varmepump_profil_{sommar,vinter,semester}`, each a thin
wrapper over `script.varmepump_profil_worker`. Full write-up in [`../THERMIQ.md`](../THERMIQ.md)
§9; the values live in the wrappers.

| Register | Sommar | Vinter | Semester |
|---|---|---|---|
| `hotwater_start_t` | 46 | 46 | 40 |
| `hotwater_stop_t` | 53 | 53 | 52 |
| `heating_stop_t` | **12** | 17 | 12 |
| `legionella_run_on` / `_stop_t` / `_run_length_h` / `_interval_d` | 1 / 65 / 1 / 7 | same | same |

Two traps the worker exists to handle, both found by breaking them:

- ⚠️ **`hotwater_stop_t` has a floor around 49 °C, and a rejected write snaps the register to
  60 °C** rather than leaving it alone. Measured 2026-08-17: 52 accepted, 48 rejected → 60. A
  failed write is therefore *worse* than no write. That is why Semester saves via a lower **start**
  temperature instead, and why every write is verified.
- The hot-water pair must be written in the right order or start momentarily exceeds stop and the
  pump refuses: **stop first when raising the band, start first when lowering.**

Verified end to end on 2026-08-17 — all three profiles applied, every register acknowledged by the
pump, and the verify step caught the rejected 46 °C on its own:

```
Värmepumpsprofil: Semester: pumpen nekade hotwater_stop_t (vill 46.0, reglage 60.0, pump 60.0)
```
