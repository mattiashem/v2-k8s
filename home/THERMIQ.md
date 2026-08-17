# ThermIQ / Thermia värmepump — registerkarta och styrning

Referens för värmepumpen i huset: vad den skickar, vad varje register betyder, vad som går att
styra och hur. Genererad mot den **installerade** integrationen (`thermiq_mqtt` 3.1.0) och en
**live-avläsning** av pumpen 2026-08-16 — inte avskriven från dokumentation.

> **HA-konfigurationen ligger på en PVC, inte i git.** Den här filen är dokumentation; själva
> integrationen och dashboarden bor i `/config` på `homeassistant`-podden i namespace `home`.

---

## 1. Kedjan

```
Thermia-pump (Rego-buss)
      │
      ▼
ThermIQ-room2-brygga  ──WiFi──►  mosquitto (ns home)      MQTT-användare: thermia
      │                          home/mqqt.yaml:134       (endast lösenordshashen ligger i git)
      ▼
  ThermIQ/ThermIQ-room2/data    ~30 s, JSON, EJ retained
      │
      ▼
Home Assistant  custom_components/thermiq_mqtt  ──►  191 entiteter
```

| | |
|---|---|
| Config entry | `id_name: vp1`, `mqtt_node: ThermIQ/ThermIQ-room2`, `hexformat: false`, `language: en` |
| Entitetsmönster | `<domän>.thermiq_mqtt_vp1_<register-namn>` |
| Läsa | `ThermIQ/ThermIQ-room2/data` |
| Skriva register | `ThermIQ/ThermIQ-room2/write` |
| Namngivna kommandon | `ThermIQ/ThermIQ-room2/set` |
| Klient-id | `ThermIQ_2CBCBB051350` |
| Dashboard | **Värmepump** → `http://ha.v2.local/heat-pump` |

**Entitetsfördelning:** 102 `sensor`, 38 `binary_sensor`, 48 `input_number` (skrivbara),
1 `input_select` (läge), 1 `input_boolean` (EVU), 1 `update`.

---

## 2. `dNNN` ↔ `rXX`

`dNNN` är **decimalformen av det interna hex-registret `rXX`**: `d0`=`r00`, `d50`=`r32`,
`d116`=`r74`. Firmware ≥ 2.22 skickar `d`-notation (opaddad: `"d7":58`), äldre 1.xx skickar hex.
Vår brygga (`ThermIQ-room2 2.68`) kör decimal.

Byt utformat på enheten med `{"REGFMT":1}` (decimal) / `{"REGFMT":0}` (hex) till `/set`.

**Integrationen efterbehandlar två fält:** `r01 = r01 + r02/10` och `r03 = r03 + r04/10`.
Sensorn `indoor_t` innehåller alltså **redan** decimalen — `indoor_dec_t` är råregistret,
lägg inte ihop dem igen.

Nycklar i payloaden som **inte** är register måste vara längre än 4 tecken, annars krockar de
med `dNNN`-mönstret.

---

## 3. Registerkarta

"Värde nu" = avläst 2026-08-16 ~10:30, pumpen i sommardrift (kompressor av).
"HA-domän" visar var registret hamnar som entitet — prefixa med `thermiq_mqtt_vp1_`.

### A. Avläsning (skrivskyddade register)

