# VLAN segmentation — design and migration plan

Designed 2026-09-06. **Phases 0-5 are done.** Full history,
evidence, and every bug found along the way are in [changelog.md](changelog.md) — this
document holds the design reference and current state, not the story of how it was built.

## Status

Still open:

- **Open, not blocking**: the "second laptop" in the device inventory is still unidentified.

Recently closed: finding 21 (IPv6 on every VLAN, 2026-09-11) and IotaWatt's connectivity
(back online 2026-09-11, router-side config confirmed working, HA integration re-added) — see
`changelog.md`.

**Before writing any new `find`-based command**, skim `README.md`'s hard-won lessons —
several RouterOS `find`/`I - INVALID` reliability quirks are easy to re-hit otherwise.

## Decisions

Recorded so they are not re-litigated. Where a decision went against my recommendation, or
was later reversed, it says so and points to `changelog.md` for the full reasoning.

| Decision | Choice |
|---|---|
| VLANs | three: `users` 10, `services` 20, `iot` 30 |
| Naming | names describe what the devices *are*, not how much they are trusted |
| Media (TV, amp, console) | folded into `users` — casting is not worth breaking |
| Printer | `users`, wired — moved to `services` then **reverted**; mDNS repeater can't reliably support cross-VLAN autodiscovery (RouterOS defect, see `changelog.md`) |
| OctoPrint | `iot`, wireless for now, wired later via a workshop switch |
| IoT internet | denied by default, with a **named exception list** — OctoPrint and IotaWatt (both firmware/software update needs) |
| Wireless | two SSIDs: `LEDCOM` -> vlan 10, `LEDCOM-IoT` -> vlan 30 |
| Addressing | full renumber, `192.168.10/20/30.0/24` — host numbers preserved (`.40` stays `.40`) |
| `users -> services` | full for `mgmt` hosts, named services (DNS, HA web) for everyone else |
| `users -> iot` | full for `mgmt` hosts only |
| `services -> iot` | HA only: ESPHome (6053), Tasmota/IotaWatt web (80), Tuya local (6668) |
| IoT time | NTP server on mikrotik1; DHCP option 42 is unreliable across devices/moves, verify by hand |
| IoT DNS | direct to Pi-hole, to keep per-device attribution — except the ceiling fan (see below) |
| Ceiling fan's standing drop rule | retired — `vlan-iot` isolation now does that job |
| Fonera | removed entirely, `bridge-fon` config deleted |

**Why no separate management VLAN.** The routers hold an address on every VLAN by definition,
so a management VLAN would only decide which address you SSH to. The `mgmt` address list
already restricts management to named hosts, verified with a negative test.

**Why full renumbering, against my original recommendation.** I preferred keeping
`192.168.1.0/24` on `users` so nothing there had to change. Guillaume chose the full renumber
for a cleaner read; it touched the `mgmt` list, HA API rules, port forwards, and every DHCP
reservation, absorbed by making it its own phase (Phase 2) so a failure would be unambiguous.

**Ceiling fan moved out of migration order** (done before OctoPrint/IotaWatt) at Guillaume's
request, to have it working the same evening — overriding the plan's original "do this one
last" caution (see `changelog.md`).

**Ceiling fan DNS exception.** The general `iot -> Pi-hole DNS` rule applies to every
`vlan-iot` device except this one, which gets an explicit `drop` for DNS placed before the
general allow. Steady state: no DNS at all for this device. See `changelog.md` for why (its
own known cloud phone-home behavior needed DNS during initial setup) and the enable/disable
commands.

## Target design

```
vlan 10  vlan-users     192.168.10.0/24   desktop, laptops, phones, TV, amp, console, printer
vlan 20  vlan-services  192.168.20.0/24   Home Assistant, Pi-hole
vlan 30  vlan-iot       192.168.30.0/24   Tasmota x2, ESPHome, Hombli fan, OctoPrint, ...
```

Gateway is `.1` on each. All three VLAN interfaces live on `bridge-main` on mikrotik1;
mikrotik2 and mikrotik3 stay pure L2 and simply carry the tags.

