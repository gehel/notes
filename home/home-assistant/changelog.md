# Changelog — closed findings

Closed and verified findings for Home Assistant. Live review document:
[config-review.md](config-review.md), which holds only what is still open. Nothing is recorded
here on the strength of a change having been made — every entry carries the evidence that
verified it.

## Pi-hole pointed at a pre-VLAN-renumber address (was finding 1, high, closed 2026-09-08)

`config-review.md`'s finding 1: the `pi_hole` config entry still held `192.168.1.40`, a subnet
that no longer exists since `home/network`'s VLAN renumber — failing outright
(`Error setting up entry Pi-Hole for pi_hole`, both v6 and v5 API attempts).

No "Reconfigure" option was available for this integration, so fixed via delete + re-add
(**+ Add Integration**), pointed at **`pihole.home.ledcom.fr`** — a hostname, not the new IP,
per Guillaume's preference (Pi-hole defines its own local DNS records, so this survives any
future re-addressing). Confirmed beforehand this was safe: Pi-hole's entities key off a
generated device ID (`01JHRBV8JAD3R0FANNBCV1ACP3/...`), not the host, so no entity_id changes
were expected or observed.

**Verified:** `.storage/core.config_entries` shows `data.host: "pihole.home.ledcom.fr:80"`,
`modified_at: 2026-09-08T17:03:57`. A fresh `ha core logs` capture spanning 12:00-18:46 that
day — before and after the fix — shows the previous constant stream of `pi_hole`/`hole.v5`
connection errors, then **zero** Pi-hole-related log lines for the 1h40m following the fix.

## `configuration.yaml`'s malformed `logger:`/`zha:` block (was finding 2, medium, closed 2026-09-08)

`config-review.md`'s finding 2: `default:`/`logs:` were indented as siblings of `logger:`
rather than children, and `zha:`'s `database_path`/`enable_quirks`/`custom_quirks_path` ended
up nested inside `logs:` instead of being their own top-level key — so `logger:` was
effectively empty and ZHA never learned about its custom quirks folder.

Took three rounds to actually land, worth recording why:

1. First fix attempt only re-indented the `zha:` block, leaving `logger:` itself still broken
   (`default:`/`logs:` still flush-left) — an easy mistake since the two bugs look identical
   and it's natural to fix the one you're looking at and miss its twin a few lines up.
2. Second attempt fixed the indentation correctly, but no full Core restart had happened yet —
   confirmed via `.ha_run.lock` (`start_ts` unchanged across the edit). `zha:`'s legacy YAML
   settings are read once at integration setup, not on a generic reload, so this silently
   didn't take effect either.
3. Third round: indentation correct, restart confirmed (`.ha_run.lock`'s `pid`/`start_ts` both
   changed), and a log sync landed in the new session's actual output — first two rounds'
   syncs had raced the restart itself and only captured the *old* session's shutdown sequence
   (`s6-rc: ... stopping`), not any fresh post-restart log lines. Lesson for next time: wait a
   beat after a restart before syncing, and check `.ha_run.lock` first if verification looks
   inconclusive.

**Verified:** fresh log has multiple `DEBUG (MainThread) [zigpy.device]`/`[zigpy...]` lines
(zero before). Guillaume reconfigured the SONOFF SWV garden valve afterward and the entity
registry now shows its full quirk-defined entity set — per-channel irrigation schedules,
seasonal adjustment multipliers, rain delay, capacity units, flow rate — rather than a generic
switch; confirmed live by Guillaume ("it now shows the flow rate").

## Irrigation automation's `numeric_state` trigger pointed at switches instead of sensors (was finding 3, medium, closed 2026-09-08)

`config-review.md`'s finding 3: the `high_flow_rate` trigger in the "Irrigation" automation
used `numeric_state` against `switch.garden_water_east_switch`/`_switch_2` (on/off entities),
so it never initialized — logged as a recurring warning, not a hard error, so it went unnoticed
for a while.

Fixed by repointing the trigger at the entities it actually needed:
`sensor.water_west_volume_flow_rate` / `sensor.garden_water_east_volume_flow_rate` (the
existing flow-rate sensors — `above: 300` for 3 minutes, notifying about a possible leak). Not
a generic template/state-trigger rewrite — the automation's own intent was already a numeric
threshold, it was just wired to the wrong entities.

**Verified:** read directly from `automations.yaml` post-fix — trigger now targets the two
`_volume_flow_rate` sensors. No "Irrigation" or `numeric_state`-on-switch warnings anywhere in
the post-restart log (the "Irrigation" warnings visible in the round-2 sync were from the
*old*, pre-restart session still running the previous broken version, consistent with that
sync having raced the restart per finding 2 above).

## `smart_thermostat` (HACS) removed (was finding 5, low, closed 2026-09-08)

`config-review.md`'s finding 5: `custom_components/smart_thermostat`
(`ScratMan/HASmartThermostat`) had no config entry at all, unmaintained since `2024.12.0`, dead
weight superseded by `better_thermostat`. Removed via HACS.

