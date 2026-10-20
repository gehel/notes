# RB5009 edge migration — replacing mikrotik1

**Status: Phases 0-3 done, the RB5009 is the edge router since 2026-10-20. Phase 4 (clean-up)
in progress.** The devices were renamed on 2026-10-20: mikrotik6 is now `router`
(`router.home.ledcom.fr`, `.10.1`), and the README maps the other old names. This runbook keeps
the names it was written with: mikrotik1 is the RB2011, mikrotik6 the RB5009.

This document is the runbook for moving the edge role (routing, firewall, NAT, DHCP, DNS
forwarder, NTP, WireGuard, CAPsMAN, IPv6 PD) from mikrotik1 (RB2011UiAS-2HnD) onto it, with
the smallest possible disruption to the house. Hardware rationale is in
[config-review.md](config-review.md)'s "Hardware for the edge role"; this file only covers
*how* to do the swap.

Built from the 2026-10-09 11:00 dumps (`dumps/mikrotik1-main.txt` etc.). mikrotik1's config
had not changed since 2026-10-08 except the two TV reservations (`.10.50`/`.10.51`).
**Regenerate the dumps again right before Phase 1 and Phase 3.** They are snapshots.

## Resume here (written 2026-10-20, end of day)

**Phase 3 is done** (see `changelog.md`, "Phase 3: cutover from mikrotik1 to mikrotik6"). The
post-cutover review, the device rename and the doc pass are done too (`changelog.md`, 2026-10-20
entries; `config-review.md` round 4). State to rely on:

- `router` (RB5009) holds `.10.1`/`.20.1`/`.30.1`/`.50.1`, and `.10.6` until the rollback
  week ends. Its trunk is `ether2` → switch-main `ether1`. ap-main is on `ether3`, 1 Gbps, PoE.
- Internet-Box DMZ → `192.168.1.103`. IPv6 from `2a02:1210:7621:9ac0::/58`.
- The RB2011 is powered and off the LAN, with `wireguard1` still enabled (harmless, the DMZ no
  longer points at it). **Rollback until about 2026-10-27:** on the router
  `/system/script/run rollback`, plug the RB2011's `ether2-master` into switch-main `ether1`,
  point the DMZ back to `192.168.1.101`. The router's identity and comments changed since the
  cutover, but `rollback` only matches on what was left in place for it.
- Speed test: 865 Mbps down / 858 Mbps up (was 181 / 842 through the RB2011).

Next, in order:
1. **First, finding 40**: the router's log buffer holds under an hour. Fix HA's `samsungtv`
   host (finding 36) and raise `memory-lines` (commands in `config-review.md`), or this check
   sees nothing.
2. **2026-10-21: check 11's second half.** Run `dump-logs.sh` (now writes `logs/router.txt`)
   and review it. Expected noise: HA → `192.168.10.195:8002` (finding 36). There should be no
   old-prefix `9a41` IPv6 drops and no `dhcp-lease` script error (closes finding 37). Also check
   HA's lease for finding 38.
3. The remaining Phase 4 items below: the throughput/bufferbloat re-baseline, then the end of
   the rollback week.

## Strategy in one paragraph

The new router takes over **the exact same identity**: same LAN addresses (`.10.1`, `.20.1`,
`.30.1`, `.50.1`), same interface names (`vlan-users`/`vlan-services`/`vlan-iot`,
`wireguard1`, `ether1` = WAN, `bridge-main`), same firewall ruleset verbatim, same WireGuard
key, same SSH host key, same CAPsMAN certificate. No client, switch, AP, Pi-hole, Home
Assistant or phone config changes. The RB5009 is built and checked **in place, on the live
LAN, at `192.168.10.6` with every production service disabled**. **Both routers are connected
to the Internet-Box at the same time** (it has several LAN ports, Guillaume confirmed
2026-10-09). The RB5009 has its own WAN from day one, so it can be tested as a real router
by individual clients before it carries everyone. The cutover is then one script, one setting
in the box's UI (the DMZ host) and one cable move (mikrotik4): about **1-2 minutes without
routing, which includes DNS and internet**, and inbound access (HA HTTPS, WireGuard) down only
until the DMZ setting is changed. Rollback is "run `rollback`, plug mikrotik1's trunk back,
point the DMZ back", because mikrotik1 is never modified and keeps its WAN throughout.

### Why not move one VLAN at a time

