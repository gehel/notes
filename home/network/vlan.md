# VLAN segmentation — design and migration plan

Designed 2026-09-06. Phases 0-2 done — see `changelog.md`'s "VLAN segmentation — Phases 0-2"
entry for the full record of what was done and how it was verified. This document now holds
the design reference plus what's still ahead: Phase 3 onward.

## Status

Last updated 2026-09-07 evening.

**Done and closed to [changelog.md](changelog.md):** Phase 0 (Fonera removal, prep), Phase 1
(VLAN plumbing and wireless tagging on all three devices), Phase 2 (full renumber to
`192.168.10.0/24`), Phase 3 blocks 1-2 (services/iot VLAN interfaces, addressing, DHCP, NTP
option 42; the `LEDCOM-IoT` SSID on both CAPsMAN radios), plus a same-day cleanup pass that
caught everything Phase 2 left behind. IPv6 was also migrated onto `vlan-users` — see
[ipv6.md](ipv6.md) — and a previously-open rogue-RA finding was identified as Home Assistant's
OpenThread Border Router working as designed, not a bug — see
[config-review.md](config-review.md) (held there rather than closed, pending a few more days
of confirmed stability before it moves to the changelog too).

**Resolved 2026-09-07: DNS resolution for `home.ledcom.fr` was bypassing Pi-hole via IPv6
RDNSS.** Discovered while scoping the Home Assistant migration: the desktop's `dig -t A
home.ledcom.fr` returned the *public* record (`188.61.18.91`) rather than Pi-hole's local
override, because the router was advertising the ISP's own DNS server to `vlan-users` clients
over IPv6 RA. Full diagnosis and fix in
[ipv6.md](ipv6.md#resolved-rdnss-was-leaking-the-isps-own-dns-server-bypassing-pi-hole) and
[changelog.md](changelog.md#ipv6-rdnss-was-leaking-the-isps-own-dns-server-bypassing-pi-hole-2026-09-07).
With this fixed, `home.ledcom.fr` resolves correctly via Pi-hole for internal clients, so it's
safe to keep using **the same name for both internal and external access** (Guillaume's
preference) — see the corrected note below.

**Done and closed to [changelog.md](changelog.md):** the printer's revert from `services` back
to `users`, verified 2026-09-08 — discovery and adding it worked cleanly from the household's
non-technical user's own phone and laptop. The printer is no longer part of the Phase 3 device
migration. **Step 2 (Pi-hole) also done and verified 2026-09-08**, including a real firewall
gap found and fixed along the way (`services -> internet: allow` was missing from the live
ruleset and from Phase 4's own script — see that section). **Step 3 (Home Assistant) done and
verified 2026-09-08** — local and remote HTTPS access, and the MikroTik integration reaching
all three routers. The integration took real work to get right: two mistakes made and fixed
along the way (an idempotency guard that skipped creating a needed address-list, and a rule
added without `place-before=` that landed dead after the catch-all drop — a repeat of a mistake
already documented for the `services: internet` rule), plus the actual root cause, which was
neither of those — mikrotik2 and mikrotik3 had no default route at all, so they could accept
HA's connection but never reply. Full account, including why the failure produced no log
entries at all, in `changelog.md`. **Step 7 (Ceiling fan) also done and verified 2026-09-08**,
moved out of order (see Decisions above) and confirmed working in HA via `tuya-local` after a
live-discovered policy gap (`services -> iot` tcp/6668) was closed. Also where the `I -
INVALID` finding grew a lot more nuanced — see `README.md`'s hard-won lessons. **Step 6 (Kids
light) also done and verified 2026-09-08** — connected to HA over the (newly-applied,
permanent) `iot: MQTT to HA` rule, and confirmed the DHCP-option-42 assumption below. **Steps 4
and 5 (OctoPrint, IotaWatt) are what's left.**

**One open item, not a blocker:** the "second laptop" from the device inventory below is still
unidentified. Also corrected in this document,
discovered while debugging a WiFi problem during Phase 1/2: the original inventory's guess that
`BC:CE:25:5E:7F:8A` was the TV was wrong — the real TV is `F4:DD:06:2A:FB:AF` (see the
inventory below for detail).

**Before starting Phase 3, read this — the single biggest lesson from Phases 1-2:** any config
that references a device by literal IP address, rather than an interface, address-list, or DNS
name, has to be found and updated by hand, and the true list of such references is longer than
it looks from reading the obvious spots (a DHCP reservation and a NAT rule). Hit repeatedly and
expensively in Phase 2 — user-account `address=` restrictions (separate from any firewall rule
entirely), a NAT rule's *paired* forward-chain accept rule (updating the NAT rule alone wasn't
enough), other forward-chain rules matching a device by address (one of which was a *security*
rule that went silently unenforced once its target renumbered), and CAPsMAN's own discovery
config in three separate places. Full account in `changelog.md`. **Before moving Pi-hole or
Home Assistant in Phase 3, `grep` a fresh `dump-configs.sh` export for their current IP
literally, across every device** — don't rely on memory for the reference list.

Also worth a skim before writing any new `find`-based command: `README.md`'s "Hard-won lessons"
has a running list of RouterOS `find`/`print where` reliability quirks hit across this whole
project — several specific menus and property combinations silently match nothing rather than
erroring, with no error to catch it.

## Decisions

Recorded so they are not re-litigated. Where a decision went against my recommendation it
says so.

| Decision | Choice |
|---|---|
| VLANs | three: `users` 10, `services` 20, `iot` 30 |
| Naming | names describe what the devices *are*, not how much they are trusted |
| Media (TV, amp, console) | folded into `users` — casting is not worth breaking |
| Printer | `users`, wired — **reverted from `services` 2026-09-08**, see below |
| OctoPrint | `iot`, **wireless for now**, wired later via a workshop switch |
| IoT internet | denied by default, with a **named exception list** — currently OctoPrint only |
| Wireless | two SSIDs: `LEDCOM` -> vlan 10, `LEDCOM-IoT` -> vlan 30 |
| Addressing | full renumber, `192.168.10/20/30.0/24` |
| `infra -> users` | denied by default, with a log rule to find real exceptions |
| `users -> services` | full for `mgmt` hosts, named services for everyone else |
| `users -> iot` | full for `mgmt` hosts only |
| IoT time | NTP server on mikrotik1, advertised by DHCP option 42 |
| IoT DNS | direct to Pi-hole, to keep per-device attribution — **except the ceiling fan**, see below |
| Ceiling fan's standing drop rule | **retired 2026-09-08**, superseded by `vlan-iot` isolation — see below |
| Fonera | **removed entirely**, `bridge-fon` config deleted |
| Rollback | scheduled auto-revert before every risky change |

**Why no separate management VLAN.** The routers hold an address on every VLAN by
definition, so a management VLAN would only decide which address you SSH to. The `mgmt`
address list already restricts management to named hosts and has been verified with a
negative test. Adding a fourth VLAN to re-state that is complexity without a gain.

**Where I was overruled, and what it costs.** I recommended keeping `192.168.1.0/24` on the
users VLAN so that nothing on the users side had to change. Full renumbering is tidier to
read but touches the `mgmt` list, the HA API rules on four devices, the HTTPS port forward,
every DHCP reservation and your own muscle memory. The plan below absorbs this by making the
renumber **its own phase**, separate from the VLAN plumbing, so a failure is unambiguously
one or the other.

**Printer reverted to `users`, 2026-09-08 — autodiscovery over segmentation purity.** Moved to
`services` as step 1 of the migration, then moved back the same day. Cause: a confirmed
RouterOS defect in `mdns-repeat-ifaces` (proxies a client's mDNS query onto the far VLAN under
its own address, gets an answer, drops the reply instead of relaying it back — see the Phase 4
mDNS section and `changelog.md` for the full packet-capture evidence, independently
corroborated on [MikroTik's forum](https://forum.mikrotik.com/t/mdns-repeater-forwarding-queries-but-not-all-responses-across-vlans/269317))
means autodiscovery cannot work reliably for a printer on a different VLAN than its clients.
Guillaume's household includes a non-technical user who needs to add this printer on her own
phone and laptop without manual IP configuration — that requirement outweighs keeping this one
device segmented. The printer is wired, low-risk, and was the least security-sensitive device
in `services` anyway; reverting it costs nothing else in the design.

**Ceiling fan moved out of order, 2026-09-08 — wanted it working that same night.** `vlan.md`
had said to do this device last, since it already carried a standing security restriction and
was judged the worst one to debug first if the IoT VLAN plumbing itself had an untested issue.
Guillaume moved it first anyway, explicitly overriding that caution, to have it working that
evening. Also decided at the same time: the standing `chain=forward action=drop
src-address=192.168.10.63` rule (a "deliberately distrusted device" restriction from an earlier
config-review round — see `changelog.md`) is **retired, not carried forward to the new
address**. `vlan-iot` provides the same isolation by construction (no general allow exists for
it yet, so anything not explicitly permitted already falls to the catch-all drop) — a
per-device rule restating that is redundant now that segmentation does the job network-wide,
where before this specific rule was the *only* thing containing this specific device.

**IoT DNS, ceiling-fan exception.** The general `iot -> Pi-hole DNS` allow (pulled forward from
Phase 4, same reasoning as `services: internet` for Pi-hole) applies to every `vlan-iot`
device — except this one, which gets an explicit `drop` for DNS specifically, placed *before*
the general allow so it takes precedence. Steady state: this device gets no DNS at all, even
though its VLAN-mates do. **Not enabled immediately** — the fan's own known phone-home
behavior to a vendor cloud service (see `changelog.md`'s original review) means tonight's
reconfiguration likely needs DNS to complete, so the drop rules are created `disabled=yes` and
a temporary internet-access toggle (`ceiling fan: TEMP internet for setup`, `tcp dst-port=
80,443`, `out-interface=ether1`) is enabled instead. Once HA confirms the fan is working:
disable the internet toggle, enable both DNS-drop rules — commands are in
`scripts/phase3-10-ceilingfan-mikrotik1.rsc`'s own comments.

## Target design

```
vlan 10  vlan-users     192.168.10.0/24   desktop, laptops, phones, TV, amp, console, printer
vlan 20  vlan-services  192.168.20.0/24   Home Assistant, Pi-hole, OctoPrint
vlan 30  vlan-iot       192.168.30.0/24   Tasmota x2, ESPHome, Hombli fan, ...
```

Gateway is `.1` on each. All three VLAN interfaces live on `bridge-main` on mikrotik1;
mikrotik2 and mikrotik3 stay pure L2 and simply carry the tags.

### Policy matrix

| From \ To | internet | users | services | iot | router mgmt |
|---|---|---|---|---|---|
| **users** | allow | — | `mgmt` full; else DNS/HA | `mgmt` full only | `mgmt` list only |
| **services** | allow | **drop + log** | — | HA: 6053, 80, 6668 | `mgmt` list only |
| **iot** | **DROP** | drop | Pi-hole 53, HA 1883 | — | NTP 123 to gateway |

The one hole in IoT containment is `iot -> services` on tcp/1883, because the MQTT broker
runs on the HA host and devices connect outbound to it. Written narrowly: that host, that
port, nothing else.

**Port 6668 added 2026-09-08**, found live while pairing the ceiling fan: HA's `tuya-local`
integration talks directly to the device over Tuya's local protocol (bypassing Tuya's cloud),
not anticipated in the original matrix. Applied early via
`scripts/phase3-13-ha-tuya-local.rsc`, same shape as the existing `HA -> Tasmota/IotaWatt`
rule below (not scoped to one device's address, since any future Tuya-local device needs the
same access) — added directly to the Phase 4 draft.

### The IoT internet exception

Decided 2026-09-06, and it changes the stated policy. "None of my IoT devices should be
accessing the internet in any way" becomes **"no internet except a named list"**, because
OctoPrint needs apt, pip, GitHub and plugin repositories to update itself.

This is worth being uncomfortable about: OctoPrint is a full Linux host with a web UI sitting
among ESP microcontrollers, and it is now the one device in the isolated VLAN that can reach
the internet. It is also the one most worth compromising. The exception is therefore scoped
rather than blanket:

```
/ip/firewall/address-list/add list=iot-internet address=<octoprint> comment=octoprint

