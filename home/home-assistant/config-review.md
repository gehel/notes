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

**2026-09-29 update — auto-close switch exists in the quirk but never got created; frontend
crash blocking "Reconfigure":** the valve was reconnected to external power and Guillaume
confirms it responds correctly now — consistent with the "failed to deliver packet"/backlog
symptoms above being a reachability issue, not a config bug. Separately, the deployed quirk
(`config/zha_quirks/sonoff_swv.py`) already defines a `switch` entity for
`auto_close_water_shortage` (cluster attribute `0x5011`, `off_value=0`/`on_value=30`,
`fallback_name="Water shortage auto-close"`) — the control for finding 16's water-shortage
fault, toggling the valve's own auto-close reaction rather than the shortage detection itself.
It's absent from the last-synced `.storage/core.entity_registry` (2026-09-28 22:56, 74 entities
for this device, none tied to `0x5011`). `home-assistant-current.log` shows why: ten identical
frontend crashes on the ZHA "Reconfigure device" dialog at 18:36:14–19 that evening
(`TypeError: Cannot read properties of undefined (reading 'get')` in
`dialog-zha-reconfigure-device.ts:383`, from a Chrome/Android client) — almost certainly an
attempt to make ZHA pick up the new quirk attribute, which never completed.

**Tried a full HA Core restart (2026-09-29 09:43) — didn't help.** Fresh sync afterwards: still
81 entities on this device, none created today, no errors anywhere near ZHA/quirk setup in the
log (`zhaquirks: Loaded custom quirks` logged cleanly at 09:42:59, and the module's `.pyc` was
freshly compiled from the current source on 2026-09-24). But a naming check shows the live
entities weren't actually rebuilt from the current file: the current source's shortage-bit
`binary_sensor` uses `unique_id_suffix="water_supply_status"` / `translation_key="water_supply"`,
while the entity actually registered (created 2026-09-08) is
`unique_id: ...-water_shortage_status_v2` / `translation_key: water_shortage` — a scheme that
doesn't exist anywhere in the current file. So the quirk module loads without error, but *this
device's* quirked cluster instance isn't being rebuilt against it — a plain Core restart isn't
sufficient here, unlike the usual ZHA custom-quirk iteration workflow.

**Tried `homeassistant.reload_config_entry` on the ZHA entry (2026-09-29 09:53) — also didn't
help, but confirmed the reload mechanism itself works.** Fresh sync afterwards: `zhaquirks:
Loaded custom quirks` logged again cleanly, the same two pre-existing volume-sensor unit
warnings re-fired (proof entity setup actually re-ran for this integration), but still zero new
entities and `core.entity_registry`'s `deleted_entities` list (488 entries) has nothing for this
device's IEEE or unique_id — ruling out HA's "don't recreate a manually-removed entity"
blacklist as the cause.

**Likely root cause found by comparing code patterns, not yet verified against a live
traceback:** the `auto_close_water_shortage` `.switch()` block is the only writable entity
definition in the whole file missing two kwargs that every other one sets —
`attribute_initialized_from_cache=False` and an explicit `unique_id_suffix`. Without the former,
ZHA seeds the entity's initial state from zigpy's attribute cache at setup, which has nothing
for `0x5011` since it's never been read from this device before — a plausible silent-drop cause,
though not confirmed by a captured exception (only INFO/WARNING-level log was available, no
`zhaquirks`/`zha` DEBUG capture). Suggested fix, matching the file's own pattern (e.g.
`valve_work_state`'s binary_sensor block):

```python
.switch(
    SonoffWaterValveCluster.AttributeDefs.auto_close_water_shortage.name,
    SonoffWaterValveCluster.cluster_id,
    off_value=0,
    on_value=30,
    attribute_initialized_from_cache=False,
    unique_id_suffix="auto_close_water_shortage",
    translation_key="water_shortage_auto_close",
    fallback_name="Water shortage auto-close",
)
```