Two routers on the WAN suggests a gradual migration, for example `iot` first. **Not
recommended.** A VLAN's gateway address can only live on one router. With VLANs split between
routers, all inter-VLAN traffic (DNS to Pi-hole on `services` is used by every VLAN) would
have to cross a new transit link between the two routers, the firewall policy would be split
across two boxes, and return traffic could take a different path from the outbound traffic.
That is exactly the conntrack "established traffic seen as `new`" failure class that findings
28/33 are still chasing. The short single cutover is less disruptive than a long split state.
What two WANs *do* give cheaply is **per-client opt-in testing** (Phase 2b): any one test
host can use the RB5009 as its gateway while everyone else stays on mikrotik1.

## What is *not* changing (correcting an older expectation)

[ipv6.md](ipv6.md)'s "Migration path: MikroTik at the edge" assumed the Internet-Box would go
into bridge mode. **The current box has no bridge/modem mode** (checked 2026-09-11, see
`config-review.md`). The RB5009 therefore still sits behind the box as its DMZ host:

- IPv4 double NAT **stays**.
- NAT66 **stays**. The box still won't route the delegated prefix back to us. Port the
  `ipv6 firewall nat` masquerade rule as-is.
- The "TLS question" in `config-review.md` stays parked for the same reason.

What does change: CPU headroom (fasttrack/QoS/WireGuard), Gigabit to mikrotik4 with PoE
(`ether10` on the RB2011 is Fast-Ethernet-only), a 2.5G WAN port, and an arm64 box that can run
the new `/interface/wifi/capsman` next to the legacy `/caps-man` (target B3, `wifi.md`).

## Before starting: things found in the 2026-10-09 dumps

1. **mikrotik5 is down.** `dump-configs.sh` got `UNREACHABLE on port 22` for it, and on
   mikrotik2 `ether12-slave-local` is not running (no `R` flag, its bridge port shows
   `I` (inactive)). The TV and everything else in the living room is off the wired network.
   Most likely physical: the spare patch cable was pulled, mikrotik5 lost power, or the cable
   is unplugged. **Fix this before the migration** so the post-cutover checks cover all five
   devices.
2. **mikrotik1's own 2.4 GHz radio is not running.** `ap-MikroTik-1` has 26 link-downs and
   has been down since 2026-10-08 17:30. `ap-MikroTik-1-1` (`LEDCOM-IoT` on the same radio)
   has **564 link-downs**. Only mikrotik2's radio (`ap-MikroTik-Switch-1*`) has clients.
   Nothing in `changelog.md` covers this. It matters here because the RB5009 has no radio:
   losing mikrotik1 loses nothing that works today. But it also means the RB2011's radio
   should not be relied on if it is redeployed as a CAP (Phase 5).
3. **OSPF instances and an `ovpn-server1` entry are back in mikrotik1's export**, although
   `changelog.md` records both as removed on 2026-09-04. Not investigated. **Do not port
   them** either way.
4. `README.md` said the upstream box is at `10.1.1.1`. That is the old box. The current box's
   LAN is `192.168.1.0/24`: mikrotik1 holds `192.168.1.101` on `ether1` and its gateway is
   `192.168.1.1`. Corrected in `README.md` at the same time as this plan was written.

## Port plan

RB5009UPr+S+IN: `ether1` is 2.5G, `ether2`-`ether8` are Gigabit, `sfp-sfpplus1` is 10G SFP+.
PoE-out is available on the RJ45 ports. **Confirm the real port names from the box's own
`/interface/print` before writing any script.** The names below are expected, not verified.

| RB5009 port | Role | PVID | Tagged | PoE-out | Replaces mikrotik1 |
|---|---|---|---|---|---|
| `ether1` | WAN → Internet-Box (2.5G) | — (not bridged) | — | **off** | `ether1` |
| `ether2` | trunk → mikrotik2 | 10 | 20, 30 | **off** | `ether2-master` |
| `ether3` | mikrotik4 (cAP XL ac) | 10 | 30 | **auto-on** | `ether10` |
| `ether4`-`ether8` | unused, `users` access | 10 | — | **off** | `ether3`-`ether9` |
| `sfp-sfpplus1` | unused | 10 | — | n/a | `sfp1` |

**Set `poe-out=off` explicitly on every port except `ether3`**, then
`/interface/ethernet/poe/print` to confirm. The reason is the same one recorded in
`config-review.md` for the office switch: never leave PoE on ports that serve non-PoE devices.
Before relying on `auto-on`, check the PoE mode the RB5009UPr+S+IN offers against what the
cAP XL ac accepts (`/interface/ethernet/poe/monitor ether3` after connecting).