### Policy matrix

| From \ To | internet | users | services | iot | router mgmt |
|---|---|---|---|---|---|
| **users** | allow | — | `mgmt` full; else DNS/HA | `mgmt` full only | `mgmt` list only |
| **services** | allow | drop + log | — | HA: 6053, 80, 6668 | `mgmt` list only |
| **iot** | DROP | drop | Pi-hole 53, HA 1883 | — | NTP 123 to gateway |

The one hole in IoT containment is `iot -> services` on tcp/1883 (the MQTT broker runs on the
HA host); services -> iot is HA reaching device APIs (ESPHome, Tasmota/IotaWatt web, Tuya
local) — narrowly scoped to those ports only.

### The IoT internet exception

"No internet except a named list" rather than a blanket ban, because OctoPrint needs apt/pip/
GitHub to update itself — and it's the device most worth compromising precisely because it's
a full Linux host sitting among microcontrollers. Implemented as a named address-list
(`octoprint`, renamed from `iot-internet` during the Phase 5 reorg) with a narrow forward-chain
accept for tcp/443 ahead of the catch-all drop — see [firewall.md](firewall.md) for the live
rule and address-list membership. `iotawatt` (added 2026-09-11, same shape, firmware updates)
is the second entry.

A domain-level allowlist (TLS SNI matching, `tls-host=` — no proxy, transparent to any
device) was tried and abandoned the same day: found not to work as intended (a wildcard match
broke OctoPrint's access outright rather than adding visibility) and suspected unreliable
against modern TLS 1.3/Encrypted Client Hello regardless of that specific bug — see
`changelog.md`. Both devices are back to unrestricted HTTPS to any destination.

**Keep the list short and review it.** One entry is a decision; six is the policy quietly
abandoned — if it grows, give those devices their own VLAN with internet instead.

## Device inventory and address plan

Host numbers are preserved across the renumber (`.40` stays `.40` on every VLAN).

### users — VLAN 10, 192.168.10.0/24

| Device | Address | Attachment | Notes |
|---|---|---|---|
| desktop "during" | `.10.90` | mikrotik3 `ether3` | |
| laptop "gimli" | `.10.92` | wireless | |
| second laptop | pool | wireless | **still not identified** |
| Galaxy S24 Ultra | pool | wireless, randomised MAC | |
| phone `EA:84:28` | pool | wireless, randomised MAC | |
| TV (Samsung), wired `4C:57:39:2C:20:2C` | `.10.50` | mikrotik5 `ether2`, added 2026-10-08 — link is 100Mbps not Gigabit, accepted, see "Living room and workshop" | |
| TV (Samsung), wifi `F4:DD:06:2A:FB:AF` | `.10.51` | wireless | the MAC this file always called "the TV's" before 2026-10-08 — it's the wifi interface, not wired |
| Nintendo Switch (likely) `BC:CE:25:5E:7F:8A` | pool | wireless | not 100% confirmed |
| Onkyo amp `00:09:B0` | `.10.104`? | wireless | **address stale — no static reservation for this MAC found in a 2026-10-08 lease print; `.10.104` was instead held by the TV's wifi MAC at the time.** Not re-investigated, see `changelog.md`'s "mikrotik5 build" follow-ups |
| Printer `NPI52346B` | `.10.110` | mikrotik3 `ether2` | reverted from `services` |
| mikrotik1 | `.10.1` | gateway on all three VLANs | |
| mikrotik2 | `.10.2` | mikrotik1 `ether2-master` | |
| mikrotik3 | `.10.3` | mikrotik2 `ether16` | |
| mikrotik4 (cAP XL ac) | `.10.4` | mikrotik1 `ether10` (final location) | Standalone `wifi-qcom-ac`, not CAPsMAN — `LEDCOM` only, no `LEDCOM-IoT`; built 2026-10-06/07, see `wifi.md` |
| mikrotik5 (RB750Gr3, living room) | `.10.5` | mikrotik2 `ether12-slave-local` | Built and hardened 2026-10-08; moved to the living room and connected 2026-10-08 — see "Living room and workshop" below |

### services — VLAN 20, 192.168.20.0/24

| Device | Address | Attachment |
|---|---|---|
| Pi-hole | `.20.40` | mikrotik2 `ether23` |
| Home Assistant | `.20.60` | mikrotik2 `ether21` |

### iot — VLAN 30, 192.168.30.0/24

| Device | Address | Attachment | Status |
|---|---|---|---|
| IotaWatt | `.30.50` | wireless | migrated, verified — back online 2026-09-11 after an extended outage |
| Kids light (Tasmota) | `.30.61` | wireless | migrated, verified |
| Hombli ceiling fan | `.30.63` | wireless | migrated, verified |
| OctoPrint | `.30.81` (wifi), `.30.80` (wired) | wireless now; mikrotik2 `ether24` tagged for when the wired cable is fixed | migrated, verified (reimaged after a lost system password, reconfigured onto `LEDCOM-IoT`) |

Kitchen light (Tasmota) is confirmed dead — its reservation was deleted in Phase 2, not
migrated.

### Still to confirm

- **The second laptop.** Never seen in any capture.
- **The Nintendo Switch identity.** Strongly indicated for `BC:CE:25:5E:7F:8A`, not confirmed.

### Static reservations: one caveat

Several clients (Galaxy S24 Ultra, phone `EA:84:28`) use randomised MACs (locally-administered
bit set) — a reservation against one works until the device re-randomises, then silently
stops. Either set the WiFi network to "use device MAC," or accept the pool address; don't
spend effort on reservations that will decay.

## Living room and workshop

The Amp, TV and Nintendo Switch all live on `users`, so the living room doesn't *need* a
VLAN-aware switch — one access port with `pvid=10` would cover it. **2026-10-06: the office PoE
switch purchase is dropped** — a PoE injector covers the SXTsq Lite2 from the office, so
mikrotik3 stays there and does not free up for the living room after all. The living room needed
its own, separate switch purchase; see `config-review.md`'s hardware section for the candidate
(plain hEX, RB750Gr3, matching mikrotik3).

**Received 2026-10-07, built 2026-10-08, moved to the living room and connected 2026-10-08.
Decision: build it VLAN-aware anyway** (trunk carrying 20/30 tagged, same shape as mikrotik3's
`ether1`), even though nothing on it needs tagged traffic today — Guillaume's call, for fleet
consistency and so a future services/iot device on the spare port doesn't need the trunk
re-cabled later. Assigned **mikrotik5**, `192.168.10.5`. Full build account, including two real
RouterOS scripting bugs found and fixed along the way, in `changelog.md`'s "mikrotik5 build"
entry (2026-10-08).

**Config build done and verified on every device involved (mikrotik1-5), 2026-10-08** —
mikrotik5 itself (VLAN bring-up, `pvid=10` confirmed on all five ports, baseline hardening, SSH
key access confirmed working), mikrotik2's trunk port (`ether12-slave-local` tagged for VLAN 20
and 30), and mikrotik1/3/4's own `mgmt`-list entries for mikrotik5. All five one-shot scripts
for this build have been run, verified, and deleted per this repo's scripts/ convention —
`changelog.md`'s "mikrotik5 build" entry is the durable record.