| d | r | register-namn | Betydelse | Enhet | Min…Max | HA-domän | Värde nu |
|---|---|---|---|---|---|---|---|
| `d0` | `r00` | `outdoor_t` | Utetemperatur | °C |  | sensor | 20 |
| `d1` | `r01` | `indoor_t` | Innetemperatur (heltal + d2/10) | °C |  | sensor | 20.0 |
| `d2` | `r02` | `indoor_dec_t` | Innetemperatur, decimal | 0.1C |  | sensor | 0 |
| `d3` | `r03` | `indoor_target_t` | Innetemp. börvärde (+ d4/10) | °C |  | sensor | 21.0 |
| `d4` | `r04` | `indoor_target_dec_t` | Innetemp. börvärde, decimal | 0.1C |  | sensor | 0 |
| `d5` | `r05` | `supplyline_t` | Framledning | °C |  | sensor | 29 |
| `d6` | `r06` | `returnline_t` | Returledning | °C |  | sensor | 28 |
| `d7` | `r07` | `boiler_t` | Varmvatten | °C |  | sensor | 53 |
| `d8` | `r08` | `brine_out_t` | Köldbärare ut | °C |  | sensor | 22 |
| `d9` | `r09` | `brine_in_t` | Köldbärare in | °C |  | sensor | 25 |
| `d10` | `r0a` | `cooling_t` | Kyla | °C |  | sensor | -40 |
| `d11` | `r0b` | `supply_shunt_t` | Framledning, shunt | °C |  | sensor | 0 |
| `d12` | `r0c` | `current_consumed_a` | Strömförbrukning | A |  | sensor | 0 |
| `d14` | `r0e` | `supplyline_target_t` | Framledning börvärde | °C |  | sensor | 0 |
| `d15` | `r0f` | `supplyline_shunt_target_t` | Framledning börvärde, shunt | °C |  | sensor | 0 |
| `d18` | `r12` | `pwm_out_period` | PWM ut | % |  | sensor | 0 |
| `d21` | `r15` | `demand1` | Behov 1 |  |  | sensor | 1 |
| `d22` | `r16` | `demand2` | Behov 2 |  |  | sensor | 0 |
| `d23` | `r17` | `pressurepipe_t` | Hetgasrör | °C |  | sensor | 27 |
| `d24` | `r18` | `hgw_water_t` | Varmvatten framledning (HGW) | °C |  | sensor | 28 |
| `d25` | `r19` | `integral1` | Integral A1 (gradminuter) | Cmin |  | sensor | 0 |
| `d26` | `r1a` | `integral1_a_step` | Integral, nått A-gräns |  |  | sensor | 0 |
| `d27` | `r1b` | `defrost_time_m` | Avfrostning | *10s |  | sensor | 0 |
| `d28` | `r1c` | `time_to_start_min_m` | Min. tid till start | min |  | sensor | 0 |
| `d29` | `r1d` | `sw_version` | Programversion (pumpen) |  |  | sensor | 140 |
| `d30` | `r1e` | `supply_pump_speed` | Framledningspump varvtal | % |  | sensor | 0 |
| `d31` | `r1f` | `brine_pump_speed` | Köldbärarpump varvtal | % |  | sensor | 0 |
| `d32` | `r20` | `status3_m` | STATUS3 (internt) |  |  | sensor | 0 |

### B. Styrning (skrivbara register)

Varje skrivbart register har **två** entiteter: den skrivbara `input_*` som visas här, och en skrivskyddad `sensor.…`-tvilling med samma namn. Dashboardens *Styrning*-vy använder den första, *Inställningar*-vyn den andra.