# allow, in the forward chain, before the iot drop
allow src-address-list=iot-internet out-interface=<wan> protocol=tcp dst-port=80,443
allow src-address-list=iot-internet out-interface=<wan> protocol=udp dst-port=53
drop  in-interface=vlan-iot out-interface=<wan> log=yes log-prefix="iot-internet"
```

Ports 80 and 443 cover apt, PyPI and GitHub. Everything else stays denied, and the drop is
logged so any further need shows up as evidence rather than a guess.

**Keep the list short and review it.** An allow-list of one is a decision; an allow-list of
six is the policy quietly having been abandoned. If it grows, that is the signal to give
these devices their own VLAN with internet rather than keep punching holes in this one.

## Device inventory and address plan

Complete as of 2026-09-06, from the bridge host tables, the ARP table and the full lease list.
**Host numbers are preserved across the renumber** — only the third octet changes — so
`192.168.1.40` becomes `192.168.20.40`. That makes every address in this document mentally
translatable and makes a mistyped rule obvious on sight. `users` addresses below already show
the post-Phase-2 `192.168.10.x` values, since that renumber is done.

### users — VLAN 10, 192.168.10.0/24

| Device | Address | Attachment | Last seen |
|---|---|---|---|
| desktop "during" | `.10.90` | mikrotik3 `ether3` | live |
| laptop "gimli" | `.10.92` | wireless | 12 weeks |
| second laptop | pool | wireless | not yet identified |
| Galaxy S24 Ultra | pool | wireless, randomised MAC | live |
| phone `EA:84:28` | pool | wireless, randomised MAC | live |
| TV (Samsung), `F4:DD:06:2A:FB:AF` | pool, no reservation yet | wireless | live — corrected 2026-09-07, see note below |
| Nintendo Switch (likely) `BC:CE:25:5E:7F:8A` | pool | wireless | live, very consistently — was misidentified as the TV in the original inventory; still not 100% confirmed |
| Onkyo amp `00:09:B0` | `.10.104` | wireless | intermittent |
| Printer `NPI52346B` | `.10.110` | mikrotik3 `ether2` | live — moved to `services` then reverted 2026-09-08, see Decisions above |
| mikrotik1 | `.10.1` | gateway on all three VLANs | — |
| mikrotik2 | `.10.2` | mikrotik1 `ether2-master` | — |
| mikrotik3 | `.10.3` | mikrotik2 `ether16` | — |
| mikrotik4 | `.10.4` | to be deployed | 143 weeks |

**The TV correction.** The original inventory guessed `.100`/`BC:CE:25` was the TV, flagged as
unconfirmed. It wasn't — found instead while debugging a real WiFi outage: the TV's actual MAC
is `F4:DD:06:2A:FB:AF` (DHCP hostname "Samsung"), and it has no reservation at all currently,
landing on whatever the pool hands out. `BC:CE:25` is very likely the Nintendo Switch instead
(consistently active, matches the living-room device profile) but that's still not directly
confirmed. Worth adding a proper reservation for the TV's real MAC next time this is touched.

### services — VLAN 20, 192.168.20.0/24 (Pi-hole migrated 2026-09-08; Home Assistant next)

| Device | Address | Attachment | Last seen |
|---|---|---|---|
| Pi-hole | `.20.40` | mikrotik2 `ether23` | live, migrated 2026-09-08 |
| Home Assistant | `.20.60` | mikrotik2 `ether21` | live, migrated 2026-09-08 |

### iot — VLAN 30, 192.168.30.0/24 (not yet migrated — Phase 3)

| Device | New address | Attachment | Last seen |
|---|---|---|---|
| IotaWatt | `.30.50` | wireless | live |
| Kids light (Tasmota) | `.30.61` | wireless | live, migrated 2026-09-08 |
| Kitchen light (Tasmota) | — | wireless | **confirmed dead, reservation deleted in Phase 2** |
| Hombli ceiling fan | `.30.63` | wireless | live |
| OctoPrint | `.30.81` | wireless for now, wired later | intermittent |

**The IoT migration is three live devices, not five.** IotaWatt, the kids light and the
ceiling fan are the only ones currently on the network. OctoPrint has to be brought back up
regardless. The kitchen light is confirmed gone — its DHCP reservation was deleted rather than
migrated during Phase 2's cleanup, no need to plan a migration step around it.

### Still to confirm

- **The second laptop.** Never seen in any capture. It will want a reservation once identified.
- **The Nintendo Switch identity.** Strongly indicated for `BC:CE:25:5E:7F:8A` but not
  directly confirmed — check from the console's own network settings.

### Static reservations for everything: one caveat

Decided 2026-09-06: as many devices as possible get static DHCP reservations.

**Several of your current clients use randomised MAC addresses** — the Galaxy S24 Ultra and
the phone `EA:84:28`, among others — all with the locally-administered bit set. These are
phones and laptops with MAC privacy enabled. A reservation against a randomised MAC works
until the device decides to re-randomise, then silently stops.

For those devices, either set the WiFi network to "use device MAC" in the client's settings,
or accept that they take pool addresses. Do not spend effort on reservations that will decay.

## Living room: one socket, three devices

The Amp, TV and Nintendo Switch all live on `users`, so **the living room does not need a
managed switch** — anything there lands on the same VLAN via a single access port with
`pvid=10`. A plain unmanaged gigabit switch is sufficient and correct.

The better option, if you are buying the office PoE switch anyway: **move mikrotik3 to the
living room** and put the new PoE switch in the office. mikrotik3 has five ports — uplink,
Amp, TV, Switch, one spare — and the office needs eight for the desktop, two laptops, two
PoE access points and the uplink. That buys one device instead of two and retires nothing.

Note this also moves the TV off wireless, which frees airtime on a band that is your main
wireless constraint.

## Workshop: a third location needing a switch

OctoPrint's wired link is down — probably a bad cable — and the intent is a switch or router
in the workshop for OctoPrint plus other devices later. Until then it runs on `LEDCOM-IoT`
over wireless.

**This one may need to be VLAN-aware, unlike the other two.** The living room carries only
`users` devices and the office switch terminates VLANs anyway, but the workshop is expected to
hold OctoPrint on `iot` *and* unspecified other devices that may not be. An unmanaged switch
can serve exactly one VLAN — whatever the uplink port's PVID says. If the workshop stays
single-VLAN, unmanaged is fine and cheap; the moment it is mixed, it needs a managed switch or
the RB2011 once that frees up.

Decide what else goes in the workshop before buying, and note that the RB2011 becomes
available when the edge role moves to an RB5009.

## Trunk and access port plan

The state as of the end of Phase 1 — every port below still carries `pvid=10` and full VLAN 10
membership, even the ones (`ether21`/`ether23` on mikrotik2) destined to move to `services` in
Phase 3. That move is deliberately deferred: see the migration table above and the note about
it being two commands (VLAN-table membership *and* `pvid`), not one. `ether2` on mikrotik3
(the printer) briefly moved to `services` and back — see the Decisions section above — and is
shown below in its final, reverted state.

`ether16` on mikrotik2 is a trunk carrying VLANs 20/30 toward mikrotik3 in case something else
there ever needs them; nothing currently attached to mikrotik3 uses anything but `users`.

### mikrotik1 — `bridge-main`

| Port | Role | PVID | Untagged | Tagged |
|---|---|---|---|---|
| `ether2-master` | trunk to mikrotik2 | 10 | 10 | 20, 30 |
| `ether3`-`ether10`, `sfp1` | unused | 10 | 10 | — |
| `ap-MikroTik-1`, `ap-MikroTik-Switch-1` | wireless, CAPsMAN dynamic | — | — | 10 (30 once Phase 3 creates the IoT SSID) |
| `bridge-main` itself | carries the VLAN interfaces | — | — | 10, 20 (once created), 30 (once created) |

### mikrotik2 — `bridge-local`

| Port | Role | PVID | Untagged | Tagged |
|---|---|---|---|---|
| `ether1-gateway` | trunk to mikrotik1 | 10 | 10 | 20, 30 |
| `ether16-slave-local` | trunk to mikrotik3 | 10 | 10 | 20, 30 |
| `ether21-slave-local` | Home Assistant — moves to `services` in Phase 3 | 10 | 10 | — |
| `ether23-slave-local` | Pi-hole — moves to `services` in Phase 3 | 10 | 10 | — |
| all other ports | unused | 10 | 10 | — |
| `bridge-local` itself | management address | — | — | 10 |

### mikrotik3 — `bridge`

| Port | Role | PVID | Untagged | Tagged |
|---|---|---|---|---|
| `ether1` | trunk to mikrotik2 | 10 | 10 | 20, 30 |
| `ether2` | printer (`users`, reverted 2026-09-08) | 10 | 10 | — |
| `ether3` | desktop | 10 | 10 | — |
| `ether4`, `ether5` | unused | 10 | 10 | — |
| `bridge` itself | management address | — | — | 10 |

## Migration

Six phases, numbered 0-5. Each is independently verifiable and independently reversible. **Do
not start a phase until the previous one is verified.** Phases 0-2 are done — see
`changelog.md`. What follows is Phase 3 onward.

### The rollback pattern

Arm this on the device being changed, **before** every step marked RISKY — and make sure the
`on-event` actually restores *everything* the step changes, not just the most obvious flag.
Phases 1 and 2 both had their rollback scripts grow well past a single `vlan-filtering=no`
toggle once the real scope of a change became clear (full account in `changelog.md`); treat
this as the pattern to build from, not a complete example on its own:

```
/system/scheduler/add name=rollback interval=5m on-event={
    /interface/bridge/set [find] vlan-filtering=no;
    /system/scheduler/remove rollback }