`ether3` keeps VLAN 30 tagged only to match mikrotik1's `ether10` today. mikrotik4 does not
serve `LEDCOM-IoT` (`wifi.md`), so this is harmless but unused.

## Phase 0 — prepare (no network impact)

- [ ] Fix mikrotik5 (finding 1 above). Regenerate `dumps/` and confirm all five devices answer.
- [ ] `scripts/fetch-backups.sh`, then take a **sensitive** export of mikrotik1 for the secrets
      that `hide-sensitive` strips. Save it under `backups/` (gitignored), never in git:
      ```
      /export show-sensitive file=mikrotik1-pre-rb5009
      ```
      It provides: the WireGuard private key, the CAPsMAN `LEDCOM`/`LEDCOM-IoT` passphrases,
      and SNMP/other secrets. **User passwords are never exported.** Have the `admin`
      password and the `homeassistant` password (Home Assistant's MikroTik integration uses
      it) ready separately. If the `homeassistant` password is not known, plan to set a new
      one and update the HA integration in Phase 4.
- [ ] Export the material that is easier to move than to recreate:
      ```
      /ip/ssh/export-host-key key-file-prefix=m1-hostkey
      /certificate/export-certificate CAPsMAN-CA-E48D8C196F30 type=pkcs12 export-passphrase=<tmp>
      /certificate/export-certificate CAPsMAN-E48D8C196F30   type=pkcs12 export-passphrase=<tmp>
      ```
      Copy these files off with `scp`, then remove them from mikrotik1's `/file`.
      - **SSH host key:** keeps `known_hosts` valid for `router1.home.ledcom.fr`, so
        `dump-configs.sh` and friends need no change.
      - **CAPsMAN certificate:** mikrotik2's CAP has
        `caps-man-certificate-common-names=CAPsMAN-E48D8C196F30`, which pins it to
        mikrotik1's manager certificate. **A fresh RB5009 manager would be refused, and
        mikrotik2's radio (the only one that works today) would stay down after cutover.**
        Importing the same CA and certificate avoids any change on mikrotik2. Fallback, if the
        import fails: just before cutover, clear the pin on mikrotik2
        (`/interface/wireless/cap/set caps-man-certificate-common-names=""`, then check it
        with `print`, because property clears are unreliable, see README) and re-pin it to
        the new certificate's CN afterwards.
- [ ] Warn the house: the cutover drops wifi on mikrotik2's AP for a minute or two (the CAP has
      to re-join a new manager), and the internet for a few minutes.

## Phase 1 — base build and staging on the live LAN (no network impact)

The RB5009 joins the LAN as mikrotik6 at **`192.168.10.6`** (its permanent management
address), and the Internet-Box on its own WAN port. All production addresses and services are
present but **disabled**. That lets it be configured over SSH from the desktop, fetch packages
over its own WAN, and be fully checked before it carries any traffic.

1. **First boot, on the bench.** Connect a laptop directly, log in, and record
   `/system/routerboard/print`, `/interface/print`, `/system/package/print`. Then reset
   with **no default config** (`/system/reset-configuration no-defaults=yes
   skip-backup=yes`). The defconf firewall, NAT, DHCP and `192.168.88.1` would otherwise
   collide with the port. Reconnect via MAC-Winbox/MAC-Telnet.