| d | r | register-namn | Betydelse | Enhet | Min…Max | HA-domän | Värde nu |
|---|---|---|---|---|---|---|---|
| `d50` | `r32` | `indoor_requested_t` | Önskad innetemperatur | °C | 0…50 | input_number | 21.0 |
| `d51` | `r33` | `main_mode` | Driftläge |  | 0…16 | input_select | 1 - Auto |
| `d52` | `r34` | `integral1_curve_slope` | Värmekurva (lutning) | °C | 0…200 | input_number | 39.0 |
| `d53` | `r35` | `integral1_curve_min` | Kurva min | °C | 0…200 | input_number | 10.0 |
| `d54` | `r36` | `integral1_curve_max` | Kurva max | °C | 0…200 | input_number | 65.0 |
| `d55` | `r37` | `integral1_curve_p5` | Kurva +5 | °C | -5…5 | input_number | 0.0 |
| `d56` | `r38` | `integral1_curve_0` | Kurva 0 | °C | -5…5 | input_number | 0.0 |
| `d57` | `r39` | `integral1_curve_n5` | Kurva −5 | °C | -5…5 | input_number | 0.0 |
| `d58` | `r3a` | `heating_stop_t` | Värmestopp (utetemp.) | °C | 0…200 | input_number | 16.0 |
| `d59` | `r3b` | `reduction_t` | Temperatursänkning (natt) | °C | 0…100 | input_number | 2.0 |
| `d60` | `r3c` | `room_factor` | Rumsfaktor | factor | 0…4 | input_number | 2.0 |
| `d61` | `r3d` | `integral2_curve_slope` | Kurva 2 | °C | 0…200 | input_number | 40.0 |
| `d62` | `r3e` | `integral2_curve_min` | Kurva 2 min | °C | 0…200 | input_number | 10.0 |
| `d63` | `r3f` | `integral2_curve_max` | Kurva 2 max | °C | 0…200 | input_number | 55.0 |
| `d64` | `r40` | `integral2_curve_target` | Kurva 2 börvärde | °C | 0…200 | input_number | 20.0 |
| `d65` | `r41` | `integral2_curve_actual` | Kurva 2 aktuell | °C | 0…200 | input_number | 2.0 |
| `d66` | `r42` | `outdoor_stop_t` | Utetemp. stopp ⚠️ 20 = −20 °C | °C | 0…100 | input_number | 20.0 |
| `d67` | `r43` | `pressure_pipe_limit_t` | Hetgasrör tempgräns | °C | 0…200 | input_number | 135.0 |
| `d68` | `r44` | `hotwater_start_t` | Varmvatten starttemp. | °C | 0…100 | input_number | 48.0 |
| `d69` | `r45` | `hotwater_runtime_m` | Varmvattencykel | min | 0…32767 | input_number | 20.0 |
| `d70` | `r46` | `heatpump_runtime_m` | Värmecykel | min | 0…32767 | input_number | 20.0 |
| `d71` | `r47` | `legionella_interval_d` | Legionella intervall | days | 0…32767 | input_number | 7.0 |
| `d72` | `r48` | `legionella_stop_t` | Legionella stopptemp. | °C | 0…100 | input_number | 60.0 |
| `d73` | `r49` | `integral1_a_limit` | Integralgräns A1 | Cmin | -32768…32767 | input_number | 150.0 |
| `d74` | `r4a` | `integral1_hysteresis_t` | Hysteres A1 | °C | 0…100 | input_number | 8.0 |
| `d75` | `r4b` | `returnline_max_t` | Returledning maxgräns | °C | 0…100 | input_number | 60.0 |
| `d76` | `r4c` | `start_interval_min_m` | Min. startintervall | min | 0…32767 | input_number | 23.0 |
| `d77` | `r4d` | `brine_min_t` | Köldbärare min ⚠️ −15 = av | °C | -25…100 | input_number | -15.0 |
| `d78` | `r4e` | `cooling_target_t` | Kyla börvärde | °C | 0…50 | input_number | 18.0 |
| `d79` | `r4f` | `integral2_a_limit` | Integralgräns A2 | 10 Cmin | 0…200 | input_number | 60.0 |
| `d80` | `r50` | `integral2_hysteresis_t` | Hysteres A2 | °C | 0…100 | input_number | 20.0 |
| `d81` | `r51` | `elect_boiler_steps_max` | Max elsteg | steps | 0…3 | input_number | 2.0 |
| `d82` | `r52` | `current_consumption_max_a` | Max ström | A | 0…100 | input_number | 20.0 |
| `d83` | `r53` | `shunt_time_s` | Shunttid | s | 0…32767 | input_number | 60.0 |
| `d84` | `r54` | `hotwater_stop_t` | Varmvatten stopptemp. | °C | 0…100 | input_number | 60.0 |
| `d87` | `r57` | `language` | Language |  | 0…255 | input_number | 0.0 |
| `d91` | `r5b` | `outdoor_sensor_offset_t` | Calibration outdoor sensor | °C | -5…5 | input_number | 0.0 |
| `d92` | `r5c` | `supplyline_sensor_offset_t` | Calibration supplyline sensor | °C | -5…5 | input_number | 0.0 |
| `d93` | `r5d` | `returnline_sensor_offset_t` | Calibration returnline sensor | °C | -5…5 | input_number | 0.0 |
| `d94` | `r5e` | `boiler_sensor_offset_t` | Calibration hotwater sensor | °C | -5…5 | input_number | 0.0 |
| `d95` | `r5f` | `brine_in_sensor_offset_t` | Calibration brine out sensor | °C | -5…5 | input_number | 0.0 |
| `d96` | `r60` | `brine_out_sensor_offset_t` | Calibration brine in sensor | °C | -5…5 | input_number | 0.0 |
| `d97` | `r61` | `heatingsystem_type` | Värmesystem (0=VL, 4=D) | type | -32768…32767 | input_number | 0.0 |
| `d99` | `r63` | `internal_logging_t` | Loggtid | min | 0…32767 | input_number | 1.0 |
| `d100` | `r64` | `brine_runout_t` | Köldbärare eftergång | *10s | 0…32767 | input_number | 3.0 |
| `d101` | `r65` | `brine_run_in_t` | Köldbärare föregång | *10s | 0…32767 | input_number | 3.0 |
| `d102` | `r66` | `legionella_run_on` | Legionella spetsvärme på |  | 0…1 | input_number | 0.0 |
| `d103` | `r67` | `legionella_run_length_h` | Legionella spetsvärme längd | h | 0…32767 | input_number | 0.0 |

### C. Drifttider och interna register (skrivskyddade)