**Applied that edit and restarted (2026-09-29 10:00) — still no switch.** Third clean reload
cycle confirmed (`zhaquirks: Loaded custom quirks` at 09:42:59 → 09:53:02 → 10:00:27, `.pyc`
recompiled fresh each time, same two benign volume-sensor warnings re-firing, zero errors), so
the reload mechanism, the file edit taking effect, and the two added kwargs are all ruled out —
still 81 entities, no `0x5011`/`auto_close`-anything. Whatever's blocking this one entity is
failing below the log level `ha core logs` captures (INFO+); a per-attribute read failure from
zigpy would normally only show at DEBUG.

**Root cause found (2026-09-29, via `homeassistant.components.zha.entity`/`zhaquirks` DEBUG
capture): the quirk was never applied to the east valve at all.** `sonoff_swv.py` registers only
for the exact model string `"SONOFF"`/`"SWV"` (`QuirkBuilder("SONOFF", "SWV")`, line 479 — no
`.also_applies_to()` anywhere in the file). The **west** valve's device record
(`40:38:02:ff:fe:19:71:26`) has `model: "SWV"` — an exact match — and its
`switch.water_west_water_shortage_auto_close` has existed since **2026-05-05**, entirely
unrelated to any of today's work; seeing it fire in the DEBUG log during a reload is what
surfaced this. The **east** valve's device record has `model: "SWV-ZF2"` (the dual-channel
variant — also confirmed via its OTA metadata's sibling-model list
`('SWV-ZF2', 'SWV-ZF2E', 'SWV-ZF2U')`), which this quirk's registration never matches. Every
restart/reload/edit this session tried was reloading a quirk that was never being matched to
this device — hence zero effect each time, with no error anywhere to explain it.

East's other ~81 entities (the CH1/CH2 schedule/Tuya-DP ones, stylistically similar to this
quirk's own) are therefore **not** from this file — almost certainly from the quirk bundled with
zigpy's own `zha-device-handlers` package, which already supports `SWV-ZF2`. The "5.x/6.x/7.x"
DP-numbering convention matching between the two is coincidental — both are transcribing the
same Tuya DP catalog, not sharing code.

**Correction — that `.also_applies_to` fix would have been a regression, not a fix.** Checking
the *other* file already sitting in `config/zha_quirks/`, `"Hydro DUO ZHA script.py"` (2695
lines, initially assumed unrelated), turned out to be what actually governs east:
`QuirkBuilder("SONOFF", "SWV-ZF2E").also_applies_to("SONOFF", "SWV-ZF2")...` — an exact model
match — and its `water_shortage_status_v2`/`water_shortage` binary-sensor definition is
byte-for-byte what's live on `binary_sensor.garden_water_east_water_shortage`. It implements the
full CH1/CH2 schedule/seasonal-adjustment/weekday-switch/child-lock feature set (confirmed:
**west has 26 entities**, exactly matching `sonoff_swv.py`'s ~20-entity chain — no CH2 features,
correctly, since west is single-channel — while **east's 81** come entirely from this second
file). Widening `sonoff_swv.py` to also claim `SWV-ZF2` would have replaced east's 81-entity
quirk with `sonoff_swv.py`'s 26-entity one — losing all CH1/CH2 scheduling, not adding to it.
Caught before applying.

**Conclusive negative result: `0x5011` does not exist on the east valve's firmware, on either
channel.** `Hydro DUO ZHA script.py`'s own `SonoffWaterValveCluster.AttributeDefs` never defined
`0x5011` (confirmed by reading the file) — that's why it doesn't show in the "Manage Zigbee
Device" attribute picker, which only lists attributes the matched quirk declares. Added the bare
attribute definition (no entity) to test live: **read attribute `0x5011` on cluster `0xFC11`,
endpoints 1 and 2 — both explicitly rejected by the device**, confirmed via the raw ZCL response
in a targeted `zigpy.zcl: debug` capture, not just the UI's ambiguous "value=None" summary:
```
ReadAttributesResponse(status_records=[ReadAttributeRecord(attrid=20497, status=<Status.UNSUPPORTED_ATTRIBUTE: 134>, value=None)])
```
`status=UNSUPPORTED_ATTRIBUTE`, on both endpoints — an explicit device-side rejection, not a
timeout or a quirk-code bug. The single-channel SWV's auto-close control at this attribute ID
simply isn't implemented on the dual-channel SWV-ZF2's firmware.

