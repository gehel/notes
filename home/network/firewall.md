# Firewall rules — current live state

Generated 2026-10-20 from `dumps/router.txt` (15:25 collection), after the RB5009 cutover and
the device rename. The rule tables are produced mechanically from the router's numbered
`/ip/firewall/filter/print`, `/ip/firewall/nat/print` and `/ipv6/firewall/filter/print`, so
the `#` column is RouterOS's print index at that moment. It shifts whenever a rule is added
above, so **find rules by comment, not by number**. Regenerate this file from a fresh dump after
any firewall change.

This is the actual ruleset, in evaluation order, not the design intent. For the intended policy
and its reasoning, see [vlan.md](vlan.md)'s policy matrix; for open issues,
[config-review.md](config-review.md). The ruleset was ported verbatim from the RB2011 (old
mikrotik1) in Phase 2 of [rb5009-migration.md](rb5009-migration.md). The only changes since then
are the WireGuard rules (already on mikrotik1 before), finding 36's `samsung-tv` list, and the
2026-10-20 clean-up (finding 39: `HA API access` renamed, the stray `log-prefix` removed).

**Since this was generated (2026-10-20 evening):** two `chain=input` accepts were added after rule
13, `DHCP server (vlan-services)` and `DHCP server (vlan-iot)` (finding 38). Every `#` from 14 on
is therefore 2 higher on the device until the next regeneration. On 2026-11-08, MotionEye's
HTTP/HTTPS exception went into `iot2internet` on IPv4 and IPv6, each just above the deny-all,
with the `motioneye` and `motioneye-v6` lists, then SMTP submission (587, Gmail) the same way
(rows marked `(+)` below). The same day, HA got
MotionEye's API and stream (`services2iot`, 8765 and 9081) and SSH (`.30.20` in `ssh-hosts`).
**On 2026-11-19 MotionEye was retired:** all of the above was removed (rows struck through
below). The Reolink camera `camera-garage` (`.30.21`) got one `services2iot` accept, HA -> TCP
80/443/554/1935/8000/9000 on the `camera-garage` list, just above the deny-all. It has no
internet exception. See `changelog.md`, 2026-11-19.
On the switches,
`ingress-filtering=yes` was set on every Ethernet/SFP port (S21, a bridge setting, not a
firewall rule).

RouterOS evaluates each chain top to bottom and stops at the first match, so **position is
part of the rule** — a correct-looking rule in the wrong place is a bug.

## Quick reference: what can reach what

`vlan-users` is VLAN 10, `vlan-services` VLAN 20, `vlan-iot` VLAN 30, all on the router's
`bridge-main`. `wireguard1` is the phone's VPN. Every cell below is exactly one jump chain, named
the same way:

| From \ To | internet | users | services | iot | router mgmt |
|---|---|---|---|---|---|
| **users** | allow (`users2internet`) | — | `mgmt` full; DNS (53, UDP+TCP); HA web (443) for everyone; DoT (853) rejected quietly (`users2services`) | `mgmt` full; everyone -> OctoPrint web UI (80) (`users2iot`) | `mgmt` list only, + NTP (123) to gateway |
| **services** | HTTPS from any host; HTTP (80) for `http-outbound` (HA); Pi-hole's own DNS (53) and DoT (853) (`services2internet`) | HA -> MikroTik API on `ha-mikrotik-targets` (8728), printer (631), Samsung TV (8002), `ssh-hosts` (22) (`services2users`) | — | HA -> Tuya (6668), Tasmota/IotaWatt (80), ESPHome (6053), Reolink `camera-garage` (80, 443, 554, 1935, 8000, 9000), `ssh-hosts` (22) (`services2iot`) | NTP (123) to gateway; HA API (8728) |
| **iot** | deny by default; ceiling fan silenced first; `octoprint` and `iotawatt` 80/443; `iotawatt` NTP (123) (`iot2internet`) | deny, logged (`iot2users`) | ceiling fan's DNS dropped first; Pi-hole DNS (53); MQTT to HA (1883); DoT rejected quietly (`iot2services`) | — | NTP (123) to gateway only |
| **wireguard** (phone) | as users (`users2internet`) | `mgmt` hosts only (`wireguard2users`; the phone is in `mgmt`) | as users (`users2services`) | as users (`users2iot`) | `mgmt` list (the phone is in it) |
| **internet** | — | — | HA HTTPS (443) via dst-nat only (`internet2services`) | — | WireGuard (UDP 51820) only |