```

Make the change — as a `/system/script`, not pasted interactively, whenever it moves an
address or anything else that could drop the current session; the change needs to complete
server-side regardless of whether the session survives. If the device is still reachable and
working afterward, `/system/scheduler/remove rollback` (and remove the migration script too).
If not, wait five minutes and the scheduler reverts itself.

**Do not use safe mode.** It silently discarded work twice on this network when the session
dropped. See [changelog.md](changelog.md).

### Phase 3 — services and iot, devices one at a time

**Before touching Pi-hole or Home Assistant, re-read the Status section above** — a fresh
`grep` of a current `dump-configs.sh` export for their literal IP, across all three devices,
is cheaper than finding each reference the hard way again.

Create the two remaining VLANs on mikrotik1:

```
/interface/vlan/add interface=bridge-main vlan-id=20 name=vlan-services
/interface/vlan/add interface=bridge-main vlan-id=30 name=vlan-iot
/ip/address/add address=192.168.20.1/24 interface=vlan-services
/ip/address/add address=192.168.30.1/24 interface=vlan-iot

/ip/pool/add name=pool-services ranges=192.168.20.100-192.168.20.200
/ip/pool/add name=pool-iot      ranges=192.168.30.100-192.168.30.200
/ip/dhcp-server/add name=dhcp-services interface=vlan-services address-pool=pool-services lease-time=5m
/ip/dhcp-server/add name=dhcp-iot      interface=vlan-iot      address-pool=pool-iot      lease-time=5m
/ip/dhcp-server/network/add address=192.168.20.0/24 gateway=192.168.20.1 \
    dns-server=192.168.20.40 domain=home.ledcom.fr
