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

"Värde nu" = avläst 2026-08-16 ~10:30, pumpen i sommardrift (kompressor av). Rader märkta
**🅿️** styrs av profilerna (avsnitt 9) och visar värdet i profilen **Sommar**, satt 2026-08-17 —
ändra dem via väljaren, inte för hand, annars skriver nästa profilkörning över.
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
| `d52` | `r34` | `integral1_curve_slope` | Värmekurva (nivå) | °C | 0…200 | input_number | 39.0 |
| `d53` | `r35` | `integral1_curve_min` | Kurva min | °C | 0…200 | input_number | 10.0 |
| `d54` | `r36` | `integral1_curve_max` | Kurva max | °C | 0…200 | input_number | 65.0 |
| `d55` | `r37` | `integral1_curve_p5` | Kurva +5 | °C | -5…5 | input_number | 0.0 |
| `d56` | `r38` | `integral1_curve_0` | Kurva 0 | °C | -5…5 | input_number | 0.0 |
| `d57` | `r39` | `integral1_curve_n5` | Kurva −5 | °C | -5…5 | input_number | 0.0 |
| `d58` | `r3a` | `heating_stop_t` | Värmestopp (utetemp.) 🅿️ | °C | 0…200 | input_number | 12.0 |
| `d59` | `r3b` | `reduction_t` | Temperatursänkning (natt) | °C | 0…100 | input_number | 2.0 |
| `d60` | `r3c` | `room_factor` | Rumsfaktor | factor | 0…4 | input_number | 2.0 |
| `d61` | `r3d` | `integral2_curve_slope` | Kurva 2 | °C | 0…200 | input_number | 40.0 |
| `d62` | `r3e` | `integral2_curve_min` | Kurva 2 min | °C | 0…200 | input_number | 10.0 |
| `d63` | `r3f` | `integral2_curve_max` | Kurva 2 max | °C | 0…200 | input_number | 55.0 |
| `d64` | `r40` | `integral2_curve_target` | Kurva 2 börvärde | °C | 0…200 | input_number | 20.0 |
| `d65` | `r41` | `integral2_curve_actual` | Kurva 2 aktuell | °C | 0…200 | input_number | 2.0 |
| `d66` | `r42` | `outdoor_stop_t` | Utetemp. stopp ⚠️ 20 = −20 °C | °C | 0…100 | input_number | 20.0 |
| `d67` | `r43` | `pressure_pipe_limit_t` | Hetgasrör tempgräns | °C | 0…200 | input_number | 135.0 |
| `d68` | `r44` | `hotwater_start_t` | Varmvatten starttemp. 🅿️ | °C | 0…100 | input_number | 46.0 |
| `d69` | `r45` | `hotwater_runtime_m` | Varmvattencykel | min | 0…32767 | input_number | 20.0 |
| `d70` | `r46` | `heatpump_runtime_m` | Värmecykel | min | 0…32767 | input_number | 20.0 |
| `d71` | `r47` | `legionella_interval_d` | Legionella intervall 🅿️ | days | 0…32767 | input_number | 7.0 |
| `d72` | `r48` | `legionella_stop_t` | Legionella stopptemp. 🅿️ | °C | 0…100 | input_number | 65.0 |
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
| `d84` | `r54` | `hotwater_stop_t` | Varmvatten stopptemp. 🅿️ | °C | 0…100 | input_number | 53.0 |
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
| `d102` | `r66` | `legionella_run_on` | Legionella spetsvärme på 🅿️ |  | 0…1 | input_number | 1.0 |
| `d103` | `r67` | `legionella_run_length_h` | Legionella spetsvärme längd 🅿️ | h | 0…32767 | input_number | 1.0 |

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
| Värmekurva (nivå) | `integral1_curve_slope` | 39 |
| Parallellförskjutning | `input_number.…indoor_requested_t` | 21 °C |
| Värmestopp (utetemp.) | `heating_stop_t` | 16 °C |
| Nattsänkning | `reduction_t` | 2 °C |
| Läge | `input_select.…main_mode` | `1 - Auto` |