**Physically in place as of 2026-10-08: mikrotik5 is connected to mikrotik2's
`ether12-slave-local` in the living room, and the TV is plugged into `ether2`.** Verified via
`/ip/dhcp-server/lease/print` on mikrotik1 — both of the TV's MACs (wifi and wired) bound fresh
`vlan-users` leases within minutes of the physical move, confirming the new link works. The TV
now has static reservations, `.10.50` (wired, `4C:57:39:2C:20:2C`) and `.10.51` (wifi,
`F4:DD:06:2A:FB:AF`) — see the `users` device table above and `changelog.md` for the
mixed-up-then-corrected MAC assignment (the MAC `vlan.md` had always documented as "the TV's"
turned out to be the wifi interface, not the newly-wired one). Nintendo Switch and amp aren't
plugged in yet.

**The mikrotik2-mikrotik5 trunk's 100Mbps-instead-of-Gigabit cap is root-caused: a bad patch
cable at the living-room end, not the in-wall run or either device's port.** Config was already
correct on both ends, and neither a scripted interface bounce nor a genuine physical
unplug/replug of the original cable fixed it — but swapping in a spare patch cable immediately
negotiated a full Gigabit link (confirmed 2026-10-08). **Still open: a permanent replacement
cable needs to be bought** — the spare isn't meant to stay in place. See `changelog.md`'s
"mikrotik5 build" entry for the full diagnostic trail.