/ip/dhcp-server/network/add address=192.168.30.0/24 gateway=192.168.30.1 \
    dns-server=192.168.20.40 domain=home.ledcom.fr
```

DHCP option 42 for NTP, on each network:

```
/ip/dhcp-server/option/add name=ntp-users    code=42 value=0xC0A80A01
/ip/dhcp-server/option/add name=ntp-services code=42 value=0xC0A81401
/ip/dhcp-server/option/add name=ntp-iot      code=42 value=0xC0A81E01
```

Create the IoT SSID as a slave configuration on both radios:

```
/caps-man/configuration/add name=caps_iot ssid=LEDCOM-IoT country=switzerland \
    security.authentication-types=wpa2-psk security.passphrase="<choose one>" \
    datapath.bridge=bridge-main datapath.vlan-id=30 datapath.vlan-mode=use-tag
/caps-man/provisioning/set [find] slave-configurations=caps_iot
/caps-man/remote-cap/provision [find]
```

**Before moving Home Assistant**, update Pi-hole's existing local DNS record for
`home.ledcom.fr` to its new address once it moves, and keep using that one name for both
internal and external access — the DNS-bypass finding above is what made this risky, and it's
now fixed. Reconfigure devices to use the name rather than the IP where they don't already;
then this migration, and every future one, costs one DNS record instead of a visit to every
device.

Migrate in this order — chosen so no device is touched twice:

**Step 1 (Printer) tried 2026-09-07, reverted 2026-09-08** — moved to `services`, confirmed
working via a static-URI print, then moved back to `users` once the mDNS repeater defect made
autodiscovery unreliable there. See the Decisions section above and `changelog.md` for the
full account. The printer is no longer part of this migration.

**Step 2 (Pi-hole) done and verified 2026-09-08** — see `changelog.md`, including a plain `dig`
from a `vlan-users` client confirming the full DHCP -> `dns-server=` -> Pi-hole chain, not just
router-sourced queries. One nice-to-have left unchecked: Pi-hole's own admin UI showing
per-client attribution still intact (queries by real client IP, not collapsed to the router) —
not expected to be an issue since these are plain routed queries with no NAT involved between
`users` and `services`, but worth a glance next time the Pi-hole UI is open anyway.

**Step 3 (Home Assistant) done and verified 2026-09-08** — see `changelog.md`.

**Step 7 (Ceiling fan) done out of order, 2026-09-08** — see the Decisions section above for
why, and `changelog.md` for the router-side application. Reconfiguring it in Home Assistant
(rejoining `LEDCOM-IoT`, re-pairing) is Guillaume's own next action, not scripted here.

**Step 6 (Kids light) done and verified 2026-09-08, including its NTP fix** — see
`changelog.md`.

| # | Device | To | Also change | Verify |
|---|---|---|---|---|
| 4 | OctoPrint | iot (wireless) | join `LEDCOM-IoT`, add to `iot-internet` list, update HA's integration | plugin update succeeds; HA sees it |
| 5 | IotaWatt | iot | new SSID, broker hostname, `NtpServer1 192.168.30.1` (confirmed needed — DHCP option 42 doesn't work, see below) | appears in HA |

**Reference checklist for steps 2-3, from a full `dump-configs.sh` grep of all three devices
(2026-09-07) for `192.168.10.40` and `192.168.10.60` — do this grep again before actually
migrating, in case anything's changed since:**

*Pi-hole (`192.168.10.40` -> `192.168.20.40`):*
- Port move (mikrotik2 `ether23-slave-local` -> `pvid=20`) and DHCP reservation (mikrotik1) —
  `scripts/phase3-05a-pihole-mikrotik2-port.rsc`, `scripts/phase3-05b-pihole-mikrotik1-dhcp-and-fw.rsc`
- **Do the rest only after confirming Pi-hole answers DNS at `192.168.20.40`** — these all
  repoint something at Pi-hole as an upstream resolver, so doing them early would cut off DNS
  before it's ready to serve it:
  - mikrotik1's own `/ip/dns` `servers=`, and the forward-chain rule *"Accept DNS requests
    from Pi-hole"* (`src-address=`) — `scripts/phase3-05c-pihole-mikrotik1-dns.rsc`
  - `/ip/dns` `servers=192.168.10.40` **also set independently on mikrotik2 and mikrotik3** —
    three separate settings, not one shared config —
    `scripts/phase3-05d-pihole-mikrotik2-dns.rsc`, `scripts/phase3-05e-pihole-mikrotik3-dns.rsc`
  - The `vlan-users` DHCP network's `dns-server=` (mikrotik1) — **do this one by hand, not
    scripted**: `/ip/dhcp-server/network/set [find address=...]` is the confirmed-buggy find
    filter (silently matches nothing on this RouterOS version). Print
    `/ip/dhcp-server/network/print` first, confirm the `192.168.10.0/24` row's numeric index
    (it was `0` as of the Phase 3 block 1 work), then `set 0 dns-server=192.168.20.40`, then
    print again to confirm — same pattern already used for the `ntp-users` retrofit.

*Home Assistant (`192.168.10.60` -> `192.168.20.60`):*
- DHCP reservation (mikrotik1)
- The dst-nat port forward *and* its paired forward-chain accept rule for HTTPS, both on
  mikrotik1 — update both, per the NAT/forward-chain lesson above
- **The `homeassistant` user account's own `address=192.168.10.60/32` restriction, present
  independently on all three devices** (mikrotik1, mikrotik2, mikrotik3) — this is an
  account restriction, not a firewall rule, so it is easy to miss; same category of reference
  that caused the Phase 2 lockout
- The input-chain *"HA API access (post-renumber)"* rule (`src-address=192.168.10.60
  dst-port=8728`), **also present separately on all three devices**
- HA's own MikroTik integration config (the host/address it connects to)
- The `ha.home.ledcom.fr` Pi-hole record, once added per the note above

So "on four devices" really means: three MikroTiks × the account restriction, plus the
router-level DHCP/NAT/forward rules that live on mikrotik1 alone.

**Each `pvid=20` move in steps 1-3 is two commands, not one.** Since Phase 1 kept these ports
as VLAN 10 members (see the trunk/port plan above), moving a port also means switching its
VLAN table membership, not just its `pvid` — e.g. for the printer:

```
/interface/bridge/vlan/set [find vlan-ids=10] untagged=[remove ether2 from the list]
/interface/bridge/vlan/set [find vlan-ids=20] untagged=[add ether2 to the list]
/interface/bridge/port/set [find interface=ether2] pvid=20
```

`/interface/bridge/vlan/set` takes the full replacement list for `untagged=`, not a
single-port add/remove, so print the current membership first and paste back the edited list —
same pattern for `ether21-slave-local`/`ether23-slave-local` on mikrotik2. Also remember:
`/ip/dhcp-server/network/set [find address=...]` has a confirmed bug on this RouterOS version
where the `address=` find filter silently matches nothing — use the row's numeric index instead
(`/ip/dhcp-server/network/set <N> ...`), and always `print` to confirm which index is which
first.

**Temporary rule, steps 3 to 8.** Once HA is on `services` but IoT devices are still on
`users`, they need `users -> services tcp/1883` to reach the broker. Add it at step 3, remove
it at Phase 4. Write the removal down — a forgotten temporary rule is indistinguishable from
a deliberate one six months later.

~~Do the ceiling fan last.~~ **Overridden 2026-09-08** — done first instead, see the Decisions
section above. The reasoning here (the standing drop rule made it the riskiest device to debug
first) no longer fully applies anyway, since that rule is now retired rather than carried
forward.

**Do not batch the remaining IoT devices.** A Tasmota device that fails to join `LEDCOM-IoT` is
offline until you reach its fallback AP or reflash it. One device, verify fully, then the next.

### Phase 4 — firewall policy and tightening

Only now, with every device in place, apply the real policy. Adding it earlier means debugging
tagging and filtering at the same time.

**One rule pulled forward, 2026-09-08: `services -> internet: allow`.** The policy matrix
above always said `services` gets unconditional internet access, but neither the live ruleset
nor this Phase 4 script itself ever actually added that rule — only `vlan-users` had a broad
"connect everywhere" accept, and VLAN sub-interfaces are distinct firewall interfaces from
`bridge-main`, so that rule never covered `vlan-services` at all. Found migrating Pi-hole,
which needs outbound access immediately for its own upstream DNS queries — not something that
can wait for the rest of Phase 4's restrictive rules. Applied via
`scripts/phase3-05b-pihole-mikrotik1-dhcp-and-fw.rsc`, inserted with `place-before=` the
catch-all drop (a plain `/add` appends to the end of the chain, which would have put it after
the already-unconditional "Drop all other forward traffic" and made it dead):

```
/ip/firewall/filter/add chain=forward action=accept connection-state=new \
    in-interface=vlan-services out-interface=ether1 comment="services: internet"