**ICMP is not governed by the table.** The `ICMP` chain is reached from `forward` rule 22,
before the dispatch rules, so rate-limited ping works between every VLAN pair and to/from the
internet. This is a deliberate widening (Phase 5, see `changelog.md`).

## router — `chain=input`

| # | Action | Match | Comment |
|---|---|---|---|
| 1 | accept | `connection-state=established,related` | defconf: accept established,related |
| 2 | add-to-list `Syn_Flooder` | `tcp-flags=syn connection-limit=30,32 protocol=tcp in-interface-list=WAN` | Add Syn Flood IP to the list |
| 3 | drop | `src-address-list=Syn_Flooder in-interface-list=WAN` | Drop to syn flood list |
| 4 | add-to-list `Port_Scanner` | `protocol=tcp psd=21,3s,3,1 in-interface-list=WAN` | Port Scanner Detect |
| 5 | drop | `src-address-list=Port_Scanner in-interface-list=WAN` | Drop to port scan list |
| 6 | accept | `connection-state=new protocol=udp in-interface-list=WAN dst-port=51820` | Accept WireGuard road-warrior VPN |
| 7 | drop | `in-interface-list=WAN` | defconf: drop all from WAN |
| 8 | jump -> `ICMP` | `protocol=icmp` | Jump for icmp input flow |
| 9 | accept | `protocol=tcp src-address=192.168.20.60 dst-port=8728` | HA API access |
| 10 | accept | `src-address-list=mgmt` | mgmt hosts to router |
| 11 | accept | `protocol=udp port=53` | Accept DNS - UDP |
| 12 | accept | `protocol=tcp port=53` | Accept DNS - TCP |
| 13 | accept | `protocol=udp in-interface=vlan-users dst-port=67` | DHCP server (vlan-users) |
| (+) | accept | `protocol=udp in-interface=vlan-services dst-port=67` | DHCP server (vlan-services), added 2026-10-20 |
| (+) | accept | `protocol=udp in-interface=vlan-iot dst-port=67` | DHCP server (vlan-iot), added 2026-10-20 |
| 14 | accept | `connection-state=new protocol=udp in-interface=vlan-services dst-port=123` | services: NTP from gateway |
| 15 | accept | `connection-state=new protocol=udp in-interface=vlan-users dst-port=123` | users: NTP from gateway |
| 16 | accept | `connection-state=new protocol=udp in-interface=vlan-iot dst-port=123` | iot: NTP from gateway |
| 17 | drop | *(none, catch-all)* | Drop anything else! |

## router — `chain=forward`