| d | r | register-namn | Betydelse | Enhet | Min…Max | HA-domän | Värde nu |
|---|---|---|---|---|---|---|---|
| `d85` | `r55` | `manual_test_mode_on` | Manuellt testläge |  |  | sensor | 0 |
| `d86` | `r56` | `status7` | DT_LARMOFF (internt) |  |  | sensor | 0 |
| `d88` | `r58` | `status8` | SERVFAS (internt) |  |  | sensor | 0 |
| `d89` | `r59` | `factory_reset_req` | Fabriksåterställning | setting |  | sensor | 0 |
| `d90` | `r5a` | `runtime_counters_reset_req` | Nollställ drifttidsräknare |  |  | sensor | 0 |
| `d104` | `r68` | `compressor_runtime_h` | Drifttid kompressor | h |  | sensor | 26570 |
| `d105` | `r69` | `msd1_dvp` | DVP_MSD1 |  |  | sensor | 32103 |
| `d106` | `r6a` | `boiler_3kw_runtime_h` | Drifttid 3 kW | h |  | sensor | 125 |
| `d107` | `r6b` | `msd1_dts` | DTS_MSD1 |  |  | sensor | 29440 |
| `d108` | `r6c` | `hotwater_runtime_h` | Drifttid varmvatten | h |  | sensor | 2419 |
| `d109` | `r6d` | `msd1_dvv` | DVV_MSD1 |  |  | sensor | 9 |
| `d110` | `r6e` | `passive_cooling_runtime_h` | Drifttid passiv kyla | h |  | sensor | 0 |
| `d111` | `r6f` | `msd1_dpas` | DPAS_MSD1 |  |  | sensor | 0 |
| `d112` | `r70` | `active_cooling_runtime_h` | Drifttid aktiv kyla | h |  | sensor | 0 |
| `d113` | `r71` | `msd1_dact` | DACT_MSD1 |  |  | sensor | 46848 |
| `d114` | `r72` | `boiler_6kw_on_runtime_h` | Drifttid 6 kW | h |  | sensor | 183 |
| `d115` | `r73` | `msd1_dts2` | DTS2_MSD1 |  |  | sensor | 0 |
| `d116` | `r74` | `graph_display_offset` | GrafCounterOffSet (internt) |  |  | sensor | 0 |

### D. Namngivna nycklar (inte d-register)

| d | r | register-namn | Betydelse | Enhet | Min…Max | HA-domän | Värde nu |
|---|---|---|---|---|---|---|---|
| `—` | `indr_t` | `room_sensor_set_t` | Mata in verklig rumstemp. (skriv-endast, `/set`) | °C | 0…50 | input_number | 20.5 |
| `—` | `time` | `time` | Pumpens klocka | s |  | sensor | 2026-08-16 10:33:38 CEST |
| `—` | `evu` | `heatpump_evu_block` | EVU-blockering (`/set`) |  | 1…1 | input_boolean | off |
| `—` | `mqtt_counter` | `mqtt_counter` | Antal mottagna MQTT-paket |  |  | sensor | 14 |
| `—` | `time_str` | `time_str` | Pumpens klocka (text) |  |  | sensor | 2026-08-16 10:33:38 CEST |
| `—` | `timestamp` | `timestamp` | Tidsstämpel (unix) |  |  | sensor | 1786869218 |
| `—` | `rssi` | `rssi` | WiFi-signalstyrka (bryggan) | dBm |  | sensor | -70 |
| `—` | `app_info` | `app_info` | ThermIQ firmware-version |  |  | sensor | ThermIQ-room2 2.68 |
| `—` | `communication_status` | `communication_status` | Kontakt med pumpens buss (`Ok`) |  |  | sensor | Ok |

### E. Bitfält


**`d13` / `r0d`**

| Bit | Mask | Entity | Betydelse |
|---|---|---|---|
| 0b1 | `0x01` | `boiler_3kw_on` | Elpatron 3 kW till |
| 0b10 | `0x02` | `boiler_6kw_on` | Elpatron 6 kW till |

**`d16` / `r10`**

| Bit | Mask | Entity | Betydelse |
|---|---|---|---|
| 0b1 | `0x01` | `brine_pump_on` | Köldbärarpump går |
| 0b10 | `0x02` | `compressor_on` | Kompressor går |
| 0b100 | `0x04` | `supply_pump_on` | Framledningspump går |
| 0b1000 | `0x08` | `hotwaterproduction_on` | Varmvattenproduktion |
| 0b10000 | `0x10` | `aux2_heating_on` | Tillsatsvärme 2 |
| 0b100000 | `0x20` | `shunt1_n` | Shunt stänger (−) |
| 0b1000000 | `0x40` | `shunt1_p` | Shunt öppnar (+) |
| 0b10000000 | `0x80` | `aux1_heating_on` | Tillsatsvärme 1 |

**`d17` / `r11`**

| Bit | Mask | Entity | Betydelse |
|---|---|---|---|
| 0b1 | `0x01` | `shunt2_n` | Shuntgrupp stänger (−) |
| 0b10 | `0x02` | `shunt2_p` | Shuntgrupp öppnar (+) |
| 0b100 | `0x04` | `shunt_cooling_n` | Kylshunt stänger (−) |
| 0b1000 | `0x08` | `shunt_cooling_p` | Kylshunt öppnar (+) |
| 0b10000 | `0x10` | `active_cooling_on` | Aktiv kyla |
| 0b100000 | `0x20` | `passive_cooling_on` | Passiv kyla |
| 0b1000000 | `0x40` | `alarm_indication_on` | Larmindikering |