```

**A second rule pulled forward, 2026-09-08: HA's MikroTik integration needs `services -> users`
to mikrotik2/mikrotik3.** Found testing the HA migration: the integration reached mikrotik1
fine (HA and mikrotik1 share `vlan-services` directly — mikrotik1 holds an address on every
VLAN, so that's not a cross-VLAN hop at all), but got "Failed to connect" on mikrotik2 and
mikrotik3, whose management addresses (`192.168.10.2`, `192.168.10.3`) live on `vlan-users`.
Reaching them means mikrotik1 forwarding `vlan-services -> vlan-users`, which nothing allows —
the account restriction and the `HA API access` rule (updated on all three devices, see
`changelog.md`) only control the *destination* device's own input chain; they don't get HA's
packets there in the first place. Narrow exception, not a blanket `services -> users` allow —
same shape as `iot -> services`'s one hole below.

**First attempt landed the rule dead.** `scripts/phase3-08-ha-mikrotik-integration-access.rsc`
used a plain `/add`, which appends to the end of the chain — after the unconditional "Drop all
other forward traffic" catch-all, so the rule was correctly written but never evaluated.
Exactly the mistake already documented above for the `services: internet` rule, repeated here
by not applying it consistently. Fixed by moving the existing rule
(`scripts/phase3-08c-ha-mikrotik-rule-reorder.rsc`) rather than recreating it. The version
below has `place-before=` built in from the start:

```
/ip/firewall/address-list/add list=ha-mikrotik-targets address=192.168.10.2 comment=mikrotik2
/ip/firewall/address-list/add list=ha-mikrotik-targets address=192.168.10.3 comment=mikrotik3
/ip/firewall/filter/add chain=forward action=accept connection-state=new \
    src-address=192.168.20.60 dst-address-list=ha-mikrotik-targets protocol=tcp dst-port=8728 \
    in-interface=vlan-services out-interface=vlan-users \
    comment="HA MikroTik integration: services -> users API" \
    place-before=[find where comment="Drop all other forward traffic"]
