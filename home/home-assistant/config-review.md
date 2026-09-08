# Config review — Home Assistant

Round 1: 2026-09-08, against `config/` synced with
[scripts/sync.sh](scripts/sync.sh) (config + `.storage` + a fresh `ha core logs` capture).
First full pass since starting this project — see [README.md](README.md) for why.

**Open findings only.** A finding leaves this document once fixed and verified, moving to
`changelog.md` (not created yet — nothing has been fixed here so far).

## Open findings

### 1. Three integrations still point at pre-VLAN-renumber addresses (high)

The `home/network` VLAN migration renumbered everything from `192.168.1.0/24` to
`192.168.10/20/30.0/24` (see `home/network/vlan.md`). Three HA config entries were never
updated and still hold the dead old addresses:

| Integration | Stored `data.host` | Should be | Evidence |
|---|---|---|---|
| Pi-hole | `192.168.1.40` | `192.168.20.40` | Currently failing outright: `Error setting up entry Pi-Hole for pi_hole` in today's log, both v6 and v5 API attempts |
| IotaWatt | `192.168.1.50` | `192.168.30.50` | `source: user` — a manually-entered host, so it will never self-heal via rediscovery |
| OctoPrint | `192.168.1.81` | `192.168.30.80` or `.81` (check which port it's actually on) | Also has an open **reauth** issue since 2026-06-11, predating the renumber — likely two separate problems on the same entry |

**Why Onkyo and the Samsung TV didn't have this problem, for context:** those integrations are
zeroconf/SSDP-discovered, so they picked up their new `192.168.10.x` addresses automatically
the moment the devices re-announced themselves after the renumber (`modified_at: 2026-09-07`
on both). IotaWatt/Pi-hole/OctoPrint are all manually-configured hosts (`source: user` or a
one-time `zeroconf` claim that doesn't re-trigger), so nothing rediscovers them — they need a
manual fix via **Settings → Devices & Services → (integration) → Reconfigure**.

Fix each one via the UI reconfigure flow, then confirm no more connection errors in the log.

### 2. `configuration.yaml`'s `logger:` block is malformed — debug logging and ZHA's custom quirks path are silently not applied (medium)

```yaml
logger:
default: warning
logs:
  homeassistant.components.zha: debug
  zigpy: debug

  zha:
  database_path: /config/zigbee.db
  enable_quirks: true
  custom_quirks_path: /config/zha_quirks/
```

`default:` and `zha:`/`database_path:`/`enable_quirks:`/`custom_quirks_path:` are indented at
the same level as their intended parent (`logger:` and `logs:` respectively), so YAML parses
them as unrelated top-level/sibling keys, not as children. Concretely:

- `logger:` ends up empty — `default: warning` and the two `debug` overrides never reach the
  `logger` integration at all.
- `zha:`'s legacy YAML block (`database_path`, `enable_quirks`, `custom_quirks_path`) ends up
  nested inside `logs:` instead of being its own top-level key — so it never reaches the `zha`
  integration either.

**Verified, not just inferred from reading the YAML:** today's log has zero `DEBUG`-level
`zigpy`/`zha` lines despite the file explicitly asking for them (the November 2025 log,
`home-assistant.log.old`, *does* have them — this broke sometime between then and this file's
last edit, 2026-08-21). Neither log mentions `custom_quirks_path` or `zha_quirks` at all.

**Likely real-world effect:** `zha_quirks/Hydro DUO ZHA script.py` (a custom quirk for a SONOFF
SWV dual-channel Zigbee water valve — almost certainly the garden irrigation valves referenced
in finding 4) is sitting in the configured quirks folder, but ZHA was never told that folder
exists, so the quirk is likely never loaded and the device falls back to generic Zigbee
exposure.

Fix: re-indent so `logger:` has `default:`/`logs:` as children, and `zha:` is its own top-level
key with `database_path:`/`enable_quirks:`/`custom_quirks_path:` as its children — not nested
under `logs:`. Verify by restarting and checking for `DEBUG` zigpy/zha lines and any zigpy
startup message referencing the custom quirks path.

### 3. Irrigation automation's `numeric_state` trigger is applied to on/off switches (medium)

```
WARNING [homeassistant.components.homeassistant.triggers.numeric_state] Error initializing
'Irrigation' trigger: In 'numeric_state' condition: entity switch.garden_water_east_switch
state 'off' cannot be processed as a number
```

Repeats for `switch.garden_water_east_switch` and `switch.garden_water_east_switch_2` — both
plain on/off switches, not numeric entities. The trigger silently fails to initialize each time
this fires (visible only as a warning, not a hard error), so whatever this automation is
supposed to do based on that condition never runs.

**Possibly connected to finding 2:** if these switches are the SONOFF SWV valve from the
unloaded quirk, the quirk may have been meant to expose a numeric entity (flow, duration) that
the automation was written against — worth re-checking once finding 2 is fixed, since the fix
might make this resolve itself, or reveal a different intended entity.

Per this project's best-practices guidance: a `numeric_state` trigger against a switch is the
wrong tool regardless — if the intent is "did this switch turn on/off", that's a plain `state`
trigger.

### 4. Two `mikrotik` config entries silently lose an entity to a duplicate ID (low)

```
ERROR [homeassistant.components.binary_sensor] Platform mikrotik does not generate unique IDs.
ID 00_00_00_00_00_00_wlan2 already exists - ignoring binary_sensor.wlan2_connectivity
ERROR [homeassistant.components.switch] Platform mikrotik does not generate unique IDs.
ID 00_00_00_00_00_00_wlan2 already exists - ignoring switch.wlan2_wlan
```

mikrotik1 and mikrotik2 (`home/network`) both run a `wlan2` virtual CAPsMAN interface
(`LEDCOM-IoT`) with the same placeholder MAC `00:00:00:00:00:00` — the mikrotik integration
derives its unique ID from the MAC, so the second router's `wlan2` entities collide with the
first's and get dropped. Whichever router's `wlan2` binary_sensor/switch you're not seeing in
HA is the one losing this race. Not fixable from HA's side (it's an upstream integration
limitation — it should be including the router's own identity in the unique ID, not just the
interface MAC); worth a note in `home/network` as a known HA-integration quirk of the two-router
CAPsMAN setup, and possibly a bug report upstream.

### 5. `smart_thermostat` (HACS) is installed but unused and unmaintained (low)

`custom_components/smart_thermostat` (`ScratMan/HASmartThermostat`) has no config entry at all
— it's dead weight, superseded by `better_thermostat`. HACS's own tracked data shows no release
since `2024.12.0` (fetched as recently as 2026-02-16, so this isn't a stale-cache artifact).
Safe to remove via HACS.

### 6. InfluxDB connection timeouts (low, needs a live check)

```
ERROR (influxdb) [homeassistant.components.influxdb] Cannot connect to InfluxDB due to
'{"error":"timeout"}'. ... Resumed, lost 30 events.
```

`configuration.yaml` points it at `localhost:8086` — same host as HA itself (it's an App, not a
separate device), so this isn't a VLAN/routing issue like finding 1. Worth checking whether the
InfluxDB App is actually running and its own resource usage; "lost 30 events" means a gap in
history for that window, not just a log nuisance.

### 7. Two `dlna_dmr` entries are dead weight, superseded by native integrations (low)

Both the Onkyo receiver and the Samsung TV have a `dlna_dmr` config entry with
`source: "ignore"` (deliberately dismissed at some point) sitting alongside the actual
`onkyo`/`samsungtv` integrations that are in real use. Harmless, but safe to delete from
**Settings → Devices & Services → Ignored** if you want the list clean.

### 8. Accumulated un-cleared HACS "restart required" repairs (informational)

`repairs.issue_registry` has HACS "restart required" entries going back to 2025-02-09, one per
component version bump, never dismissed. Each is superseded by a newer one rather than cleared,
suggesting HA hasn't had a clean restart in a while relative to how often HACS updates things.
Not urgent — a routine restart clears the live ones — but worth doing before assuming the
system is in the state the config files describe.

## Not yet reviewed

- `automations.yaml` (16 KB, ~15 automations) — only scanned for a couple of anti-patterns
  while chasing the above. Several use `device_id` triggers; worth a dedicated pass against
  this project's Home Assistant best-practices guidance (entity_id vs device_id, automation
  modes, purpose-specific triggers) rather than folding into this round.
- `scenes.yaml`, `blueprints/`, dashboards (`.storage/lovelace*`) — not looked at yet.
- Z-Wave JS: three Fibaro FGT-001 thermostatic valves (Parent's Bedroom, Bathroom Upstairs,
  Living Room) are reported `unavailable` by `better_thermostat`'s watcher, going back to
  2025-12-22 for the first one. Same hardware/controller as four working ones (Kitchen, Hall
  Downstairs, Office, Playroom), so not a model/firmware issue — likely a Z-Wave mesh/range or
  battery problem needing a live check (Z-Wave JS's own network map, or physically checking
  batteries), not something visible from static config.