**Kurvan i korthet:** `integral1_curve_slope` sätter kurvans *nivå*.
`integral1_curve_p5` / `_0` / `_n5` är **tre likvärdiga finjusteringspunkter** (±5 °C) vid
utetemperatur +5 / 0 / −5 °C — `_0` är alltså **inte** en parallellförskjutning, vilket det här
dokumentet tidigare påstod. Det finns **inget parallellförskjutningsregister**;
**`indoor_requested_t` (d50) är det som flyttar hela kurvan** och därmed grovreglaget för
innetemperaturen. `integral1_curve_min` / `_max` (10 / 65) klampar resultatet.
*Värmestopp* är utetemperaturen där värmen stängs av helt.

Uppmätt samband (nivå 39, börvärde 21, `room_factor` 2) — ca −1,1 K framledning per +1 K ute,
och exakt 0 vid `heating_stop_t`:

| Ute | 9 | 10 | 11 | 12 | 13 | 14 | 15 | 16 |
|---|---|---|---|---|---|---|---|---|
| `supplyline_target_t` | 33 | 32 | 31 | 30 | 28 | 27 | 26 | 25 → **0** |

Integrationen räknar **ingen** kurvmatematik alls — allt utom `r01 += r02/10` och
`r03 += r04/10` sker i pumpens firmware.

**Integral A1 (gradminuter)** är det som startar kompressorn, och registret ⚠️ **räknar nedåt
mot negativa tal**: underskottet integreras och pumpen startar när
`integral1 ≤ −integral1_a_limit` (alltså vid **−150**, inte +150). Vid stopp nollställs
`integral1` och svänger sedan positivt. Kompressorn stoppar när
`supplyline_t ≥ supplyline_target_t + integral1_hysteresis_t` (31 + 8 = 39; uppmätt avstängning
vid 41–45). En automation som testar `integral1 > 150` löser **aldrig** ut.

För att ändra takten: `integral1_a_limit` styr *väntetiden* mellan starter,
`integral1_hysteresis_t` styr *körlängden*. Kortcykling måste åtgärdas genom att höja **båda** —
höjer man bara `a_limit` blir pausen längre men körningarna är fortfarande två minuter.

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
7. ⚠️ **Negativa värden maskas till unsigned 16-bit vid skrivning.** `send_mqtt_reg` gör
   `value = int(value) & 0xFFFF`, så `−1` går ut på tråden som `65535`. Det drabbar **varje**
   signerat register: `integral1_curve_p5/_0/_n5` (±5), alla sex `*_sensor_offset_t` (±5),
   `brine_min_t` (−25…100) och `integral1_a_limit`. Om bryggan tolkar tillbaka till int16 går
   inte att avgöra ur koden — **skriv −1 och se vad pumpen ekar på `/data`** innan du förlitar
   dig på en negativ finjustering. Flyttal trunkeras också (`int(value)`).
8. ⚠️ **`hotwater_stop_t` har ett golv, och ett nekat värde snappar till 60 °C.** Uppmätt
   2026-08-17: **52 accepterades, 48 nekades** (golvet ligger alltså i 49–52). Det viktiga är
   vad som händer vid ett nej: registret står **inte** kvar på sitt förra värde utan hamnar på
   **60**. En misslyckad skrivning är därför sämre än ingen skrivning — den ändrar
   inställningen till standardvärdet. Verifiera alltid efter skrivning, och räkna inte med att
   ett avslag är ofarligt. Samma sak gäller sannolikt andra register med dolda gränser.
9. ⚠️ **Skriv aldrig `main_mode` > 4 via rå MQTT.** `heatpump/__init__.py` slår upp
   `id_names["mode<N>"]` och bara `mode0`–`mode4` finns. Ett högre värde ger `KeyError` inne i
   `message_received`, som bara fångar `ValueError` — hanteraren avbryter före
   `mqtt_counter`-ökningen och uppdateringseventet, så **alla** entiteter slutar uppdateras så
   länge pumpen rapporterar det läget. `input_select` är säkert (skickar `int(option[0])`).
10. ⚠️ **`/api/history/period/<start>` har ett standardfönster på ett dygn.** En naiv
    14-dagarsfråga returnerar tyst bara första dygnet, vilket får resultaten att se
    motsägelsefulla ut. Skicka alltid explicit `end_time` — eller läs
    `/config/home-assistant_v2.db` direkt, vilket är enda vägen för längre analyser
    (`purge_keep_days: 14`).
11. **Länken är ryckig.** Bryggan har svag WiFi och kan tappa anslutningen i perioder utan att
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