**`0x5011` itself is a dead end — but turned out not to be the whole story.** If SONOFF exposes
single-channel-style auto-close at all for this SKU, it's likely only through the eWeLink app's
Bluetooth connection (the device's OTA release notes mention improved Bluetooth reliability,
implying a BLE config path separate from Zigbee). **Cleanup done:** the exploratory `0x5011`
attribute declaration was removed from `Hydro DUO ZHA script.py` and confirmed synced
(2026-09-29 evening).

**Context that reopened the question:** Guillaume reports the valve actually stops mid-cycle
when this triggers (confirmed real functional impact, not just a dashboard/diagnostic nuisance),
and recalls that before the firmware update to 1.0.9 this either didn't trigger or was
disableable. The underlying cause is a deliberately restrictive flow rate on this zone's drip
system — a real design choice, not a fault — so the goal became finding *any* Zigbee-reachable
control for this on the current firmware, not just re-testing `0x5011`.

**Exhaustive attribute-surface review of `Hydro DUO ZHA script.py`:** every real device
attribute in `SonoffWaterValveCluster.AttributeDefs`, plus every `LocalDataCluster` the quirk
adds (schedule/seasonal-adjustment/rain-delay/manual-irrigation configs) — nothing beyond
`unit_of_water_flow` (L/gal/US-gal) relates to flow at all. `valve_abnormal_state` (`0x500C`) is
the only shortage-related attribute, and it's read-only.

**GitHub/web research (session got `WebFetch`/`WebSearch` access mid-session — both confirmed
working, `gh` CLI is not usable here, permission-denied on its config) turned up the real
picture:** `0x5011` (`lackWaterCloseValveTimeout`, exposed by Zigbee2MQTT as
`auto_close_when_water_shortage`) is specific to the **single-channel SWV** — matches west
exactly, explains why west has had this working since May. The **dual-channel SWV-ZF2 uses an
entirely different, newer attribute scheme**: `enable_alarm_water_leak`,
`enable_alarm_water_shortage`, `alarm_water_leak_duration`, `alarm_water_shortage_duration`
(1–10 min), `enable_water_shortage_auto_close` — packed together into one composite attribute,
**`0x5020` (`valve_alarm_settings`)**, per Zigbee2MQTT's own converter and related GitHub issues
(Koenkk/zigbee-herdsman-converters #12599, #12891, PR #13223 — upstream has been actively
reworking this exact feature; it briefly regressed from individually-writable fields to a
read-only blob and back). Checking `Hydro DUO ZHA script.py`'s attribute list confirmed the gap:
it maps `...0x501E (quarterly_adjustment) → 0x5021 (unit_of_water_flow)`, **skipping `0x5020`
entirely** — a real, evidenced gap, not a guess.