```

The rest of Phase 4 below is unchanged and still waits for every device to be in place.
**`connection-state=new` added throughout, 2026-09-08** — every `accept` rule below originally
lacked it; the printer/Pi-hole/HA work found that a forward-chain accept rule combining
`in-interface=`/`out-interface=` with `dst-address=`/`dst-port=` shows RouterOS's `I - INVALID`
flag (silently not enforced) without it, confirmed live on the `TEMP: iot mqtt` rule added for
HA. Not added to the `drop` rules — those are intentional catch-alls and adding it would narrow
what they actually block.

**Corrected 2026-09-08, ceiling fan work: `connection-state=new` alone isn't sufficient.**
Three rules below (`iot: MQTT to HA`, both `iot: DNS to pi-hole` rules, `iot exception:
updates`, `users: DNS`, `users: HA web`) originally specified only *one* of `in-interface=`/
`out-interface=` alongside an address/port matcher — confirmed live to also show `I - INVALID`
despite already having `connection-state=new`. Contrast with `Home can connect everywhere`
(one interface, no address/port matcher: valid) and the HA-integration/`TEMP: iot mqtt` rules
(both interfaces, with address/port matchers: valid) — the actual rule is that an address/port
matcher combined with an interface matcher needs **both** interface directions specified
together, not just one. Fixed below by adding the missing complementary interface to each.
Not verified whether this also affects `chain=input` (no `out-interface=` concept applies
there) — check the `iot: NTP from gateway` rule specifically when Phase 4 is actually applied.

**Further refined the same evening, ceiling fan lockdown:** this isn't limited to `accept`
rules or to "one interface + address matcher" — a `drop` rule combining both `src-address=`
*and* `dst-address=` together, with *no* interface matcher at all, also showed `I - INVALID`
once enabled (the fan's DNS-drop rules). Also: **RouterOS doesn't evaluate the flag on a
`disabled=yes` rule at all** — these looked clean when created disabled and only showed the
problem once switched on. See `README.md`'s hard-won lessons for the fuller, still-not-fully-
characterized list of triggers — treat `I - INVALID` as something to check after any multi-
matcher rule, not as one fixed rule to remember.

```
# address lists
/ip/firewall/address-list/add list=iot-internet address=192.168.30.81 comment=octoprint