**`d19` / `r13`**

| Bit | Mask | Entity | Betydelse |
|---|---|---|---|
| 0b1 | `0x01` | `highpressure_alm` | Larm: högtryckspressostat |
| 0b10 | `0x02` | `lowpressure_alm` | Larm: lågtryckspressostat |
| 0b100 | `0x04` | `motorbreaker_alm` | Larm: motorskydd |
| 0b1000 | `0x08` | `brine_flow_alm` | Larm: lågt flöde köldbärare |
| 0b10000 | `0x10` | `brine_temperature_alm` | Larm: låg temp. köldbärare |

**`d20` / `r14`**

| Bit | Mask | Entity | Betydelse |
|---|---|---|---|
| 0b1 | `0x01` | `outdoor_sensor_alm` | Larm: givare utomhus |
| 0b10 | `0x02` | `supplyline_sensor_alm` | Larm: givare framledning |
| 0b100 | `0x04` | `returnline_sensor_alm` | Larm: givare returledning |
| 0b1000 | `0x08` | `boiler_sensor_alm` | Larm: givare varmvatten |
| 0b10000 | `0x10` | `indoor_sensor_alm` | Larm: givare inomhus |
| 0b100000 | `0x20` | `phase_order_alm` | Larm: felaktig fasföljd |
| 0b1000000 | `0x40` | `overheating_alm` | Larm: överhettning |

**`d98` / `r62`**

| Bit | Mask | Entity | Betydelse |
|---|---|---|---|
| 0b1 | `0x01` | `opt_phasemeassure_installed` | Tillval: fasföljdsmätning |
| 0b10 | `0x02` | `opt_2_installed` | Tillval: TILL2 |
| 0b100 | `0x04` | `opt_hgw_installed` | Tillval: HGW |
| 0b1000 | `0x08` | `opt_4_installed` | Tillval: TILL4 |
| 0b10000 | `0x10` | `opt_5_installed` | Tillval: TILL5 |
| 0b100000 | `0x20` | `opt_6_installed` | Tillval: TILL6 |
| 0b1000000 | `0x40` | `opt_optimum_installed` | Tillval: Optimum |
| 0b10000000 | `0x80` | `opt_flowguard_installed` | Tillval: flödesvakt |

---

## 4. Så styr man pumpen

Tre nivåer. **Använd nivå 1 om du inte har en specifik anledning att låta bli.**

### Nivå 1 — HA-entiteterna (rekommenderat)

Integrationen skapar en skrivbar hjälpentitet per styrregister. Skriv till den, så översätter
integrationen till ett MQTT-kommando åt dig.

```yaml
# Önskad innetemperatur → 21 °C   (d50 / r32)
action: input_number.set_value
target: {entity_id: input_number.thermiq_mqtt_vp1_indoor_requested_t}
data: {value: 21}

# Driftläge → Auto                (d51 / r33)
action: input_select.select_option
target: {entity_id: input_select.thermiq_mqtt_vp1_main_mode}
data: {option: "1 - Auto"}

# EVU-blockering på/av            (namngivet kommando)
action: input_boolean.turn_on
target: {entity_id: input_boolean.thermiq_mqtt_vp1_heatpump_evu_block}
```

Giltiga lägen: `0 - Off`, `1 - Auto`, `2 - Heatpump only`, `3 - Heater only`, `4 - Hot water only`.

### Nivå 2 — rå MQTT-skrivning

Fungerar även om integrationen krånglar. Registret **nollpaddas till tre siffror vid skrivning**
(`d050`), medan pumpen skickar opaddat (`d50`) — båda accepteras.

```yaml
action: mqtt.publish
data:
  topic: ThermIQ/ThermIQ-room2/write
  payload: '{"d050":21}'      # innetemp. börvärde
  qos: 2
  retain: false
```

### Nivå 3 — namngivna kommandon (`/set`, inte `/write`)

```yaml
topic: ThermIQ/ThermIQ-room2/set
payload: '{"EVU":1}'          # 1 = blockera drift, 0 = tillåt
payload: '{"INDR_T":20.3}'    # mata in verklig rumstemperatur (skriv-endast)
payload: '{"REGFMT":1}'       # 1 = decimal dNNN, 0 = hex rXX
```

### Vad som är värt att röra i vardagen

