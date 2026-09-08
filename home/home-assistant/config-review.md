# Config review — Home Assistant

Round 1: 2026-09-08, against `config/` synced with
[scripts/sync.sh](scripts/sync.sh) (config + `.storage` + a fresh `ha core logs` capture).
First full pass since starting this project — see [README.md](README.md) for why.

**Open findings only.** A finding leaves this document once fixed and verified, moving to
[changelog.md](changelog.md) with the evidence. Numbering is stable and never reused — gaps
(like 2 and 3 below) mean a finding closed, not a mistake.

## Open findings

### 1. Two integrations still point at pre-VLAN-renumber addresses (high)

The `home/network` VLAN migration renumbered everything from `192.168.1.0/24` to
`192.168.10/20/30.0/24` (see `home/network/vlan.md`). Three HA config entries were never
updated and still held the dead old addresses. **Pi-hole is fixed — see `changelog.md`.**
Convention going forward: **hostname, not IP** (Pi-hole itself defines these in its local DNS)
— `pihole.home.ledcom.fr`, `iotawatt.home.ledcom.fr`, and presumably an equivalent for OctoPrint
if one exists.

| Integration | Stored `data.host` | Should be | Evidence |
|---|---|---|---|
| IotaWatt | `192.168.1.50` | `iotawatt.home.ledcom.fr` | `source: user` — a manually-entered host, so it will never self-heal via rediscovery. Device is currently powered off — Guillaume to reconfigure once it's back up |
| OctoPrint | `192.168.1.81` | `octoprint.home.ledcom.fr` if it exists, else the new IP | Also has an open **reauth** issue since 2026-06-11, predating the renumber — likely two separate problems on the same entry |

**Why Onkyo and the Samsung TV didn't have this problem, for context:** those integrations are
zeroconf/SSDP-discovered, so they picked up their new `192.168.10.x` addresses automatically
the moment the devices re-announced themselves after the renumber (`modified_at: 2026-09-07`
on both). IotaWatt/Pi-hole/OctoPrint are all manually-configured hosts (`source: user` or a
one-time `zeroconf` claim that doesn't re-trigger), so nothing rediscovers them.

**Neither Pi-hole nor IotaWatt offered a "Reconfigure" option** in Settings → Devices &
Services — apparently not implemented by these integrations. Fixed instead via delete +
re-add (**+ Add Integration**, same host field, new value). Confirmed safe beforehand: both
integrations key their entities off the device's own identity (Pi-hole: a generated ID;
IotaWatt: the device MAC), not the host, so entity IDs survive a delete + re-add unchanged.

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
