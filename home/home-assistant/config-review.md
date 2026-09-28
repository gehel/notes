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

### 15. IotaWatt's Energy dashboard aggregates reference sensors that don't exist (medium)

Found 2026-09-11 while confirming finding 1's IotaWatt fix (now closed — see `changelog.md`).
The Energy dashboard (`.storage/energy`) references four sensors —
`sensor.total_power_wh`, `sensor.total_buandrie_wh`, `sensor.total_cuisson_wh`,
`sensor.total_reserve_wh` — that don't exist anywhere in the current config: not in any YAML
file, not as a registered helper, nothing. These sum IotaWatt's per-phase circuits and are
configured as calculated **Output** channels on IotaWatt itself (formulas confirmed directly
from the device, e.g. `Total_Cuisson = Cuisson_L1 + Cuisson_L2 + Cuisson_L3`), not raw Inputs.
One real bug found and fixed on the device side while checking: `Total_Buandrie`'s formula
double-counted `Buandrie_L1` and never referenced `L2` — corrected on IotaWatt directly.

**Not yet reconciled:** the `iotawatt` integration's current 29 entities are all raw Inputs,
zero Outputs — but the integration's own documentation
(home-assistant.io/integrations/iotawatt/) indicates Outputs are supported. Need to check
whether they require enabling explicitly (IotaWatt's own web UI, or the integration's options
in HA) before concluding anything needs rebuilding as HA-side template sensors instead.

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

### 7. `dlna_dmr` entry for the Onkyo receiver is dead weight, superseded by the native integration (low)

Originally both the Onkyo receiver and the Samsung TV had a `dlna_dmr` config entry with
`source: "ignore"` (deliberately dismissed at some point) sitting alongside the actual
`onkyo`/`samsungtv` integrations that are in real use. Guillaume un-ignored both 2026-09-08 to
see whether they'd reappear/misbehave now that the network renumber was done.

**Answered by a later sync (2026-09-10), narrowing this finding:** the Samsung TV's `dlna_dmr`
entry is gone entirely — only its `samsungtv` entry remains, so that half is fully resolved on
its own, no action needed. The Onkyo's `dlna_dmr` entry did resettle, though — still present,
`source: ssdp` now (successfully rediscovered, no longer dismissed), sitting alongside the
`onkyo` integration that's actually in use. Not misbehaving, just redundant. Guillaume's call
whether to re-ignore/remove it or leave it — not otherwise urgent.

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

### 14. Six of seven Z-Wave thermostats have duplicate "Battery level" entities (informational, safe cleanup)

Follow-up to the retracted observation in an earlier round — Guillaume noticed the duplicates
directly in the UI (e.g. "Battery level" and "Battery level (2)" on Thermostat Bathroom
Upstairs) and asked where it comes from. Now fully explained by the entities' own unique IDs
(`<home_id>.<node_id>-128-<endpoint>-level` — 128 is the Z-Wave Battery command class): the
Fibaro FGT-001 exposes battery status on **more than one endpoint of the same physical
device**, so Z-Wave JS creates one entity per endpoint for what's the same physical battery.
Confirmed structural to the device model, not a re-pairing artifact and not specific to the
three problem valves — 5 of 7 zones have it (Bathroom Upstairs, Hall Downstairs, Office, Living
Room, Parent's Bedroom), Playroom has *three* copies (endpoints 0, 1, and 2), and only Kitchen
is clean with one.

**Safe to clean up.** `better_thermostat`'s own internal tracking (visible in `scenes.yaml`'s
embedded battery data) already consistently prefers the same endpoint across every zone —
disabling the other one via **Settings → Devices & Services → Entities → (entity) → Disable**
loses nothing:

| Zone | Keep | Disable |
|---|---|---|
| Bathroom Upstairs | `sensor.thermostat_bathroom_upstairs_battery_level_2` | `sensor.thermostat_bathroom_upstairs_battery_level` |
| Hall Downstairs | `sensor.thermostat_hall_downstairs_battery_level_2` | `sensor.thermostat_hall_downstairs_battery_level` |
| Office | `sensor.thermostat_office_battery_level_3` | `sensor.thermostat_office_battery_level` |
| Living Room | `sensor.thermostat_living_room_battery_level_2` | `sensor.thermostat_living_room_battery_level_2_2` |
| Parent's Bedroom | `sensor.thermostat_parent_s_bedroom_battery_level_2` | `sensor.thermostat_parent_s_bedroom_battery_level_2_2` |
| Playroom | `sensor.thermostat_playroom_battery_level_2` | both `..._battery_level` and `..._battery_level_2_2` |

The matching `binary_sensor.*_low_battery_level` duplicates follow the identical endpoint
pattern, same fix if wanted. Purely cosmetic — not chasing this further as its own task unless
asked.