OctoPrint's wired link is down (bad cable); it runs on `LEDCOM-IoT` wireless until fixed. The
workshop switch, when bought, needs to be VLAN-aware unless it ends up carrying only `iot`
devices — decide what else goes there before buying.

## Trunk and access port plan

Current state, all four devices (mikrotik2's `ether12-slave-local` trunk to mikrotik5 went live
2026-10-08, see `changelog.md`).

### mikrotik1 — `bridge-main`

| Port | Role | PVID | Tagged |
|---|---|---|---|
| `ether2-master` | trunk to mikrotik2 | 10 | 20, 30 |
| `ether3`-`ether10`, `sfp1` | unused | 10 | — |
| `ap-MikroTik-1`, `ap-MikroTik-Switch-1` | wireless, CAPsMAN dynamic | — | 10, 30 |
| `bridge-main` itself | carries the VLAN interfaces | — | 10, 20, 30 |

### mikrotik2 — `bridge-local`

| Port | Role | PVID | Tagged |
|---|---|---|---|
| `ether1-gateway` | trunk to mikrotik1 | 10 | 20, 30 |
| `ether16-slave-local` | trunk to mikrotik3 | 10 | 20, 30 |
| `ether12-slave-local` | trunk to mikrotik5 (living room) — **100Mbps on the current cable, bad patch cable, replacement needed** | 10 | 20, 30 |
| `ether21-slave-local` | Home Assistant | 20 | — |
| `ether23-slave-local` | Pi-hole | 20 | — |
| `ether24-slave-local` | OctoPrint wired (cable down) | 30 | — |
| all other ports | unused | 10 | — |

### mikrotik3 — `bridge`

| Port | Role | PVID | Tagged |
|---|---|---|---|
| `ether1` | trunk to mikrotik2 | 10 | 20, 30 |
| `ether2` | printer | 10 | — |
| `ether3` | desktop | 10 | — |
| `ether4`, `ether5` | unused | 10 | — |

### mikrotik5 — `bridge`