| # | Action | Match | Comment |
|---|---|---|---|
| 18 | fasttrack-connection | `connection-state=established,related` | defconf: fasttrack |
| 19 | accept | `connection-state=established,related` | defconf: accept established,related |
| 20 | add-to-list `Syn_Flooder` | `tcp-flags=syn connection-nat-state=dstnat connection-limit=30,32 protocol=tcp in-interface-list=WAN` | Syn flood detect - any forwarded port |
| 21 | drop | `src-address-list=Syn_Flooder in-interface-list=WAN` | Drop syn flooders - inbound |
| 22 | jump -> `ICMP` | `protocol=icmp` | Jump for icmp forward flow |
| 23 | drop | `dst-address-list=bogons` | Drop to bogon list |
| 24 | add-to-list `spammers` | `connection-limit=30,32 protocol=tcp dst-port=25,587 limit=30/1m,0` | Add Spammers to the list for 3 hours |
| 25 | drop | `protocol=tcp src-address-list=spammers dst-port=25,587` | Avoid spammers action |
| 26 | drop | `connection-state=invalid` | defconf: drop invalid |
| 27 | jump -> `users2internet` | `in-interface=vlan-users out-interface-list=WAN` | dispatch: users -> internet |
| 28 | jump -> `users2services` | `in-interface=vlan-users out-interface=vlan-services` | dispatch: users -> services |
| 29 | jump -> `users2iot` | `in-interface=vlan-users out-interface=vlan-iot` | dispatch: users -> iot |
| 30 | jump -> `services2internet` | `in-interface=vlan-services out-interface-list=WAN` | dispatch: services -> internet |
| 31 | jump -> `services2users` | `in-interface=vlan-services out-interface=vlan-users` | dispatch: services -> users |
| 32 | jump -> `services2iot` | `in-interface=vlan-services out-interface=vlan-iot` | dispatch: services -> iot |
| 33 | jump -> `iot2internet` | `in-interface=vlan-iot out-interface-list=WAN` | dispatch: iot -> internet |
| 34 | jump -> `iot2users` | `in-interface=vlan-iot out-interface=vlan-users` | dispatch: iot -> users |
| 35 | jump -> `iot2services` | `in-interface=vlan-iot out-interface=vlan-services` | dispatch: iot -> services |
| 36 | jump -> `internet2services` | `connection-nat-state=dstnat out-interface=vlan-services in-interface-list=WAN` | dispatch: internet -> services |
| 37 | jump -> `users2internet` | `in-interface=wireguard1 out-interface-list=WAN` | dispatch: wireguard -> internet |
| 38 | jump -> `users2services` | `in-interface=wireguard1 out-interface=vlan-services` | dispatch: wireguard -> services |
| 39 | jump -> `users2iot` | `in-interface=wireguard1 out-interface=vlan-iot` | dispatch: wireguard -> iot |
| 40 | jump -> `wireguard2users` | `in-interface=wireguard1 out-interface=vlan-users` | dispatch: wireguard -> users |
| 41 | drop | *(none, catch-all)* | Drop all other forward traffic |

Rules 20-26 (syn-flood, ICMP jump, bogons, spammers, invalid) sit ahead of the dispatch rules on
purpose: behind them, the dispatch jumps' unconditional termination made them dead (Phase 5).
Every dispatch jump (27-40) matches an interface on both sides. The wireguard jumps (37-39) reuse
the `users*` chains, so the phone gets exactly the `users` policy, and 40 sends it into its
own `wireguard2users` (mgmt hosts only).

## router — `chain=ICMP` and `chain=output`

| # | Action | Match | Comment |
|---|---|---|---|
| 42 | accept | `protocol=icmp icmp-options=8:0 limit=10,50:packet` | Echo request - Avoiding Ping Flood |
| 43 | accept | `protocol=icmp icmp-options=0:0` | Echo reply |
| 44 | accept | `protocol=icmp icmp-options=11:0` | Time Exceeded |
| 45 | accept | `protocol=icmp icmp-options=3:0-1` | Destination unreachable |
| 46 | accept | `protocol=icmp icmp-options=3:4` | PMTUD |
| 47 | drop | `protocol=icmp` | Drop to the other ICMPs |

| # | Action | Match | Comment |
|---|---|---|---|
| 48 | jump -> `ICMP` | `protocol=icmp` | Jump for icmp output |

## router — jump chains

Dispatched from `chain=forward` rules 27-40. Every accept declares `connection-state=new`.
Every chain except `users2internet` and `internet2services` ends in a logged deny-all whose
`log-prefix` is the chain name, for `dump-logs.sh` review.

**`users2internet`**

| # | Action | Match | Comment |
|---|---|---|---|
| 49 | accept | `connection-state=new` | users2internet: internet |

**`users2services`**

| # | Action | Match | Comment |
|---|---|---|---|
| 61 | accept | `connection-state=new src-address-list=mgmt` | users2services: mgmt hosts full |
| 62 | accept | `connection-state=new protocol=udp dst-address=192.168.20.40 port=53` | users2services: DNS (UDP) |
| 63 | accept | `connection-state=new protocol=tcp dst-address=192.168.20.40 dst-port=53` | users2services: DNS (TCP) |
| 64 | accept | `connection-state=new protocol=tcp dst-address=192.168.20.60 dst-port=443` | users2services: HA web |
| 65 | reject (tcp-reset) | `protocol=tcp dst-address=192.168.20.40 dst-port=853` | users2services: reject DoT probe (853), quiet |
| 66 | drop, logged | *(none, catch-all)* | users2services: deny everything else |

