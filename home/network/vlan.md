# VLAN segmentation — design and migration plan

Designed 2026-09-06. **Phases 0-4 are done; Phase 5 is what's left.** Full history,
evidence, and every bug found along the way are in [changelog.md](changelog.md) — this
document holds the design reference and current state, not the story of how it was built.

## Status

- **Phases 0-4: done.** VLAN plumbing, full renumber to `192.168.10/20/30.0/24`, all seven
  original devices have router-side work done, and the real firewall policy is live.
- **Printer**: reverted to `users` (autodiscovery over segmentation — see Decisions).
- **Pi-hole, Home Assistant, Kids light, ceiling fan**: migrated and verified.
- **OctoPrint, IotaWatt**: router-side config applied, device-side verification still pending
  (OctoPrint was off; IotaWatt was unreachable, possibly pre-existing).
- **Phase 5, next**: read a week of `infra2users`/`users2services`/`users2iot`/`iot-drop` log
  evidence and tighten from there (see Phase 5 below).
- **Open, not blocking**: the "second laptop" in the device inventory is still unidentified.

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
| IoT internet | denied by default, with a **named exception list** — currently OctoPrint only |
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
vlan 20  vlan-services  192.168.20.0/24   Home Assistant, Pi-hole, OctoPrint
vlan 30  vlan-iot       192.168.30.0/24   Tasmota x2, ESPHome, Hombli fan, ...
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
a full Linux host sitting among microcontrollers. Scoped narrowly:

```
/ip/firewall/address-list/add list=iot-internet address=<device> comment=<name>
/ip/firewall/filter/add chain=forward action=accept connection-state=new in-interface=vlan-iot \
    src-address-list=iot-internet out-interface=ether1 protocol=tcp dst-port=80,443 \
    comment="iot exception: updates" place-before=[find where comment="Drop all other forward traffic"]
```

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
| TV (Samsung) `F4:DD:06:2A:FB:AF` | pool | wireless | no reservation yet |
| Nintendo Switch (likely) `BC:CE:25:5E:7F:8A` | pool | wireless | not 100% confirmed |
| Onkyo amp `00:09:B0` | `.10.104` | wireless | intermittent |
| Printer `NPI52346B` | `.10.110` | mikrotik3 `ether2` | reverted from `services` |
| mikrotik1 | `.10.1` | gateway on all three VLANs | |
| mikrotik2 | `.10.2` | mikrotik1 `ether2-master` | |
| mikrotik3 | `.10.3` | mikrotik2 `ether16` | |
| mikrotik4 | `.10.4` | to be deployed | offline |

### services — VLAN 20, 192.168.20.0/24

| Device | Address | Attachment |
|---|---|---|
| Pi-hole | `.20.40` | mikrotik2 `ether23` |
| Home Assistant | `.20.60` | mikrotik2 `ether21` |

### iot — VLAN 30, 192.168.30.0/24

| Device | Address | Attachment | Status |
|---|---|---|---|
| IotaWatt | `.30.50` | wireless | applied, unreachable — investigating |
| Kids light (Tasmota) | `.30.61` | wireless | migrated, verified |
| Hombli ceiling fan | `.30.63` | wireless | migrated, verified |
| OctoPrint | `.30.81` (wifi), `.30.80` (wired) | wireless now; mikrotik2 `ether24` tagged for when the wired cable is fixed | applied, device off |

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

The Amp, TV and Nintendo Switch all live on `users`, so the living room needs no managed
switch — one access port with `pvid=10` covers it. If buying the office PoE switch anyway,
consider moving mikrotik3 to the living room instead (5 ports covers uplink + 3 devices +
spare) and putting the new switch in the office; this also gets the TV off wireless.

OctoPrint's wired link is down (bad cable); it runs on `LEDCOM-IoT` wireless until fixed. The
workshop switch, when bought, needs to be VLAN-aware unless it ends up carrying only `iot`
devices — decide what else goes there before buying.

## Trunk and access port plan

Current state, all three devices:

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

## Migration reference

The commands below are what's actually live, kept as a runbook/reference — not a plan still
being executed. Full narrative (mistakes, root causes, evidence) is in `changelog.md`.

**Rollback pattern**, used for changes that could affect the current management session
(address moves, `vlan-filtering` toggles) — not needed for ordinary rule additions:

```
/system/scheduler/add name=rollback interval=5m on-event={
    /interface/bridge/set [find] vlan-filtering=no;
    /system/scheduler/remove rollback }
```
Make the change as a `/system/script`, not pasted interactively, so it completes server-side
even if the session drops. Remove the scheduler once confirmed working. **Never use safe
mode** — it silently discarded work twice on this network.

**VLAN interfaces, addressing, DHCP, NTP option 42** (mikrotik1):

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
    dns-server=192.168.20.40 domain=home.ledcom.fr dhcp-option=ntp-services
/ip/dhcp-server/network/add address=192.168.30.0/24 gateway=192.168.30.1 \
    dns-server=192.168.20.40 domain=home.ledcom.fr dhcp-option=ntp-iot

/ip/dhcp-server/option/add name=ntp-users    code=42 value=0xC0A80A01
/ip/dhcp-server/option/add name=ntp-services code=42 value=0xC0A81401
/ip/dhcp-server/option/add name=ntp-iot      code=42 value=0xC0A81E01
```

DHCP option 42 is unreliable in practice (see Decisions) — always verify NTP by hand on a
newly-migrated device rather than assuming it picked up the right server.

**`LEDCOM-IoT` SSID** on both CAPsMAN radios:

```
/caps-man/configuration/add name=caps_iot ssid=LEDCOM-IoT country=switzerland \
    security.authentication-types=wpa2-psk security.passphrase="<redacted>" \
    datapath.bridge=bridge-main datapath.vlan-id=30 datapath.vlan-mode=use-tag
/caps-man/provisioning/set [find] slave-configurations=caps_iot
/caps-man/remote-cap/provision [find]
```

**Per-device VLAN port move** is two commands, not one — bridge-vlan table membership and
`pvid` are separate:

```
/interface/bridge/vlan/set [find where vlan-ids=10] untagged=<full list, minus the port>
/interface/bridge/vlan/set [find where vlan-ids=20] untagged=<full list, plus the port>
/interface/bridge/port/set [find where interface=<port>] pvid=20
```
`untagged=` takes the full replacement list, not add/remove — for a long list, read and
rebuild it programmatically in the script rather than hand-retyping (see any `phase3-*`
script in git history for the pattern). `/ip/dhcp-server/network/set [find address=...]` is
confirmed buggy on this RouterOS version (silently matches nothing) — use the row's numeric
index instead, always `print` to confirm.

**Full firewall policy**, applied 2026-09-08:

```
# address lists
/ip/firewall/address-list/add list=iot-internet address=192.168.30.81 comment=octoprint-wifi
/ip/firewall/address-list/add list=iot-internet address=192.168.30.80 comment=octoprint-wired

# --- forward chain, in order, before the catch-all drop ---

# iot -> services: the one hole in containment
/ip/firewall/filter/add chain=forward action=accept connection-state=new in-interface=vlan-iot \
    out-interface=vlan-services dst-address=192.168.20.60 protocol=tcp dst-port=1883 \
    comment="iot: MQTT to HA"
/ip/firewall/filter/add chain=forward action=accept connection-state=new in-interface=vlan-iot \
    out-interface=vlan-services dst-address=192.168.20.40 port=53 protocol=udp \
    comment="iot: DNS to pi-hole"
/ip/firewall/filter/add chain=forward action=accept connection-state=new in-interface=vlan-iot \
    out-interface=vlan-services dst-address=192.168.20.40 port=53 protocol=tcp \
    comment="iot: DNS to pi-hole"

# ceiling fan: excluded from the DNS rule above (see Decisions) -- must sit
# before it to take precedence; disabled by default, see changelog.md
/ip/firewall/filter/add chain=forward action=drop protocol=udp src-address=192.168.30.63 \
    dst-address=192.168.20.40 in-interface=vlan-iot out-interface=vlan-services port=53 \
    disabled=yes comment="ceiling fan: drop DNS (udp)"
/ip/firewall/filter/add chain=forward action=drop protocol=tcp src-address=192.168.30.63 \
    dst-address=192.168.20.40 in-interface=vlan-iot out-interface=vlan-services port=53 \
    disabled=yes comment="ceiling fan: drop DNS (tcp)"

# iot -> internet: the named exception, then the wall
/ip/firewall/filter/add chain=forward action=accept connection-state=new in-interface=vlan-iot \
    src-address-list=iot-internet out-interface=ether1 protocol=tcp dst-port=80,443 \
    comment="iot exception: octoprint updates"