Config is live and verified (`pvid=10` confirmed on all five ports via `/interface/bridge/port/
print detail`, 2026-10-08). The device is now physically in the living room, connected to
mikrotik2's `ether12-slave-local` — confirmed working end-to-end (TV DHCP lease verified), but
**currently at 100Mbps due to a bad patch cable, root-caused, replacement needed** (see "Living
room and workshop" above for the diagnostic trail). The TV is plugged into `ether2`; Nintendo
Switch and amp aren't plugged in yet.

| Port | Role | PVID | Tagged |
|---|---|---|---|
| `ether1` | trunk to mikrotik2 `ether12-slave-local` — **100Mbps on the current cable, bad patch cable, replacement needed** | 10 | 20, 30 |
| `ether2` | TV | 10 | — |
| `ether3` | Nintendo Switch (not yet connected) | 10 | — |
| `ether4` | amp (not yet connected) | 10 | — |
| `ether5` | spare | 10 | — |

## Migration reference

What's actually live is documented where it's kept current, not repeated here as a point-in-time
snapshot: the exact commands and evidence for each phase are in `changelog.md`; the live
ruleset, in evaluation order, is in [firewall.md](firewall.md) (regenerated after every
significant firewall change, most recently the Phase 5 reorg — the address-list `iot-internet`
referenced during the original design was renamed `octoprint` there); the addressing and
DHCP/NTP layout is in this document's device inventory and `README.md`'s network summary; and
safe, idempotent scripting practice (including the auto-rollback pattern this migration used by
hand for management-path changes) is now covered by the `mikrotik-routeros-rsc` skill rather than
written out here.

One gotcha worth keeping as prose since it has no other home: a per-device VLAN port move is two
separate commands, not one — bridge-vlan table membership and `pvid` are independent, and
`untagged=` on the bridge-vlan table takes the full replacement port list, not an add/remove
delta. For a long list, read and rebuild it programmatically rather than hand-retyping (see
README.md's hard-won lessons).

**mDNS repeat: deliberately off.** Tried for cross-VLAN discovery, found to have a confirmed
RouterOS defect (drops the reply to a proxied query — see `changelog.md` and README's
hard-won lessons), and explicitly not re-enabled. Any cross-VLAN mDNS consumer needs a static
IP-based address instead of a discovered one.

## Phase 5 — read the evidence, then tighten

**Done.** Findings 19/20 (dead debris) closed 2026-09-09. The rest of Phase 5 turned into a
full forward chain reorganization rather than incremental tightening of the old rule set,
finished 2026-09-10 — see `changelog.md`'s Phase 5 entries for the complete story. Summary of
what the original checklist below turned into:

- ~~Convert genuine `infra2users`/`users2services`/`users2iot`/`iot-drop` log hits into narrow
  rules~~ — superseded: the whole forward chain was reorganized into one jump-chain per VLAN
  pair instead (`users2internet`, `services2internet`, `iot2internet`, `users2services`,
  `users2iot`, `services2users`, `services2iot`, `iot2users`, `iot2services`,
  `internet2services`), each with its own `log=yes` deny-everything-else at the end. Verified
  clean, then log-reviewed before cleanup as this checklist intended — found and fixed
  Pi-hole's DNS-over-TLS, Home Assistant's printer/Samsung-TV access, and missing
  `src-address` scoping on every HA-sourced rule. Two more things the review surfaced, both now
  resolved: the DoT burst from HA itself (not Pi-hole) turned out to be its internal DNS plugin
  leaking private reverse-lookups to Cloudflare — root-caused and closed on the HA side (see
  `home/home-assistant/changelog.md`), accepted as legitimate discovery behavior once the leak
  itself was fixed; and Pi-hole's NTP not honoring the DHCP-supplied option (was finding 23) —
  closed, `chain=input` was missing an NTP accept for `vlan-services`/`vlan-users` entirely
  (only `vlan-iot` ever had one), and Pi-hole itself needed pinning directly at mikrotik1 since
  its OS wasn't propagating the DHCP option to its own NTP client.
- **Remove the temporary `users -> services tcp/1883` rule** — done, folded into
  `scripts/phase5-06-firewall-reorg-cleanup.rsc` along with every other old rule the reorg
  made dead (plus a straggler it missed, `"Accept DNS requests from Pi-hole"`, caught and
  removed in a follow-up polish pass along with four remaining literal `ether1` references).
- **Narrow `services -> internet` from blanket allow to specific ports** — done: HTTP/HTTPS
  plus Pi-hole's own DNS/DoT, everything else denied and logged.
- IotaWatt verified 2026-09-11 — the last device migration is closed out. It got its own
  `iotawatt` address-list (2026-09-11, firmware updates) rather than joining `octoprint`'s —
  see `firewall.md`.
- Confirm `octoprint`'s (and now `iotawatt`'s) address lists still have exactly their intended
  entries — growth is the signal to give those devices their own VLAN instead. Still applies,
  now at two named exceptions instead of one.
- Consider moving VLAN 10 to tagged-only on the trunks. Still open, unrelated to the reorg.

## Open technical question

**RB2011 hardware offload for VLAN filtering** — not checked whether bridge VLAN filtering is
offloaded to the switch chips; if not, forwarding moves to the 600 MHz single core. Watch CPU;
`performance.md` has the throughput baseline. No symptoms of exhaustion observed so far.