**Live test of `0x5020` (2026-09-29 21:06–21:08): real progress, not another rejection.** Added
a bare declaration (`type=foundation.Array`, matching `quarterly_adjustment`'s existing pattern)
to `Hydro DUO ZHA script.py`, reloaded ZHA, read endpoint 1 via Manage Zigbee Device. Raw ZCL
response captured via `zigpy.zcl: debug`:
```
18 02 01 20 50 00 48 48 04 00 00 00 00 00
```
Decoded: attrid `0x5020` (`20 50` LE) ✓, **status = `00` = SUCCESS** — the attribute is real and
the device answered, unlike `0x5011`. But the UI read errored (`ValueError: Data is too short to
contain 2 bytes`, `zigpy.exceptions.ParsingError`): zigpy's generic ZCL parser read the type
byte (`0x48` = Array, matches), then tried to recurse into the payload as a standard nested
Array (element_type + LE count + elements) and ran out of bytes partway through the 7 remaining
bytes (`48 04 00 00 00 00 00`). This is the same class of problem `sonoff_swv.py`'s
`CyclicIrrigation(t.LVBytes)` class already solves for a different mistagged attribute
(`0x42`/CharacterString there, `0x48`/Array here) — Tuya/eWeLink-family devices commonly tag a
raw packed-byte blob with a ZCL type that doesn't match how they actually encode it. Because
zigpy resolves an attribute's deserialization type from the cluster's own `AttributeDefs` schema
(not blindly from the wire tag) when a matching attrid is declared — confirmed by precedent:
that's exactly how `CyclicIrrigation` already overrides parsing for its own mistagged attribute
in the sibling file — declaring `0x5020` with a custom raw-bytes-capturing type instead of
`foundation.Array` should let us pull the undecoded payload out cleanly.

---
**2026-10-01 correction — the planned Step 1/2 fix was based on a wrong assumption about
zigpy, caught before implementing it.** Re-declaring `valve_alarm_settings` with a custom
Python `type=` (the `CyclicIrrigation` trick) does *not* fix the crash, because
`ReadAttributeRecord.deserialize()` dispatches `array`/`set`/`bag` wire types straight to
`Array.deserialize()` (verified against zigpy's own `zigpy/zcl/foundation.py` on GitHub, since
zigpy isn't installed locally) — it never consults the cluster's declared attribute schema for
incoming reads at all. `CyclicIrrigation` only works because `0x5008`/`0x5009`'s wire tag
genuinely is `CharacterString`, which parses correctly; `0x5020`'s wire tag genuinely is `Array`,
and the bytes after it aren't a well-formed array (confirmed by hand-decoding the captured
`48 04 00 00 00 00 00` against `Array.deserialize`'s real logic: nested element-type byte, 2-byte
count, then not enough bytes left for that many elements — the exact "Data is too short" crash
already seen live). Declaring a different `type=` changes nothing about how the generic parser
handles the wire-level `Array` tag.

**Implemented instead (not yet pushed to the device or tested live):** a `deserialize()` override
on `SonoffWaterValveCluster` in `Hydro DUO ZHA script.py`, which lets the normal parser run first,
and on failure hand-parses the raw frame bytes to pull out `0x5020`'s payload directly — only for
the single-attribute-read case "Manage Zigbee Device" actually exercises (a frame containing just
this one attribute record); anything else falls through to the original error, unchanged. Added
`ValveAlarmSettings(bytes)` to hold the recovered raw bytes, and `valve_alarm_settings` is now
declared as `type=ValveAlarmSettings, zcl_type=foundation.DataTypeId.array` (the explicit
`zcl_type=` is required — without it, `ZCLAttributeDef` tries to reverse-map our custom type to a
wire `DataTypeId` at class-definition time and would fail since `ValveAlarmSettings` isn't a
registered type, same reason `CyclicIrrigation` needs it).

This is unverified against the real device — reasoned from zigpy's source, not from a live test.
**Next session, in order:**

1. Copy the updated `Hydro DUO ZHA script.py` to the HA host's custom quirks directory (this repo
   only pulls `/config` down via `scripts/sync.sh`; pushing the edited file up is a manual step —
   not something to script/automate here per this repo's "don't execute host-touching scripts"
   convention) and restart/reload ZHA.
2. Re-read `0x5020` on endpoint 1 via Manage Zigbee Device, confirm it now returns successfully
   instead of erroring, and inspect the raw bytes — should still be the same `48 04 00 00 00 00
   00` shape unless the device's state changed. If it still errors, capture the new traceback;
   the hand-parse's frame-shape assumptions (single-attribute response) may not hold.