/ip/firewall/filter/add chain=forward action=drop in-interface=vlan-iot \
    log=yes log-prefix="iot-drop" comment="iot: deny everything else"

# services -> internet: unconditional
/ip/firewall/filter/add chain=forward action=accept connection-state=new \
    in-interface=vlan-services out-interface=ether1 comment="services: internet"

# services -> iot: HA reaching device APIs, then the wall
/ip/firewall/filter/add chain=forward action=accept connection-state=new \
    in-interface=vlan-services out-interface=vlan-iot dst-port=80 protocol=tcp \
    comment="HA -> Tasmota/IotaWatt"
/ip/firewall/filter/add chain=forward action=accept connection-state=new \
    in-interface=vlan-services out-interface=vlan-iot dst-port=6668 protocol=tcp \
    comment="HA -> Tuya local (fan)"
/ip/firewall/filter/add chain=forward action=accept connection-state=new \
    in-interface=vlan-services out-interface=vlan-iot dst-port=6053 protocol=tcp \
    comment="HA -> ESPHome (IotaWatt)"
/ip/firewall/filter/add chain=forward action=drop in-interface=vlan-services \
    out-interface=vlan-users log=yes log-prefix="infra2users" comment="services: no users"

# services -> users: HA's MikroTik integration reaching mikrotik2/mikrotik3
/ip/firewall/address-list/add list=ha-mikrotik-targets address=192.168.10.2 comment=mikrotik2
/ip/firewall/address-list/add list=ha-mikrotik-targets address=192.168.10.3 comment=mikrotik3
/ip/firewall/filter/add chain=forward action=accept connection-state=new \
    src-address=192.168.20.60 dst-address-list=ha-mikrotik-targets protocol=tcp dst-port=8728 \
    in-interface=vlan-services out-interface=vlan-users \
    comment="HA MikroTik integration: services -> users API"

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
    out-interface=vlan-services log=yes log-prefix="users2services" comment="users2services"

# users -> iot: mgmt only
/ip/firewall/filter/add chain=forward action=accept connection-state=new \
    in-interface=vlan-users out-interface=vlan-iot src-address-list=mgmt \
    comment="mgmt hosts: iot"
/ip/firewall/filter/add chain=forward action=drop in-interface=vlan-users \
    out-interface=vlan-iot log=yes log-prefix="users2iot" comment="users2iot"

# input chain: NTP for iot
/ip/firewall/filter/add chain=input action=accept connection-state=new in-interface=vlan-iot \
    protocol=udp dst-port=123 comment="iot: NTP from gateway" \
    place-before=[find comment="Drop anything else!"]
```

The existing broad `Home can connect everywhere (vlan-users)` rule was deliberately left
untouched — every rule above is inserted before it, so `users -> internet` keeps working
unmodified while `users -> services/iot` now hits the narrow allows and logged drops first.

**mDNS repeat: deliberately off.** Tried for cross-VLAN discovery, found to have a confirmed
RouterOS defect (drops the reply to a proxied query — see `changelog.md` and README's
hard-won lessons), and explicitly not re-enabled. Any cross-VLAN mDNS consumer needs a static
IP-based address instead of a discovered one.

## Phase 5 — read the evidence, then tighten

After a week of normal use:

```
/log/print where message~"infra2users"
/log/print where message~"users2services"
/log/print where message~"users2iot"
/log/print where message~"iot-drop"
```

- Convert genuine hits into narrow rules, or confirm none and set `log=no`.
- Remove the temporary `users -> services tcp/1883` rule (added during Home Assistant's
  migration, superseded by the permanent `iot: MQTT to HA` rule).
- Full config review once OctoPrint/IotaWatt are verified — see
  [config-review.md](config-review.md#planned-full-config-review-once-the-vlan-migration-is-complete),
  in particular auditing every port-opening rule for `connection-state=new`.
- Confirm `iot-internet` still has exactly the OctoPrint entries — growth is the signal to
  give those devices their own VLAN instead.
- Narrow `services -> internet` from blanket allow to specific ports (DNS upstream for
  Pi-hole, HTTPS for HA) once actual needs are confirmed.
- Consider moving VLAN 10 to tagged-only on the trunks.

## Open technical question

**RB2011 hardware offload for VLAN filtering** — not checked whether bridge VLAN filtering is
offloaded to the switch chips; if not, forwarding moves to the 600 MHz single core. Watch CPU;
`performance.md` has the throughput baseline. No symptoms of exhaustion observed so far.