| Vad | Entitet (`input_number.thermiq_mqtt_vp1_…`) | Nu |
|---|---|---|
| Innetemperatur | `indoor_requested_t` | 21 °C |
| Varmvatten start / stopp | `hotwater_start_t` / `hotwater_stop_t` | 48 / 60 °C |
| Värmekurva (lutning) | `integral1_curve_slope` | 39 |
| Parallellförskjutning | `integral1_curve_0` | 0 |
| Värmestopp (utetemp.) | `heating_stop_t` | 16 °C |
| Nattsänkning | `reduction_t` | 2 °C |
| Läge | `input_select.…main_mode` | `1 - Auto` |

**Kurvan i korthet:** *lutningen* bestämmer hur mycket varmare framledningen blir när det blir
kallare ute. *Kurva 0* flyttar hela kurvan parallellt — grovreglaget för innetemperaturen.
*+5 / −5* finjusterar vid +5 °C respektive −5 °C ute. *Värmestopp* är utetemperaturen där
värmen stängs av helt.

**Integral A1 (gradminuter)** är det som faktiskt startar kompressorn: underskott mot börvärdet
integreras över tid, och vid `integral1_a_limit` (150) startar pumpen. Det är därför `integral1`
är det mest informativa värdet när man undrar "varför går den inte igång".

---

## 5. Fallgropar

1. **Skrivtopicen är `/write`, inte `/set`.** `/set` tar bara `INDR_T`, `EVU` och `REGFMT`.
   `{"d050":21}` till `/set` gör ingenting — tyst.
2. **`d66` `outdoor_stop_t` har omvänt tecken** — värdet `20` betyder **−20 °C**.
3. **`d77` `brine_min_t` = `−15` betyder AV**, inte −15 °C.
4. **`indoor_t` innehåller redan decimalen** (integrationen adderar `d2/10`). Addera inte
   `indoor_dec_t` igen.
5. **Integrationen har inga egna services** — `services.yaml` är tom. Allt som refererar
   `thermiq_mqtt.set_*` är fel.
6. **Pumpen vinner alltid.** Inkommande MQTT skriver över UI-värdet inom ~30 s. Hoppar ett fält
   tillbaka har pumpen nekat värdet — det är inte ett HA-fel.
7. **Länken är ryckig.** Bryggan har svag WiFi och kan tappa anslutningen i perioder utan att
   publicera. Vid tappad länk går sensorerna till `unknown` **och `input_select.main_mode` faller
   tillbaka till `0 - Off`** — det betyder *inte* att pumpen är avstängd. Kolla
   `sensor.…communication_status` (`Ok`) och `sensor.…time_str` (pumpens klocka) först.
   RSSI låg på −83…−88 dBm i juni 2026, men mäter **−66…−68 dBm** nu.
8. **`cooling_t` visar `−40 °C`** när kylgivare saknas — normalt, inte ett fel.

---

## 6. ⚠️ Lokal patch av integrationen (2026-08-16)

`thermiq_mqtt` 3.1.0 är **trasig på HA 2025.12.4** och alla 48 `input_number`-entiteterna
gick `unavailable`. Felet finns även i upstream master.

`custom_components/thermiq_mqtt/input_number.py` ärver från `input_number.InputNumber` men
använder **Number-entitetens API**, som basklassen inte har:

| Upstream använder | HA:s `InputNumber` har |
|---|---|
| `self._attr_native_value` | `self._current_value` |
| `self.native_min_value` / `native_max_value` | `self._minimum` / `self._maximum` |
| `async_set_native_value()` | `async_set_value()` |

Två separata fel: (a) `async_added_to_hass` läste `_attr_native_value` som aldrig sätts →
`AttributeError` för alla 48 entiteter vid uppstart; (b) skrivkroken satt på
`async_set_native_value`, en metod HA aldrig anropar → även efter (a) hade en ändring i UI:t
aldrig nått pumpen.

**Åtgärd:** attributnamnen rättade och skrivkroken döpt om till `async_set_value`.
Originalet ligger kvar som `input_number.py.orig-3.1.0` i samma katalog.

```python
async def async_added_to_hass(self):
    await super(InputNumber, self).async_added_to_hass()   # RestoreEntity, ej InputNumbers egen
    if self._current_value is not None:
        return
    ...
    if value is not None and self._minimum <= value <= self._maximum:
        self._current_value = value
    else:
        self._current_value = None        # behåll None i stället för att hitta på _minimum

async def async_set_value(self, value):   # hette async_set_native_value
    await super().async_set_value(value)
    ...oförändrad MQTT-skrivning...
```

`super(InputNumber, self)` hoppar medvetet över `InputNumber.async_added_to_hass`, som annars
klampar ett okänt värde till `_minimum` och därmed skulle hitta på en avläsning (t.ex. 0 °C)
tills första MQTT-paketet kom.

