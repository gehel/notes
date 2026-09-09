# Config review — Home Assistant

Round 1: 2026-09-08, against `config/` synced with
[scripts/sync.sh](scripts/sync.sh) (config + `.storage` + a fresh `ha core logs` capture).
First full pass since starting this project — see [README.md](README.md) for why. Extended
2026-09-09 to cover `automations.yaml`, `scenes.yaml`, and dashboards (`.storage/lovelace*`),
the parts of round 1 originally left for later.

**Open findings only.** A finding leaves this document once fixed and verified, moving to
[changelog.md](changelog.md) with the evidence. Numbering is stable and never reused — gaps
(like 2 and 3 below) mean a finding closed, not a mistake.

## Open findings

### 1. One integration still points at a pre-VLAN-renumber address (high)

The `home/network` VLAN migration renumbered everything from `192.168.1.0/24` to
`192.168.10/20/30.0/24` (see `home/network/vlan.md`). Three HA config entries were never
updated and still held the dead old addresses. **Pi-hole and OctoPrint are fixed — see
`changelog.md`.** Convention going forward: **hostname, not IP** (Pi-hole itself defines these
in its local DNS) — `pihole.home.ledcom.fr`, `octoprint-wifi.home.ledcom.fr`.

| Integration | Stored `data.host` | Should be | Evidence |
|---|---|---|---|
| IotaWatt | `192.168.1.50` | `iotawatt.home.ledcom.fr` | `source: user` — a manually-entered host, so it will never self-heal via rediscovery. Device is currently powered off — Guillaume to reconfigure once it's back up |

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

### 11. ZHA `device_id` triggers/actions are fragile against re-pairing (low, no known live impact)

`automations.yaml` review, 2026-09-09. Per this project's best-practices guidance: ZHA has no
event entities, so the recommended pattern for buttons/remotes is an `event` trigger keyed on
`device_ieee` (persistent across re-pairing) — not `device_id` (HA-registry-generated, changes
if the device is ever removed and re-added). Three automations use `device_id` throughout:

- **"Kid's room lights"** — 14 separate `device` triggers across three ZHA remotes (two named,
  "Augustin"/"Oscar", one "main"), covering dim up/down, on/off, toggle, full-on, two wake-up
  variants. Also two `device_id`-targeted light actions (`brightness_increase`/`_decrease`) in
  the response sequence.
- **"Button - All Cold"** / **"Button - All warm"** — one `device` trigger each, same remote
  (`c3121d4cb16bfa5af85a441cbfb73de6`).

None of this is broken today — it only becomes a problem if one of these three remotes is ever
removed and re-added (a battery swap alone doesn't do this; a factory reset or re-pair does).
When that happens, the affected triggers will silently stop firing rather than error, so it's
worth knowing about *before* it's the explanation for "the kids' light remote stopped working."
Not urgent enough to fix pre-emptively; worth converting the next time any of these three
automations is touched for another reason.

**Also noticed, lower priority still:** ten of the climate schedule automations (Bathroom
upstairs, Downstairs, Parents ×3, Playroom, Office — the `schedule.*` warm/cold pairs at the
top of the file) use a plain `state` trigger on the schedule entity (`to: 'on'`/`'off'`)
instead of the newer purpose-specific `schedule.block_started`/`schedule.block_ended` triggers
that the "Irrigation" automation already correctly uses. Still fully supported, not deprecated
— purely a style modernization, not worth a dedicated pass on its own.

### 12. "All cold" scene is broken and inconsistent with its siblings (medium)

`scenes.yaml` review, 2026-09-09 — this scene is wired to a physical remote button
(`automations.yaml`'s "Button - All Cold"), so this is a live behavioral bug, not just file
hygiene.

- **References a nonexistent entity:** `climate.bt_kitchen` — there is no "BT Kitchen"
  `better_thermostat` instance (the five real ones are office/parent's bedroom/playroom/
  bathroom upstairs/downstairs; kitchen only has the raw `climate.thermostat_kitchen`).
  Confirmed missing from `.storage/core.entity_registry`. Activating this scene silently does
  nothing for the kitchen zone.
- **Missing two zones entirely:** covers 5 of the 7 heating zones (Bathroom Upstairs, Kitchen
  (broken, see above), Office, Parent's Bedroom, Playroom) — Hall Downstairs and Living Room
  aren't in it at all, while the sibling "All warm" and "Sleep" scenes (created ~10 minutes
  later per their epoch-based IDs) cover all 7.
- **Goes through `better_thermostat` wrapper entities (`climate.bt_*`) instead of the raw
  Z-Wave ones (`climate.thermostat_*`)** that "All warm"/"Sleep" set directly — inconsistent
  approach between sibling scenes, and the `dashboard_areas` auto-generated dashboard's own
  config suggests the wrapper entities are the intended "real" interface (it hides the raw
  `climate.thermostat_*` entities per-area in favor of them), which would mean "All warm"/
  "Sleep" are the ones going through the "wrong" layer, not "All cold" — worth deciding which
  approach is actually intended and making both scenes consistent.

Simplest fix: recreate "All cold" via **Settings → Automations & Scenes → Scenes → All cold →
capture current states**, choosing the same 7 zones and the same entity type (`bt_*` vs
`thermostat_*`) as "All warm"/"Sleep" for consistency.

## Not yet reviewed

- `blueprints/` (the IKEA Bilresa scrollwheel blueprint referenced from `automations.yaml` is
  the only one in use, and follows the recommended `!input`-selector pattern correctly) — the
  directory itself not otherwise inventoried.
- Z-Wave JS: three Fibaro FGT-001 thermostatic valves (Parent's Bedroom, Bathroom Upstairs,
  Living Room) are reported `unavailable` by `better_thermostat`'s watcher, going back to
  2025-12-22 for the first one, and confirmed 2026-09-08 as 2 of the only 3 currently-live
  entries in Settings → Repairs. Same hardware/controller as four working ones (Kitchen, Hall
  Downstairs, Office, Playroom), so not a model/firmware issue.

  **Current battery levels still need a live check — not possible from static config.** Z-Wave
  JS entities aren't `RestoreEntity`s, so `.storage/core.restore_state` has no battery data for
  any of them. Compounding this, finding 13 means the dashboard's own automatic warning for
  Living Room can't have fired even if its battery is genuinely low. Check Developer Tools →
  States (search `battery_level`) for the 3 broken zones vs. a working one like Kitchen.

  **One historical data point, from `scenes.yaml`'s "All cold" scene** (captured 2025-12-03,
  over 9 months old, not current): Bathroom Upstairs 54%, Parent's Bedroom 83%, Playroom 62% —
  none critically low *at the time*, though a Fibaro valve's motor draws down noticeably faster
  than a passive sensor, so this doesn't rule out low-battery today. The earlier theory that
  these three had suspicious duplicate/renumbered battery entities (`_2`-suffixed) turned out
  to be a false lead — the same scene shows Hall Downstairs and Living Room (one broken, one
  fine) both also using `_2`-suffixed battery entity IDs, and Office uses `_3` while working
  fine — this is just ordinary HA entity-ID collision numbering from setup order, not a signal
  of anything. Retracting that observation.