**`users2iot`**

| # | Action | Match | Comment |
|---|---|---|---|
| 67 | accept | `connection-state=new src-address-list=mgmt` | users2iot: mgmt hosts full |
| 68 | accept | `connection-state=new protocol=tcp dst-address-list=octoprint dst-port=80` | users2iot: everyone -> octoprint web UI |
| 69 | drop, logged | *(none, catch-all)* | users2iot: deny everything else |

**`services2internet`**

| # | Action | Match | Comment |
|---|---|---|---|
| 50 | accept | `connection-state=new protocol=tcp dst-port=443` | services2internet: HTTPS from any services host |
| 51 | accept | `connection-state=new protocol=udp src-address=192.168.20.40 dst-port=53` | services2internet: Pi-hole's own upstream DNS |
| 52 | accept | `connection-state=new protocol=tcp src-address=192.168.20.40 dst-port=53` | services2internet: Pi-hole's own upstream DNS (TCP) |
| 53 | accept | `connection-state=new protocol=tcp src-address=192.168.20.40 dst-port=853` | services2internet: Pi-hole's own upstream DNS-over-TLS |
| 54 | accept | `connection-state=new protocol=tcp src-address-list=http-outbound dst-port=80` | services2internet: HTTP exception (http-outbound list) |
| 55 | drop, logged | *(none, catch-all)* | services2internet: deny everything else |

**`services2users`**

| # | Action | Match | Comment |
|---|---|---|---|
| 70 | accept | `connection-state=new protocol=tcp src-address=192.168.20.60 dst-address-list=ha-mikrotik-targets dst-port=8728` | services2users: HA MikroTik integration API |
| 71 | accept | `connection-state=new protocol=tcp src-address=192.168.20.60 dst-address=192.168.10.110 dst-port=631` | services2users: HA -> printer (CUPS) |
| 72 | accept | `connection-state=new protocol=tcp src-address=192.168.20.60 dst-address-list=samsung-tv dst-port=8002` | services2users: HA -> Samsung TV |
| 73 | accept | `connection-state=new protocol=tcp src-address=192.168.20.60 dst-address-list=ssh-hosts dst-port=22` | services2users: HA SSH (ssh-hosts list) |
| 74 | drop, logged | *(none, catch-all)* | services2users: deny everything else |

**`services2iot`**

| # | Action | Match | Comment |
|---|---|---|---|
| 75 | accept | `connection-state=new protocol=tcp src-address=192.168.20.60 dst-port=6668` | services2iot: HA -> Tuya local (fan) |
| 76 | accept | `connection-state=new protocol=tcp src-address=192.168.20.60 dst-port=80` | services2iot: HA -> Tasmota/IotaWatt |
| 77 | accept | `connection-state=new protocol=tcp src-address=192.168.20.60 dst-port=6053` | services2iot: HA -> ESPHome (IotaWatt) |
| 78 | accept | `connection-state=new protocol=tcp src-address=192.168.20.60 dst-address-list=ssh-hosts dst-port=22` | services2iot: HA SSH (ssh-hosts list) |
| ~~(+)~~ | ~~accept~~ | ~~`... dst-address-list=motioneye dst-port=8765,9081`~~ | ~~services2iot: HA -> motioneye API + stream~~, removed 2026-11-19 |
| (+) | accept | `connection-state=new protocol=tcp src-address=192.168.20.60 dst-address-list=camera-garage dst-port=80,443,554,1935,8000,9000` | services2iot: HA -> camera-garage (Reolink), added 2026-11-19 |
| 79 | drop, logged | *(none, catch-all)* | services2iot: deny everything else |

**`iot2internet`**