2. **Packages.** Upgrade to the latest `stable` release with `scripts/upgrade-fleet.sh`
   (RouterOS and RouterBOOT firmware). If that is newer than the rest of the fleet, the
   same run upgrades every device, so the fleet stays on one version. Then **verify the B3 prerequisite from `wifi.md`**: the legacy
   `wireless` package must install on arm64 next to `wifi-qcom`/`wifi-qcom-ac`.
   - If it installs, the RB5009 runs legacy `/caps-man` for mikrotik2 (target B3).
   - If it does not, **this plan changes**: the RB2011 has to stay as the legacy CAPsMAN
      manager after cutover (`wifi.md`'s fallback, "B2 by another name"). Stop and re-plan
      Phase 3 before going further.
3. **Minimal staging identity** (typed directly, short lines; see the README's
   truncation lesson):
   - `bridge-main`, `vlan-filtering=yes`, ports per the port plan, bridge-vlan table for
     10/20/30, `vlan-users`/`vlan-services`/`vlan-iot` interfaces.
   - `192.168.10.6/24` on `vlan-users`. This is mikrotik6's own management address and it
     **stays after cutover** (the `router6` name keeps working). No static default route:
     the default route comes from the `ether1` DHCP client (step 4).
   - **Staging routes** `192.168.20.0/24`, `192.168.30.0/24`, `192.168.50.0/24` via
     `192.168.10.1` (comment `staging`). Without them, mikrotik6's replies to Pi-hole, HA or
     the phone over WireGuard follow the WAN default route to the Internet-Box and are lost.
   - Built by `scripts/mikrotik6-base.rsc` (run and deleted 2026-10-19) via `run-after-reset` (it also turns IPv6 off
     until Phase 2, which is simpler than disabled ND entries).
   - `admin` password, SSH key (`gehel@durin`), `admin` `address=` restriction identical to
     mikrotik1 (`192.168.10.0/24,192.168.50.0/24`), `mgmt` address-list **built before** any
     input rule that references it (README lesson).
   - **No IPv6 RAs on the LAN while staging.** Create every `/ipv6/nd` entry for the three
     VLANs `disabled=yes`, and leave the `from-pool` addresses disabled too. Otherwise the
     RB5009 would advertise itself as a second IPv6 router on the live VLANs. The DHCPv6-PD
     client on `ether1` *can* run during staging (see Phase 2b).
   - **The input firewall comes before the WAN cable.** Port mikrotik1's `chain=input` rules
     (and the `mgmt` list they need) before connecting `ether1`. The box's LAN is not the
     internet (no DMZ points here yet), but it is still the `WAN` side.
4. **WAN.** RB5009 `ether1` to a free Internet-Box LAN port. Check that
   `/ip/dhcp-client/print detail` is `bound`, with a default route via `192.168.1.1`. Note the
   lease address and reserve it in the box if possible.
5. **LAN.** Cable from RB5009 `ether2` to a **spare mikrotik2 port**, configured on
   mikrotik2 as a second trunk (pvid 10, tagged 20/30, the same shape as
   `ether1-gateway`). This makes the staging link **the production link**: at cutover
   nothing needs re-cabling on the LAN side. Use the bridge-vlan rebuild-from-`current-*`
   pattern from README's lessons for mikrotik2's tagged lists. Log the mikrotik2 change in
   `changelog.md`.
   - Topology during staging: mikrotik1 — mikrotik2 — RB5009 is a chain, not a loop, so no
     STP concern. The RB5009 has no IP on VLANs 20/30 yet.
6. **Add `192.168.10.6` to `mgmt` on mikrotik1-5** (comment `mikrotik6`), the same as every
   other router. It stays. Add a Pi-hole local DNS record `router6.home.ledcom.fr` →
   `192.168.10.6`.

**Exit check:** `ssh admin@router6.home.ledcom.fr` works from the desktop; `/ping 1.1.1.1`
works from the RB5009 over its own WAN; `/interface/bridge/vlan/print detail` shows the expected
`current-tagged`/`current-untagged`.

## Phase 2 — port the production config, all disabled (no network impact)

Generate this as an idempotent `.rsc` (one per area, following the `mikrotik-routeros-rsc`
skill) **from the fresh Phase 1 dump of the RB5009 plus mikrotik1's export**, not by
importing mikrotik1's raw export. The raw export carries RB2011-specific names
(`ether2-master`, `wlan1`, dangling `*18`/`*19`/`*E` references) and leftovers.

| Area | Port as-is | Notes |
|---|---|---|
| Interface lists | `WAN` (=`ether1`), `discover`, `mactel`, `mac-winbox` | Rebuild `discover` membership from RB5009 port names, without the dangling `*E` |
| Addresses | `.10.1`, `.20.1`, `.30.1`, `.50.1` | **Add with `disabled=yes`.** They conflict with mikrotik1 until cutover. `.10.6` stays alongside `.10.1` permanently |
| DHCP | options 42 ×3, pools ×3, servers ×3 (with the `lease-script`), networks ×3, **all static leases** | Servers `disabled=yes`. Copy leases from the fresh dump, not this one: the TV ones are new |
| DHCP client | `ether1`, `use-peer-dns=no` | Already live from Phase 1 |
| DNS | `servers=192.168.20.40`, `allow-remote-requests=yes`, static `router` A record | `dhcp-to-dns` entries regenerate on their own (lease-script) |
| NTP | client (pool.ntp.org ×4) + server enabled | |
| Firewall v4 | filter, NAT, all address-lists, `udp-timeout=10s` | **Verbatim, same order.** Every interface name already matches. Print after import and check for `I - INVALID` (expected transiently on `iot2services`, see README) |
| Firewall v6 | filter, address-lists, NAT66 masquerade on `ether1` | v6 EUI-64 lists may need recomputing at cutover if the prefix changes (Phase 3) |
| IPv6 | `accept-router-advertisements=yes`, DHCPv6-PD client on `ether1` (`pool-name=swisscom-pd`, `/64` slices), `from-pool` addresses ×3, ND ×3 (`advertise-dns=no`) | Addresses and ND `disabled=yes` until cutover. PD client enabled (Phase 2b) |
| WireGuard | `wireguard1`, port 51820, MTU 1420, **mikrotik1's private key**, peer `192.168.50.2/32` | Same key, so the phone needs no change. Interface `disabled=yes` until cutover: mikrotik1 owns `192.168.50.0/24` and the DMZ until then |
| CAPsMAN (legacy) | channels ch1/ch6/ch11, configs `caps_config`/`caps_ch11`/`caps_iot` with passphrases, provisioning (incl. the `radio-mac=4C:5E:0C:91:51:99` rule), manager interface `vlan-users`, **imported certificate** | **Manager `enabled=no`.** Interface entry `bridge-main` too, as on mikrotik1 |
| Users | `homeassistant` in group `ha` (`read,test,api`), `address=192.168.20.60/32` | Same password, or a new one plus an HA update |
| Services | ftp/telnet/api-ssl/reverse-proxy/www-ssl off; ssh, www, winbox, api on; SSH strong-crypto, 4096 host key **imported** | Match `/ip/service/print` |
| Misc | time zone, `max-neighbor-entries`, mac-server lists, neighbor discovery, SNMP off, BFD off, `/ip/cloud ddns-enabled=auto` | |
| **Do not port** | `ipv6-migrate` script, OSPF instances/areas, BGP template, `ovpn-server1`, LTE APN, SMB, `wlan1`/local CAP config, legacy `ether*-master` naming | Leftovers or RB2011-only |

**Scripts (written 2026-10-19 from the 12:55 dump of mikrotik1; all run and verified the
same day. Scripts 1-4 are deleted, see `changelog.md`. Only the secrets template and
`mikrotik6-p2-cutover.rsc` stay in `scripts/`).** Imported in this order. The order matters, because later scripts reference what
earlier ones create:

| # | File | What it does |
|---|---|---|
| — | `mikrotik6-p2-secrets.rsc.example` | Template. The filled copy goes in `backups/` (gitignored) and sets 4 globals: WireGuard key, 2 CAPsMAN passphrases, the `homeassistant` password |
| 1 | `mikrotik6-p2-system.rsc` | Interface lists, `wireguard1` + peer (disabled), production addresses (disabled), DNS → Pi-hole, NTP upstreams + server, `ha` group + `homeassistant` user, services, misc |
| 2 | `mikrotik6-p2-dhcp.rsc` | Option 42 ×3, pools ×3, servers ×3 (disabled, with the dhcp-to-dns lease-script), networks ×3, all 15 static leases |
| 3 | `mikrotik6-p2-firewall.rsc` | **Generated** from the export: 30 address-list entries, 89 filter rules and 2 NAT rules, verbatim and in order, plus finding 36's fix (`samsung-tv` list). The staging rules are removed only after the new ones are all in |
| 4 | `mikrotik6-p2-capsman.rsc` | Channels, the 3 configurations, provisioning, and manager interfaces. Uses mikrotik1's imported certificate, and the manager stays `enabled=no` |
| 5 | `mikrotik6-p2-cutover.rsc` | Stores `cutover` and `rollback` in `/system/script`. Does not run them |

Each script's body is one `{ }` block, so that `:local` values persist (README lesson), and it
guards every add. **IPv6 is not ported yet**: it waits for the Phase 2b PD test, and when it
is ported, the `cutover` script gets the IPv6 steps too. A few mikrotik1 items are left out on
purpose: `detect-internet`, the `sniffer` settings, the RB2011 `advertise=` settings and
`max-neighbor-entries=8192` (below the RB5009's default soft-max, refused on import).

**WAN: own MAC, own lease, DMZ moved at cutover.** Both routers sit on the box's LAN at the
same time, so the RB5009 keeps its **own** `ether1` MAC (cloning mikrotik1's would put two
identical MACs on the box's LAN). It gets its own `192.168.1.x` lease. If the box UI allows
it, reserve that address for the RB5009 so it stays the same. Inbound traffic follows the
box's **DMZ host** setting, which points at mikrotik1 (`192.168.1.101`) until the cutover moves
it. Nothing on the router side depends on the WAN address: the HA `dst-nat` rule has no
`dst-address=` (`ipv6.md`, 2026-09-11) and the WireGuard input rule only matches the `WAN`
interface list.

**A pre-written cutover script** goes onto the RB5009 as `/system/script` `cutover`, and a
matching `rollback`. Make both safe to run twice (README lesson on schedulers firing
twice):

```
cutover:  remove the three "staging" routes
          enable .10.1/.20.1/.30.1 addresses, wireguard1 and .50.1
          enable dhcp-home/dhcp-services/dhcp-iot
          enable the three IPv6 from-pool addresses and ND entries
          /caps-man/manager/set enabled=yes
rollback: the exact reverse. .10.6 and the WAN are untouched either way
```

**Exit check:** `/export` on the RB5009 diffed against mikrotik1's export, section by section.
Every difference should be either a port name or something in the "do not port" row. Firewall
rule counts are equal per chain.

## Phase 2b — opt-in testing through the RB5009 (one test host only)

Possible only because the RB5009 has its own WAN. Everyone else stays on mikrotik1.

- **IPv4 internet, NAT and the `users` firewall path.** On one `users` laptop, set the
  default gateway to `192.168.10.6` by hand (e.g. `ip route replace default via
  192.168.10.6`). Check: browsing works; `curl -4 ifconfig.co` shows the same public IP
  (same box); the counters of `dispatch: users -> internet` and `users2internet` on the RB5009
  increase.
  - **Add routes for the internal subnets first, through mikrotik1**: `ip route add
    192.168.20.0/24 via 192.168.10.1` (and `.30.0/24`, `.50.0/24`). Without them, DNS to
    Pi-hole goes to mikrotik6, which sends it on to mikrotik1 out of `vlan-users`, the same
    interface it came in on. No `dispatch` rule matches `vlan-users` → `vlan-users`, so
    `Drop all other forward traffic` drops it, and name resolution breaks during the test.
  - Only internet-bound traffic can be tested this way. Traffic from the test host to
    `services`/`iot` would leave through the RB5009, but replies would come back through
    mikrotik1 (each host's gateway). That is asymmetric routing, so it does not prove anything.
- **IPv6 PD.** With the DHCPv6 client on `ether1` enabled (and ND still disabled), check
  whether the box delegates a **second** prefix to the RB5009 (`/ipv6/dhcp-client/print
  detail`). If it does, write down the prefix: after cutover the `vlan-*` addresses come
  from this pool, so `ha-v6`/`pihole-v6`/`octoprint-v6`/`http-outbound-v6` **have to be
  recomputed for it** (Phase 2 can already prepare them). If the box refuses a second
  delegation, plan for `/ipv6/dhcp-client/release` on mikrotik1 and the RB5009 at cutover.
  - **Result 2026-10-19: the box does delegate a second prefix.** mikrotik6 (DUID
    `…38327a44b445`) got `2a02:1210:7621:9ac0::/58`, and mikrotik1 kept `9a40::/58`. The
    DHCPv6 client only started after a reboot, because RouterOS asks for one after
    `accept-router-advertisements` changes. `scripts/mikrotik6-p2b-ipv6-addr.rsc` holds the
    recomputed EUI-64 lists (`9ac1`/`9ac2`) and the disabled from-pool addresses, and
    `cutover` enables them together with the ND entries. No `release` is needed at cutover.
- **WireGuard and HA HTTPS cannot be tested before cutover**: they need the DMZ.

Reset the test laptop's gateway afterwards (`dhclient` or reconnect).

## Phase 3 — cutover (the only disruptive step, ~2 minutes)

Pick a quiet moment. All three boxes sit in the same place. Have the desktop (wired, via
mikrotik3) logged in to the RB5009 at `.10.6`, and a phone on mobile data for the external
tests.

| # | Action | Effect |
|---|---|---|
| 0 | Regenerate `dumps/` and `logs/`. Note both routers' `/ipv6/dhcp-client/print detail` prefixes | Baseline |
| 1 | **Unplug mikrotik1 `ether2-master`** (the trunk to mikrotik2) | LAN loses its gateway. **Outage starts.** The RB5009 stays reachable at `.10.6` |
| 2 | On the RB5009 (`ssh router6`): `/system/script/run cutover` | `.10.1`/`.20.1`/`.30.1` are now on the RB5009. Routing, DNS and internet come back (the RB5009's WAN is already up). **Outage ends** |
| 3 | **Internet-Box UI (`https://192.168.1.1`): change the DMZ host** from mikrotik1 (`192.168.1.101`) to the RB5009 (`192.168.1.103`) | HA HTTPS from outside and the WireGuard VPN come back |
| 4 | **Move mikrotik4**: mikrotik1 `ether10` → RB5009 `ether3` | mikrotik4 reboots on PoE (~1 min outage on that AP only) |
| 5 | On mikrotik1: `/interface/wireguard/disable wireguard1` | No second router answering for the phone's tunnel |
| 6 | Leave mikrotik1 powered, on the box's WAN, off the LAN | Rollback stays one cable away |

Clients keep their ARP entry for `.10.1` → mikrotik1's MAC for a short time. Most refresh
within a minute or two. A device that stays offline after that has a stale ARP entry: toggle
its wifi or cable. This is the one cost of not cloning the bridge MAC; it is smaller than the
complexity of MAC cloning on a bridge that later gets redeployed.

**Rollback** (any time in the first week): on the RB5009 run `rollback`; plug mikrotik1's
`ether2-master` (and `ether10`) back; point the DMZ back to `192.168.1.101`; re-enable
`wireguard1` on mikrotik1. mikrotik1 was never touched, so it returns exactly as it was. DHCP
leases are on the long side (1d), so clients ride through either direction.

**Verify, in this order** (any failure: fix, or roll back):

1. `ssh admin@router1.home.ledcom.fr` from the desktop. Should connect **without a host-key
   warning**, and `/system/routerboard/print` should show `RB5009`.
2. The Internet-Box's DMZ page shows the RB5009's WAN address. `/ip/route/print` on the
   RB5009 has the default via `192.168.1.1`.
3. Internet from each VLAN: desktop (`users`), Pi-hole and HA (`services`), OctoPrint
   (`iot`, also checks the `octoprint` exception).
4. DNS: `dig @192.168.20.40 router1.home.ledcom.fr` and a public name from a `users` host.
   Within a few minutes, new leases should appear as `dhcp-to-dns` static entries.
5. DHCP: force one renew per VLAN (`dhclient -r/ -v` on a laptop, or
   `/ip/dhcp-server/lease/print` filling up). The RB5009 starts with an empty lease table.
   Clients that renew an address it doesn't know either get it re-ACKed or get a NAK and
   rediscover. Either way they recover alone. Reserved hosts keep their addresses.
6. CAPsMAN: `/caps-man/remote-cap/print` shows mikrotik2, and
   `/caps-man/registration-table/print` fills with clients on both `LEDCOM` and
   `LEDCOM-IoT` (IotaWatt `A8:48:FA:F2:40:4D` and the Tasmota light were on it in the last
   dump: good canaries).
7. mikrotik4: `/interface/ethernet/monitor ether3 once` shows **`rate: 1Gbps`** (it was
   capped at 100M on `ether10`), and PoE is delivering. Clients on `LEDCOM` 5 GHz.
8. IPv6: `/ipv6/dhcp-client/print detail` is `bound` with `2a02:1210:7621:9ac0::/58` (the
   Phase 2b delegation; the EUI-64 lists are already computed for it). If the prefix has
   changed, recompute `ha-v6`, `pihole-v6`, `octoprint-v6` and `http-outbound-v6`
   (`ipv6.md`). `/ipv6/address/print` shows `9ac0::1`, `9ac1::1` and `9ac2::1`, not `X`.
   Then check `ping -6` from a client on each VLAN. Clients keep their old `9a4x` SLAAC
   addresses until mikrotik1's prefix lifetimes run out. Traffic from those still works
   (NAT66 masquerades whatever leaves `ether1`), but it does not match the new
   EUI-64 lists. So Pi-hole's own upstream IPv6 DNS, and HA's IPv6 to the printer and TV,
   can fail until the old addresses expire. Those paths fall back to IPv4.
9. External, from the phone on mobile data: `https://home.ledcom.fr` (HA, via
   `dst-nat` + `internet2services`), then the **WireGuard tunnel**: connect it, then reach
   `192.168.10.1` and the internet through it.
10. Home Assistant: the MikroTik integration still connects (API, `homeassistant` user).
    Also the HA → printer, Samsung TV, IotaWatt and Tasmota paths.
11. The firewall log still shows only the known noise. Run `dump-logs.sh` the next day.
12. NTP: `/system/ntp/client/print` is synced, and a client on `iot` gets time from
    `.30.1`.

Log the cutover in `changelog.md` **as it happens**, with the output of each check.

## Phase 4 — clean-up (within the week)

- [x] ~~Decide whether the new mikrotik2 trunk port stays.~~ Done 2026-10-20: the cable moved to
      `ether1-gateway` (now switch-main `ether1`), and `ether18` is an access port again.
- [x] ~~CAPsMAN certificate.~~ The import worked: switch-main's CAP joined the router's manager
      at cutover with the unchanged `caps-man-certificate-common-names` (Phase 3 check 6).
- [x] ~~IPv6 on the RB5009.~~ Verified in Phase 3 check 8 (addresses, ND, NAT66, `ping -6` and
      `curl -6` from a client). `ipv6.md` has a "Moved to the RB5009" section.
- [x] ~~Fleet scripts.~~ Done 2026-10-20, then switched to the new names: every script uses
      `<name>.home.ledcom.fr` and writes `<name>.txt`. `upgrade-fleet.sh` upgrades the router
      last. `measure-bufferbloat.sh` targets `192.168.10.1`/`192.168.1.1`/`1.1.1.1`.
- [x] ~~Post-cutover review and device rename.~~ Done 2026-10-20: `config-review.md` round 4
      (37-39 open, S19/S20 closed), role-location names on all five devices.
- [x] ~~Docs.~~ Done 2026-10-20: README, `vlan.md`, `wifi.md`, `ipv6.md`, `vpn.md`,
      `performance.md`, `qos.md`, `config-review.md`, `network.md` and both diagrams.
      `firewall.md` is regenerated from the first post-rename dump.
- [ ] Re-baseline throughput: `measure-bufferbloat.sh` (then update `qos.md`), and the router's
      `cpu-load` under real load with the WireGuard tunnel up (`vpn.md`'s open item).
- [ ] **End of the rollback week (not before 2026-10-27).** First unplug the RB2011 from the
      Internet-Box and wipe it (it holds the WireGuard key and wifi passphrases). Keep its
      `show-sensitive` export only in `backups/`. Then, on the router:
      ```
      /system/script/remove cutover
      /system/script/remove rollback
      /ip/address/set [find address="192.168.10.1/24"] comment="users gateway"
      /ip/address/set [find address="192.168.20.1/24"] comment="services gateway"
      /ip/address/set [find address="192.168.30.1/24"] comment="iot gateway"
      /ip/address/set [find address="192.168.50.1/24"] comment="wireguard gateway"
      /ipv6/address/set [find from-pool=swisscom-pd] comment="gateway, from the delegated prefix"
      /ip/address/remove [find address="192.168.10.6/24"]
      /ip/firewall/address-list/remove [find address=192.168.10.6]
      ```
      Connect to `router.home.ledcom.fr` (`.10.1`) for this, not to `.10.6`. On switch-main,
      switch-office, ap-main and switch-livingroom:
      `/ip/firewall/address-list/remove [find address=192.168.10.6]`. In Pi-hole, delete the
      `router1`-`router6` records. Checks: `/system/script/print` empty, `/ip/address/print`
      and `/ipv6/address/print` with the new comments and no `.10.6`, and
      `/ip/firewall/address-list/print where list=mgmt` with 8 entries on every device. This
      also closes finding 39.

## Phase 5 — later, separate decisions (not part of the swap)

None of these need to happen at cutover. Each one is a separate change with its own risk.

- **What the RB2011 becomes.** `config-review.md`'s redeployment table proposed "media
  switch by the TV, or CAPsMAN-only box". The living room is now covered by mikrotik5.
  If the B3 package check in Phase 1 passed, it isn't needed as a CAPsMAN box either. Its
  radio is flapping (see above). Options: legacy CAP next to mikrotik2 (low value, the
  radio needs investigating first), workshop switch (`vlan.md` still needs one, and it would
  need VLAN awareness), or a spare. **Guillaume's call.**
- **mikrotik4 under the new `/interface/wifi/capsman`** (target B3). This only centralizes
  the config. It does **not** bring `LEDCOM-IoT` to mikrotik4: VLAN-tagged multi-SSID is
  unsupported on this hardware/driver under any manager (`wifi.md`, README). Low value, real
  wifi risk. Defer unless a second `wifi-qcom-ac` AP shows up.
- **Patch-panel rewiring** (`config-review.md`'s "Physical wiring"): now the RB5009 has 7
  Gigabit ports with a switch chip, some rooms could land on it directly. Revisit after the
  throughput re-baseline.
- **QoS / CAKE** (`qos.md` closed it by measurement on the old box): re-measure first.
- **Finding 25 (`home.ledcom.fr` DDNS)**: unaffected by the swap as long as the public IP
  stays the same, but `/ip/cloud` is a new identity (new serial), so any `sn.mynetname.net`
  idea in that finding now refers to the RB5009's serial.