**Ingen ekorisk:** inkommande MQTT sätter `_hpstate[reg]` *före* anropet till
`input_number.set_value`, så vakten `value != self.heatpump._hpstate[self.reg]` gör att en
inkommande uppdatering aldrig skrivs tillbaka till pumpen.

**Omstart av HA krävs** för att ladda om modulen (`POST /api/services/homeassistant/restart` —
använd **inte** `kubectl rollout restart`: `home/ha.yaml` saknar `strategy: Recreate` och
Longhorn-volymen är RWO, så en rullande omstart låser sig på Multi-Attach).

### 6.1 Skrivvägen är verifierad hela vägen (2026-08-17)

Inte bara kodläst — körd. `d50` drevs 21 → 20 → 21 med broker-sniff parallellt:

```
ThermIQ/ThermIQ-room2/write  {"d050": 20}     <- HA publicerade
ThermIQ/ThermIQ-room2/data   d50=20  d3=20    <- pumpen kvitterade, räknade om börvärdet
ThermIQ/ThermIQ-room2/write  {"d050": 21}     <- återställt
ThermIQ/ThermIQ-room2/data   d50=21  d3=21
```

`d3` (`indoor_target_t`) är ett **annat**, skrivskyddat register som pumpen räknar ut själv,
och det släpade ~20 s efter återställningen. Just den fördröjningen är beviset för att det är
en riktig rundtur genom pumpen och inte en optimistisk lokal uppdatering.

Vid upprepning: flytta börvärdet **nedåt**, aldrig uppåt — en sänkning kan inte starta
kompressorn.

### 6.2 ⚠️ HACS-uppdatering återställer patchen — tyst

En HACS-uppdatering skriver över `input_number.py` och tar bort **all** styrning igen.
Avläsningen fortsätter fungera — 102 sensorer, 38 binärsensorer, grafer, historik — så
**ingenting ser trasigt ut**. Bara de 48 reglagen försvinner, och det märks först när man
försöker ändra något.

Två lager fångar det:

1. `sensor.varmepump_styrningar_otillgangliga` räknar thermiq-`input_number` som är
   `unavailable`/`unknown`. Friskt = **0 av 48**. Syns på dashboarden under
   **Diagnostik → System**.
2. `automation.varmepump_styrning_borta` larmar på Telegram efter 15 min över 0, och naggar
   sedan var 12:e timme tills det är åtgärdat.

Ett MQTT-avbrott utlöser **inte** vakten — `input_number` behåller sitt värde när MQTT tystnar.
Ett värde > 0 pekar alltså på patchen, inte på WiFi.

**Åtgärd när det händer:**

```bash
home/thermiq/reapply-patch.sh      # idempotent: backar upp, kopierar, startar om, verifierar
```

Hela återställningssatsen — patchad fil, orörd upstream-fil, diffen, `templates.yaml` och
automationen — ligger i **[`home/thermiq/`](thermiq/README.md)**. HA:s config bor på en PVC
och finns inte i git; den katalogen är kopian som överlever.

---

## 7. Dashboarden

**Värmepump** → `http://ha.v2.local/heat-pump` (storage mode, `id: heat_pump`, endast
inbyggda kort — inga HACS-kort).

| Vy | Innehåll |
|---|---|
| **Status** | Drift just nu, mätare (varmvatten/inne/ute), alla temperaturer (inkl. båda ΔT), effekt & behov, larm, anslutning |
| **Temperaturer** | 6 history-graphs (24 h / 12 h) + 4 statistics-graphs (30 dygn) + förklaring av ΔT-hålen |
| **Styrning** | Läge, innetemp., EVU, varmvatten, värmekurva — **skrivbara** |
| **Inställningar** | Djupare inställningar skrivskyddat + drifttider + installerade tillval |
| **Diagnostik** | Givarkalibrering, shuntutgångar, råa statusregister, MSD-register, **patchvakt** |

**Recorder håller bara 14 dygn lokalt**; 30-dagarsgraferna använder long-term statistics
(98 serier finns). Allt går även vidare till InfluxDB (bucket `homeassistant`, tag
`instance: homeassistant`) för Grafana.

Dashboarden byggs om med `build_heatpump_dash.py` (WebSocket `lovelace/config/save`).
Den validerar varje `entity_id` mot `/api/states` och släpper döda referenser. Ser en sparad
ändring inte ut att slå igenom i webbläsaren: **hård omladdning (Ctrl+Shift+R)**.

---

## 8. Härledda hjälpsensorer (ΔT och patchvakt)

Definieras i `/config/templates.yaml` (inkluderat från `configuration.yaml` som
`template: !include templates.yaml`). Källkopia: [`home/thermiq/templates.yaml`](thermiq/templates.yaml).
Efter ändring: `action: template.reload` — ingen omstart behövs.