### 16. East irrigation valve (`switch.garden_water_east_switch_2`) unreachable over Zigbee — manual `switch.turn_on` fails with "failed to deliver packet" (medium, needs physical check)

Reported 2026-09-24: the "Irrigation" automation's east-side output
(`switch.garden_water_east_switch_2`, device `a4:c1:38:97:f6:03:d0:d7`) isn't turning the valve
on, and a manual `switch.turn_on` fails in the UI with "failed to deliver packet." Investigated
against a fresh `config/` sync from the same day.

**Confirmed radio-level failure, not an automation logic bug.** `automations.yaml`'s
"Irrigation" automation (`1778147581285`) is wired correctly — `schedule.block_started`/
`timer.started` both fire `switch.turn_on` on `switch.water_west` and
`switch.garden_water_east_switch_2` together, no condition gates it. `home-assistant-current.log`
(2026-09-24 15:45, a live DEBUG capture) shows repeated
`zigpy.exceptions.DeliveryError: Failed to deliver packet: <TXStatus.APS_NO_ACK: 167>` —
the coordinator sends but never gets a link-layer acknowledgment — alongside a large and slowly
growing per-device request backlog ("Device concurrency (1) reached, delaying request (96
enqueued)", delayed ~440-450s and rising), consistent with one device being persistently
unreachable while HA keeps queueing its routine polls. The log snippet available doesn't tag
device identity on the failure lines themselves, but the east valve is by far the most
entity-heavy Zigbee device in this config (~70 entities — schedule/number/select/button per
channel), making it the most likely source of that backlog; not yet 100% confirmed against a
longer log capture.

**The valve's only known Zigbee route is stale.** `zigbee.db`'s neighbor/route tables (last
updated 2026-09-08, 16 days before this report) show the valve as a **child** of `Switch
Buanderie` (`00:17:88:01:0f:03:44:0a`, Philips LOM006 smart plug, laundry room) with LQI 216 —
good at the time — and a second device routing to the valve via that same plug as next hop. The
laundry-room plug itself is clearly still alive and chatty in the live log (`[0x568b] Filtering
duplicate packet` recurs throughout), so the parent hop itself isn't dark; the break looks like
it's specifically between that parent and the valve. Not yet confirmed live, since this session
has no way to trigger a fresh ZHA topology scan or see current LQI.

**A second, independent fault is also visible and may block the valve even once radio comms are
restored:** `binary_sensor.garden_water_east_water_shortage` reads `on` (last set 2026-09-23
23:25:52) — the device's own no-water-flow protection flag. `binary_sensor.garden_water_east_water_leak`
is `off` and `sensor.garden_water_east_battery` was 78% as of the same timestamp, ruling out a
dead battery as of yesterday. The water-shortage flag is a device-reported fault, not something
the "Irrigation" automation checks or clears — worth ruling out as a real supply-side problem
(hose disconnected, inlet valve closed, kinked line) independently of the Zigbee issue.

**Needs physical access to make progress — not resolvable from config/logs alone:**
- Check the valve unit itself: powered/battery seated correctly, nothing moved that would
  increase distance/obstruction from `Switch Buanderie` in the laundry room.
- Check `Switch Buanderie` (the plug) is still plugged in and hasn't been relocated — it's the
  valve's sole known repeater hop.
- Check the actual water supply at the east valve (the water-shortage flag may be entirely
  accurate and unrelated to Zigbee).
- If comms are confirmed restored, HA's live LQI/route data can be spot-checked via
  **Settings → Devices & Services → ZHA → \<device\> → Zigbee device signal** rather than
  relying on the 2026-09-08 `zigbee.db` snapshot used above.

## Not yet reviewed

- `blueprints/` (the IKEA Bilresa scrollwheel blueprint referenced from `automations.yaml` is
  the only one in use, and follows the recommended `!input`-selector pattern correctly) — the
  directory itself not otherwise inventoried.
- Z-Wave JS: one remaining Fibaro FGT-001 thermostatic valve (Parent's Bedroom) is reported
  `unavailable` by `better_thermostat`'s watcher. **Living Room and Bathroom Upstairs are both
  fixed — see `changelog.md`.** Same hardware/controller as the working ones, so not a
  model/firmware issue — dead/empty batteries confirmed as the actual cause for both.
  Presumably the same fix applies here (charge it) — not yet started as of this writing.

  **Current battery level still needs a live check** — not possible from static config, Z-Wave
  JS entities aren't `RestoreEntity`s. Check Developer Tools → States,
  `sensor.thermostat_bathroom_upstairs_battery_level_2` (see finding 14 for why that one, not
  the unsuffixed duplicate) once it reports again.