# --- forward chain, in order, before the existing catch-all drop ---

# iot -> services: the one hole in containment, written narrowly
/ip/firewall/filter/add chain=forward action=accept connection-state=new in-interface=vlan-iot \
    out-interface=vlan-services dst-address=192.168.20.60 protocol=tcp dst-port=1883 \
    comment="iot: MQTT to HA"
/ip/firewall/filter/add chain=forward action=accept connection-state=new in-interface=vlan-iot \
    out-interface=vlan-services dst-address=192.168.20.40 port=53 protocol=udp \
    comment="iot: DNS to pi-hole"
/ip/firewall/filter/add chain=forward action=accept connection-state=new in-interface=vlan-iot \
    out-interface=vlan-services dst-address=192.168.20.40 port=53 protocol=tcp \
    comment="iot: DNS to pi-hole"

# the named internet exception, then the wall
/ip/firewall/filter/add chain=forward action=accept connection-state=new in-interface=vlan-iot \
    src-address-list=iot-internet out-interface=ether1 protocol=tcp dst-port=80,443 \
    comment="iot exception: updates"
/ip/firewall/filter/add chain=forward action=drop in-interface=vlan-iot \
    log=yes log-prefix="iot-drop" comment="iot: deny everything else"

# services -> users: denied, but logged so exceptions arrive as evidence
# (the HA-MikroTik-integration exception above also lives in this section)
/ip/firewall/filter/add chain=forward action=accept connection-state=new \
    in-interface=vlan-services out-interface=vlan-iot dst-port=80 protocol=tcp \
    comment="HA -> Tasmota/IotaWatt"
/ip/firewall/filter/add chain=forward action=accept connection-state=new \
    in-interface=vlan-services out-interface=vlan-iot dst-port=6668 protocol=tcp \
    comment="HA -> Tuya local (fan)"
/ip/firewall/filter/add chain=forward action=drop in-interface=vlan-services \
    out-interface=vlan-users log=yes log-prefix="infra2users" comment="services: no users"

# users -> services: mgmt full, everyone else named services
/ip/firewall/filter/add chain=forward action=accept connection-state=new \
    in-interface=vlan-users out-interface=vlan-services src-address-list=mgmt \
    comment="mgmt hosts: full"
/ip/firewall/filter/add chain=forward action=accept connection-state=new in-interface=vlan-users \
    out-interface=vlan-services dst-address=192.168.20.40 port=53 protocol=udp \
    comment="users: DNS"
/ip/firewall/filter/add chain=forward action=accept connection-state=new in-interface=vlan-users \
    out-interface=vlan-services dst-address=192.168.20.60 protocol=tcp dst-port=443 \
    comment="users: HA web"
/ip/firewall/filter/add chain=forward action=drop in-interface=vlan-users \
    out-interface=vlan-services log=yes log-prefix="users2services"

# users -> iot: mgmt only
/ip/firewall/filter/add chain=forward action=accept connection-state=new \
    in-interface=vlan-users out-interface=vlan-iot src-address-list=mgmt \
    comment="mgmt hosts: iot"
/ip/firewall/filter/add chain=forward action=drop in-interface=vlan-users out-interface=vlan-iot

# --- input chain: NTP for iot ---
/ip/firewall/filter/add chain=input action=accept connection-state=new in-interface=vlan-iot \
    protocol=udp dst-port=123 comment="iot: NTP from gateway" \
    place-before=[find comment="Drop anything else!"]
```

mDNS repeating, for HA device discovery. **Tried early for the printer (2026-09-07), disabled
again 2026-09-08** once the printer reverted to `users` and the confirmed RouterOS
query/response defect (below) made it clear this wouldn't reliably help discovery for anything
on `services`/`iot` either. Re-enable only with that limitation in mind — it's good for "does
this device exist," not for resolving/connecting to it — and re-scope the interface list to
whatever's actually migrated at the time:

```
/ip/dns/set mdns-repeat-ifaces=vlan-users,vlan-services,vlan-iot
```

Remember this is a single global list, not a set of pairs: IoT device names become visible
from `users`. Access is still blocked by the rules above — it is an information leak, not a
path.

**Known RouterOS limitation, root-caused 2026-09-08: `mdns-repeat-ifaces` drops the reply to a
query it proxies.** Found migrating the printer: `avahi-browse -a` sees the printer's PTR-level
announcements fine from `vlan-users`, and CUPS/GNOME's "Add Printer" discovers and adds it via
a `dnssd://` URI without complaint — but printing through that discovered printer hangs on
"processing" and CUPS logs "Unable to locate printer", because it re-resolves the `dnssd://`
URI live at print time and that resolve times out.