## 9. Profiler (Sommar / Vinter / Semester)

`input_select.varmepump_profil` + tre skript i `/config/scripts.yaml`. Källkopia:
[`home/thermiq/scripts-varmepump-profiler.yaml`](thermiq/scripts-varmepump-profiler.yaml) och
[`automation-varmepump-profil.yaml`](thermiq/automation-varmepump-profil.yaml).
Ladda om med `action: script.reload` + `action: automation.reload`.

| Register | Sommar | Vinter | Semester |
|---|---|---|---|
| `hotwater_start_t` | 46 | 46 | 40 |
| `hotwater_stop_t` | 53 | 53 | 52 |
| `heating_stop_t` | **12** | 17 | 12 |
| `legionella_run_on` | 1 | 1 | 1 |
| `legionella_stop_t` | 65 | 65 | 65 |
| `legionella_run_length_h` | 1 | 1 | 1 |
| `legionella_interval_d` | 7 | 7 | 7 |
| `main_mode` | `1 - Auto` | `1 - Auto` | `1 - Auto` |

**En worker + tre tunna wrappers** — `script.varmepump_profil_worker` innehåller all logik,
wrappern är bara värdena. Ny profil = ny wrapper, inte en kopia av logiken.

Fyra saker workern gör som en naiv skrivning inte gör:

1. **Gatar på MQTT-länken.** Vid avbrott tystnar skrivningar helt och `main_mode` läser
   `0 - Off` utan att pumpen är av (fallgrop 11). Utan gate skulle profilen "lyckas" tyst.
2. **Skriver varmvattenparet i rätt ordning.** Höjs bandet skrivs *stopp* först, sänks det
   skrivs *start* först — annars passerar start tillfälligt det gamla stoppet och pumpen nekar.
3. **Väntar 45 s före verifiering.** Pumpen ekar tillbaka och skriver över HA inom ~30 s, så en
   direkt avläsning bevisar ingenting.
4. **Verifierar mot båda hållen** — både `input_number` och pumpens egen `sensor`-tvilling — och
   skickar Telegram som namnger registret, önskat värde och det värde pumpen faktiskt håller.

Bara register som faktiskt skiljer sig skrivs: **alla skrivbara register är persistenta
inställningar i pumpen**, så varje skrivning är en flashcykel. Det är också anledningen att
prisstyrning ska använda `heatpump_evu_block` och inte hamra setpoints (avsnitt 10).

Automationen `automation.varmepump_applicera_vald_profil` kör rätt skript när väljaren ändras,
och återasserterar vid HA-omstart. Uppstartsvägen **väntar först in länken** (alla 102 sensorer
läser `unknown` i ~30 s efter omstart) och kör sedan **tyst** — en lyckad återställning är ingen
nyhet, men avvikelser larmar alltid.

**Verifierat 2026-08-17.** Alla tre profilerna kördes och pumpen kvitterade varje register.
Skrivordningen syntes på tråden: `{"d068": 40}` före `{"d084": 46}` vid sänkning, `{"d084": 53}`
före `{"d068": 46}` vid höjning. Verifieringssteget fångade dessutom ett verkligt fel direkt —
Semester var först satt till stopp 46, pumpen nekade och registret snappade till 60, vilket gav:

```
Värmepumpsprofil: Semester: pumpen nekade hotwater_stop_t (vill 46.0, reglage 60.0, pump 60.0)
```

Det var så golvet i fallgrop 8 hittades, och varför Semester nu sparar via lägre *start*temperatur
(40) i stället för lägre stopptemperatur.

### Varför värmestopp 12 och inte 16

Den viktigaste ändringen, och inte den man förväntar sig. Med `heating_stop_t` = 16 begärde pumpen
rumsvärme **varje augustinatt** (utetemp 9–15 °C), men kompressorn hann nästan aldrig starta:
underskottet är så litet att `integral1` behöver 2–3 timmar för att falla från +30 till −150, vilket
är längre än natten är under 16 °C. Resultatet blev att **cirkulationspumpen gick i timmar utan
värmekälla** — 7,8 h över 13 dygn, i episoder på 168 och 178 minuter, med noll levererad värme.

Uppmätt 17 aug (hela förloppet syns register för register):