| # | Action | Match | Comment |
|---|---|---|---|
| 56 | drop | `src-address=192.168.30.63` | iot2internet: ceiling fan phone-home (silenced, expected) |
| 57 | accept | `connection-state=new protocol=tcp src-address-list=octoprint dst-port=80,443` | iot2internet: octoprint updates exception |
| 58 | accept | `connection-state=new protocol=tcp src-address-list=iotawatt dst-port=80,443` | iot2internet: iotawatt firmware updates exception |
| 59 | accept | `connection-state=new protocol=udp src-address-list=iotawatt dst-port=123` | iot2internet: iotawatt NTP exception |
| ~~(+)~~ | ~~accept~~ | ~~`... src-address-list=motioneye dst-port=80,443` and `dst-port=587`~~ | ~~iot2internet: motioneye HTTP/HTTPS exception, SMTP submission~~, both removed 2026-11-19 |
| 60 | drop, logged | *(none, catch-all)* | iot2internet: deny everything else |

**`iot2users`**

| # | Action | Match | Comment |
|---|---|---|---|
| 80 | drop, logged | *(none, catch-all)* | iot2users: deny everything else |

**`iot2services`**

| # | Action | Match | Comment |
|---|---|---|---|
| 81 | drop | `protocol=udp src-address=192.168.30.63 dst-address=192.168.20.40 port=53` | iot2services: ceiling fan drop DNS (udp) |
| 82 | accept | `connection-state=new protocol=udp dst-address=192.168.20.40 port=53` | iot2services: DNS to pi-hole (udp) |
| 83 | accept | `connection-state=new protocol=tcp dst-address=192.168.20.40 dst-port=53` | iot2services: DNS to pi-hole (tcp) |
| 84 | accept | `connection-state=new protocol=tcp dst-address=192.168.20.60 dst-port=1883` | iot2services: MQTT to HA |
| 85 | reject (tcp-reset) | `protocol=tcp dst-address=192.168.20.40 dst-port=853` | iot2services: reject DoT probe (853), quiet |
| 86 | drop, logged | *(none, catch-all)* | iot2services: deny everything else |

**`internet2services`**

| # | Action | Match | Comment |
|---|---|---|---|
| 87 | accept | `connection-state=new connection-nat-state=dstnat protocol=tcp dst-address=192.168.20.60 dst-port=443` | internet2services: Home Assistant HTTPS |

**`wireguard2users`**

| # | Action | Match | Comment |
|---|---|---|---|
| 88 | accept | `connection-state=new src-address-list=mgmt` | wireguard2users: mgmt hosts full |
| 89 | drop, logged | *(none, catch-all)* | wireguard2users: deny everything else |

`internet2services` has no deny-all: its dispatch jump (36) is already scoped to
`connection-nat-state=dstnat` plus `WAN`/`vlan-services`.

## router — NAT

| # | Chain | Action | Match | Comment |
|---|---|---|---|---|
| 0 | `srcnat` | masquerade | `out-interface-list=WAN` |  |
| 1 | `dstnat` | dst-nat -> `192.168.20.60:443` | `protocol=tcp in-interface-list=WAN dst-port=443` | Home Assistant - HTTPS |


Rule 1 pairs with the `internet2services` dispatch (36) and its accept (87). **It has no
`dst-address=`** on purpose (since 2026-09-11): matching `in-interface-list=WAN` survives any
WAN address change, which is what let the cutover move the DMZ host to `192.168.1.103` with no
rule change. IPv6 has one more NAT rule, the NAT66 masquerade (below).

## router — address lists in use