**Verified:** `.storage/hacs.repositories`'s `smart_thermostat` entry no longer has
`installed`/`installed_commit`/`version_installed` — HACS itself no longer considers it
installed. The `custom_components/smart_thermostat` folder is still on disk as of this sync —
expected, HACS can't delete a loaded integration's files from a running instance, so that
finishes on the next restart. Not worth restarting just for this; it'll clear on its own next
time HA restarts for another reason.

## `repairs.issue_registry`'s stale entries sorted out (was finding 8, closed 2026-09-08)

`config-review.md`'s finding 8 started as "HACS restart-required entries never clear, probably
just needs a restart." That theory didn't survive a check against a restart that had actually
happened (finding 2's fix): all 23 stored issues, unchanged, byte-for-byte. Broke the list down
instead of guessing further:

- **13 HACS "restart required" entries** (oldest 2025-02-09) — survived the restart, so
  permanent cosmetic noise, not a live signal. HACS/hassio never seem to purge a
  `repairs.issue_registry` entry once superseded by a newer one; they just stop being shown as
  active. Left alone — no functional impact either way, safe to dismiss for tidiness only.
- **Two `mikrotik` reauth issues** — referenced config entry IDs
  (`01KZRMCPZXVWTAXGX5C7YRTBTG`, `01KZRM9Y1G2SSZ1PQFAT1NYNJG`) that no longer exist; the three
  current `mikrotik` entries were all freshly created 2026-09-08T11:18. Stale, moot.
- **`unhealthy_system_setup`/`unhealthy_system_supervisor` and three opaque-hex `hassio`
  entries** — also stale. **Verified directly** against Settings → System → Repairs (the live
  UI, not the storage file): only 3 issues actually show there — the 2 `better_thermostat`
  missing-entity ones (tracked against the Z-Wave mesh health question in `config-review.md`),
  and one detached-App issue, promoted to its own finding 10.
- The `octoprint` reauth issue is the one real, current entry in the list — already tracked
  under finding 1, not a separate problem.

**General lesson recorded for future rounds:** `repairs.issue_registry`'s storage file is not a
reliable signal for "is this currently active" — it accumulates historical entries that HA
itself has stopped surfacing. The live Settings → System → Repairs page is authoritative;
reading the storage file alone will overstate what's actually open.

## `mikrotik2`'s RouterBOARD firmware upgraded (was finding 9, low, closed 2026-09-08)

`config-review.md`'s finding 9: `update.under_the_stairs_mikrotik_2_routerboard` showed
`installed_version: '7.23.3'` against `latest_version: '7.24.2'` — genuinely behind, not stale
integration cache (mikrotik2's RouterOS package itself was already correctly 7.24.2; RouterBOARD
firmware is a separate layer). Guillaume upgraded it directly via RouterOS, out of band from
HA — consistent with the finding's prediction that the `homeassistant` API user's `!write,!reboot`
policy would likely block triggering it from HA's own "Install" button.

**Verified against `home/network`'s own fresh dump** (`dumps/mikrotik2-switch.txt`,
2026-09-08 21:57:25): `/system/routerboard/print` shows `current-firmware: 7.24.2` matching
`upgrade-firmware: 7.24.2`. **Also confirmed from HA's side** on the next sync:
`update.under_the_stairs_mikrotik_2_routerboard` now shows `installed_version`/`latest_version`
both `7.24.2`, state `off` (no update pending).

## OctoPrint reimaged, reconfigured, and moved to `vlan-iot` (was part of finding 1, high, closed 2026-09-08)

`config-review.md`'s finding 1: OctoPrint's HA integration held the pre-renumber
`192.168.1.81` and had a separate open reauth issue since 2026-06-11. Guillaume lost the
system password, backed up OctoPrint's config via its own Settings → Backup & Restore, and
reimaged the SD card fresh — which resolved both problems at once by necessity, same pattern
as finding 9's prediction: a fresh OS means a fresh OctoPrint install with a new API key, so
the HA integration entry had to be recreated regardless.

New entry points at **`octoprint-wifi.home.ledcom.fr`** (hostname, matching the
`iot-internet` address-list naming already used on mikrotik1 —
`home/network/dumps/mikrotik1-main.txt`), fresh `entry_id`
(`01M21CPY0KC4Z8ZG96KGJ5A6PA`, replacing the old reauth-flagged
`01KBN54W3AQH7RP37SPW9XGM62` — that old reauth issue is now stale/moot, same pattern as the
mikrotik ones in finding 8).

**Verified:** zero `octoprint`-related log lines across 2+ hours since the new entry was
created (20:52 to 22:53), where the old entry had been erroring or flagged for reauth.
`home/network`'s fresh CAPsMAN registration table shows a freshly-connected client on
`LEDCOM-IoT` (uptime ~53 minutes at dump time, matching the reimage timeline) — consistent
with OctoPrint rejoining the correct SSID/VLAN post-reimage. `home/network/vlan.md`'s device
migration table updated to mark OctoPrint fully verified, not just router-side-applied.