```
01:58  ute 13 -> börvärde 28 -> supply_pump ON    integral1 = +29
 ...   integral1 kryper ned ~1-2 Cmin/min
04:38  integral1 = -144        <-- nådde aldrig -150
04:46  ute 16  -> börvärde 0  -> supply_pump OFF
       kompressorn startade aldrig
```

Vid 12 °C startar den begäran inte alls. Kompressorstatistik som jämförelse: 37 starter över
13,2 dygn, varav **32 varmvatten (12,4 h)** och 5 rumsvärme (0,21 h).

---

## 10. Prisstyrning — design, inte byggd

Målet: ladda tanken när elen är billig och låta den svalna när den är dyr. Bygg genom att spegla
`nattladdning`-paret (planerare + exekverare) i `automations.yaml`, som redan är beprövat här.

**Förutsättningen är mätt och den är god:** tanken svalnar bara **−0,74 °C/h**. Från 60 °C ned
till 48 är ~16 h; med sommarprofilens tak på 53 och start 46 är det ~9,5 h. Det är gott och väl
mer än en kvällstopp. ⚠️ Notera kopplingen: **att sänka tanktemperaturen krymper bufferten som
prisstyrningen ska spendera.** Blockeringen måste därför begränsas av **mätt `boiler_t`-fall**,
aldrig av en fast tid, och släppa tidigt om `boiler_t` närmar sig `hotwater_start_t`.

**Priskälla:** kärnintegrationen `nordpool`, config entry `01KRY9DGJ57F9046Q7JBC9Y6CF`, område SE3.
Använd **`nordpool.get_price_indices_for_date` med `resolution: 60`** — `get_prices_for_date` (som
`nattladdning` använder) har inget resolutionsfält och ger 15-minutersslots, 96 per dygn, vilket en
värmepumpsoptimerare inte behöver. ⚠️ **Tjänstesvaret är i råa `SEK/MWh`; bara sensorerna är
delade till `SEK/kWh`.** Båda returnerar `{"SE3":[{start,end,price},…]}`, och ett tomt API-svar är
`{område: []}` — inte ett fel.

**Planerare** (~22:00 + `homeassistant start`): hämta idag+imorgon, glidande fönster med minsta
summa, skriv blocket till `input_datetime.varmepump_billigt_{start,slut}` med `has_date: true` så
att `state_attr(…,'timestamp')` blir absolut epoch. Sentinel `NONE` → logga och stoppa.

**Exekverare** (`mode: restart`): `time`-triggers som pekar på de två `input_datetime`-entiteterna
— de omarmerar sig själva när planeraren skriver om dem, och det är hela kopplingen — plus en
`/15`-`time_pattern` som **rekoncilierar**, så en missad trigger eller en omstart självläker.

**Spakar, i prioritetsordning:**

1. **Dyrt block → `input_boolean.thermiq_mqtt_vp1_heatpump_evu_block` PÅ** (`{"EVU":1}` på `/set`).
   Den enda spaken som är byggd för just det här, och den enda som **inte** är en flashskrivning.
   ⚠️ Om EVU även blockerar elpatronen går inte att avgöra ur koden — verifiera innan du litar på
   den en kall dag.
2. **Billigt block → höj `hotwater_stop_t`** för att förladda tanken, återställ efter. Sparsamt:
   varje ändring är en flashcykel, och ett värde under golvet snappar registret till 60 (fallgrop 8).
3. Bara vinter: **`indoor_requested_t` (d50)** ±1–2 K för att förladda husets massa — det är den
   verkliga parallellförskjutningen, **inte** `integral1_curve_0`.

**Två sovande resurser att utvärdera först:** `aio_energy_management` 1.1.0 ligger installerad i
`/config/custom_components/aio_energy_management/` med en färdig `cheapest_hours`-motor och **noll
config entries** — inläst och oanvänd. Och nordpools `off_peak_1 / peak / off_peak_2`-sensorer finns
redan och används inte av någonting.

---

## 11. Snabbkommandon

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
  diff, `templates.yaml`, profilskript, automationer, `reapply-patch.sh`)**, `home/mqqt.yaml` (broker +
  `thermia`-användaren), `home/ha.yaml` (HA), `home/influxdb.yaml` + `home/grafana.yaml`
  (långtidslagring), `.claude/commands/v2-home.md` (HA-styrning generellt).
