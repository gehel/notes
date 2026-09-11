# IPv6 on the MikroTik home network

Configured 2026-09-03. Front router is a MikroTik running RouterOS 7.23.3 (now 7.24.2).

**Moved from `bridge-main` to `vlan-users` on 2026-09-07** — see
[Migrated onto `vlan-users`](#migrated-onto-vlan-users) below.

## Current state

IPv6 is addressed and firewalled on all three VLANs, verified end-to-end from real clients on
each (finding 21, closed 2026-09-11 — see
[Extending to every VLAN](#extending-to-every-vlan-finding-21) below) — via **NAT66**, not
native routing. This is a deliberate workaround, not an oversight — see
[Why NAT66](#why-nat66) below.

**The Internet-Box itself was replaced 2026-09-11** with a new, 10G-capable Swisscom box —
see [Internet-Box replacement](#internet-box-replacement-2026-09-11) below for what changed
and what broke.

| | |
|---|---|
| Upstream | Swisscom, native IPv6 via DHCPv6 (no PPPoE, no 6rd) |
| Topology | Swisscom Internet-Box → MikroTik `ether1` → `bridge-main` → `vlan-users`/`vlan-services`/`vlan-iot` → mikrotik2 + mikrotik3 (pure L2 bridges) → clients |
| Delegated prefix | `/58` from the Internet-Box via DHCPv6-PD as of 2026-09-11 (was `/62` on the old box), i.e. 64 × `/64` — one per VLAN, the rest spare |
| LAN prefixes | `vlan-users` `2a02:1210:7621:9a40::/64`, `vlan-services` `2a02:1210:7621:9a41::/64`, `vlan-iot` `2a02:1210:7621:9a42::/64` (all **illustrative**, see below), router at `::1` on each |
| Client addressing | SLAAC from RAs sent by the MikroTik on every VLAN |
| `bridge-fon` | removed entirely, along with the FON network — see `changelog.md`'s VLAN segmentation entry |
| DNS | clients use `192.168.10.40` (Pi-hole) over IPv4 — was leaking the ISP's own resolver via RDNSS until 2026-09-07, fixed; see `changelog.md` |

Prefix values are **not stable**. Swisscom's delegation to the Internet-Box can change, and
the box's delegation to us changes with it — confirmed the hard way on 2026-09-11, when a
router swap changed the delegated prefix entirely and broke both of finding 21's pinned
EUI-64 address-lists (`ha-v6`, `octoprint-v6`), exactly as the caveat below already warned.
Every address below is derived from the pool at runtime — nothing is hardcoded, and nothing
should be. The values quoted in this document are illustrative only and may already be stale.

## Why NAT66

The Internet-Box delegates a prefix over DHCPv6-PD and then does not deliver return traffic
to it. This is a documented limitation of the box: it has no static IPv6 route capability and
its cascaded-router support is incomplete.

The discriminating test, run on the MikroTik — this is the fastest way to re-confirm the
diagnosis if IPv6 breaks again:

```
/ping 2606:4700:4700::1111 count=3
# → works, sourced from the WAN SLAAC address inside the box's own /64

/ping 2606:4700:4700::1111 src-address=<LAN address from /ipv6/address/print> count=3
# → 100% loss, because the box does not route the prefix it delegated to us
```

Everything on the MikroTik side is correct: PD binds, the LAN is addressed from the pool,
RAs reach clients across both L2 bridges, and clients install a default route. Only the
return path is missing. NAT66 rewrites the source to the WAN address, which *is* routed,
so replies come back and conntrack un-NATs them.

Consequences to be aware of:

- No inbound connections to LAN hosts. No end-to-end addressing.
- Clients hold globally-scoped addresses that are not globally reachable.
- `curl -6 https://ifconfig.co` reports the router's WAN address, not the client's.
  That is the NAT working, not a fault.

## Working configuration

**Current as of 2026-09-07.** Interface names: `ether1` = WAN toward the Internet-Box,
`vlan-users` = LAN (VLAN 10, layered on `bridge-main` — see
[Migrated onto `vlan-users`](#migrated-onto-vlan-users)). The commands below are written for
the current, post-migration state; the original 2026-09-03 setup used `bridge-main` directly.

```
# IPv6 is disabled by default on this box — this is the master switch.
# There is no separate ipv6 package in RouterOS 7.
/ipv6/settings/set disable-ipv6=no

# A forwarding router ignores RAs by default. The WAN side needs them
# for its own address and default route.
/ipv6/settings/set accept-router-advertisements=yes

# Request a prefix from the Internet-Box.
# pool-prefix-length=64 is the slice size handed out from the pool, so a
# delegated /62 yields 4 usable /64s.
/ipv6/dhcp-client
add interface=ether1 request=prefix pool-name=swisscom-pd pool-prefix-length=64 \
    add-default-route=yes use-peer-dns=yes comment="PD from Internet-Box"

# Address the LAN from the pool. Use address=::1 — without it you get the
# all-zeros subnet-router anycast address, which is a poor router address.
/ipv6/address/add from-pool=swisscom-pd interface=vlan-users advertise=yes address=::1

# Send RAs on the LAN only. The * default ND entry covers interface=all,
# which would also advertise toward the Internet-Box; point it at the LAN
# instead of adding a second entry (the default entry cannot be deleted).
# advertise-dns=no: the router's own DNS list (including a dynamic entry
# learned from the Internet-Box's RA) must not reach clients via RDNSS,
# or it bypasses Pi-hole entirely — see changelog.md, fixed 2026-09-07.
/ipv6/nd/set [find default=yes] interface=vlan-users advertise-dns=no \
    managed-address-configuration=no other-configuration=no ra-lifetime=30m

# The workaround. Remove this line if the upstream is ever fixed.
/ipv6/firewall/nat/add chain=srcnat out-interface=ether1 action=masquerade \
    comment="workaround: Internet-Box will not route delegated prefix"
```

### Firewall

The RouterOS defconf IPv6 rules are the *permit* half of a ruleset. The deny half is absent
on a fresh install: both chains default to accept. IPv6 has no NAT to hide behind, so without
these three rules every LAN host is reachable from the internet.

```
/ipv6/firewall/filter
add chain=forward action=accept in-interface=vlan-users comment="LAN outbound"
add chain=input action=accept in-interface=vlan-users comment="LAN to router"
add chain=input action=drop comment="drop everything else to router"
add chain=forward action=drop comment="drop inbound from WAN"
```

The original `bridge-main`-referencing pair of rules (`LAN outbound`, `LAN to router`) are
still present and harmless — they simply never match anything now that LAN traffic arrives
via `vlan-users` instead. Not yet cleaned up.

These must sit **after** the defconf accepts. Order matters: the DHCPv6 client reply rule
(UDP 546 from `fe80::/10`) and the ICMPv6 accepts have to be matched before the drops, or
PD and neighbour discovery break.

Do not block ICMPv6. IPv6 has no in-path fragmentation, so filtering it breaks path-MTU
discovery — which shows up as large transfers hanging rather than failing cleanly.

Adding an input accept for another trusted interface must go before the input drop, or that
segment loses IPv6 access to the router. IPv4 management is unaffected either way, so this
cannot lock you out entirely.

### Why the LAN keeps a global prefix rather than ULA

ULA is the semantically honest choice behind NAT, but it would defeat the purpose here. Under
RFC 6724's default policy table, `fc00::/7` has precedence 3 while IPv4 has 35 — dual-stack
clients would prefer IPv4 for almost every destination and the IPv6 path would go unused.
Clients holding a global address prefer it over IPv4, which is what we want.

If stable internal addressing is needed for firewall rules or local DNS, add a ULA
*alongside* the global prefix, never instead of it.

## Migrated onto `vlan-users`

Done 2026-09-07, discovered as the fix for a real, if minor, outage. The VLAN segmentation
work in [vlan.md](vlan.md) moved the router's *IPv4* address and DHCP server off `bridge-main`
onto a `vlan-users` VLAN 10 sub-interface, but IPv6 was out of scope for that document and got
left behind on `bridge-main` — nobody planned to skip it, it just wasn't tracked anywhere.

The gap stayed invisible for a day because, before `vlan-filtering=yes` and the CAPsMAN
wireless-tagging fix landed, wireless clients were in enough of a broken, VLAN-mismatched
state that they could still incidentally reach `bridge-main`'s untagged RA. Once wireless was
*correctly* tagged into VLAN 10 (its own fix, see `vlan.md`), it could reach `vlan-users` (IPv4
DHCP, now working) but could no longer reach `bridge-main`'s RA at all — leaving Home
Assistant's OpenThread Border Router as the *only* IPv6 router visible to wireless clients.
That's a Thread/Matter border router doing its normal job — advertising the Thread mesh's
prefix (and a companion on-link ULA) onto the LAN via RA — not a bug on Home Assistant's side.
It just happened to be reachable when the router's real RA wasn't, so clients preferred or
outright adopted its non-routable ULA prefix instead of the real global one. Diagnosed by:
desktop WiFi held a valid IPv6 address but `ping6` to a real host failed with "Network is
unreachable" — the signature of holding only a ULA with no route to the internet, and the two
prefixes traced to `d8:3a:dd:31:e0:59` (`192.168.1.60`, Home Assistant) via `wpan0`'s own
address matching one of them exactly and `ip -6 neigh show` flagging that MAC `router`.

The pre-existing "possible rogue RA source" note in `config-review.md` — the desktop had
briefly held this same ULA on its *wired* NIC days earlier — turned out to be the same root
cause, present since before this migration ever started; the VLAN work made it fully visible
on wireless rather than causing it.

Fixed the same way as the IPv4 migration: address, RA (`/ipv6/nd`), and the two IPv6 firewall
rules referencing `bridge-main` all moved to `vlan-users`. Verified: desktop's WiFi picked up
the real `2a02:1210:680f:c40c::/64` prefix as primary, the old ULA aged out on its own as
`deprecated`/`preferred_lft 0` (the same graceful-expiry behavior already documented under
"Stale prefix on clients after renumbering" below), and `ping6` to a real host succeeded.

## Extending to every VLAN (finding 21)

Started 2026-09-10. `vlan-users` had IPv6 from the start; `vlan-services` and `vlan-iot` never
got it, so their firewall silently fell through to catch-all drops instead of a deliberate
policy — [config-review.md](config-review.md)'s finding 21. Rolling out one VLAN at a time,
each with the same per-VLAN-pair dispatch shape the IPv4 firewall already uses (see
[firewall.md](firewall.md)). Full evidence for each phase is in `changelog.md`.

- **Phase 1, `vlan-users` (done).** Already had addressing; its firewall was two flat
  unscoped accepts. Restructured to match IPv4's shape, and closed an incidental gap along the
  way: router management (ssh/Winbox/API/www) was reachable from any `vlan-users` host over
  IPv6, with none of IPv4's `mgmt`-list scoping. Fixed by not exposing router management over
  IPv6 at all — SLAAC gives no stable per-host address to scope an address-list against, so
  "not exposed" is the honest equivalent rather than a leaky approximation.
- **Phase 2, `vlan-services` (done, verified 2026-09-11).** Got its own `/64` and RA, same
  pattern as `vlan-users`. Its IPv4 firewall scopes several rules to Home Assistant's own
  address specifically (`192.168.20.60`) — not reproducible directly under SLAAC, so Home
  Assistant's IPv6 address is pinned via a computed **EUI-64** address instead of a
  DHCP-style reservation: take its known LAN MAC (`D8:3A:DD:31:E0:59`, from
  `/ip dhcp-server lease`), flip the universal/local bit of the first byte, split around
  `ff:fe`, and append the result to the VLAN's actual `/64`. Held in the `ha-v6` IPv6
  address-list; Pi-hole's own (`pihole-v6`) followed the same recipe once its DNS exception
  was added (below). Two caveats that don't apply to IPv4's version of this scoping, **both
  of which turned out to be real, not just theoretical** — see
  [Privacy extensions broke the EUI-64 pinning](#privacy-extensions-broke-the-eui-64-pinning-2026-09-11)
  below:
  - Valid only as long as the host keeps IPv6 privacy extensions (RFC 4941 temporary
    addresses) off — otherwise it prefers a rotating source address for outbound connections
    and stops matching the address-list entirely.
  - The prefix half is Swisscom's current delegation, which this document already says is not
    stable — if it's ever re-delegated, every pinned entry needs recomputing. Happened once
    already, the same day this was built (see `changelog.md`'s Internet-Box replacement
    entry).

  `services2internet` (HTTP/HTTPS) is host-unscoped, matching IPv4's own rule 45, which isn't
  host-scoped either. Pi-hole's own upstream DNS/DoT exception (mirroring its IPv4 one) was
  added 2026-09-11 after the firewall log showed it repeatedly failing over IPv6 — the
  original "nothing needs it yet" assumption turned out wrong once real traffic was observed.
  `services2iot` still doesn't exist — `vlan-iot` doesn't need it.
- **Phase 3, `vlan-iot` (done, verified 2026-09-11).** Its own `/64` and RA, then a
  deny-by-default `iot2internet` chain with one named exception — OctoPrint, mirroring its
  existing IPv4 `octoprint` address-list, pinned via EUI-64 the same way as `ha-v6`
  (`octoprint-v6`, both its wifi and wired MACs). No `iot2services`/`iot2users` chains —
  nothing here needs IPv6 access to either, so both fall through to the general catch-all,
  same outcome as an explicit deny. This closes the accidentally-correct gap finding 21
  originally described for this VLAN, deliberately rather than by accident. Confirmed working
  via `ping -6`/`curl -6` from OctoPrint itself, once its own address was fixed to actually
  match `octoprint-v6` (below).

### Privacy extensions broke the EUI-64 pinning (2026-09-11)

Found while reviewing a firewall log the day after phase 2 shipped: Pi-hole's and OctoPrint's
*real* outbound IPv6 traffic used addresses that didn't match `pihole-v6`/`octoprint-v6` at
all — `2a02:...2f67:e1e2:25f2:be49` instead of Pi-hole's computed
`2a02:...ba27:ebff:fe83:7948`, for instance. Both hosts had IPv6 privacy extensions on,
contradicting the assumption made when this design was chosen ("likely already the default on
a Pi-hole/Debian install") — an assumption that was never actually verified against real
traffic until this log review. The address-list-scoped rules looked entirely correct on
`print` the whole time; only checking actual traffic revealed they'd never matched anything
real.

**Fixed per host** (Pi-hole, OctoPrint; Home Assistant not yet checked or fixed — no
`services2users`-triggering traffic has been observed from it to confirm either way):

```
sudo tee /etc/sysctl.d/99-disable-ipv6-privacy.conf <<'EOF'
net.ipv6.conf.all.use_tempaddr = 0
net.ipv6.conf.default.use_tempaddr = 0
net.ipv6.conf.all.addr_gen_mode = 0
net.ipv6.conf.default.addr_gen_mode = 0
EOF
sudo sysctl --system

# NetworkManager can override the sysctl on reconnect -- belt and suspenders
sudo nmcli connection modify <connection-name> ipv6.ip6-privacy 0 ipv6.addr-gen-mode eui64
sudo nmcli connection up <connection-name>
sudo reboot
```

`addr_gen_mode=0` matters as much as `use_tempaddr=0`: modern NetworkManager/systemd-networkd
defaults often use RFC 7217 "stable-privacy" addressing for the *permanent* address too — a
stable but non-MAC-derived hash, not classic EUI-64. Disabling only temporary addresses isn't
enough; the generation mode has to be forced to EUI-64 explicitly.

**Verified:** `ip -6 addr show scope global` on both hosts, post-reboot, now shows exactly the
precomputed EUI-64 address. Functional confirmation followed from each host directly
(`ping -6`/`curl -6` from OctoPrint; Pi-hole's `ping -6` — its DNS-over-v6 specifically wasn't
independently re-tested, `dig` wasn't available on the host tried, but the address match plus
the already-proven rule mechanism from phase 2's Pi-hole-exclusion test make this high
confidence, not a direct retest).

**If either address-list stops matching real traffic again, check privacy extensions before
the prefix** — this is now the second time an assumption about a "fixed appliance" host's own
network behavior turned out to need direct verification rather than being taken on faith.

## Internet-Box replacement (2026-09-11)

Swisscom Internet-Box replaced with a new, 10G-capable model. mikrotik1 is configured as its
DMZ host (no bridge/modem mode available on this box — checked). Two things broke, both fixed
same-day; full evidence in `changelog.md`.

1. **Home Assistant's remote HTTPS access.** The new box's LAN-side subnet is entirely
   different (`192.168.1.0/24` instead of the old `10.1.1.0/24`), so mikrotik1's WAN DHCP
   lease changed address — and the `dst-nat` rule for HA's HTTPS forward was hardcoded to the
   old one (`dst-address=10.1.1.101`), matching nothing afterward. Fixed by dropping
   `dst-address=` from the rule entirely, matching only on `in-interface-list=WAN
   protocol=tcp dst-port=443` — survives any future WAN IP change without needing to be
   touched again. The paired forward-chain rule (`internet2services: Home Assistant HTTPS`)
   was never affected: it matches on HA's real internal address plus
   `connection-nat-state=dstnat`, never on the WAN IP.
2. **IPv6 stopped working entirely.** The new box didn't answer DHCPv6-PD requests at all
   (`status=searching`, permanently) until prefix delegation was explicitly enabled in its own
   admin UI — plausibly because DMZ-hosting a client can make some consumer CPE treat it as
   "gets full pass-through" instead of "also gets a routable delegation," though this wasn't
   confirmed further. Even after enabling it, mikrotik1's DHCPv6 client needed an explicit
   `/ipv6/dhcp-client/release` to actually pick up the new lease rather than retrying its own
   stuck `searching` state. Once bound, the delegated prefix had changed entirely (a `/58` on
   a new `2a02:1210:7621:...` base, replacing the old `/62` on `2a02:1210:680f:...`) — which
   broke `ha-v6` and `octoprint-v6` (finding 21, phases 2-3) exactly as their own
   documentation warned it would. Recomputed and updated (same MACs, same EUI-64 method, new
   prefix) and reverified from Pi-hole.

One coincidence worth recording: the box's own admin UI reported the delegated prefix as a
`/56` on `2a02:1210:7621:9a00::/56` — which would have overlapped the WAN transit link's own
SLAAC `/64` (also `...9a00::/64`), a real collision risk if RouterOS's pool allocator had
handed that same `/64` to a LAN VLAN. The *actual* bound delegation
(`/ipv6/dhcp-client/print detail`) was a `/58` on `2a02:1210:7621:9a40::/58` — a different,
non-overlapping range. **Trust the router's own bound state over the box's admin UI when they
disagree.**

## Operational notes

**Stale prefix on clients after renumbering.** An earlier attempt had hardcoded
`2a02:1205:34dc:d053::1/64` on `bridge-main` with `advertise=yes`. When Swisscom's prefix
changed, clients kept advertising-derived addresses in a prefix that no longer routed. Clients
show these as `deprecated` with `preferred_lft 0` and stop using them for new connections;
they age out on their own, or `ip -6 addr del ... dev <iface>` clears them immediately. This
is the failure mode `from-pool=` exists to prevent.

**`ipv6-fasttrack-active: no`.** No IPv6 fasttrack rule, so all v6 traffic takes the full
firewall path. Fine at this line rate; only worth adding if throughput becomes a concern.

**The two downstream MikroTiks need no IPv6 configuration.** Both are pure L2 bridges, and
bridging forwards IPv6 frames regardless of whether the router's own IPv6 stack is enabled.
Verified clean on 2026-09-03: `igmp-snooping=no`, `use-ip-firewall=no`, no bridge filters,
`ra-guard=no`.

If IPv6 ever breaks *only* for clients behind them, check `igmp-snooping` first. In RouterOS 7
it covers MLD as well as IGMP, and with no MLD querier on the segment it can filter the
solicited-node multicast groups that neighbour discovery depends on. The failure mode is
deceptive: clients get a valid address from the RA, then cannot resolve the router's
link-local to a MAC, so everything times out and it looks like a routing or firewall problem.

## Verifying it works

On the MikroTik:

```
/ipv6/dhcp-client/print detail    # status=bound AND a non-empty prefix
/ipv6/pool/print
/ipv6/address/print               # LAN address present, FROM-POOL set, advertise=yes
/ipv6/route/print                 # active default route via the box's link-local
/ipv6/firewall/filter/print stats where comment~"LAN"
```

On a client:

```
ip -6 addr show scope global      # a global address in the current delegated prefix
ip -6 route show default          # via the MikroTik's bridge-main link-local
ping -6 -c 3 2606:4700:4700::1111
ping -6 -c 3 ipv6.google.com      # if this fails but the above works, it is DNS
ping -6 -c 3 -M do -s 1452 ipv6.google.com   # 1500-byte frame, DF set — checks path MTU
```

`status=searching` on the DHCPv6 client that never settles means the box is not answering
DHCPv6 at all. `bound` with an empty prefix means it answers but will not delegate.

## Migration path: MikroTik at the edge

The proper fix, and the only one giving native end-to-end IPv6 and the full `/56` to subnet
across both bridges. Swisscom supports third-party routers: DHCP on the WAN, no PPPoE,
VLAN 10 on the handoff. It also removes the IPv4 double-NAT as a side effect.

Everything above carries over. The migration is:

1. Delete the masquerade rule.
2. Point the DHCPv6 client at the new WAN interface.
3. Leave the `from-pool=` address and the ND entry untouched — they keep working.
4. Optionally add `bridge-fon` with a second `/64` from the pool.

The thing to plan around is Swisscom TV, which depends on the box and on ISP multicast.

## References

- [Swisscom community — Statische IPv6 Route mit Internet Box 4](https://community.swisscom.ch/t5/Router-Hardware/Statische-IPv6-Route-mit-Internet-Box-4/td-p/721529)
- [Swisscom community — Prefix Delegation](https://community.swisscom.ch/d/567232-prefix-delegation)
- [Swisscom community — IPv6 PD auf Fritzbox hinter InternetBox](https://community.swisscom.ch/t5/Archiv-Internet/IPv6-PD-auf-Fritzbox-hinter-InternetBox-Standard/td-p/490722)
- [Swiss IPv6 Council — Residential IPv6 at Swisscom (PDF)](https://www.swissipv6council.ch/sites/default/files/images/ipv6-residential-swisscom.pdf)
- [iway KB — IPv6 on VDSL and Swisscom fibre with DHCP](https://wiki.iway.ch/kb/wiki/Internet_Access/Internet_Access_Allgemein/IPv6/IPv6_auf_VDSL_und_Swisscom_Fiber_Anschl%C3%BCssen_mit_DHCP)