| Sensor | Formel | Grind | Normalt under drift |
|---|---|---|---|
| `sensor.varmepump_dt_varmebarare` | `supplyline_t − returnline_t` | `supply_pump_on` | +5…+13 K |
| `sensor.varmepump_dt_koldbarare` | `brine_in_t − brine_out_t` | `brine_pump_on` | +2…+2,5 K |
| `sensor.varmepump_styrningar_otillgangliga` | antal `unavailable` av 48 | — | **0** |

**Varför de är `unavailable` för det mesta.** Ett ΔT är bara definierat när det finns flöde i
kretsen. Med pumparna stillastående driver givarna isär och siffran blir skräp — mätt
2026-08-17 på ett stillastående system: **−3 K** på köldbäraren och **+28 K** på värmebäraren,
båda meningslösa. Därför är sensorerna grindade på respektive cirkulationspump. Det ger hål i
graferna, och det är hela poängen: ett flödeslöst värde som skrivs in i långtidsstatistiken
förstör min/max/medel permanent, och hål är ärligare.

**Tolkning.** Värmebärar-ΔT som närmar sig 0 medan pumpen går = vattnet cirkulerar utan att
avge värme (luft i systemet, stängda ventiler, trasig cirkulationspump). Köldbärar-ΔT som
stiger över säsongen = borrhålet räcker inte till.

> ⚠️ **Om köldbärarens riktning.** Integrationens egna kalibreringsregister är korsmärkta i
> källkoden — `brine_in_sensor_offset_t` beskrivs som *"Calibration brine out sensor"* och
> omvänt — vilket lockar till slutsatsen att `brine_in`/`brine_out` är förväxlade. **De är det
> inte.** Kontrollerat mot tre riktiga kompressorkörningar 2026-08-14 via recorder-historik:
> `brine_in_t` är den varma sidan i alla tre (+2,5 / +2,2 / +2,0 K), alltså verkligen vätskan
> som kommer upp från borrhålet. Ändra inte tecknet utifrån en avläsning när pumpen står still.

---

## 9. Snabbkommandon

```bash
# Lyssna på pumpen live (ej retained — vänta ~30 s)
kubectl exec -n home deploy/mosquitto -- mosquitto_sub -t 'ThermIQ/#' -v -W 60

# Nuvarande värden — fristående, myntar en kortlivad token i podden
kubectl exec -n home deploy/homeassistant -- python3 -c "
import json, jwt, datetime, urllib.request
rt=[t for t in json.load(open('/config/.storage/auth'))['data']['refresh_tokens']
    if t.get('token_type')=='long_lived_access_token'][0]
now=datetime.datetime.now(datetime.timezone.utc)
tok=jwt.encode({'iss':rt['id'],'iat':now,'exp':now+datetime.timedelta(minutes=5)},
               rt['jwt_key'],algorithm='HS256')
r=urllib.request.Request('http://127.0.0.1:8123/api/states',
                         headers={'Authorization':'Bearer '+tok})
s={x['entity_id']:x['state'] for x in json.load(urllib.request.urlopen(r))}
for k in ['outdoor_t','indoor_t','boiler_t','supplyline_t','returnline_t',
          'integral1','current_consumed_a','communication_status','rssi']:
    print(f'{k:22}', s['sensor.thermiq_mqtt_vp1_'+k])"

# Är styrentiteterna friska? (ska vara 0 — annars har HACS ätit patchen)
kubectl exec -n home deploy/homeassistant -- sh -c \
  "grep -c 'Error adding entity input_number.thermiq' /config/home-assistant.log"

# Samma fråga, men via vaktsensorn (överlever logrotation)
#   -> läs sensor.varmepump_styrningar_otillgangliga, ska vara 0 av 48

# Applicera om patchen efter en HACS-uppdatering (idempotent)
home/thermiq/reapply-patch.sh
```

---

## Källor

- Installerad kod: `/config/custom_components/thermiq_mqtt/` (3.1.0) — `heatpump/thermiq_regs.py`
  är den auktoritativa registerkartan, `heatpump/__init__.py` innehåller parsning och skrivning.
- [github.com/ThermIQ/thermiq_mqtt-ha](https://github.com/ThermIQ/thermiq_mqtt-ha)
- Relaterat i repot: **[`home/thermiq/`](thermiq/README.md) (återställningssats — patchad fil,
  diff, `templates.yaml`, automation, `reapply-patch.sh`)**, `home/mqqt.yaml` (broker +
  `thermia`-användaren), `home/ha.yaml` (HA), `home/influxdb.yaml` + `home/grafana.yaml`
  (långtidslagring), `.claude/commands/v2-home.md` (HA-styrning generellt).
