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

### 7. Two `dlna_dmr` entries are dead weight, superseded by native integrations (low) — in progress

Both the Onkyo receiver and the Samsung TV have a `dlna_dmr` config entry with
`source: "ignore"` (deliberately dismissed at some point) sitting alongside the actual
`onkyo`/`samsungtv` integrations that are in real use.

**Guillaume un-ignored both 2026-09-08** to see whether they reappear/misbehave now that the
network renumber is done (they held pre-renumber addresses — see finding 1's neighbour
discussion of why zeroconf-discovered entries self-heal). Watching; check next sync whether
they've settled on current addresses harmlessly or gone back to being worth re-ignoring.

### 9. `mikrotik2`'s RouterBOARD firmware is genuinely behind, and HA likely can't fix it itself (low)

`update.under_the_stairs_mikrotik_2_routerboard` (in `.storage/core.restore_state`) shows
`installed_version: '7.23.3'`, `latest_version: '7.24.2'`, state `on` (update available) — this
is real, not stale integration cache as first assumed. The mix-up: **RouterBOARD firmware
(the bootloader) is a separate thing from the RouterOS package** — mikrotik2's RouterOS is
correctly on 7.24.2 (matches its own `update.*_routeros` entity, and `home/network`'s own
dumps), it's specifically the RouterBOARD/RouterBOOT layer that's still on 7.23.3. All three
routers' `_routeros` update entities correctly show `installed == latest`; only mikrotik2's
`_routerboard` one doesn't — so this isn't a systemic caching problem, just one real update
sitting unapplied.

**On triggering the update from HA:** the entity's `supported_features: 1` does include
`UpdateEntityFeature.INSTALL`, so HA believes it can. But `home/network`'s dumps show the
`homeassistant` API user's group policy on mikrotik2 explicitly includes `!write,!reboot` —
and a RouterBOARD firmware flash necessarily needs both. So even though the UI would show an
"Install" button, invoking it will very likely fail against this account. Confirm by trying it
(low risk — a failed API call, not a bad flash) before assuming it's blocked; if it does fail,
the actual fix is either upgrading mikrotik2's RouterBOARD firmware directly via RouterOS
(`/system/routerboard/upgrade`, out of band from HA), or widening the `homeassistant` group's
policy — the latter trades a large, deliberate part of `home/network`'s security posture for a
convenience feature and is probably not worth it for something this infrequent.

### 10. An App has been removed from its repository (needs the exact name to act on)

Live in Settings → System → Repairs (`hassio: issue_addon_detached_addon_remove`) — an
installed App's source repository is gone, so Supervisor can no longer update or manage it.
Guillaume's recollection: possibly Prometheus or InfluxDB, unconfirmed. **This is also the
best current candidate for the original "app integration no longer available" issue this whole
project started from** — worth checking the exact App name in that repair card's details
before doing anything else with it.

If it turns out to be InfluxDB: that App is still actively configured
(`configuration.yaml`'s `influxdb:` section, `localhost:8086`) and finding 6's connection
timeouts are unexplained so far — a detached/broken InfluxDB App would directly explain both at
once. Worth checking together once the name's confirmed.

## Not yet reviewed

- `automations.yaml` (16 KB, ~15 automations) — only scanned for a couple of anti-patterns
  while chasing the above. Several use `device_id` triggers; worth a dedicated pass against
  this project's Home Assistant best-practices guidance (entity_id vs device_id, automation
  modes, purpose-specific triggers) rather than folding into this round.
- `scenes.yaml`, `blueprints/`, dashboards (`.storage/lovelace*`) — not looked at yet.
- Z-Wave JS: three Fibaro FGT-001 thermostatic valves (Parent's Bedroom, Bathroom Upstairs,
  Living Room) are reported `unavailable` by `better_thermostat`'s watcher, going back to
  2025-12-22 for the first one, and confirmed 2026-09-08 as 2 of the only 3 currently-live
  entries in Settings → Repairs. Same hardware/controller as four working ones (Kitchen, Hall
  Downstairs, Office, Playroom), so not a model/firmware issue.

  **Tried to check battery levels from static config first — not possible.** Z-Wave JS entities
  aren't `RestoreEntity`s, so `.storage/core.restore_state` has no battery data for any of
  them, working or broken. This needs a live check: Developer Tools → States (search
  `battery`) or each valve's device page, comparing the 3 broken ones against a working one
  like Kitchen.

  **One static-config observation, unconfirmed:** the 3 broken valves' battery-related entities
  include oddly-suffixed duplicates (e.g. `sensor.thermostat_parent_s_bedroom_battery_level_2`
  alongside a differently-named one) that the working Kitchen valve doesn't have. Could just be
  Fibaro's proprietary Z-Wave command classes producing two legitimately-different battery
  sensors (harmless), or could indicate these three were re-interviewed/re-included in the
  Z-Wave network at some point, leaving orphaned old entities behind — worth a glance at each
  device's page for duplicate/renamed entities while checking battery levels, not worth
  chasing on its own.