Confirmed with `/tool/sniffer/quick` on both VLANs simultaneously with the resolve retrying:
- On `vlan-services`: the query arrives **re-sourced as `192.168.20.1`** (the router's own
  gateway address, not the desktop's) — the router proxies the query under its own identity
  rather than relaying it raw. The printer answers it twice, real data (189-192 bytes).
- On `vlan-users`, for the same window: **nothing comes back at all.** Every packet captured
  is the desktop's own outbound query; not one packet from `192.168.20.110` or any
  router-proxied equivalent.

So the router receives the printer's answer and drops it instead of repeating it back to the
querying VLAN. Spontaneous, unprompted announcements repeat fine in both directions (that's
how browse found the name in the first place) — only the reply half of a router-proxied
query/response pair goes missing. This is a specific, reproducible RouterOS defect, not a
firewall rule, not an avahi quirk, and not configurable away from this side; it would need a
MikroTik firmware fix. Worth reporting to MikroTik given how cleanly it's reproduced, but
separate from this project.

**Workaround, confirmed working, and treated as the permanent approach rather than a
stopgap:** configure any cross-VLAN mDNS consumer with a static IP-based URI instead of a
discovered one — `ipp://192.168.20.110/ipp/print` or `socket://192.168.20.110:9100` for this
printer — which bypasses mDNS for the actual connection entirely. Expect the same fix to be
needed for any future cross-VLAN mDNS consumer (a phone adding this printer, HA discovering an
IoT device once `vlan-iot` joins the repeat list): mDNS on this network is good enough to find
that a device exists, not to reliably resolve and connect to it across VLANs.

### Phase 5 — read the evidence, then tighten

After a week of normal use:

```
/log/print where message~"infra2users"
/log/print where message~"users2services"
/log/print where message~"iot-drop"
```

- Convert genuine hits into narrow rules, or confirm there were none and set `log=no`.
- Remove the temporary `users -> services tcp/1883` rule from Phase 3.
- **Once the whole migration is done: full config review, see
  [config-review.md](config-review.md#planned-full-config-review-once-the-vlan-migration-is-complete)**
  — in particular, audit every port-opening firewall rule for `connection-state=new`, not just
  the ones this project added.
- Confirm the `iot-internet` list still contains exactly one address. **An allow-list of one
  is a decision; an allow-list of six is the policy having been quietly abandoned** — if it
  has grown, that is the signal to give those devices their own VLAN with internet rather
  than keep punching holes in this one.
- Test discovery properly: printer findable from a phone on `users`, HA able to discover a
  new device on `iot`. If it misbehaves, check whether repeated multicast traverses the
  forward chain — **not verified**.
- Consider moving VLAN 10 to tagged-only on the trunks.
- **Narrow `services -> internet` from blanket allow to specific protocols.** Noted
  2026-09-08. The rule added early for Pi-hole (`comment="services: internet"`, see Phase 4
  above) allows all forward traffic from `vlan-services` to `ether1` — broader than it needs
  to be. `services` devices' actual internet needs are narrow and known (Pi-hole: DNS lookups
  to its configured upstreams; HA: HTTPS for cloud integrations/updates) — replace the blanket
  accept with specific `dst-port=53,80,443` (or narrower, once HA's actual needs are known
  post-migration) rules, same shape as the `iot-internet` exception list above.

## Known unverified assumptions

Listed so they are not mistaken for established fact.

1. ~~CAPsMAN VLAN tagging.~~ **Resolved 2026-09-07.** The dynamic CAP interfaces do need
   CAPsMAN's own `datapath.vlan-mode=use-tag` — bridge-VLAN table membership alone is not
   sufficient. Confirmed live: wireless clients had no working IPv4 until this was set. See
   `changelog.md` for the full diagnosis.
2. ~~mDNS repeater and the forward chain.~~ **Resolved 2026-09-08, root-caused via
   `/tool/sniffer/quick` on both VLANs.** Not a forward-chain question after all — the router's
   mDNS repeater proxies a client's query onto the other VLAN under its own address, the
   printer answers it, and the router drops that reply instead of repeating it back. Spontaneous
   announcements repeat fine both ways (that's how browse works); only query-triggered replies
   go missing. A specific RouterOS defect, not fixable from the config side. See the printer's
   mDNS finding under Phase 4 above for the full packet-capture evidence. Static IP addressing
   is the confirmed, permanent workaround for any cross-VLAN mDNS consumer.
3. ~~DHCP option 42 uptake.~~ **Resolved 2026-09-08 on the Kids light, twice corrected along
   the way — full sequence kept since each correction is the actual lesson.** First observation: after migrating, it was still pointed at `192.168.10.1` — not a
   random default, but the *exact* `ntp-users` option-42 value this project created on
   2026-09-07 while the device was still on `vlan-users`. Initially wrote this up as "Tasmota
   ignores option 42 entirely" — wrong, or at least unproven; the only thing actually
   confirmed is that an old, DHCP-or-otherwise-acquired value **persisted across the VLAN
   migration** rather than being refreshed. Whether a fresh DHCP renewal alone would have
   picked up the new network's option-42 value was never tested, since manual reconfiguration
   was done instead (`NtpServer1 192.168.30.1`, applied and confirmed via Tasmota's console).
   **That manual fix was correct but time still didn't sync** — the actual remaining blocker
   was that mikrotik1's `chain=input` had no rule permitting UDP/123 from `vlan-iot` at all
   (the Phase 4 draft's `iot: NTP from gateway` rule, never pulled forward like the others).
   Fixed via `scripts/phase3-17-iot-ntp-input.rsc`. **Net takeaway: don't assume a device's
   automatically-acquired NTP config survives a VLAN move — check and re-point it by hand
   either way — and a "correct" device-side fix can still fail silently if the matching
   router-side rule was never actually applied.** **Verified fixed:** Tasmota's `Status 7`
   shows correct local time (`2026-09-08T15:26:23`, not the epoch stall). Still worth testing
   fresh, cleanly, on the next device (IotaWatt/ESPHome, not yet migrated): does an actual DHCP
   renewal on the new network's scope update its NTP server, or does it also need manual
   reconfiguration?
4. **RB2011 hardware offload for VLAN filtering.** If bridge VLAN filtering is not offloaded
   to the switch chips, forwarding moves to a 600 MHz single core. Watch CPU during Phase 3;
   the throughput measurements in [performance.md](performance.md) are the baseline. Not
   specifically checked during Phase 1, though no symptoms of CPU exhaustion were observed.