3. Work out the byte layout (5 known fields against 7 bytes of payload — there may be a small
   header, or per-channel duplication given this is dual-channel; channel 2 hasn't been read yet
   either). Zigbee2MQTT's own `sonoff.ts` converter has the authoritative byte-packing logic but
   was too large for a prior session's `WebFetch` to reach in one pass — worth another attempt,
   or reverse-engineering from the raw bytes directly now that there's a real live sample.
4. Once decoded, add proper `.number()`/`.switch()` entities for at least
   `enable_water_shortage_auto_close` (and ideally `alarm_water_shortage_duration`, to raise the
   threshold instead of disabling detection outright, given the drip system's restrictive flow is
   intentional), following the `LocalDataCluster` unpacking pattern already used for
   `single_irrigation_set`/`quarterly_adjustment` in this same file. Writes will need their own
   wire-format investigation (the `deserialize()` override only covers reads) before this entity
   can be made to actually write through to the device.
5. Verify, then close this sub-thread and fold it into finding 16's remaining physical-check
   items (or close finding 16 entirely if the physical supply checks are also done by then).

Also still untried, unrelated to this thread: "Reconfigure device" now that the valve is
reachable on external power (the 2026-09-28 frontend crashes there may have been caused by the
device being unreachable at that moment, not a pure frontend bug).

---
**2026-10-01 — upstream research: no drop-in newer quirk file exists, but confirms the firmware
did change and gives a faster non-Zigbee workaround to try first.** `Hydro DUO ZHA script.py` is
our own hand-built quirk, not a copy of any upstream package, so there's no single "latest
version" to diff against — but `WebSearch`/`WebFetch` turned up three live upstream threads and
one concrete lead:

- [zigpy/zha-device-handlers PR #5110](https://github.com/zigpy/zha-device-handlers/pull/5110)
  (yezi289) adds official `SWV-ZF2E`/variant support, still **open** as of 2026-07-30. Doesn't
  decode `valve_alarm_settings` (0x5020) — passes it as raw bytes, blocked on an upstream
  `ZhaJsonEncoder` bytes-serialization limitation unrelated to our problem.
- [PR #4927](https://github.com/zigpy/zha-device-handlers/pull/4927) (FraserKillip, bench data
  from nglessner) — the single-channel SWV-ZFU/ZFE PR our `manual_default_settings` pattern was
  adapted from. Still **open**, last activity 2026-07-02. Touches `0x5020` but only to expose it
  via switches, not to document its byte layout. Confirms firmware-dependent behavior differences
  between ZFE (fw `0x1004`/`0x1007`) and ZFU (fw `0x1007`, never auto-reports `0x5010`).
- `Koenkk/zigbee-herdsman-converters` (Zigbee2MQTT) is the more actively maintained reference:
  [PR #13223](https://github.com/Koenkk/zigbee-herdsman-converters/pull/13223), **merged
  2026-09-18**, replaced the composite `manual_default_settings` control with scalar controls
  (`irrigation_duration`, `irrigation_mode`, `irrigation_amount`, `irrigation_amount_unit`,
  `fail_safe`) — same composite-to-scalar shape as our own `0x5020` problem, but this specific PR
  doesn't touch `valve_alarm_settings` (checked its diff directly).
- **Firmware confirmed to have moved**: `sonoff.ts` notes dual-channel SWV-ZF2 only gained
  unified imperial-gallon support in firmware **1.0.9**, and
  [issue #12891](https://github.com/Koenkk/zigbee-herdsman-converters/issues/12891) reports
  SWV-ZFE firmware **1.0.8** changed how these alarm settings get exposed via the frontend. This
  lines up with Guillaume's recollection that auto-close behavior changed around the 1.0.9
  update — not misremembered.
- Repeated attempts to pull the actual `0x5020` byte-parsing code out of `sonoff.ts` itself
  failed: the full file is too large for one `WebFetch` pass (returns type definitions, not
  function bodies), GitHub's diff views don't render for `WebFetch` (JS-rendered, comes back as
  "Uh oh! There was an error while loading"), and GitHub code search requires authentication.
  Traced it down to two specific commits that likely contain it (`d757bf2` SWV-ZNE irrigation
  support, `48ddb47` SWV-ZF2 dual-channel support) but couldn't extract their diffs through
  `WebFetch` either. **This avenue is likely exhausted for automated fetching** — next attempt
  should browse these commits manually rather than retry `WebFetch`.
- Checked `dgaust/sonoff-swv-quirk` (community ZHA quirk): single-channel SWV only, doesn't
  handle `SWV-ZF2` or `0x5020`. Not useful here.
- `zigbee2mqtt.io` and `gist.github.com` are blocked by this sandbox's network proxy —
  couldn't fetch the device's Z2M docs page or nglessner's companion gist directly; everything
  above came from GitHub PR/issue pages and `raw.githubusercontent.com` instead.

**New recommended next step, cheaper than finishing the Zigbee decode: try the eWeLink app over
Bluetooth first.** The Hydro DUO is explicitly a dual BLE+Zigbee device (marketed and reviewed as
such), and device-side settings like the water-shortage alarm threshold live on the valve itself,
independent of which radio you use to reach it — so raising `alarm_water_shortage_duration` (or
disabling `enable_water_shortage_auto_close`) from the app, if the UI exposes it, would fix the
actual mid-cycle-stop problem without needing the ZHA quirk to decode or write `0x5020` at all.
Unverified — couldn't confirm the app's exact menu path (the one review covering this was also
blocked by the proxy) — but worth five minutes with the phone before investing more session time
in the byte-layout reverse-engineering below.

### 17. Hourly full-subnet reverse-DNS sweep of `services`, overloading Pi-hole's concurrent-query cap (low, source not yet identified)

Found 2026-10-07 from the `home/network` side: Pi-hole's diagnostics showed a recurring
`DNSMASQ_WARN`, "Maximum number of concurrent DNS queries to 168.192.in-addr.arpa reached (max:
150)". A full day's `pihole.log` (per-query log, pulled via `home/network`'s new
`dump-pihole-logs.sh`) showed Home Assistant (`192.168.20.60`) issuing a complete, sequential
PTR sweep of all 254 addresses on the `services` subnet (`1.20.168.192.in-addr.arpa` through
`254.20.168.192.in-addr.arpa`) once per hour, every hour — 4502 of ~5197 total PTR queries that
day. The warning's timestamp (11:50:26) lines up exactly with that hour's query count spiking to
887 (vs. ~254 every other hour) — the sweep running fast enough to hit the cap. Full evidence in
`home/network/changelog.md`'s "Pi-hole PTR-lookup warning traced to Home Assistant's hourly
full-subnet reverse sweep" entry.

**Not yet found: which HA-side mechanism does this.** Checked the synced `config/` for an
obvious cause — `core.config_entries` (no `nmap_tracker`, no `device_tracker`-style domain),
`configuration.yaml` (just `default_config`, `zha`, frontend/automation includes — no explicit
scan config), `custom_components/` (`better_thermostat`, `linux_monitor`, `smart_thermostat`,
`tuya_local`, `watchman` — none of these obviously do active network scanning). Candidates not
yet ruled in or out: a core component enabled by `default_config` that does more than its
manifest suggests, an add-on/Supervisor-level network health check invisible to this config
sync, or something in `mikrotik`/`iotawatt`/`tasmota`'s own polling that happens to resolve the
whole subnet rather than just its configured host. Not urgent (doesn't break anything, Pi-hole
just logs the warning), but worth a live check — e.g. watch `ha core logs` across the top of an
hour, or check Settings → Devices & Services for anything scan-interval-configured against the
whole subnet rather than a single host.

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