| List | Members | Purpose |
|---|---|---|
| `mgmt` | router (`.10.1`), switch-main, switch-office, ap-main, switch-livingroom, `.10.6` (router staging address, until the rollback week ends), desktop, x1 (work laptop, was gimli), legolas (kid's laptop, `.10.94`), phone and x1 (via `wireguard1`) | full management access. Separate gate: each device's `admin` user has its own `address=` restriction |
| `ha-mikrotik-targets` | switch-main, switch-office, ap-main, switch-livingroom | HA's MikroTik integration (8728) through `services2users`. ap-main and switch-livingroom were added 2026-10-20. The router itself is reached through `chain=input` |
| `octoprint` | OctoPrint wired (`.30.80`) and wifi (`.30.81`) | exception to `iot2internet` and `users2iot` |
| `iotawatt` | IotaWatt (`.30.50`) | exception to `iot2internet` (firmware updates, NTP) |
| `camera-garage` | Reolink W320 garage camera (`.30.21`), added 2026-11-19 | destination of `services2iot`'s HA -> camera-garage (Reolink). No internet exception. (Replaces `motioneye`, removed 2026-11-19.) |
| `http-outbound` | Home Assistant (`.20.60`) | exception to `services2internet`'s HTTPS-only policy |
| `ssh-hosts` | desktop, OctoPrint wired and wifi (MotionEye removed 2026-11-19) | HA's SSH monitoring, used by `services2users` and `services2iot` |
| `samsung-tv` | TV wired (`.10.50`) and wifi (`.10.51`) | finding 36's fix: HA -> TV (8002) |
| `bogons` | RFC 1918/3330 ranges; `10.0.0.0/8`, `192.168.0.0/16` and `224.0.0.0/4` disabled | `forward` rule 23 |
| `Syn_Flooder`, `Port_Scanner`, `spammers` | dynamic, filled at runtime | anti-abuse |

`WAN` is an interface list holding `ether1`, so the firewall never names the WAN port directly.
Separately, `/ip/dns/static` holds one `<hostname>.home.ledcom.fr` entry per bound DHCP lease
(`dhcp-to-dns` comment, set by the `lease-script`); not reproduced here.

## router — IPv6 firewall

| # | Chain | Action | Match | Comment |
|---|---|---|---|---|
| 0 | `input` | accept | `connection-state=established,related,untracked` | defconf: accept established, related, untracked |
| 1 | `input` | drop | `connection-state=invalid` | defconf: drop invalid |
| 2 | `input` | accept | `protocol=icmpv6` | defconf: accept ICMPv6 |
| 3 | `input` | accept | `protocol=udp src-address=fe80::/10 dst-port=546` | defconf: accept DHCPv6-Client prefix delegation |
| 4 | `forward` | accept | `connection-state=established,related,untracked` | defconf: accept established, related, untracked |
| 5 | `forward` | drop | `connection-state=invalid` | defconf: drop invalid |
| 6 | `forward` | drop | `src-address-list=bad_ipv6` | defconf: drop packets with bad src ipv6 |
| 7 | `forward` | drop | `dst-address-list=bad_ipv6` | defconf: drop packets with bad dst ipv6 |
| 8 | `forward` | drop | `protocol=icmpv6 hop-limit=equal:1` | defconf: rfc4890 drop hop-limit=1 |
| 9 | `forward` | accept | `protocol=icmpv6` | defconf: accept ICMPv6 |
| 10 | `input` | drop | *(none, catch-all)* | drop everything else to router |
| 11 | `forward` | jump -> `users2internet` | `in-interface=vlan-users out-interface-list=WAN` | dispatch: users -> internet |
| 12 | `forward` | jump -> `services2internet` | `in-interface=vlan-services out-interface-list=WAN` | dispatch: services -> internet |
| 13 | `forward` | jump -> `services2users` | `in-interface=vlan-services out-interface=vlan-users` | dispatch: services -> users |
| 14 | `forward` | jump -> `iot2internet` | `in-interface=vlan-iot out-interface-list=WAN` | dispatch: iot -> internet |
| 15 | `forward` | drop | *(none, catch-all)* | drop inbound from WAN |
| 16 | `users2internet` | accept | `connection-state=new` | users2internet: internet |
| 17 | `services2internet` | accept | `connection-state=new protocol=tcp dst-port=443` | services2internet: HTTPS |
| 18 | `services2internet` | accept | `connection-state=new protocol=udp src-address-list=pihole-v6 dst-port=53` | services2internet: Pi-hole's own upstream DNS |
| 19 | `services2internet` | accept | `connection-state=new protocol=tcp src-address-list=pihole-v6 dst-port=53` | services2internet: Pi-hole's own upstream DNS (TCP) |
| 20 | `services2internet` | accept | `connection-state=new protocol=tcp src-address-list=pihole-v6 dst-port=853` | services2internet: Pi-hole's own upstream DNS-over-TLS |
| 21 | `services2internet` | accept | `connection-state=new protocol=tcp src-address-list=http-outbound-v6 dst-port=80` | services2internet: HTTP exception (http-outbound-v6 list) |
| 22 | `services2internet` | drop, logged | *(none, catch-all)* | services2internet: deny everything else |
| 23 | `services2users` | accept | `connection-state=new protocol=tcp src-address-list=ha-v6 dst-port=631` | services2users: HA -> printer (CUPS) |
| 24 | `services2users` | accept | `connection-state=new protocol=tcp src-address-list=ha-v6 dst-port=8002` | services2users: HA -> Samsung TV |
| 25 | `services2users` | drop, logged | *(none, catch-all)* | services2users: deny everything else |
| 26 | `iot2internet` | accept | `connection-state=new protocol=tcp src-address-list=octoprint-v6 dst-port=80,443` | iot2internet: octoprint updates |
| ~~(+)~~ | ~~`iot2internet`~~ | ~~accept~~ | ~~`... src-address-list=motioneye-v6`, 80/443 and 587~~ | ~~iot2internet: motioneye HTTP/HTTPS, SMTP submission~~, both removed 2026-11-19 |
| 27 | `iot2internet` | drop, logged | *(none, catch-all)* | iot2internet: deny everything else |


IPv6 NAT: one rule, `chain=srcnat action=masquerade out-interface=ether1`, comment
`workaround: Internet-Box will not route delegated prefix` (see [ipv6.md](ipv6.md#why-nat66)).

IPv6 address lists (EUI-64 addresses in `2a02:1210:7621:9ac0::/58`, recomputed before the
cutover): `pihole-v6` (Pi-hole on `9ac1`), `ha-v6` and `http-outbound-v6` (HA on `9ac1`),
`octoprint-v6` (OctoPrint wired and wifi on `9ac2`), ~~`motioneye-v6`~~ (MotionEye, removed 2026-11-19), plus defconf's `bad_ipv6`.

Notes:
- **No router management over IPv6.** SLAAC gives no stable per-host address to scope a `mgmt`
  list against, so input drops everything except established, ICMPv6 and DHCPv6-PD.
- **The EUI-64 lists only match if IPv6 privacy extensions are off on the host** (fixed on
  Pi-hole and OctoPrint 2026-09-11, on HA 2026-09-15, finding 31). If a list stops matching real
  traffic, check that first. If the delegated prefix changes, recompute the lists.
- `services2users` is narrower than its IPv4 twin: it scopes by port only, not by the
  printer's or TV's own address.
- No `services2iot`, `iot2services` or `iot2users` chains: that traffic falls to the forward
  catch-all, the same outcome as an explicit deny. No wireguard dispatch either: the tunnel
  carries IPv4 only.

## Switches and ap-main — `chain=input`

The same input chain on switch-main, switch-office, ap-main and switch-livingroom (2026-10-20
dumps). They are pure L2 devices with `disable-ipv6=yes`, so there is no NAT and no IPv6 filter:

| # | Action | Match | Comment |
|---|---|---|---|
| — | accept | `connection-state=established,related` | established |
| — | drop | `connection-state=invalid` | drop invalid |
| — | accept | `protocol=icmp` | ICMP |
| — | accept | `src-address-list=mgmt` | mgmt hosts to device |
| — | accept | `protocol=tcp src-address=192.168.20.60 dst-port=8728` | HA API access |
| — | drop | *(none, catch-all)* | drop everything else |

switch-main and switch-office also have three defconf `chain=forward` rules (established,
related, invalid) in front. They never match: the bridges have `use-ip-firewall=no`, so bridged
traffic skips the IP firewall. switch-livingroom's six router-style forward rules and its IPv6
filter were removed on 2026-10-20 (S19). Each device's `mgmt` list holds the same 11 addresses as
the router's.
