# Changelog — closed findings

Closed and verified findings for every MikroTik on the network, moved here 2026-09-05 so the
review documents hold only what is still open.

Live review document: [config-review.md](config-review.md), which covers every device and
holds only what is still open.

Nothing is recorded here on the strength of a change having been made. Every entry carries
the device output that verified it, and where a negative test exists — proving a restriction
actually blocks rather than merely being configured — that test is recorded too. Finding
numbers are stable and are never reused.

## Main router — mikrotik1 (RB2011UiAS-2HnD)

### Round 1 (2026-09-03)

- **Telnet and FTP disabled.** Both show `X` in `/ip service`.
- **RouterOS upgraded** 7.23.3 → 7.24.2, now current.
- **WPA1 removed** from the CAPsMAN config — `security.authentication-types=wpa2-psk`.
- **SNMP community narrowed** to `192.168.1.0/24`. SNMP itself remains off.
- **IPv4 LAN address moved** from `ether2-master` to `bridge-main`.
- **`admin` bound to the LAN** — `address=192.168.1.0/24`.
- **Broken `/ipv6 dhcp-server dhcp1`** (referencing a nonexistent `delegation` pool) removed.
- **IPv6 IPsec, IKE, and HIP accepts removed** from both chains.
- **Confirmed mikrotik1 is not an open DNS resolver**, despite `/ip/dns
  allow-remote-requests=yes` predating this work. Confirmed from the full config export:
  `drop all from WAN in-interface=ether1` is rule 1 of the IPv4 input chain, ahead of the port
  53 accepts; the IPv6 side is covered by its own input drop. Not actionable — informational
  only, no configuration change made.

Round 1 finding 18 (`udp-timeout=10s`) was withdrawn as a false positive: it is the
RouterOS default and governs only unreplied UDP flows. Not re-raised.

### Round 2 (2026-09-04 onward)

**2026-09-05 — `api-ssl` listening without a certificate (was the last of finding 3, high).**
Enabled on 8729 with `certificate=none`: listening, unable to complete a handshake, unused.
The same defect was cleared on both switches under S5 a day earlier; the main router was
missed.

Verified: `/ip/service/print where name="api-ssl"` shows the service flagged `X`.

**Finding 3 is now closed in full.** Both halves — the full-admin credential and the
certificate-less TLS listener — are done. What remains is not a finding but a parked
decision: whether Let's Encrypt can be made to work without an external host. That is
recorded under "The TLS question" in [config-review.md](config-review.md), along with the
condition that would unblock it.

**2026-09-05 — Home Assistant moved off `admin` (was the open half of finding 3, high).**
HA authenticated as `admin` in group `full` — effectively root on the router — over the
plaintext API on 8728.

Fixed by creating `homeassistant` in a purpose-built `ha` group
(`policy=read,test,api`, everything else negated) bound to `address=192.168.1.60/32`, on all
three devices, and repointing the Home Assistant MikroTik integration at it.

Verified by the router's own account log rather than by configuration, which is the only
thing that shows which credential is actually in use:

```
2026-09-05 16:44:45  user homeassistant logged in from 192.168.1.60 via api
2026-09-05 17:03:01  user homeassistant logged in from 192.168.1.60 via api
```

Two successful API logins from `.60` as `homeassistant`, and **no** `admin` login from `.60`
anywhere in the log. The `read,test,api` policy proved sufficient — the integration did not
need `write` added.

The temporary firewall rule was renamed from `TEMP: HA API - remove after finding 3` to
`HA API access`, since plaintext management traffic within the LAN is an accepted risk and
the rule is now permanent.

What remains open under finding 3 is only `api-ssl` listening with `certificate=none`, plus
the deferred Let's Encrypt question.

**Finding 6 — `admin` is LAN-bound; know what that costs you (closed 2026-09-05).**
Informational only, no configuration change intended. Guillaume confirmed he has read and
accepted it. The substance, kept here so it is not re-derived: `admin` is restricted to
`address=192.168.1.0/24` on all three devices, so a MAC-Telnet session sourced from outside
that subnet is refused at login even with correct credentials. Recovery works because the
other MikroTiks source from inside the range. If `admin`'s address is ever narrowed further,
the serial console becomes the only route in — the local console ignores the user address
restriction. Still a single account with the default name.

**2026-09-04 — IPv6 broken by misplaced WAN drop (was finding 1, critical).** The
`drop input from WAN` rule sat ahead of the DHCPv6-client accept, so prefix delegation
never bound and the `swisscom-pd` pool did not exist. Introduced by the round 1 finding 4
remediation, whose `place-before=` target was wrong.

Fixed by deleting both the UDP traceroute accept and the WAN drop: with the traceroute rule
gone, the chain's terminating drop covers WAN input on its own, so the drop had no remaining
job and its position could no longer break anything.

Verified: `/ipv6/pool/print` shows `swisscom-pd` = `2a02:1210:680f:c40c::/62`;
`/ipv6/address/print` shows `2a02:1210:680f:c40c::1/64` on `bridge-main`, `advertise=yes`,
no pool error; `/ipv6/route/print` shows an active default route; desktop pings
`2606:4700:4700::1111` at 0% loss.

**2026-09-04 — LAN-wide management-plane access (was finding 2, high).** The
`accept chain=input src-address-list=home` rule granted every host on `192.168.1.0/24` —
IoT devices included — full access to ssh, the web UI, the API, and Winbox.

Replaced with an `mgmt` address list holding the desktop (`.90`), mikrotik2 (`.2`), and
mikrotik3 (`.3`). Two explicit carve-outs were added ahead of it so the change did not break
working services: DHCP server (UDP 67 on `bridge-main`), and a temporary accept for Home
Assistant's API on 8728 from `.60` which finding 3 will replace.

Verified: from Pi-hole at `192.168.1.40`, outside `mgmt`, `nc` to ports 22 and 8291 both
time out (exit 124) while port 53 succeeds. Rule order confirmed, with the broad `home` rule
disabled at position 10 behind the `mgmt` accept at 9. DHCP confirmed still working by fresh
*dynamic* leases (`.101`, `.102`, `.106`) issued after the change, proving full
DISCOVER/OFFER rather than only renewals.

**2026-09-04 — `192.168.1.4` added to `mgmt`.** A MikroTik being returned to service,
allowed in advance so it has management access when it comes back online.

**2026-09-04 — RouterBOOT version unknown (was finding 9, medium).** RouterBOOT upgrades
separately from RouterOS and does not follow the package upgrade, so it was unclear whether
it lagged the move to 7.24.2.

No action needed. Verified: `/system/routerboard/print` reports `current-firmware: 7.24.2`
equal to `upgrade-firmware: 7.24.2`. RouterBOOT is current.

**2026-09-04 — TLS services listening without a certificate (was finding 4, high).**
`reverse-proxy` was enabled on 443 with `certificate=none`: listening, unable to complete a
handshake, unused.

Verified: `/ip/service/print` shows `reverse-proxy` flagged `X`. `www-ssl` remains disabled
as before.

Partially folded rather than closed: `api-ssl` has the same defect and `www` is plain HTTP
in active use. Both need the certificate from finding 3, so they were moved into that
finding instead of being tracked separately.

**2026-09-04 — Home Assistant port-forwarded over plaintext HTTP (was finding 5, high).**
A `dst-nat` on port 80 from `ether1` to `192.168.1.60:80`, with a matching forward-chain
accept, would have carried HA credentials and session cookies in clear text had the
Internet-Box forwarded port 80 inward. (HA was not listening on 80 in any case.)

Verified: `/ip/firewall/nat/print` shows only the HTTPS dst-nat remaining;
`/ip/firewall/filter/print where chain=forward` shows only the HTTPS accept. Both halves of
the HTTPS pair are intact, so no orphaned NAT entry or unreachable filter rule was left
behind.

**2026-09-04 — Unused routing protocol config (was finding 11, low).** OSPF v2/v3
instances, a BGP template, and an enabled BFD configuration existed on a router with no
dynamic routing.

Verified: `/routing/ospf/instance/print`, `/routing/bgp/template/print`, and
`/routing/bfd/configuration/print` all return empty. Confirmed observably by the
`route_BFD` services on UDP 3784/4784 no longer appearing in `/ip/service/print`.

**2026-09-04 — `detect-internet` enabled on all interfaces (was finding 14, low).**

Verified: `/interface/detect-internet/print` shows `detect-interface-list: none`, and every
`detnet` dynamic service has disappeared from `/ip/service/print`.

**2026-09-04 — Stale OVPN server entry (was finding 15, low).** An OVPN server configured
with `auth=sha1,md5`, long unused.

Verified: `/interface/ovpn-server/server/print` returns empty.

**2026-09-04 — Anti-scan rules dead and a self-lockout risk (was finding 7, medium).** The
`Syn_Flooder` and `Port_Scanner` rules sat after `drop all from WAN`, so they never saw
internet traffic — the only thing they were written to stop. Worse, they sat *before* the
`mgmt` accept and were unscoped, so the only addresses they could ever match were LAN hosts:
a management host tripping `Port_Scanner` would have been dropped for a week.

Fixed by scoping all four rules to `in-interface=ether1` and moving them ahead of the WAN
drop, rather than deleting them.

Took two attempts. The first pass was made in safe mode and the reordering was rolled back
when the session ended without a commit — only the `in-interface=ether1` scoping survived.
Redone outside safe mode, which was safe to do because none of these rules can affect the
management path.

The second attempt used a single move (send the WAN drop down) instead of lifting four
rules up:

```
/ip/firewall/filter/move [find comment="defconf: drop all from WAN"] \
    destination=[find comment="Jump for icmp input flow"]
```

Verified 2026-09-04 outside safe mode: `/ip/firewall/filter/print where chain=input` shows
positions 2-5 as the four detector rules, each with `in-interface=ether1`, and
`defconf: drop all from WAN` at position 6. They now see internet traffic and can never
match a LAN host.

A matching SYN-flood pair was added to the **forward** chain, where inbound traffic to port
forwards actually flows. Verified positioned between the Pi-hole DNS accept and
`Home can connect everywhere`, detector before drop, matching on
`connection-nat-state=dstnat` rather than a literal port so every future port forward is
covered without revisiting the rule.

Watch for false positives: `connection-limit=30,32` is plausible for a single browser under
poor connectivity, and tripping it locks out remote Home Assistant for 30 minutes. Check
`/ip/firewall/address-list/print where list=Syn_Flooder` if remote access misbehaves.

**Lesson recorded:** safe mode discards everything on session loss. For changes that cannot
affect the management path, run them directly and verify immediately instead.

Note on realistic value: input from `ether1` was already fully dropped, and the
Internet-Box only forwards 443 inward, so little traffic reaches this chain. A matching
SYN-flood pair was added to the **forward** chain, scoped to `dst-port=443`, where inbound
traffic to Home Assistant actually flows. Watch `Syn_Flooder` for false positives —
`connection-limit=30,32` is plausible for a single browser under poor connectivity, and
tripping it locks out remote HA for 30 minutes.

**2026-09-04 — MikroTik cloud DDNS active (was finding 13, low). Not actionable.**
`/ip/cloud/set ddns-enabled=` tab-completes to `auto` and `yes` only; RouterOS 7.24.2 offers
no way to switch DDNS off, and `auto` still populates `public-address`. The RouterOS 6
`no` value is gone.

`update-time` was set to `no`, removing the redundant cloud time source (NTP is already
configured against `0-3.pool.ntp.org`).

Remaining exposure is an outbound report to a vendor service plus a resolvable
`<serial>.sn.mynetname.net` name. Closed as not actionable on this version rather than left
open indefinitely.

**2026-09-04 — Firewall rule logging (was finding 10, low).** Six drop rules carried
`log=yes` on a 600 MHz single-core CPU, where a chatty device retrying against a permanent
drop fills the buffer continuously.

All firewall rule logging disabled with `/ip/firewall/filter/set [find log=yes] log=no`.
Verified: `/ip/firewall/filter/print where log=yes` returns empty.

`/system/logging` was deliberately left alone — `info`, `error`, `warning`, and `critical`
still go to memory. Those are low-volume, cost nothing per packet, and are what is needed
when diagnosing a problem. Only per-packet firewall logging was removed.

The `Hombli` ceiling-fan rule was the one worth keeping (distinct prefix, low volume,
deliberately distrusted device). Re-enable with
`/ip/firewall/filter/set [find comment~"Ceiling Fan"] log=yes` if that visibility is wanted
back.

**2026-09-04 — Wrong CAPsMAN address on the FON network (was finding 12, low).** The
`192.168.2.0/24` DHCP network advertised `caps-manager=192.168.2.1`, where no manager
exists.

Two earlier attempts using `[find address=192.168.2.0/24]` silently did nothing — that
filter matches no rows on this menu, and `set` against an empty result is a no-op that
looks identical to success. Fixed by addressing the row by index instead.

Verified: `/ip/dhcp-server/network/print detail` shows `caps-manager=192.168.1.1` on the
`192.168.2.0/24` network.

## Switches — mikrotik2 (CRS125-24G-1S-2HnD) and mikrotik3 (RB750Gr3)

### Closed 2026-09-05

Verified against `dumps/mikrotik2-switch.txt` and `dumps`, collected
2026-09-05 16:37–16:38.

**S1 — no input-chain firewall on either device.** Both now carry the full pattern, in the
correct order, ending in a terminating drop. `/ip/firewall/filter/print` on each shows rules
3–8: accept established/related, drop invalid, accept ICMP, accept `src-address-list=mgmt`,
accept `192.168.1.60` to 8728, drop everything else. The `mgmt` list on both holds
`192.168.1.90`, `.1`, `.2`, `.3`, `.4`.

Confirmed by negative test from Pi-hole (`192.168.1.40`, deliberately outside `mgmt`):

```
timeout 5 nc -zv 192.168.1.2 8291   ->  124
timeout 5 nc -zv 192.168.1.3 22     ->  124
```

Both timed out rather than being refused, which is the drop rule acting — a device with no
listener would have returned a refusal immediately.

**S2 — FTP and Telnet enabled.** `/ip/service/print` on both: `0 X ftp`, `3 X telnet`.

**S3 — `admin` unrestricted.** `/user/print detail` on both: `name="admin" group=full
address=192.168.1.0/24`. Last logins recorded from within the range, so the restriction is
not blocking normal access.

**S4 — open DNS resolvers.** `/ip/dns/print` on both: `allow-remote-requests: no`. Each
still resolves for itself (mikrotik2 → `192.168.1.1`, mikrotik3 → `192.168.1.40` dynamic),
which is what was wanted.

**S5 — `reverse-proxy` and `api-ssl` listening with no certificate.** `/ip/service/print` on
both: `10 X reverse-proxy`, `15 X api-ssl`. `www-ssl` was already disabled.

**S6 — mikrotik2's broken and disabled NAT rules.** `/ip/firewall/nat/print` returns empty
and the export has no `/ip firewall nat` section at all.

**S8 — mikrotik3 logged every forwarded UDP packet.** Gone; `/ip/firewall/filter/print`
shows only the three defconf forward rules plus the new input chain.

**S9 — mikrotik2's wireless profile permitted TKIP.** The export now reads
`set [ find default=yes ] authentication-types=wpa2-psk mode=dynamic-keys
supplicant-identity=MikroTik` with no cipher parameters. `/export` prints only non-default
values, and `group-ciphers=tkip,aes-ccm unicast-ciphers=tkip,aes-ccm` was previously shown
explicitly — its disappearance means both are back to the `aes-ccm` default.

**S12 — mikrotik2's address sat on a bridge port.** `/ip/address/print` now shows
`192.168.1.2/24 ... bridge-local`, no slave flag.

**S13 — Home Assistant account on the switches.** Both devices have `homeassistant` in group
`ha` bound to `address=192.168.1.60/32`, with the group policy matching the main router's
exactly (`read,test,api`, everything else negated), plus the `HA API access` input rule
correctly placed before the terminating drop. Note the caveat from the original finding still
stands: neither switch runs a DHCP server and mikrotik2's wlan1 is CAPsMAN-managed, so HA may
see little from them beyond interface state. Worth confirming the integration reports
something useful before adding all of them to HA.

**Also done, not previously tracked as a finding:** SSH public-key authentication is
configured on all three devices (`/user/ssh-keys/print` shows `admin` / `gehel@durin`) with
`password-authentication=yes` kept as the fallback, which is what was asked for.

**S7 — leftover DHCP configuration.** On mikrotik2, `/ip/dhcp-server/print` and
`/ip/dhcp-server/network/print` both return empty, and the `/ip dhcp-server` sections are
gone from the export — the dormant server bound to `ether2-master-local` with the dangling
`address-pool=*1` no longer exists. On mikrotik3, `/ip/pool/print` is empty and
`/ip/dns/static/print` returns nothing, so the `192.168.88.10-254` pool and the
`router.lan -> 192.168.88.1` record are both gone. mikrotik2 keeps one static record,
`router -> 192.168.1.2`, which is correct and points at itself.

**S10 — orphaned OSPF areas.** `/routing/ospf/area/print` and `/routing/ospf/instance/print`
both return empty on both devices, and no `/routing` section survives in either export.

**S11 — mikrotik2's OVPN server.** `/interface/ovpn-server/server/print detail` returns
empty and the `/interface ovpn-server server` section is gone from the export. The only
crypto config left on either device is the IPsec proposal at `aes-256-cbc` and a default
IPsec profile carrying nothing but DPD timers.

**S14 — SSH weak defaults.** `/ip/ssh/print` on **all three** devices now reports
`strong-crypto: yes` and `host-key-size: 4096`, with `password-authentication: yes` retained
as the fallback. Verified functionally as well as by print: `dump-configs.sh` completed a
full authenticated run against all three devices after the host keys were regenerated, which
is the check that matters — a broken algorithm negotiation would have failed the run
outright rather than showing up in any single command's output.

## Tooling

### Dump script

`dump-configs.sh` gained `/ip/pool/print`, `/ip/dhcp-server/print`,
`/ip/dhcp-server/network/print`, `/ip/dns/static/print`, `/routing/ospf/area/print`,
`/routing/ospf/instance/print` and `/interface/ovpn-server/server/print detail` on
2026-09-05. These are absence checks: `/export` only prints configuration that exists, so
proving something was removed needs a print that comes back empty rather than a section that
merely fails to appear.

**S16 — mikrotik3 had no working out-of-band recovery path.** `ether1` moved from the `WAN`
interface list to `LAN`, which is what neighbour discovery, MAC-Telnet and MAC-Winbox all
key off. Confirmed in both directions: `/ip/neighbor/print` on mikrotik1 now lists
`MikroTik - Office` at `192.168.1.3`, and mikrotik3's own neighbour table — previously
completely empty — now shows mikrotik1 and mikrotik2, **both on `ether1`**. That last detail
confirms the diagnosis rather than merely the fix: `ether1` is in fact the uplink, so
discovery and MAC-Telnet had been deaf on the only port that reaches the network. The
recovery path was then proven rather than inferred — `/tool/mac-telnet 74:4D:28:C9:4F:FD`
from mikrotik1 reached a login prompt and authenticated, before any change that could
strand the device.

**S15 — mikrotik3 took its address from DHCP.** Converted via a `/system/script`, so the
sequence completed despite the session dropping when the address went away. Verified after
a reboot, with the dump collected at 1m14s uptime:

```
/ip/address/print    ;;; static management
                     0  192.168.1.3/24  192.168.1.0  bridge      (no D flag)
/ip/route/print      ;;; static default
                     0  As  0.0.0.0/0  192.168.1.1                (As, not DAd)
/ip/dns/print        servers: 192.168.1.40   dynamic-servers: (empty)
/ip/dhcp-client/print
                     0  X  bridge  ...  stopped
```

The temporary script was removed and does not appear in the export. mikrotik1's reservation
for `192.168.1.3` was deliberately kept as a safety net.

Addressing across the estate now reads: mikrotik1 static on both bridges with `ether1`
dynamic by design (WAN lease from the Internet-Box), mikrotik2 static with its DHCP client
shelved as `disabled=yes`, mikrotik3 the same. mikrotik4 to match when it returns.

## VLAN segmentation — Phases 0-4 (2026-09-06 to 2026-09-08)

Full design and current state live in [vlan.md](vlan.md); Phase 5 is what's left. This entry
records what's actually done, closed the way every other entry in this file is: with the
output that verified it, not just the change that was made. Ordered chronologically, except
where noted (the ceiling fan was deliberately moved out of its planned order).

### Phase 0 — preparation

All steps completed on mikrotik1 and verified against live output: backups (`pre-vlan.backup`
and `.rsc`) taken and downloaded from all three devices via a new `fetch-backups.sh`; stale
domain (`ledcom.ch` → `home.ledcom.fr`) corrected on both DHCP networks; `dhcp-home` lease
time shortened to 5m ahead of the later renumber; two long-dead DHCP reservations removed;
CAP interface names stabilized to `ap-MikroTik-1` / `ap-MikroTik-Switch-1`
(`name-format=prefix-identity`); NTP server enabled. The Fonera and its entire `bridge-fon`
config (firewall rules, DHCP server, pool, address, bridge, address-list) were deleted
outright — verified clean via `/ip/firewall/filter/print` showing no remaining reference —
and the freed ports (`ether3`, `ether6`-`ether10`) folded into `bridge-main`.

### Phase 1 — VLAN plumbing and wireless tagging

`vlan-filtering=yes` on all three bridges, with VLAN 10/20/30 tables configured per the port
map in `vlan.md`. Went through real trouble getting here, all now folded into the plan as
corrections — the short version: a device's own management IP needs a real `/interface vlan`
sub-interface, not just VLAN-table membership, to survive `vlan-filtering=yes`; the address
move, DHCP-server rebind, and any interface-keyed firewall rules all have to land atomically;
and CAPsMAN's wireless datapath needs its own explicit `vlan-mode=use-tag` — the bridge-VLAN
table alone isn't sufficient. Verified working: all three devices reachable at
`192.168.1.1/2/3` (unrenumbered at this point) with `vlan-filtering=yes` holding through a
reboot test on mikrotik3; wireless clients (desktop, TV) confirmed getting real DHCPv4 leases
over WiFi, not just association.

**Side effects surfaced and fixed along the way, not part of the original Phase 1 scope:**
IPv6 had never been migrated off `bridge-main` — fixed, full write-up in
[ipv6.md](ipv6.md)'s "Migrated onto `vlan-users`" section. That same investigation identified
the source of a previously "possible" rogue IPv6 router advertisement: Home Assistant's
OpenThread Border Router, working as designed, not a bug — the actual defect was mikrotik1's
own IPv6 config being left on `bridge-main`, fixed and verified here.

### Phase 2 — renumber to 192.168.10.0/24

All three devices moved from `192.168.1.0/24` to `192.168.10.0/24`. Done via a dual-homing
technique to sidestep a chicken-and-egg reachability problem (mikrotik1 held both
`192.168.1.1/24` and `192.168.10.1/24` simultaneously while mikrotik2 and mikrotik3 were
migrated one at a time, only dropping the old address once everything else was confirmed on
the new subnet).

Twelve DHCP reservations migrated by MAC address (IotaWatt, Home Assistant, Pi-hole, both
OctoPrint entries, the desktop, a phone, two Tasmota lights, a laptop, the ceiling fan, and
mikrotik3's own safety-net reservation); the long-dead kitchen-light Tasmota reservation
deleted rather than migrated; a new reservation added for the printer, which had never had one
despite the design assuming stable addressing for it. `mgmt` address-list and the `HA API
access` rule updated on all three devices; the HTTPS NAT forward to Home Assistant updated.

**Verified:** every device reachable at its `192.168.10.x` address; DHCP issuing
`192.168.10.x` to fresh and renewing clients; internet and DNS working; Home Assistant
reachable locally and remotely (external HTTPS access confirmed from cellular data); mikrotik3
rebooted and came back on `192.168.10.3` unassisted; wireless (LEDCOM) confirmed broadcasting
and connectable after a CAPsMAN reconnection issue was fully resolved; non-overlapping wireless
channels (1 and 11) confirmed still correctly assigned per-radio after all the reconnection
work. A follow-up `dump-configs.sh` grep for literal `192.168.1.` references across all three
exports, plus a cleanup pass, closed out every remaining leftover (stale DNS server settings on
mikrotik2/mikrotik3, stale local `router` DNS records, the deliberately-kept old `mgmt`/`HA API
access` entries, `admin`'s temporarily-widened address restriction narrowed back down, and
mikrotik1's SNMP community address restriction cleared entirely since SNMP stays disabled).

**Real gaps found only via live failures, each now documented in `vlan.md` and `README.md`'s
hard-won lessons for Phase 3:** the `admin`/`homeassistant` user-account `address=`
restriction is separate from any firewall rule and isn't found by reading firewall config; a
NAT rule's `to-addresses=` and its paired forward-chain accept rule are two separate things to
update, not one, and missing the second produces a silent drop rather than an error; a
forward-chain `drop` rule blocking a specific IoT device by literal address silently stopped
enforcing once that device renumbered — a renumber can quietly remove a security restriction,
not just break connectivity; and CAPsMAN's own discovery config hides literal IP references in
three separate places (`/interface/wireless/cap`, `/ip/dhcp-server/network`'s `caps-manager=`,
and `/caps-man/manager/interface`'s listening-interface list) that took down both wireless
radios entirely when missed.

Also recorded in `README.md`: `/ip/dhcp-server/network/set [find address=...]` and
`/ip/firewall/filter/remove [find ... and ...]` (multiple conditions combined with `and`) both
silently match nothing on this RouterOS version, with no error — the second is a repeat
appearance of a bug pattern already documented in this file's 2026-09-04 FON-network finding,
missed here because the earlier lesson wasn't carried forward into the new work.

### Phase 3, block 1 — services/iot VLAN interfaces, addressing, DHCP, NTP option 42 (2026-09-07)

Applied via `home/network/scripts/phase3-01-networking.rsc` (idempotent, `find`-guarded) on
mikrotik1: `vlan-services`/`vlan-iot` interfaces on `bridge-main`, their `.20.1`/`.30.1`
gateway addresses, `pool-services`/`pool-iot`, `dhcp-services`/`dhcp-iot` servers, and the
`ntp-users`/`ntp-services`/`ntp-iot` DHCP option-42 definitions (mikrotik1's own address on
each VLAN, so IoT and services clients can get NTP without internet access).

`ntp-services`/`ntp-iot` were wired into their networks' `dhcp-option=` inline as part of the
`add` (a fresh object, so the known `network/set [find address=...]` bug doesn't apply).
Retrofitting `ntp-users` onto the pre-existing `192.168.10.0/24` network needed the documented
workaround: printed the network table, found it at index `0`, `set 0 dhcp-option=ntp-users`,
re-printed to confirm.

**Verified** by `import ... dry-run` followed by `import`, then the script's own end-of-run
`print` of every object created, plus a fresh `dump-configs.sh` run (16:58) confirming all of
it landed. No impact to the management path — none of this touches `bridge-main`,
`vlan-users`, or any existing address.

### Phase 3, block 2 — LEDCOM-IoT SSID on both CAPsMAN radios (2026-09-07)

Applied via `home/network/scripts/phase3-02-iot-ssid.rsc`: `caps_iot` configuration
(`ssid=LEDCOM-IoT`, `datapath.vlan-id=30`, `datapath.vlan-mode=use-tag` on `bridge-main`),
added as `slave-configurations=caps_iot` on both provisioning rules (the `caps_ch11`
radio-mac-specific one and the `caps_config` catch-all), then `/caps-man/remote-cap/provision
[find]`.

**Verified** by the script's own `print detail` of the new configuration and both
provisioning rules, both showing `slave-configurations=caps_iot`. No wireless-outage reports
during the reprovision.

### IPv6 RDNSS was leaking the ISP's own DNS server, bypassing Pi-hole (2026-09-07)

Found while scoping the Home Assistant VLAN migration: a dual-stack desktop's `dig` for a name
with both a public and a Pi-hole-local answer got the public one — a second instance of
[config-review.md](config-review.md)'s finding 8 (DNS can bypass Pi-hole). See
[ipv6.md](ipv6.md) for the current IPv6 configuration this fix is now part of.

Two fix attempts before the real one. First: `use-peer-dns=no` on the IPv6 DHCP client
(`ether1`), on the theory that DHCPv6-PD's peer-DNS copy was populating `/ip/dns`'s
`dynamic-servers` with the ISP's IPv6 resolver, which `/ipv6/nd`'s `advertise-dns=yes` then
re-advertised via RDNSS on `vlan-users`. That didn't clear the existing lease's entry, so a
follow-up forced both `ether1` DHCP clients (v4 and v6) to release and rebind, and set
`use-peer-dns=no` on the **IPv4** client too — which turned out to be an independent, real
leak of its own (`10.1.1.1`, the Internet-Box's IPv4 address, into the same `dynamic-servers`
list). That part worked and stayed fixed. **The IPv6 entry survived a full DHCPv6-PD
release/rebind with `use-peer-dns=no` already set** — proof DHCPv6 was never its actual
source.

Actual cause: `/ipv6/settings`' `accept-router-advertisements=yes` on `ether1` (needed for this
router's own WAN default route) also accepts the RDNSS option carried in the Internet-Box's own
RA on that link, with no DHCPv6 involved. That can't be turned off without breaking the WAN
route, so the real fix scopes the *other* end instead: `advertise-dns=no` on the `/ipv6/nd`
entry, stopping `vlan-users` from advertising any DNS server via RA at all — matching what this
project already intended (clients resolve via Pi-hole over the IPv4 DHCP-assigned server).

**Verified:** `/ipv6/nd/print detail` shows `advertise-dns=no`. On the desktop,
`resolvectl status` already showed `Current DNS Server: 192.168.10.40` before this last fix
(the IPv4-side cleanup was enough for that), and `dig home.ledcom.fr` returned `192.168.10.60`
from Pi-hole. The IPv6 entry lingered in `resolvectl`'s server list after the fix — expected:
`resolvectl flush-caches` clears cached answers, not the RA-learned server list, which has its
own RFC 8106 lifetime and ages out client-side within the `ra-lifetime=30m` window once the
router stops sending it; there is no explicit withdrawal message, only omission.

Scripts: `scripts/fix-ipv6-rdnss-dns.rsc`, `scripts/fix-ipv6-rdnss-dns-cleanup.rsc`,
`scripts/fix-ipv6-rdnss-dns-v2.rsc` (the one that actually closed it).

### Phase 3, step 1 — printer migrated to services (2026-09-07/08)

Moved via `scripts/phase3-03a-printer-mikrotik3-port.rsc` (mikrotik3: `ether2` from VLAN 10 to
VLAN 20 — both the bridge-vlan table membership and `pvid`, the two-command move `vlan.md`
flags) and `scripts/phase3-03b-printer-mikrotik1-dhcp.rsc` (mikrotik1: DHCP reservation to
`192.168.20.110` on `dhcp-services`, matched by MAC).

Also enabled `/ip/dns mdns-repeat-ifaces=vlan-users,vlan-services` early (a scoped-down piece
of Phase 4, brought forward because the printer needed it immediately) via
`scripts/phase3-04-mdns-repeat-early.rsc`.

**Verified:** `/interface/bridge/vlan/print` and `/interface/bridge/port/print` on mikrotik3
show the target state; the DHCP lease went `status=bound`, `active-address=192.168.20.110`,
`active-server=dhcp-services` within its lease window, no power-cycle needed. Printing via a
manually-configured static URI (`ipp://192.168.20.110/ipp/print` or
`socket://192.168.20.110:9100`) succeeded from the desktop.

**Real gap found and root-caused, not a blocker:** printing through a printer added via mDNS
*discovery* (GNOME/CUPS's `dnssd://` URI) hung on "processing" / "Unable to locate printer".
Root-caused with `/tool/sniffer/quick` run on both VLANs simultaneously while retrying the
resolve: the router's `mdns-repeat-ifaces` proxies a client query onto the other VLAN under its
own address (`192.168.20.1`, not the desktop's), the printer answers it, and the router drops
that reply instead of repeating it back to the querying VLAN — confirmed by a clean capture
showing the query and its answer on `vlan-services`, and nothing but the original query on
`vlan-users`. Spontaneous, unprompted announcements repeat fine both ways (that's how discovery
found the printer's name at all); only the reply to a router-proxied query goes missing. A
specific RouterOS defect, not a firewall or avahi issue, and not fixable from the config side.
Confirmed static-URI workaround (`ipp://192.168.20.110/ipp/print` or
`socket://192.168.20.110:9100`) treated as the permanent approach for any cross-VLAN mDNS
consumer going forward. Full writeup in `vlan.md`'s Phase 4 section and its "Known unverified
assumptions" #2.

### Printer reverted from services back to users (2026-09-08)

Migrated to `services` as Phase 3 step 1 above, then moved back the same week once the
mDNS-repeater defect was root-caused: `mdns-repeat-ifaces` doesn't reliably deliver working
autodiscovery across VLANs (queries get proxied and answered, but the router drops the reply
on the way back — see the printer migration entry above for the capture, and `vlan.md`'s
Decisions section). Confirmed independently on the [MikroTik forum](https://forum.mikrotik.com/t/mdns-repeater-forwarding-queries-but-not-all-responses-across-vlans/269317)
— RouterOS 7.20, identical symptom. Guillaume's household needs a non-technical user to be able
to add this printer on her own phone and laptop without manual IP configuration, which
outweighs keeping it on `services`.

Reverted via `scripts/phase3-revert-printer.rsc` (mikrotik3: `ether2` back to VLAN 10,
`pvid=10`), `scripts/phase3-revert-printer-dhcp.rsc` (mikrotik1: DHCP reservation back to
`192.168.10.110` / `dhcp-home`), and `scripts/phase3-revert-mdns-repeat.rsc` (mikrotik1:
`mdns-repeat-ifaces` cleared entirely — its only beneficiary was the printer, and it didn't
reliably deliver its purpose anyway; re-enable later, eyes open, only if Pi-hole/HA/IoT
discovery actually needs it).

**Verified:** `/interface/bridge/vlan/print` and `/interface/bridge/port/print` on mikrotik3
show `ether2` back on VLAN 10; the DHCP lease went `status=bound`,
`active-address=192.168.10.110`, `active-server=dhcp-home` within its lease window, no
power-cycle needed; discovery and adding the printer worked cleanly from the household's
non-technical user's own phone and laptop (same-VLAN mDNS, no repeater involved). The printer
is no longer part of the Phase 3 device migration — `vlan.md`'s device inventory, target
design, policy matrix, trunk/port plan, and migration table were all updated to reflect it
staying on `users` permanently.

### Phase 3, step 2 — Pi-hole migrated to services (2026-09-08)

Moved via `scripts/phase3-05a-pihole-mikrotik2-port.rsc` (mikrotik2: `ether23-slave-local` from
VLAN 10 to VLAN 20). VLAN 10's untagged list is 25 ports on this device — built the target list
programmatically from the live value rather than hand-retyping it, to avoid a transcription
error at that size; confirmed by a before/after port count (25 -> 24) rather than eyeballing
the list.

**Real gap found and fixed, not deferred to Phase 4:** the policy matrix always said `services
-> internet: allow`, but no rule anywhere actually implemented it — only `vlan-users` had a
broad "connect everywhere" accept, and VLAN sub-interfaces don't inherit `bridge-main`'s rules.
Without this, Pi-hole would have had no upstream DNS resolution at all. Added via
`scripts/phase3-05b-pihole-mikrotik1-dhcp-and-fw.rsc`, `place-before=` the catch-all drop (a
plain `/add` appends to the end of the chain, which would have put it after the
already-unconditional drop and made it dead). Also moved the DHCP reservation to
`192.168.20.40` / `dhcp-services` in the same script.

DNS repointed only after confirming Pi-hole was live and resolving at the new address
(`dig @192.168.20.40 google.com` succeeded, proving both DNS and the new firewall rule worked):
mikrotik1's own `/ip/dns servers=` and the *"Accept DNS requests from Pi-hole"* rule's
`src-address=` (`scripts/phase3-05c-pihole-mikrotik1-dns.rsc`); mikrotik2 and mikrotik3's
independent `/ip/dns servers=` (`-05d-`, `-05e-`); and, by hand rather than scripted (the
confirmed `/ip/dhcp-server/network/set [find address=...]` bug), the `192.168.10.0/24`
network's `dns-server=`, via its numeric index (`0`).

**Verified:** DHCP lease `status=bound`, `active-address=192.168.20.40`,
`active-server=dhcp-services`; `dig @192.168.20.40 google.com` resolved successfully; all three
devices' `/ip/dns/print` and the DHCP network table show `192.168.20.40` throughout; a plain
`dig google.com` (no `@server`) from the desktop on `vlan-users` resolved correctly via its
stub resolver, confirming the full DHCP -> `dns-server=` -> Pi-hole chain works end-to-end for
a real client, not just the router itself. Guillaume also updated Pi-hole's own local DNS
record for itself to its new address (a Pi-hole-side admin change, not a router one).

### Phase 3, step 3 — Home Assistant migrated to services (2026-09-08)

Moved via `scripts/phase3-06a-ha-mikrotik2-port.rsc` (mikrotik2: `ether21-slave-local` from
VLAN 10 to VLAN 20 — this time VLAN 20's untagged list already had Pi-hole's port on it, so the
script read-modified-appended both sides programmatically rather than overwriting, to avoid
dropping Pi-hole's membership). `scripts/phase3-06c-ha-mikrotik1.rsc` moved the DHCP
reservation to `192.168.20.60`/`dhcp-services`, updated the dst-nat HTTPS port forward *and*
its paired forward-chain rule, and added a temporary `users -> services tcp/1883` rule for IoT
devices still on `users` to reach HA's MQTT broker (to be removed at Phase 4, per `vlan.md`).
`scripts/phase3-06b-`/`-06d-ha-mikrotik*.rsc` updated the `homeassistant` account's
`address=192.168.20.60/32` restriction and the *"HA API access (post-renumber)"* rule's
`src-address=`, independently on mikrotik2 and mikrotik3 (same pattern as Pi-hole: these exist
as separate copies per device, not shared config).

**Verified quickly:** DHCP lease bound at `192.168.20.60`; local HTTPS
(`https://192.168.20.60`) and remote/external HTTPS both worked immediately.

**The MikroTik integration inside HA took much longer to get right, through two real mistakes
before the actual root cause:**

1. **Real gap, found and fixed:** nothing allowed `vlan-services -> vlan-users` at all — the
   account restriction and API-access rule only govern the *destination's own input chain*;
   they don't get HA's packets there. Added a narrow exception
   (`scripts/phase3-08-ha-mikrotik-integration-access.rsc`): an address-list of just
   mikrotik2/mikrotik3's management IPs, `src-address=192.168.20.60`, `dst-port=8728`.
2. **Mistake 1 — my own idempotency guard was wrong.** The address-list `add`s were guarded by
   `find where address=<ip>` with no list filter; both IPs already existed in the `mgmt` list
   (from Phase 2), so the guard concluded "already exists" and silently skipped creating the
   `ha-mikrotik-targets` entries — the filter rule referenced an empty list and matched
   nothing. An unverified claim in my own comment ("neither address is used elsewhere") turned
   out to be false. Fixed in `scripts/phase3-08b-ha-mikrotik-targets-fix.rsc`, matched by
   `comment=` instead (safely distinct from the `mgmt` list's differently-worded comments).
3. **Mistake 2 — repeated a mistake already documented in this same file.** The filter rule was
   added with a plain `/add`, landing it *after* the unconditional "Drop all other forward
   traffic" catch-all — dead on arrival, exactly the failure mode already written up for the
   `services: internet` rule above, not applied consistently here. Fixed by moving the rule
   (`scripts/phase3-08c-ha-mikrotik-rule-reorder.rsc`) rather than recreating it.
4. **A genuine RouterOS finding, not a mistake:** once correctly placed, the rule still showed
   `I - INVALID` until `connection-state=new` was added — a forward-chain accept rule combining
   `in-interface=`/`out-interface=` with `dst-address=`/`dst-port=` needs it on this RouterOS
   version, confirmed by comparison with every other working custom rule on this router (all of
   which already had it). Fixed the same gap throughout `vlan.md`'s Phase 4 draft while it was
   fresh, before it could bite again later.
5. **The actual root cause, after all of the above was already correct:** mikrotik2 and
   mikrotik3 had **no default route at all** — only the directly-connected `192.168.10.0/24`.
   Every prior management connection to their own IPs had come from within `vlan-users` itself
   (same subnet, no gateway needed for the reply); HA's new address was the first-ever
   cross-subnet connection to either switch's management IP. They could accept the incoming SYN
   (confirmed live: fresh packets matched the input-chain rule on both), but had no route back
   out to reply, so the TCP handshake never completed — explaining why **nothing at all** was
   ever logged, not even a `login failure`: the API layer never saw a completed connection.
   Root-caused via a careful reset-counters-then-retry test isolating each hop, plus checking
   `/log/print` for a `login failure` message (found in an *old*, pre-migration log entry,
   confirming RouterOS does log auth failures clearly — just under `system,error,critical`, not
   the `account` topic, a wrong filter that cost real time here). Fixed with
   `scripts/phase3-09-switch-default-routes.rsc` — `/ip/route/add dst-address=0.0.0.0/0
   gateway=192.168.10.1` on each switch. **Confirmed working on both mikrotik2 and mikrotik3.**

**A caution for next time:** the packet counters this session initially misled — RouterOS
firewall rule counters are cumulative since the rule's *creation* and are not reset by a
`/set` that changes match criteria, so a nonzero counter on a long-lived rule proved nothing
about current traffic. `reset-counters` before a retry, on a freshly-relevant rule, is the
reliable way to get a clean signal.

**Likely worth adding to README.md's hard-won lessons:** a pure L2 switch whose only IP is a
management address needs its own default route the moment any management client can be on a
different subnet than that address — not just correct bridge/VLAN forwarding. The failure mode
is silent and produces no log at all, which makes it easy to misdiagnose as a firewall or
credentials problem.

### Phase 3, step 7 — ceiling fan migrated to iot, out of order (2026-09-08)

Moved before OctoPrint/IotaWatt/Kids light, deliberately overriding `vlan.md`'s "do this one
last" caution, to have it working that same evening. Wireless device, no port to move.

`scripts/phase3-10-ceilingfan-mikrotik1.rsc`: DHCP reservation to `192.168.30.63`/`dhcp-iot`;
**retired the standing `chain=forward action=drop src-address=192.168.10.63` rule** (a
"deliberately distrusted device" restriction from an earlier config-review round) rather than
carrying it to the new address — `vlan-iot` isolation now does that job by construction; added
the general `iot -> Pi-hole DNS` accept rules (pulled forward from Phase 4, first real device
on `vlan-iot`); added the fan's own DNS-drop rules, created `disabled=yes`; added a
tcp/80,443 internet-access toggle for the fan specifically, created enabled, for that night's
reconfiguration (the fan is known to phone home to a vendor cloud service, confirmed in its
original config-review finding, so reconfiguration needed DNS+internet).

**A second, broader temporary rule** (`scripts/phase3-12-iot-temp-internet.rsc`): whole-`vlan-
iot` internet access, no port restriction, enabled for pairing Guillaume's phone to
`LEDCOM-IoT` during the Tuya app's pairing flow — broader than the usual named-exception
pattern, justified by being short-lived and by not wanting a guessed-wrong port to cost a
retry mid-pairing.

**A real, previously-unanticipated policy gap found live:** HA's `tuya-local` integration talks
directly to the device over Tuya's local protocol (tcp/6668), bypassing Tuya's cloud — not in
the original policy matrix, which only listed HA on 6053/80 for ESPHome/Tasmota. Added
`services -> iot` tcp/6668 (`scripts/phase3-13-ha-tuya-local.rsc`), same shape as the existing
`HA -> Tasmota/IotaWatt` rule; folded into `vlan.md`'s policy matrix and Phase 4 draft.

Once HA confirmed the fan working: disabled both temporary internet rules and enabled the
fan's DNS-drop rules (`scripts/phase3-14-ceilingfan-lockdown.rsc`). **Verified the fan still
responds correctly in HA after lockdown** — dropping its DNS didn't affect local Tuya control,
as expected.

**Further work on the `I - INVALID` flag, refining what was already found for HA:** three new
rules added during this step (`iot: DNS to pi-hole` ×2, `ceiling fan: TEMP internet for setup`)
showed the flag despite already having `connection-state=new` — because each specified only
*one* interface direction alongside an address/port matcher, not both. Fixed by adding the
missing interface (`scripts/phase3-11-fix-invalid-rules.rsc`). Then, once the fan's DNS-drop
rules were finally *enabled* (they were created `disabled=yes` and looked clean while off), the
flag appeared on *them* too — a `drop` rule combining `src-address=` and `dst-address=` with
no interface at all. Fixed by adding both interfaces there as well
(`scripts/phase3-15-fix-dns-drop-invalid.rsc`). Net finding: RouterOS doesn't evaluate this flag
on disabled rules at all, and the actual set of triggers is broader than "accept rules need
`connection-state=new`" — see `README.md`'s hard-won lessons for the fuller list. Also applied
the same interface-completeness fixes to `vlan.md`'s Phase 4 draft, which had five more rules
with the identical one-interface-plus-address/port pattern, so Phase 4 doesn't hit this again
when it's actually run.

**Verified throughout via the forward chain's own `print` output** (not just individual rule
checks) — printing the whole chain in order after each change caught the ordering and
placement issues immediately, which checking one rule at a time would have missed.

### Phase 3, step 6 — Kids light migrated to iot (2026-09-08)

Wireless Tasmota device, no port to move. Moved via
`scripts/phase3-16-kidslight-mikrotik1.rsc`: DHCP reservation to `192.168.30.61`/`dhcp-iot`,
and the permanent `iot -> services` MQTT rule (tcp/1883, dst-address=192.168.20.60) — pulled
forward from Phase 4, first device to actually need it (the TEMP `users -> services` version
added during HA's migration only covers devices still on `vlan-users`). Both interfaces +
`connection-state=new` from the start, per the `I - INVALID` findings from the ceiling fan
work — printed clean immediately, no follow-up fix needed this time.

Guillaume rejoined the device to `LEDCOM-IoT` via Tasmota's own console/web config (not
scripted). **Verified: connected to HA successfully.**

**DHCP option 42 finding, corrected twice — full account in `vlan.md`'s "Known unverified
assumptions" #3.** After migrating, the device was still pointed at `192.168.10.1` — the exact
value this project's own `ntp-users` option-42 entry provides, acquired while it was still on
`vlan-users` and persisted across the VLAN move rather than refreshed. Manually repointed via
Tasmota's console (`NtpServer1 192.168.30.1`, confirmed applied) — but time still didn't sync.
**Actual remaining root cause:** mikrotik1's `chain=input` had no rule permitting UDP/123 from
`vlan-iot` at all — the Phase 4 draft's `iot: NTP from gateway` rule was never pulled forward
like the others were. Fixed via `scripts/phase3-17-iot-ntp-input.rsc` — printed clean, no `I`
flag, resolving the open question of whether the interface-completeness half of that finding
also applies to `chain=input` (it doesn't appear to — see `README.md`). **Verified: Tasmota's
`Status 7` shows correct local time**, no longer stuck at the 1970 epoch.

### Phase 3, step 4 — OctoPrint router-side config prepared, not yet verified (2026-09-08)

OctoPrint was powered off, so this is router-side prep only — deliberately not claimed as
"done and verified" until it's actually running and tested.

`scripts/phase3-18-octoprint-mikrotik1.rsc`: both DHCP reservations (wifi, in use; wired,
known-dead cable but kept for when it's fixed) moved to `192.168.30.81`/`.80` on `dhcp-iot`;
both addresses added to the `iot-internet` address-list with the actual allow rule (tcp
80/443 to WAN) — the "named exception" design decided back on 2026-09-06 but never applied
since nothing was on `vlan-iot` yet. Deliberately skipped a direct `iot-internet -> WAN udp/53`
rule from the original design sketch — the general `iot: DNS to pi-hole` rule already covers
this via Pi-hole's own recursion, so a second path would be redundant. Printed clean, no `I -
INVALID` flag (had both interfaces + `connection-state=new` from the start).

**A real gap caught before it could bite:** the original port/trunk plan never assigned
OctoPrint's wired connection to any specific physical port, since it was wireless-only when
that plan was drawn up and its cable was already known dead. Guillaume physically checked and
found it plugged into mikrotik2's `ether24-slave-local`. Tagged for VLAN 30 via
`scripts/phase3-19-octoprint-mikrotik2-port.rsc` (same read-modify-write approach as the
Pi-hole/HA moves, to avoid retyping VLAN 10's long untagged list) — so whenever that cable is
actually fixed, it comes up on the right VLAN without anyone having to remember this step.
Port shows `Flags: I - INACTIVE` (no link detected) — normal, given the cable is still down;
not the same `I` as the firewall's `I - INVALID`, and expected to clear once there's a live
link.

**Not verified, left for when OctoPrint is actually running:** whether HA's OctoPrint
integration needs a port beyond what `HA -> Tasmota/IotaWatt` (tcp/80) already opens — if it
uses OctoPrint's own default port 5000 instead, that'll need a new rule, discovered live the
same way tuya-local's port 6668 was for the ceiling fan.

### OctoPrint verified, after a reimage (2026-09-08)

Guillaume lost OctoPrint's system password before it was ever fully tested on `vlan-iot`;
backed up its config via OctoPrint's own Backup & Restore and reimaged the SD card fresh
rather than recover the old install. Reconnected to `LEDCOM-IoT` on the new image — no router
config changes needed, the DHCP reservation and firewall rules from the step above already
covered it.

**Verified:** mikrotik1's CAPsMAN registration table shows a freshly-connected client on
`ap-MikroTik-1-1` / `LEDCOM-IoT` (uptime ~53 minutes at dump time, matching the reimage
timeline). Home Assistant's OctoPrint integration reconfigured with a new API key against
`octoprint-wifi.home.ledcom.fr` and has logged zero errors since (see
`home/home-assistant/changelog.md`). The port-80-only question above turned out moot: nothing
in HA's logs asked for port 5000.

### Phase 3, step 5 — IotaWatt router-side config applied, not yet verified (2026-09-08)

Wireless ESPHome device, no port to move. Moved via
`scripts/phase3-20-iotawatt-mikrotik1.rsc`: DHCP reservation to `192.168.30.50`/`dhcp-iot`, and
the Phase 4 draft's `HA -> Tasmota/IotaWatt` rule (tcp/80, services -> iot) pulled forward —
needed if HA polls IotaWatt's local HTTP API directly rather than only listening over MQTT
(the general `iot: MQTT to HA` rule, already live since Kids light's migration, covers that
side unconditionally). Printed clean, no `I - INVALID` flag.

**Not verified — Guillaume couldn't reach the device after the move, but suspects it may have
already been disconnected for some time, independent of this migration.** Router-side config
is confirmed correctly applied; whether it actually works once the device is reachable again
(MQTT, the new HTTP rule, DHCP option 42 vs. ESPHome, NTP) is still open. Investigating
separately.

### Phase 4 — firewall policy applied (2026-09-08)

Applied ahead of finishing OctoPrint/IotaWatt device-side verification — Guillaume's explicit
call, since he plans to test over the coming days rather than block on it now. Deliberately
did **not** use a scheduled auto-revert here, unlike earlier risky changes: that pattern exists
for changes that could cut off the management session itself, which this doesn't (it only
restricts `users -> services/iot`, never access to the router), and an auto-revert would have
undone everything before any real-world testing happened. The actual safety net is Phase 5's
own plan — the logged drops added here are exactly what that evidence-gathering reads.

Via `scripts/phase4-01-firewall-policy.rsc`: filled every gap in the Phase 4 draft that wasn't
already pulled forward piecemeal during device migrations — `iot: deny everything else`
(logged), `HA -> ESPHome (IotaWatt)` (tcp/6053, a port the policy matrix always listed but the
draft never actually included), `services: no users` (logged), `mgmt hosts: full`, `users:
DNS`, `users: HA web`, `users2services` (logged), `mgmt hosts: iot`, `users2iot` (logged — the
draft had no logging or comment on this one at all, an oversight caught and fixed here).
Confirmed `mdns-repeat-ifaces` empty, not re-enabled (Guillaume's explicit call, given the
known cross-VLAN resolve limitations). The existing broad `Home can connect everywhere
(vlan-users)` rule was left untouched — every new rule inserted ahead of it, so
`users -> internet` keeps working exactly as before while `users -> services/iot` now hits the
narrow allows and logged drops first.

**A genuinely new `I - INVALID` trigger, distinct from every prior one:** the script cached a
single `find` result (`:local catchall [...]`) and reused it via `place-before=$catchall`
across nine separate `/add` calls. The *last* of those nine (`users2iot`) came up invalid
despite being structurally identical (drop, both interfaces, no address/port matcher, no
`connection-state`) to an earlier rule in the same batch that was valid. Removing and
re-adding it with a freshly-evaluated `place-before=[find ...]` (not the cached variable) fixed
it immediately, no other change — `scripts/phase4-02-fix-users2iot-invalid.rsc`. Lesson: always
re-evaluate `find` fresh at each insertion, even within a single script; don't cache and reuse
a `place-before=` target across multiple `/add`s. Full detail in `README.md`'s hard-won
lessons.

**Verified: full forward chain printed clean, no `I` flags anywhere**, narrow rules correctly
ordered ahead of the broad `vlan-users` allow. Not yet verified: real-world behavior over the
coming days (Phase 5's job) and the two still-pending devices (OctoPrint, IotaWatt).

**[config-review.md](config-review.md)'s finding 8 (DNS can bypass Pi-hole) is now closed by
this.** `vlan-iot` denies internet by default with only a narrow named-exception list (ports
80/443 for OctoPrint, no DNS in it), so an IoT device can no longer reach any external resolver
at all — strictly stronger than the redirect finding 8 originally proposed, as intended when it
was deferred into this work. `vlan-users` keeps its existing broad internet access unchanged;
that was already accepted as a tolerable risk for that segment, not part of what this closes.

### Phase 5 firewall cleanup — findings 19 and 20 closed (2026-09-09)

`config-review.md`'s findings 19 (a Phase-3 TEMP rule, dead code positioned after the
unconditional catch-all drop) and 20 (assorted debris: two more dead `bridge-main`-scoped IPv4
rules, two disabled TEMP setup/pairing rules, and a disabled rule referencing the long-gone
`home` address-list) — all confirmed unreachable or already-inert, nothing here was live
policy. Removed via `scripts/phase5-01-firewall-cleanup.rsc`, one `remove [find where
comment=...]` per rule, matched by comment alone (each confirmed unique beforehand).

Also removed the IPv6 twins of finding 20's dead `bridge-main` pair (`ipv6.md`'s "Migrated onto
`vlan-users`" work had already flagged these as harmless-but-dead and left them for later) —
bundled into the same cleanup since finding 21 (IPv6 for `vlan-services`/`vlan-iot`) was about
to touch this same area anyway.

**Verified:** `/ip/firewall/filter/print` — all 6 IPv4 target rules gone (by comment), all
surviving rules' `vlan-users`-suffixed counterparts intact, no `I` flags, 54 rules remaining
(was ~60). `/ipv6/firewall/filter/print` — both IPv6 target rules gone, only the
`vlan-users`-suffixed pair remains, 14 rules remaining (was 16).

### Phase 5 — forward chain reorganized into one jump-chain per VLAN pair (2026-09-09/10)

Guillaume's call: clean up and improve the IPv4 forward chain before doing anything with IPv6
for `vlan-services`/`vlan-iot` (finding 21, deliberately deferred — see its updated entry in
[config-review.md](config-review.md)). Read MikroTik's
["Building Advanced Firewall"](https://help.mikrotik.com/docs/spaces/ROS/pages/328513/Building+Advanced+Firewall)
guide and applied its jump-chain pattern: one custom chain per traffic relationship
(`users2internet`, `services2internet`, `iot2internet`, `users2services`, `users2iot`,
`services2users`, `services2iot`, `iot2users`, `iot2services`, `internet2services`), a `WAN`
interface list (`ether1`) instead of the literal interface name, and a dispatch section of
`jump` rules ahead of the old individual rules.

Applied via `scripts/phase5-02-firewall-reorg-chains.rsc` in safe mode. Every new rule's
comment is prefixed with its own chain name, deliberately never reusing an old rule's exact
comment text — this project has repeatedly hit `find`/`remove` behaving unreliably on
ambiguous combined conditions, and reusing old comment text would have made the later cleanup
(removing old rules by comment) unsafe. Caught and fixed in my own draft before handoff.

**Three real policy bugs found and fixed during Guillaume's review of the draft, before it was
ever applied:**
- `services2internet` had a blanket `accept connection-state=new` as its first rule, making
  the Pi-hole DNS accept after it permanently dead code — the exact same class of mistake as
  finding 19. Replaced with HTTP/HTTPS (tcp/80,443) from any services host, Pi-hole's own DNS,
  then a logged deny.
- `users2iot` was missing a general exception for OctoPrint's web UI — added
  (tcp/80, dst-address-list=octoprint), plus a new `octoprint` address list. Guillaume edited
  the draft himself to also point `iot2internet` at the same `octoprint` list rather than the
  pre-existing, identical-membership `iot-internet` list I had left it on (my reasoning — "may
  diverge later" — was speculative; consolidating was the better call, applied, `iot-internet`
  scheduled for removal as now-unused).
- `iot2services`' DNS-to-Pi-hole accept was UDP and TCP; narrowed to UDP only (this project has
  never needed DNS-over-TCP for IoT devices), which also made the ceiling fan's TCP DNS-drop
  override redundant — removed.

`internet2services`'s jump was also deliberately scoped with
`in-interface=ether1 out-interface=vlan-services`, tightening what had been an unscoped rule —
safe, since the matching dst-nat can only ever arrive that way.

**Verified live** (pasted safe-mode output): all 25 sub-chain rules present and correct, zero
`I - INVALID` flags anywhere, the 10 dispatch jumps landed right after
fasttrack/established-related and ahead of every old rule. Careful reachability analysis of
that output showed every one of the ~21 old `users`/`services`/`iot`-related forward rules —
including the original, previously-undiscovered bug where `Home can connect everywhere
(vlan-users)` had no `out-interface` restriction, silently bypassing `mgmt`-gating for
`users -> services`/`users -> iot` since Phase 4 — was now provably unreachable: every
destination interface for that traffic is claimed by an earlier terminating jump. No separate
fix was needed for that bug; removing it along with everything else (Phase 5's next step,
`scripts/phase5-06-firewall-reorg-cleanup.rsc`) closes it.

**DNS-over-TLS from Pi-hole, found in logs (2026-09-10).** Guillaume noticed Pi-hole also
resolves upstream over DoT (tcp/853), not just plain DNS — not covered by the reorg. Added via
`scripts/phase5-03-pihole-dot.rsc`, positioned next to Pi-hole's existing DNS accept in
`services2internet`. Verified: correctly placed, no `I` flag.

**Before running the cleanup, reviewed live firewall logs as a safety check** (Guillaume's
explicit request) and found two real gaps the reorg had missed, both invisible before because
the old ruleset never covered them either — not a reorg regression, just newly visible thanks
to the new per-chain log prefixes:
- Home Assistant repeatedly retrying two `vlan-users` hosts it has integrations for: the
  printer (`192.168.10.110`, CUPS/631) and a Samsung TV (`192.168.10.195`, port 8002).
  Confirmed by Guillaume and added to `services2users` via
  `scripts/phase5-04-firewall-additions.rsc`.
- A large burst of TCP/853 (DoT) connection attempts from Home Assistant itself
  (`192.168.20.60`), not Pi-hole — to Cloudflare's `1.1.1.1`/`1.0.0.1`. Left open, not fixed;
  worth understanding before deciding whether it needs an exception or is itself a problem to
  chase down on the HA side.
- The same log review also showed Pi-hole's own NTP traffic (udp/123, to public pool servers)
  being denied — a genuine regression, since the old blanket accept covered it incidentally.
  Not fixed with a firewall rule: Guillaume wants Pi-hole (and other services/IoT clients)
  sourcing time from mikrotik1 itself via the DHCP-advertised NTP option instead of reaching
  the internet directly for it — see the new finding in
  [config-review.md](config-review.md).

**HA-sourced rules tightened to `src-address=192.168.20.60` (2026-09-10).** Guillaume asked
for a pass over every rule whose comment names Home Assistant as the traffic's origin, to
confirm each was actually scoped to HA's address, not just by destination. Five qualified —
the two just-added `services2users` rules (printer, Samsung TV) and three `services2iot`
rules live since `phase5-02` (Tuya local/6668, Tasmota/IotaWatt/80, ESPHome/IotaWatt/6053) —
none had `src-address` set. Fixed via `scripts/phase5-05-restrict-ha-source.rsc`, one `set`
per rule matched by its own comment.

Deliberately left unrestricted: `services2internet`'s HTTP/HTTPS rule (intentionally "any
services host" by Guillaume's own design, not HA-specific), and the `services2iot` rules'
lack of a destination restriction (Guillaume's explicit call — he wants to add IoT devices on
those ports without reconfiguring the firewall each time; source-address scoping to HA is
enough).

**Verified:** `/ip/firewall/filter/print where chain=services2users` and
`where chain=services2iot`, both pasted after each change, matching exactly what was
intended.

**Cleanup applied (2026-09-10) via `scripts/phase5-06-firewall-reorg-cleanup.rsc`** — all 21
dead old rules removed, `iot-internet` address list removed, and the syn-flood/port-scan/WAN-drop
input rules plus the `srcnat` masquerade rule repointed at the `WAN` interface list instead of
literal `ether1`.

Hit one real RouterOS syntax gotcha along the way: `in-interface=""`/`out-interface=""` is
**not** valid syntax to clear a property on `set` — an empty string is treated as an ambiguous
wildcard matching every interface, and RouterOS refuses with "ambiguous value of interface".
Clearing a property needs `!property` instead (e.g. `!in-interface in-interface-list=WAN`).
First attempt hit this mid-script in safe mode (without `dry-run`, so the earlier `/remove`s in
that run had already executed); rolled back via Ctrl+X and re-ran cleanly with `dry-run` first
after the fix.

**A second pass over the live output caught two more things the reorg itself had missed:**
- `"Accept DNS requests from Pi-hole"` — only ever the *anchor* the new dispatch jumps were
  placed before (phase5-02), never itself in the removal list, but dead for the same reason as
  everything else: any Pi-hole -> internet packet already hits the `services -> internet`
  dispatch jump first, which terminates inside `services2internet` (which has its own explicit
  Pi-hole DNS accept). No path reaches it anymore.
- Four rules still hardcoded `ether1` literally instead of the `WAN` interface list created in
  phase5-02 for exactly this purpose: the three internet-facing dispatch jumps
  (`users2internet`/`services2internet`/`iot2internet`) and the `internet2services` jump, plus
  the Home Assistant HTTPS `dst-nat` rule.

Both fixed via `scripts/phase5-07-firewall-final-polish.rsc`.

**Verified: full forward chain and NAT table printed clean** — 20 forward-chain rules total (2
established/fasttrack, 10 dispatch jumps all using `WAN` where they reference the internet
side, then the pre-existing anti-scan/anti-spam/bogon rules, unchanged), NAT's `masquerade` and
`dst-nat` both on `WAN`, `iot-internet` gone from the address-list table, no leftover VLAN-era
rules anywhere.

**Two more gaps found from a second round of log review (2026-09-10), after `dump-logs.sh`
made it easy to check regularly:**

- **Pi-hole needs DNS over TCP too, not just UDP** — 166 denied attempts in one log snapshot,
  Pi-hole (`192.168.20.40`) falling back to TCP/53 for large or DNSSEC-heavy responses, only
  UDP/53 was ever allowed. Guillaume applied the fix directly:
  `services2internet: Pi-hole's own upstream DNS (TCP)`, positioned next to the existing UDP
  rule.
- **A real regression in the reorg itself, caught by Guillaume from reading the chain, not the
  logs**: the general forward-chain hygiene rules (syn-flood detect+drop, the ICMP jump,
  bogon-drop, spammer detect+drop, drop-invalid) sat *after* the ten dispatch jumps. Since
  those jumps match on interface pairs alone and every sub-chain they call terminates
  unconditionally, essentially all real traffic was swallowed by the dispatch section before
  ever reaching this block — it had been dead or misattributed since the reorg. The three
  `connection-state=invalid` HA packets seen in the earlier log review, logged under
  `services2internet`'s deny-all instead of the dedicated "drop invalid" rule, were the tell.
  Fixed via `scripts/phase5-09-forward-chain-hygiene-reorder.rsc`: moved the whole block
  (preserving its internal order) to right after "accept established,related", before the
  dispatch section, using single-condition `/move` commands per this project's own
  find-reliability history.

  **Deliberate side effect, confirmed with Guillaume before applying**: moving the ICMP jump
  this early means `chain=ICMP`'s own rules now decide every ICMP packet's fate regardless of
  VLAN pair, since (unlike the other five rules moved) it wasn't purely dead — some VLAN pairs
  (`users -> internet`) already got unrestricted ICMP via their own chain's blanket accept.
  The result is a real widening: ping now works uniformly, rate-limited, between every VLAN
  pair and to/from the internet — including `iot <-> services`/`users`, which had no ICMP
  accept anywhere before. Chosen deliberately (via `AskUserQuestion`) over keeping ICMP
  VLAN-scoped, on the reasoning that ping is low-risk and rate-limited either way.

**Verified: full `chain=forward` printed clean after the move** — order is now
established/related, syn-flood detect+drop, ICMP jump, bogon-drop, spammer detect+drop,
drop-invalid, *then* the ten dispatch jumps, then the final catch-all — no `I - INVALID`
flags anywhere, rule content unchanged, only positions moved. **Phase 5's firewall reorg is
done.** Next up: pick finding 21 (IPv6 for `vlan-services`/`vlan-iot`) back up, and separately
investigate finding 23 (Pi-hole's NTP not honoring the DHCP-supplied option).

### Home Assistant's DoT burst to Cloudflare — root-caused and closed (2026-09-10)

The recurring burst flagged above (hundreds of TCP/853 attempts from `192.168.20.60`, not
Pi-hole) turned out to be Home Assistant's own internal DNS plugin (`hassio_dns`) falling back
to Cloudflare for private (`192.168.20.0/24`) reverse-DNS lookups Pi-hole couldn't answer —
nothing wrong on the network side, and no further firewall change needed. Full root-cause and
fix (disabling HA's DNS fallback, adding Pi-hole Conditional Forwarding to mikrotik1) recorded
in `home/home-assistant/changelog.md`, since the fix lives entirely on that side. Verified
end-to-end with `dig -x 192.168.20.60 @192.168.20.40` returning a clean answer instead of
nothing.

**Correction, same day:** that "verified end-to-end" claim was wrong — Guillaume caught it.
`192.168.20.60` already had a manually-curated Pi-hole local record (`home.ledcom.fr`, this
project's own established convention for named devices), so the successful answer proved
nothing about whether Pi-hole's new Conditional Forwarding rule actually worked. See the entry
below for the real test and what it found.

### mikrotik1 didn't expose DHCP leases via DNS at all — fixed with a lease-script (2026-09-10)

Follow-up to the correction above. Clean test: `dig -x 192.168.10.194 @192.168.10.1` (a plain
dynamic lease, no Pi-hole record to fall back on) returned `NXDOMAIN` **directly from
mikrotik1** — not a Pi-hole/forwarding problem, mikrotik1 itself had nothing to answer with.
Confirmed via MikroTik's own docs: `/ip/dns/static` has no `PTR` type, and RouterOS does not
auto-generate DNS entries from DHCP leases in either direction — `add-dns-entries-suffix="lan"`
(present on all three DHCP servers, presumably original defconf) turned out to be fully inert,
confirmed by `dig am335x-opt.lan @192.168.10.1` also returning `NXDOMAIN`.

What MikroTik's docs do confirm: "for each static A and AAAA record, in cache automatically is
added a PTR record" — so a lease-script that maintains static A records for active leases gives
real reverse resolution as a side effect, no other mechanism needed. Added identically to all
three DHCP servers (`dhcp-home`/`dhcp-services`/`dhcp-iot`) via `scripts/dhcp-to-dns-setup.rsc`:
on each bind, add `<lease-hostname>.home.ledcom.fr -> lease IP` (`type=A`, `ttl=5m` matching the
lease time); on each deassign, remove it. Written out three times inline rather than shared via
a stored `/system/script` or a `:local` variable holding a script body — neither pattern's
RouterOS semantics had been verified reliable for this project, and duplication was the cheaper
risk. The add is wrapped in `:do{}on-error={}` so one malformed hostname can't break lease
processing for anyone else.

**A real gotcha, caught live:** the lease-script did not fire at all for ~25 minutes after being
set, despite multiple 5-minute lease cycles elapsing — `/log/print where message~"dhcp-to-dns"`
showed only the config-change events, no invocations. Root cause: **a renewal of an
already-bound lease does not re-trigger the script**, only a genuine new bind or a deassign
does. Confirmed by forcing one: `/ip/dhcp-server/lease/remove [find where address=192.168.10.194]`
— the device's next DHCP request produced a fresh bind, the script fired immediately, and
`/log/print` showed RouterOS's own confirmation: `static dns entry added by dhcp-lease`.

**Verified conclusively — real reverse (and bonus forward) resolution, straight from
mikrotik1:**

```
$ dig -x 192.168.10.194 @192.168.10.1
;; ANSWER SECTION:
194.10.168.192.in-addr.arpa. 300 IN PTR am335x-opt.home.ledcom.fr.
;; ADDITIONAL SECTION:
am335x-opt.home.ledcom.fr. 300  IN A   192.168.10.194
```

**Confirmed — the Pi-hole side too.** The same query through Conditional Forwarding
(`dig -x 192.168.10.194 @192.168.20.40`) still returned `SERVFAIL` immediately after this fix —
Guillaume's hypothesis was a cached negative response, from the many times that exact query
had been repeated against Pi-hole while mikrotik1 had nothing to answer. `pihole restartdns`
doesn't exist on this Pi-hole version's CLI; the correct command is **`pihole reloaddns`**
("update the lists and flush the cache without restarting the DNS server" — gentler than a
restart, no service interruption). Confirmed the hypothesis exactly: after the flush, the same
query returned `NOERROR`, `am335x-opt.home.ledcom.fr`, matching TTL 300 — identical to
mikrotik1's own direct answer. **The full chain (Pi-hole → Conditional Forwarding → mikrotik1
→ lease-script) is verified working end-to-end.**

### `add-dns-entries-suffix="lan"` repointed at the real domain (was finding 24, low, closed 2026-09-10)

All three DHCP servers carried `add-dns-entries-suffix="lan"` — undocumented in current
RouterOS docs, almost certainly a defconf leftover predating this project. Confirmed inert
before touching it: `dig am335x-opt.lan @192.168.10.1` (a real, currently-bound lease) returned
`NXDOMAIN`.

Two attempts to clear it outright were rejected by RouterOS: `!add-dns-entries-suffix` alone is
a syntax error (every prior working use of `!property` in this project paired it with another
real assignment in the same `/set` command — turns out that's load-bearing, not style);
`add-dns-entries-suffix=""` is rejected too, RouterOS enforces a minimum length of 1 on this
property. Guillaume's call: rather than keep fighting the clear, repoint it at the project's
actual domain (`home.ledcom.fr`, matching `/ip/dhcp-server/network`'s own `domain=` and the
lease-script's own naming) via `scripts/remove-dead-dns-suffix.rsc` — coherent either way,
whether the property turns out to do something under conditions not yet triggered or stays
fully inert.

**Verified no conflict with the lease-script's own entries:** forced a fresh lease event
(`/ip/dhcp-server/lease/remove [find where address=192.168.10.194]`) immediately after —
`/ip/dns/static/print` showed exactly one clean, correctly-tagged entry per device, no
duplicates or differently-sourced entries. A second device (the Samsung TV, `.195`) also
produced a fresh entry during this window from its own natural bind/renewal, unprompted —
incidental but good confirmation the lease-script (finding 24's real predecessor,
`scripts/dhcp-to-dns-setup.rsc`) keeps working correctly for organic traffic, not just forced
tests.

### Pi-hole's NTP pointed at mikrotik1 instead of the public internet (was finding 23, closed 2026-09-10)

Pi-hole (`192.168.20.40`) was sourcing time straight from `debian.pool.ntp.org`, denied by
`services2internet`'s default-deny (see Phase 5's entry above) and, before that, silently
allowed out only by the old blanket accept the reorg replaced. mikrotik1's DHCP option 42
(`ntp-services` = `192.168.20.1`) was already correctly configured and assigned (verified by
decoding the hex value), so the gap was entirely on Pi-hole's own OS.

**Root cause, found via `timedatectl`/`journalctl` on Pi-hole itself:** `systemd-timesyncd`
was never receiving the DHCP-supplied NTP server at all — `timedatectl timesync-status` showed
it going straight to `debian.pool.ntp.org` (the compiled-in `FallbackNTP=` list), and
`/etc/systemd/timesyncd.conf`'s `NTP=` was empty. DHCP-to-timesyncd propagation for option 42
depends on the DHCP client being specifically wired to forward it (typically a
`systemd-networkd` `UseNTP=` integration) — evidently not the case on this system. Matches this
project's own established caution about DHCP option 42 (`vlan.md`'s decision table: "unreliable
across devices/moves, verify by hand") — explicit configuration, not reliance on propagation,
was already the intended pattern here.

**Fixed in two parts:**
1. Pinned `NTP=192.168.20.1` directly in `/etc/systemd/timesyncd.conf`, bypassing the
   DHCP-propagation question entirely (Pi-hole-side, not scripted — applied directly).
2. **A second, independent gap found once that alone didn't work**: mikrotik1's own
   `chain=input` only ever had an NTP accept for `vlan-iot` ("iot: NTP from gateway", added
   during Kids Light's NTP fix, Phase 3) — `vlan-services` and `vlan-users` never got the
   equivalent rule, so Pi-hole's query to the router's own address was being silently dropped
   by the input chain's final catch-all before ever reaching mikrotik1's (correctly enabled,
   confirmed via `/system/ntp/server` and a live `/ip/service/print` entry) NTP server. Fixed
   universally, not just for Pi-hole, via `scripts/add-ntp-input-rules.rsc` — added
   `"services: NTP from gateway"` and `"users: NTP from gateway"`, grouped next to the existing
   `iot` rule.

**Verified conclusively, both sides:** mikrotik1's new rule shows real traffic
(`13 packets, 988 bytes` within minutes of applying); Pi-hole's `timedatectl timesync-status`
went from `Packet count: 0` (stuck retrying `debian.pool.ntp.org`) to a clean live sync against
`192.168.20.1` — `Packet count: 1`, `Stratum: 2`, `Offset: -1.276ms`, `Delay: 909us`, real
reference ID. No further public NTP traffic expected from Pi-hole.

### DHCP pool renamed for consistency (2026-09-10)

The original `dhcp-home` pool was still named `dhcp` (defconf leftover, predating the VLAN
work) while its siblings were `pool-services`/`pool-iot` — renamed to `pool-users` via
`scripts/rename-dhcp-pool.rsc` for consistency. Pool references are by name, so the DHCP
server's `address-pool=` had to be updated in the same script, pool renamed first (the
reference would otherwise briefly point at a nonexistent name).

**Verified:** `/ip/pool/print` shows `pool-users 192.168.10.100-192.168.10.200 101 4 97`
(members/usage unchanged, only the name and — as a result — `dhcp-home`'s `address-pool=`
changed); `/ip/dhcp-server/print detail` confirms `dhcp-home` now references `pool-users`.

## IPv6 dual-stack rollout — finding 21

Bringing IPv6 up to the same per-VLAN-pair firewall shape as IPv4, one VLAN at a time:
`vlan-users` first (already had IPv6, needed its firewall restructured), then addressing and
firewall for `vlan-services`, then `vlan-iot` last. Full design in [ipv6.md](ipv6.md).

**Collaboration model for this project, going forward:** every MikroTik change is delivered as
a `.rsc` script under `scripts/`, run by Guillaume (not executed by the assistant directly), with
the `print` output pasted back before anything here is marked done.

### Phase 1 — `vlan-users` IPv6 firewall hardened to match IPv4's shape (2026-09-10)

Before: two flat, unscoped accepts (`chain=input accept in-interface=vlan-users`, `chain=forward
accept in-interface=vlan-users`) — meaning every `vlan-users` host had unrestricted IPv6 access
to the router's own management services (ssh, Winbox, API, www), and the forward accept had no
destination scoping at all, which would have silently also covered `users -> vlan-services`/
`vlan-iot` once those VLANs got IPv6 addressing in phases 2-3.

Applied via `scripts/ipv6-01-users-hardening.rsc` (idempotent, comment-`find`-guarded):

1. Removed the input-chain accept entirely — router management is no longer reachable from
   `vlan-users` over IPv6 at all. IPv4's equivalent uses `src-address-list=mgmt`, but IPv6
   clients here are SLAAC-addressed with no stable per-host address to build an address-list
   against, so "not exposed" is the honest equivalent rather than a leaky approximation.
   Nothing depends on reaching the router over IPv6 today (HA's MikroTik integration is
   IPv4-only). ICMPv6/NDP/PMTUD are unaffected (already covered by the defconf accepts above
   it).
2. Replaced the forward-chain accept with a `users2internet` dispatch — `action=jump` scoped to
   `in-interface=vlan-users out-interface-list=WAN`, target chain `accept
   connection-state=new` — deliberately matching the IPv4 `users2internet` chain's name and
   shape (separate table, `/ipv6/firewall/filter` vs `/ip/firewall/filter`, so no collision).

**A new `I - INVALID` data point — transient, not permanent.** Both new rules showed
`I - INVALID` on `print` immediately after the script ran, unlike their identically-shaped IPv4
counterparts (IPv4's `users2internet` dispatch has never been flagged). Rather than assume
"unenforced" from the IPv4-derived catalog in `README.md`, this was verified functionally
instead — see below, both passed. A later, unprompted `print` (same session, no action taken in
between) showed the flag gone on both rules. Recorded in `README.md`'s hard-won lessons as an
addition to the existing `I - INVALID` catalog: on `/ipv6/firewall/filter`, the flag can appear
right after rule creation and clear on its own — re-print rather than trust the state from
immediately after an `/add`.

**Verified, from a real `vlan-users` client (not the router — the forward chain only applies to
transit traffic, so this can't be checked from the router's own CLI):**

```
ping -6 -c 3 2606:4700:4700::1111        # 0% loss
curl -6 https://ifconfig.co               # returned the client's own global address
ping -6 -c 3 2a02:1210:680f:c40c::1       # router's vlan-users address — 0% loss (ICMPv6 still accepted)
nc -6 -w 3 -zv 2a02:1210:680f:c40c::1 22  # timed out (was previously open)
```

Both changes confirmed: internet access intact, router management over IPv6 now actually
blocked (not just configured). `scripts/ipv6-01-users-hardening.rsc` deleted per this project's
one-shot-script convention — this entry is the durable record.

### Phase 2 — `vlan-services` gets IPv6 addressing and a matching firewall (2026-09-10)

Two scripts, run and verified in sequence.

**Step a**, `scripts/ipv6-02a-services-addressing.rsc`: `/ipv6/address add
from-pool=swisscom-pd interface=vlan-services advertise=yes address=::1` (drew the next
available `/64` from the same delegated `/62` `vlan-users` already uses one slice of) plus a
fresh `/ipv6/nd` entry (`advertise-dns=no managed-address-configuration=no
other-configuration=no ra-lifetime=30m`, same shape as `vlan-users`'s). **Verified:** the
resulting `/64` is `2a02:1210:680f:c40d::/64` — printed and pasted back before step b, since
this value had to be known to write it (the assistant doesn't reach the router directly, per
this project's collaboration model — see the intro to this section).

**Step b**, `scripts/ipv6-02b-services-firewall.rsc`: added the `services2internet` (HTTP/HTTPS,
tcp/80,443, host-unscoped — matches IPv4 rule 45, which isn't host-scoped either) and
`services2users` (Home Assistant only, via a new `ha-v6` address-list — printer CUPS/631 and
Samsung TV/8002, both by port only rather than also pinning the destination's address like IPv4
does) dispatch chains, each with a logged deny-all, then the two `chain=forward` jump rules
dispatching into them ahead of the terminating catch-all. `services2iot` deliberately not
added — `vlan-iot` has no IPv6 addressing yet (phase 3).

**`ha-v6`'s one entry is a computed EUI-64 address, not a DHCP reservation** — see
[ipv6.md](ipv6.md#extending-to-every-vlan-finding-21) for the full reasoning (this VLAN has no
stateful DHCPv6, deliberately, to stay consistent with `vlan-users`'s pure-SLAAC design) and the
two caveats it carries (depends on Home Assistant's host keeping IPv6 privacy extensions off;
depends on Swisscom's delegated prefix not changing). Computed from
`D8:3A:DD:31:E0:59` (Home Assistant's LAN MAC, from `/ip dhcp-server lease`) + the actual
`2a02:1210:680f:c40d::/64` from step a = `2a02:1210:680f:c40d:da3a:ddff:fe31:e059`. Pi-hole's
equivalent (`B8:27:EB:83:79:48` → `...ba27:ebff:fe83:7948`) was computed but not added to any
list — nothing references it yet.

Both new dispatch rules and every new chain rule again briefly showed `I - INVALID` on `print`
immediately after the script ran, matching phase 1's already-documented pattern (see
`README.md`'s hard-won lessons) — not re-checked for clearing this time, since functional
verification is what actually matters and that passed (below).

**Verified, from Pi-hole itself (`192.168.20.40`, a real `vlan-services` host):**

```
ping -6 -c 3 2606:4700:4700::1111        # 0% loss
curl -6 https://ifconfig.co               # returned the router's WAN v6 address (NAT66 working,
                                           # over HTTPS specifically -- confirms the port-scoped
                                           # accept rule, not just ICMPv6 which bypasses it)
nc -6 -w 3 -zv <printer's vlan-users IPv6 address> 631   # timed out
```

The `nc` is the important one: Pi-hole is *not* in `ha-v6`, so it correctly cannot reach the
printer's CUPS port over IPv6 even though Home Assistant can — proves the `src-address-list`
scoping actually discriminates between the two `vlan-services` hosts, not just that the chain
exists. Both one-shot scripts deleted per this project's convention.

Next: phase 3, `vlan-iot` — expected to be small, since most IoT devices here don't speak IPv6
at all.

### Phase 3 — `vlan-iot` IPv6 addressing and firewall, applied, verification pending (2026-09-10)

Two scripts, same split as phase 2.

**Step a**, `scripts/ipv6-03a-iot-addressing.rsc`: same pattern as `vlan-services` — drew the
last of the four `/64`s from the delegated `/62` (`from-pool=swisscom-pd interface=vlan-iot
advertise=yes address=::1`) plus a fresh `/ipv6/nd` entry, same shape as the other two VLANs.
**Verified from its own print output** — the resulting `/64` is `2a02:1210:680f:c40e::/64`,
address and RA entry both confirmed present. Deleted per this project's one-shot-script
convention: nothing here needed functional confirmation beyond what the object print already
shows (unlike firewall matching, addressing either exists correctly or it doesn't).

**Step b**, `scripts/ipv6-03b-iot-firewall.rsc`: deliberately minimal, matching this phase's
framing. One dispatch chain, `iot2internet` — deny by default, with a named exception for
OctoPrint (mirrors its existing IPv4 `octoprint` address-list exception) via a new
`octoprint-v6` address-list holding both of its known addresses (wifi + wired, same two MACs as
the IPv4 list), computed via EUI-64 the same way as `ha-v6` in phase 2:
`E4:5F:01:DA:22:96`/`E4:5F:01:DA:22:95` + `2a02:1210:680f:c40e::/64` →
`...e65f:1ff:feda:2296`/`...e65f:1ff:feda:2295`. No `iot2services`/`iot2users` chains —
nothing on this VLAN needs IPv6 access to either today, so they fall through to the existing
terminating catch-all, same outcome as an explicit deny. Router management over IPv6 stays
closed, same reasoning as the other two VLANs.

New rules again briefly showed `I - INVALID` on `print` immediately after the script ran,
matching the now-familiar pattern from phases 1-2 (see `README.md`'s hard-won lessons).

**Not yet functionally verified — OctoPrint was offline when this was applied.** Config is live
(confirmed via the script's own before/after print), but the one thing actually worth testing —
whether OctoPrint's exception really lets it reach the internet over IPv6 — hasn't been checked
from a real client, unlike every other rule change in this project. **Finding 21 stays open**
and `scripts/ipv6-03b-iot-firewall.rsc` stays in place (not deleted) until that's confirmed —
per this project's convention, a finding doesn't close on the strength of "should work." When
OctoPrint is back: `ping -6 -c 3 2606:4700:4700::1111` and `curl -6 https://ifconfig.co` from
it are the two checks to paste back.

## Internet-Box replacement (2026-09-11)

Swisscom replaced with a new, 10G-capable box. mikrotik1 configured as its DMZ host; no
bridge/modem mode available on this box (checked). Two things broke, both root-caused and
fixed the same day, working from a fresh `dump-configs.sh` run rather than assuming anything
carried over from the old box.

### Home Assistant's remote HTTPS access — broken, fixed

The new box's LAN-side subnet is entirely different from the old one (`192.168.1.0/24`
instead of `10.1.1.0/24`), so mikrotik1's WAN DHCP lease changed address —
`/ip/address/print` on the fresh dump showed `192.168.1.101/24` on `ether1`, not the
`10.1.1.101` every prior document assumed. The `dst-nat` rule for HA's HTTPS forward
(`comment="Home Assistant - HTTPS"`) was hardcoded to the old address and matched nothing
afterward.

**A near-miss worth recording:** the first hypothesis was that the paired forward-chain rule
(`internet2services: Home Assistant HTTPS`) also needed fixing, by analogy with the
NAT-rule-and-paired-forward-rule lesson from the VLAN renumber (see `README.md`). Re-reading
the dump more carefully showed this was wrong — that forward-chain rule matches
`dst-address=192.168.20.60` (HA's real internal address) plus `connection-nat-state=dstnat`,
never the WAN IP, so it was never affected. Fixing it anyway (the original draft would have
cleared its `dst-address`) would have quietly widened `internet2services` to accept HTTPS to
*any* forwarded destination, not just HA — caught before running anything, by tracing the
exact rule shape in the dump rather than trusting the by-analogy assumption.

Fixed via `scripts/fix-ha-nat-new-box.rsc`: dropped `dst-address=` from the `dst-nat` rule
entirely, matching only on `in-interface-list=WAN protocol=tcp dst-port=443` — nothing else
could legitimately arrive addressed elsewhere through this device's WAN side, and this survives
any future WAN IP change (another box swap, or even just a DHCP lease renewal) without needing
to be touched again.

**A RouterOS syntax gotcha, first attempt:** `/ip firewall nat set $natRule dst-address=""`
failed with `value of range expects range of ip addresses` — an IP-address-typed property
can't be cleared with an empty string. Fixed with the documented `!property` idiom (see
`README.md`'s hard-won lessons), paired with a harmless real reassignment
(`!dst-address in-interface-list=WAN`) in the same `/set`, since `!property` alone is a syntax
error.

**Verified:** before/after `print` shows `dst-address` gone from the rule. External HTTPS
reachability to Home Assistant itself — the test that actually matters — turned out to still
fail after this fix, for an unrelated reason (a stale DNS record) — see "External HTTPS access
to Home Assistant — root-caused" further down this file for the real fix and final
confirmation.

### IPv6 stopped working entirely — broken, fixed

The new box didn't answer DHCPv6-PD requests at all: `/ipv6/dhcp-client/print detail` showed
`status=searching...` for over three hours after the swap. Enabling IPv6 prefix delegation
explicitly in the box's own admin UI was the fix on that side — plausibly DMZ-hosting a client
makes some consumer CPE treat it as "gets full pass-through" rather than "also gets a routable
delegation," though this wasn't confirmed further, just worked around.

Even after enabling it on the box, mikrotik1's own DHCPv6 client didn't recover on its own —
still `status=searching` (its own dhcp-server-v6 field even showed a *different* link-local
address than before, `fe80::b6ee:b4ff:fe94:3b61` vs. the box's actual
`fe80::3a06:e6ff:fed9:c720`, suggesting it was talking to a stale/cached server identity).
Fixed with `/ipv6/dhcp-client/release [find interface=ether1]` followed by a 5-second wait —
came back `status=bound` with a real prefix on the very next check, no further action needed.

**The delegated prefix changed entirely** — a `/58` on a new `2a02:1210:7621:9a40::/58` base
(replacing the old `/62` on `2a02:1210:680f:...`), 64 usable `/64`s instead of 4. This broke
`ha-v6` and `octoprint-v6` (finding 21 phases 2-3's EUI-64-pinned address-lists) exactly as
their own documentation warned it would when written. Fixed via
`scripts/fix-eui64-lists-new-prefix.rsc`: same MACs, same EUI-64 computation, new prefix
(`vlan-services 2a02:1210:7621:9a41::/64`, `vlan-iot 2a02:1210:7621:9a42::/64`) —
`2a02:1210:7621:9a41:da3a:ddff:fe31:e059` (HA) and
`2a02:1210:7621:9a42:e65f:1ff:feda:2296`/`...2295` (OctoPrint wifi/wired). Script removes any
address that doesn't match the current expected value before adding the current one, so it
also self-heals after any *future* re-delegation, not just this one.

**A coincidence caught before it became a real problem:** the box's own admin UI reported the
delegated prefix as a `/56` on `2a02:1210:7621:9a00::/56` — which would have overlapped the
WAN transit link's own SLAAC `/64` (mikrotik1's `ether1` address is also on
`2a02:1210:7621:9a00::/64`), a real collision risk if RouterOS's pool allocator had handed
that same `/64` to a LAN VLAN. The actual bound delegation, read from
`/ipv6/dhcp-client/print detail` on the router itself, was the non-overlapping `/58` above.
**The router's own bound state is the authority here, not the box's admin UI** — checked before
assuming any collision needed handling, not after.

**Verified, from Pi-hole (`vlan-services`):**

```
ping -6 -c 3 2606:4700:4700::1111        # 0% loss
curl -6 https://ifconfig.co               # succeeded, over the port-restricted
                                           # services2internet chain (HTTPS specifically)
```

Desktop (`vlan-users`) picked up the new prefix automatically via SLAAC within one RA cycle,
with the old prefix's address correctly aging out as `deprecated`/`preferred_lft 0` (the same
graceful-expiry behavior already documented under "Stale prefix on clients after renumbering"
in `ipv6.md`) rather than breaking outright. `test-ipv6.run` from desktop: 10/10.

**Still open:** OctoPrint's `iot2internet` exception (finding 21 phase 3) — was already
unverified before this event (OctoPrint offline) and its `octoprint-v6` addresses needed
updating too, so it remains unverified now for the same reason plus a fresh one.

### External HTTPS access to Home Assistant — root-caused (2026-09-11)

The HA NAT fix earlier in this section (dropping `dst-address=` from the `dst-nat` rule) was
necessary but turned out not to be sufficient — external HTTPS still timed out. Real root
cause found only after a long, mostly-dead-end diagnostic session; recorded because the
dead ends are as instructive as the answer.

**What didn't turn out to be it, in the order investigated:**

1. **Syn-flood detector (`Syn_Flooder`, scoped to `connection-nat-state=dstnat` — exactly
   this traffic's shape).** Plausible given `README.md`'s own documented risk, but the list
   was empty when checked and a fully-reset counter test showed zero hits on it. Not the
   cause.
2. **`connection-state=new` not matching inside the `internet2services` chain.** A
   full-forward-chain-reset test showed the dispatch jump matching the exact same packet
   count as `dst-nat` (13/13), proving packets *did* enter the chain, but the accept rule
   inside it matched zero — implying `connection-state=new` was somehow false. Turned out to
   be a red herring: connection-tracking checks (`/ip/firewall/connection/print`) came back
   empty, most likely because the default `tcp-syn-sent` conntrack timeout is short and the
   embryonic connection had already expired before the query ran — not proof of anything
   structural.
3. **A live packet capture (`/tool/sniffer/quick`) never caught the actual attempt.** First
   pass used a nonexistent `filter-port=` parameter (`bad parameter filter-port` — RouterOS
   error, not this project's own convention this time); the correct property, found by
   Guillaume directly rather than guessed further, is `filter-interface=`. Capturing on all
   interfaces with the default buffer also drowned in LAN chatter (HA's own MikroTik API
   polling on 8728 alone produced hundreds of packets in under 2 seconds) before the phone's
   request could be captured. Neither capture attempt, even properly scoped, ever showed an
   inbound SYN to port 443 from an external address — a real, if inconclusive, signal that
   the traffic wasn't reliably reaching mikrotik1 at all.
4. **The box's own admin UI is on port 443, DMZ apparently can't override it.** `canyouseeme.org`
   succeeded at the TCP level against port 443 while a real HTTPS request (`reqbin.com`)
   timed out — consistent with the box's own listener answering the handshake instead of
   forwarding through. Worked around by moving HA's external port to 8443
   (`scripts/fix-ha-nat-port-8443.rsc`, `dst-port` changed on the `dst-nat` rule only — the
   paired forward-chain rule matches the *post-NAT* port, HA's real 443, so it never needed
   touching). **Still timed out on 8443 too**, disproving this theory as the actual blocker
   (though the port-443-conflict may still be real, just not the cause of this specific
   failure — not conclusively ruled out either way).

**The actual cause: a stale DNS record.** `home.ledcom.fr` (managed at Gandi —
`ns-142-a/203-b/107-c.gandi.net`, confirmed via `dig NS` and cross-checked against the
authoritative server directly) was still pointing at the *old* box's public IP
(`188.61.18.91`, TTL 300s) after the ISP reassigned a new one to the replacement box
(`178.192.223.49`, confirmed independently both from the box's own admin page and a
`duckduckgo.com` "what's my IP" check). mikrotik1's own `/ip/cloud` (MikroTik Cloud DDNS,
`ddns-update-interval: none`) hadn't refreshed either, still showing the old address —
consistent with it only updating on certain triggers, not proactively. Every test all day had
been reaching *something* at the stale address (most likely an unrelated host now assigned
that IP by the ISP, explaining `canyouseeme`'s earlier "success" on port 443 — a coincidence,
not evidence about this network at all) rather than the actual box.

**Fixed:** Guillaume manually updated the Gandi A record to the new IP.
`scripts/revert-ha-nat-port-443.rsc` moved the `dst-nat` rule back to port 443 (the 8443
workaround wasn't needed once the real cause was found). **Verified end-to-end from cellular**
shortly after — `https://home.ledcom.fr` loads Home Assistant correctly; script deleted.

**Also found and tracked as an open item, not fixed:** nothing updates `home.ledcom.fr`
automatically when the public IP changes — see [config-review.md](config-review.md) finding
25. Guillaume's recollection of an existing "DDNS via the Let's Encrypt app" mechanism was
checked and ruled out: that add-on's Gandi API usage (confirmed working, from its own log —
`Using Gandi personal access token` → cert type detected → not yet due for renewal) is for
DNS-01 ACME domain-ownership proof during certificate renewal, never for updating the A
record's IP. No such mechanism exists today.

### Firewall log review (2026-09-11)

Reviewed `home/network/logs/mikrotik1-main.txt` (a fresh `dump-logs.sh` collection, per this
project's standing convention) while investigating the above. Two findings, both fixed via
`scripts/log-review-fixes.rsc`:

**97% of the log (953 of 981 lines) was one source:** the Hombli ceiling fan (`192.168.30.63`,
confirmed by MAC `20:F1:B2:C3:F5:C1` against its DHCP reservation) retrying its cloud
phone-home every ~2 seconds against `iot2internet`'s deny-by-default — correctly blocked
(isolation working exactly as designed), but dominating the log buffer badly enough to risk
crowding out anything actually worth noticing, exactly the risk `README.md`'s own hard-won
lessons already flag about RouterOS's small, rotating log. Fixed with an unlogged drop for
this specific source, placed ahead of the general logged catch-all — still blocked, just not
logged; any other source hitting that catch-all still is.

**Pi-hole was repeatedly, silently failing to reach public IPv6 DNS resolvers** (Cloudflare,
Google, OpenDNS — roughly every 10 minutes, consistent with its own upstream health-checking)
for its own upstream queries, blocked by `services2internet`'s HTTP/HTTPS-only IPv6 policy
from finding 21 phase 2 — the "nothing needs v6 DNS yet" assumption made when that chain was
built turned out to be wrong once real traffic was observed. Fixed by adding the missing
exception, mirroring Pi-hole's existing IPv4 one (UDP/TCP 53, TCP 853 DoT) via a new
`pihole-v6` address-list, EUI-64-pinned the same way as `ha-v6`/`octoprint-v6`
(`B8:27:EB:83:79:48` + `vlan-services`'s current `2a02:1210:7621:9a41::/64` =
`2a02:1210:7621:9a41:ba27:ebff:fe83:7948`) — same caveats apply (privacy extensions must stay
off; breaks again if the delegated prefix changes, as already happened once today).

New rules again briefly showed `I - INVALID` on `print` immediately after creation (two of the
three new `services2internet` rules) — consistent with the now-well-established transient
pattern for `/ipv6/firewall/filter`, not re-verified for clearing this time.

**Ceiling fan silencing verified:** a later `dump-logs.sh` collection (same day, 14:49) shows
473 occurrences of its MAC before the silence rule was added (14:26:46) and exactly zero
after — confirmed working, not just applied. Pi-hole's IPv6 DNS exception is covered by the
privacy-extensions fix below (its `pihole-v6` entry didn't match real traffic until that was
fixed).

### Finding 21 (IPv6 for every VLAN) — closed, after finding a real pinning bug (2026-09-11)

Following up on the log review above: checking whether Pi-hole's new `pihole-v6` DNS exception
actually worked (not just that the rule looked right) turned up a real bug affecting the whole
EUI-64-pinning approach from phases 2-3, not just Pi-hole.

**The bug.** A fresh log check, filtered to Pi-hole's traffic *after* the `pihole-v6` fix was
applied and confirmed live, showed its DNS-over-IPv6 queries still being dropped by
`services2internet`'s catch-all. Its actual source address —
`2a02:1210:7621:9a41:2f67:e1e2:25f2:be49` — didn't match the computed EUI-64 entry
(`...ba27:ebff:fe83:7948`) at all. Same story for OctoPrint, checked at the same time:
real traffic from `...1b66:2a1a:7ff9:3e39`, `octoprint-v6` holding `...e65f:1ff:feda:2296`.
Both hosts have IPv6 privacy extensions (RFC 4941 temporary addresses) on, contradicting the
assumption made when `ha-v6` was designed in phase 2 ("likely already the default on a
Pi-hole/Debian install") — an assumption never actually checked against real traffic until
now. The rules were entirely correct on `print` the whole time; only watching real packets
revealed they'd never matched anything.

**Fixed per host**, Pi-hole and OctoPrint (Home Assistant not checked or fixed — no
`services2users`-triggering traffic has been observed from it either way, so whether `ha-v6`
has the same problem is still unknown):

```
sudo tee /etc/sysctl.d/99-disable-ipv6-privacy.conf <<'EOF'
net.ipv6.conf.all.use_tempaddr = 0
net.ipv6.conf.default.use_tempaddr = 0
net.ipv6.conf.all.addr_gen_mode = 0
net.ipv6.conf.default.addr_gen_mode = 0
EOF
sudo sysctl --system

sudo nmcli connection modify <connection-name> ipv6.ip6-privacy 0 ipv6.addr-gen-mode eui64
sudo nmcli connection up <connection-name>
sudo reboot
```

`addr_gen_mode=0` (force EUI-64) matters as much as `use_tempaddr=0` (disable temporary
addresses) — modern NetworkManager/systemd-networkd defaults often use RFC 7217
"stable-privacy" for the *permanent* address too, a stable but non-MAC-derived hash. Disabling
only temporary addresses would have left the permanent address wrong as well. `nmcli` was
applied in addition to the sysctl file as belt-and-suspenders, since NetworkManager can
override the raw kernel default on reconnect — worth it in practice: both hosts' first sysctl
file had a typo (`user_tempaddr` on Pi-hole, `addr_gen_mdoe` on OctoPrint) that would have
silently left `addr_gen_mode` unset via that path alone; the `nmcli` change is what actually
took effect for both.

**Verified:** `ip -6 addr show scope global` on both hosts, post-reboot, now shows exactly the
precomputed EUI-64 address (confirmed, not assumed). Functional retest from each:

```
# Pi-hole
ping -6 -c 3 2606:4700:4700::1111   # 0% loss (its DNS-over-v6 specifically wasn't
                                     # independently retested -- dig wasn't installed on the
                                     # host tried -- but the address now matches pihole-v6
                                     # exactly, and the rule mechanism was already proven
                                     # correct in phase 2's Pi-hole-exclusion test)

# OctoPrint
ping -6 -c 3 2606:4700:4700::1111   # 0% loss
curl -6 https://ifconfig.co         # succeeded, returning the router's WAN v6 address
                                     # (NAT66 working) -- finding 21 phase 3 now fully
                                     # confirmed end-to-end, the check that was blocked on
                                     # OctoPrint being offline since 2026-09-10
```

**Finding 21 is now closed** — all three phases (`vlan-users`, `vlan-services`, `vlan-iot`)
verified end-to-end from real clients. Moved out of `config-review.md`'s open findings; full
history is this entry plus the phase 1-3 entries earlier in this file.

### OctoPrint: NTP and DNS also not following DHCP (2026-09-11)

Found while chasing the above: OctoPrint's `curl -6` initially failed with `SSL certificate
problem: certificate is not yet valid` — not a network problem. `date` on the host showed
`Wed 20 Nov 2024`, nearly two years behind real time. Root cause matched a pattern already
documented for the Kids Light Tasmota device (see the DHCP-to-DNS section earlier in this
file): OctoPrint's `systemd-timesyncd` was pointed at public NTP pool servers, not honoring
DHCP option 42, and those outbound NTP attempts (confirmed in the firewall log, `iot2internet`
drops to `2a02:168:420b:4::7b:13`/`2a10:8247:0:1013::11` on UDP/123) were correctly being
blocked — IoT devices use the local NTP server by design, not the internet.

**Fixed:**

```
sudo tee /etc/systemd/timesyncd.conf <<'CONF'
[Time]
NTP=192.168.30.1
FallbackNTP=
CONF
sudo systemctl restart systemd-timesyncd
```

`FallbackNTP=` set empty deliberately — left at its default, systemd-timesyncd falls back to
its compiled-in public servers whenever the primary is briefly unreachable, silently
recreating the same problem later.

**Verified:** `timedatectl timesync-status` showed `Server: 192.168.30.1`, a real stratum-2
reference, and a one-time offset correction of about 1 year 9 months; `date` immediately after
showed the correct current time. `curl -6 https://ifconfig.co` (see above) then succeeded
cleanly, confirming the TLS failure really was just the clock.

**A related DNS quirk, resolved without any firewall change.** The `iot2internet` log also
showed OctoPrint repeatedly querying `1.1.1.1:53` directly over TCP, blocked the same way —
despite `/etc/resolv.conf` correctly pointing at Pi-hole (`nameserver 192.168.20.40`) the whole
time. Root cause: OctoPrint's own **Connectivity Check** feature (Settings → Server → Online
connectivity) does its own DNS lookup against a hardcoded public server, by design, to tell a
real outage apart from a broken local resolver — it doesn't use the OS resolver at all. Fixed
by Guillaume directly in OctoPrint's own settings, retargeting the check to Wikipedia's public
IP (`185.15.58.224`) on port 80 instead of a DNS lookup — already covered by the existing
`octoprint`/`octoprint-v6` exception (`dst-port=80,443`), so no firewall change was needed.

### Pi-hole's NTP fix (finding 23) was incomplete — same `FallbackNTP=` gap as OctoPrint (2026-09-11)

Found while reviewing the same firewall log as the OctoPrint NTP issue above: Pi-hole
(`192.168.20.40`) was also repeatedly hitting `services2internet`'s catch-all on UDP/123, to a
rotating set of public servers (`195.186.1.101`, `31.3.128.55`, `193.33.30.39`) — despite
finding 23 having been closed 2026-09-10 with `NTP=192.168.20.1` pinned in
`/etc/systemd/timesyncd.conf` and verified working at the time.

**Root cause: the exact same gap just found on OctoPrint.** `FallbackNTP=` was left commented
out (compiled-in default: `debian.pool.ntp.org`), so whenever `192.168.20.1` was even briefly
slow to answer, `systemd-timesyncd` silently fell back to public servers — which
`services2internet` correctly blocks, so it never actually recovered, and nothing about this
was visible without reading the firewall log. Finding 23's original closure pinned `NTP=` but
never mentioned clearing `FallbackNTP=`, so this was never actually fixed, just working well
enough at the time not to be noticed.

**Fixed** the same way as OctoPrint: `FallbackNTP=` set explicitly empty.

**Verified:** `timedatectl timesync-status` shows `Server: 192.168.20.1`, `Stratum: 2`,
`Offset: +491us` — healthy, matching the original finding 23 verification.

**Generalizable lesson, now confirmed on two separate devices in one day — added to
`README.md`'s hard-won lessons:** pinning `NTP=` on `systemd-timesyncd` is not sufficient on
its own. `FallbackNTP=` must also be set explicitly empty, or the fix silently stops working
the next time the primary is briefly unreachable, with no error and no obvious symptom short
of reading the firewall log.

### TLS SNI domain allowlist for `vlan-iot` — tried and abandoned; IotaWatt gets full HTTPS instead (2026-09-11)

IotaWatt (`192.168.30.50`) came back online today after an extended outage (its Home Assistant
integration needed a delete + re-add, entities confirmed surviving via MAC-keyed unique IDs —
see `home/home-assistant/changelog.md`) and, like OctoPrint, needs internet access for
firmware updates — it had none at all until today. Rather than just widen the
existing `octoprint`-style port exception to a second device, tried building something
better first: a domain-level allowlist using RouterOS's `tls-host=` firewall matcher, which
reads the plaintext SNI field from a TLS `ClientHello`. In principle this lets `iot2internet`
allow specific domains instead of any HTTPS destination on port 443 — no proxy needed, no
per-device client configuration (most IoT firmware, IotaWatt's included, has no way to be
told to use an upstream proxy at all), transparent regardless of what's making the connection.
Considered and rejected an actual HTTP(S) proxy for the same reason: it only helps for clients
that can be configured to use one, which is effectively just OctoPrint (a real Linux host) on
this VLAN.

**What went wrong.** First attempt: add `tls-host=*` (intended as "match any hostname, just
for logging") to OctoPrint's existing accept rule, to bootstrap visibility into what domains
it actually needs without breaking its current (broad) access. This was wrong on two counts:

1. `tls-host=*` does not match everything — confirmed live, not just suspected. The very same
   `curl` to `github.com` that should have hit the modified, now-logging accept rule instead
   fell straight through to the general `iot2internet` catch-all drop. The wildcard silently
   matched nothing, which meant the rule it was added to stopped working at all — a real
   regression (OctoPrint's internet access broken), not just a failed attempt to add
   visibility. Reverted immediately once caught.
2. Even with correct syntax, Guillaume flagged the more fundamental problem: TLS 1.3 with
   Encrypted Client Hello — increasingly common on major CDN-backed services, GitHub
   included — encrypts the SNI field entirely, making it unreadable to a passive matcher like
   this one regardless of syntax. Not independently confirmed against GitHub specifically, but
   plausible enough (and the services that matter most here — GitHub, PyPI, IotaWatt's own
   update host — are exactly the kind fronted by CDNs likely to support ECH) that pursuing
   `tls-host=` further wasn't judged worth it.

**Decision: deprioritized.** Domain-level filtering may be worth revisiting later (a real
proxy is the fallback if it ever is, accepting that it would only cover OctoPrint), but isn't
currently planned. Both OctoPrint and IotaWatt get unrestricted HTTPS (port 443 only, not 80)
to any destination instead — the same shape the `octoprint` exception already had, now with a
second entry.

**Applied:**
- `octoprint`'s accept rule narrowed from `dst-port=80,443` to `443` — kept even after
  reverting the `tls-host` experiment, since nothing here should still need plain HTTP. (The
  IPv6 equivalent, `octoprint-v6`'s rule, was not touched and still allows both ports — a
  minor inconsistency, not urgent.)
- New `iotawatt` address-list (`192.168.30.50`, IPv4 only) and a matching `iot2internet`
  accept rule, same shape as `octoprint`'s.
- Neither rule carries `log=yes` — Guillaume's call, logging wasn't judged useful now that
  domain-level decisions aren't being made from it.

**Verified:** `curl -v https://github.com` from OctoPrint after the revert — full TLS 1.3
handshake, HTTP/2 200 response. IotaWatt's own firmware-update path not independently
retested (same rule shape as OctoPrint's already-proven-working one, and it's the same
mechanism verified extensively for finding 21 phase 3 yesterday).

### IotaWatt NTP exception (2026-09-11)

Unlike Pi-hole and OctoPrint (both fixed earlier today to use mikrotik1's own NTP server —
see the `FallbackNTP=`/finding 23 entries above), IotaWatt's firmware exposes no way to point
it at an internal server at all. Rather than leave it silently unable to keep time, added a
narrow `iot2internet` exception for outbound NTP specifically — `src-address-list=iotawatt
protocol=udp dst-port=123`, same shape as its HTTPS exception, no destination restriction.

**Verified:** IotaWatt's own clock reads correctly after applying.

### Finding 26 closed — Kids Light reconnected to `LEDCOM-IoT` (2026-09-13)

Kids Light (Tasmota, `D8:BC:38:99:44:68`) had been associated to the `LEDCOM` SSID instead of
`LEDCOM-IoT` since at least 2026-09-12 21:16, stranding it on `vlan-users` with a dynamic
address and blocking every MQTT attempt to Home Assistant for ~19.5h straight (finding 26 in
`config-review.md`). Fixed device-side — reconnected to `LEDCOM-IoT` via its own Tasmota web
config, no router change.

**Verified** against a fresh dump and log (both collected 2026-09-13 ~16:49):
- `/caps-man/registration-table/print` now shows `D8:BC:38:99:44:68` on `ap-MikroTik-Switch-1-1`
  with SSID `LEDCOM-IoT`, uptime 1m35s at dump time.
- Its `dhcp-iot` static reservation (`192.168.30.61`) is bound and resolving —
  `tasmota-994468-1128.home.ledcom.fr` → `192.168.30.61` in Pi-hole's DNS record list.
- The firewall log's last `users2services` deny for this device is 16:46:32, a couple of
  minutes before the SSID switch (registration uptime places the switch around 16:48); no
  further denies logged afterward, consistent with `iot2services`'s existing MQTT-to-HA accept
  now covering it instead.

**Guillaume confirmed directly (2026-09-14):** the light connects to MQTT and is visible in
Home Assistant — full end-to-end confirmation, not just the negative log evidence above.

### Finding 27 closed — Pi-hole's NTP fallback, root cause found: an empty `FallbackNTP=` doesn't actually clear the list (2026-09-14)

Found 2026-09-13 (see the equivalent entry above for the initial log evidence — 157 blocked
UDP/123 packets over ~19.5h, once an hour, to a rotating set of public NTP servers). This is
finding 23's second recurrence, both times traced to the exact same `services2internet`
catch-all in `logs/mikrotik1-main.txt`.

**Router side checked first, ruled out cleanly:** mikrotik1's own NTP server, all three
`chain=input` "NTP from gateway" accepts, and DHCP option 42 (`ntp-services` = `192.168.20.1`)
were all unchanged and correct. The gap was entirely on Pi-hole's own OS.

**First hypothesis (a package upgrade reverted the conffile) ruled out:** `/etc/systemd/
timesyncd.conf` still had exactly the intended config (`NTP=192.168.20.1`, `FallbackNTP=`
empty), no drop-ins anywhere, `systemd-analyze cat-config systemd/timesyncd.conf` confirmed
the plain file was the only effective config, no relevant `apt` history, and `timedatectl
timesync-status` showed a healthy live sync against `192.168.20.1`. No second time-sync daemon
(`chrony`/`ntpd` not installed), no relevant cron/systemd-timer job, and Pi-hole isn't running
in Docker.

**Actual root cause, found via `timedatectl show-timesync --all`:** despite the config file's
explicit empty `FallbackNTP=`, the live `FallbackNTPServers=` property still showed
`0.debian.pool.ntp.org 1.debian.pool.ntp.org 2.debian.pool.ntp.org 3.debian.pool.ntp.org` — the
compiled-in default, untouched by the "empty" assignment. `RuntimeNTPServers=` and
`LinkNTPServers=` were both correctly empty, ruling out DHCP/`systemd-networkd`
NTP-server injection as a separate mechanism. This systemd build
(`252.33-1~deb12u1+rpi1`, Debian 12/Raspberry Pi OS) simply doesn't honor an empty
`FallbackNTP=` as "clear the compiled default" the way finding 23's original fix assumed —
and that fix's own verification never caught it, because it only ever checked
`timedatectl timesync-status` (the *active* server), which can't show an unused-but-still-
configured fallback list.

**Fixed:** pointed `FallbackNTP=` at the same real server instead of leaving it empty —

```
[Time]
NTP=192.168.20.1
FallbackNTP=192.168.20.1
```

— sidestepping the empty-list ambiguity entirely: no configuration state now has a path to
the public internet for time, regardless of how this quirk actually behaves internally.

**Verified:** `timedatectl show-timesync --all` after `systemctl restart systemd-timesyncd`
shows `FallbackNTPServers=192.168.20.1`, confirming a real value does override correctly
(only the empty-clears-list case was broken) — `SystemNTPServers=192.168.20.1`,
`ServerAddress=192.168.20.1`, clean sync (`Stratum=2`, fresh `PacketCount=1` after restart).

**Not fully explained, not blocking:** why the fallback list was being exercised roughly
hourly at all, given `192.168.20.1` was reachable throughout and `PollIntervalUSec` was
`34min 8s` (not hourly) — `journalctl -u systemd-timesyncd` was essentially silent across the
whole incident window, so no direct server-level correlation was available. Not investigated
further since the fix removes any consequence regardless of the trigger.

**Generalizable lesson — added to `README.md`'s hard-won lessons:** verifying a `FallbackNTP=`
fix requires `timedatectl show-timesync --all` (`FallbackNTPServers=`), not just
`timesync-status`.

**OctoPrint reconfigured the same way (2026-09-14).** Guillaume confirmed it directly — not
re-verified against device output in this session (no `show-timesync --all`/log evidence
collected here), so treat as done on his word rather than independently confirmed the way
Pi-hole's fix above was.

### Correction, same day: the "Finding 27 closed" entry above was premature (2026-09-14)

A fresh log collected several hours after the `FallbackNTP=192.168.20.1` fix and its
`show-timesync --all` verification shows **the exact same hourly burst of UDP/123 packets to
rotating public NTP servers, continuing unchanged after the fix**: bursts at `09:59:25`,
`10:59:25`, `11:59:26`, and `12:59:26` (2026-09-14), all still to different public IPs
(`84.254.99.155`, `158.180.28.150`, `193.134.29.12`, `85.195.210.125`) — including the two
bursts *after* the fix was applied and restarted at `11:52:37`. If `systemd-timesyncd`'s
`FallbackNTP=` were really the mechanism, changing it to `192.168.20.1` should have made these
bursts either disappear or start hitting `192.168.20.1` (accepted by `chain=input`, so not
logged here at all) — neither happened.

**Conclusion: `systemd-timesyncd` was never actually the source of this traffic.** The
`show-timesync --all` verification was real (the property genuinely changed), but it verified
the wrong thing — a live property readback, not a behavioral test over time. The precise
hourly-at-:59 cadence, unaffected by any change to `timesyncd.conf`, points at something else
entirely on Pi-hole: most likely a `cron.hourly`/systemd-timer job whose *contents* weren't
checked in the earlier investigation (only `/etc/crontab` and `/etc/cron.d/*`'s own text were
grepped for "ntp" — not what any referenced `/etc/cron.hourly/*` script actually does), a user
crontab entry with a schedule like `59 * * * *` (the two crontab checks that ran wouldn't
catch this unless the literal word "ntp" appeared in the crontab line itself, not inside a
script it calls), or something unrelated to `cron`/`systemd-timesyncd` entirely.

**Finding 27 reopened** — see `config-review.md`. `FallbackNTP=192.168.20.1` stays applied (it
is at minimum harmless, and closes the theoretical gap it was meant to close even though it
wasn't the live problem), but the real source of the hourly bursts is still unidentified.
OctoPrint's identical reconfiguration is unverified against its own log either way.

### `services2internet` narrowed to HTTPS-only (2026-09-14)

Guillaume applied directly: rule 45 (`services2internet: HTTP/HTTPS from any services host`,
`dst-port=80,443`) narrowed to `dst-port=443` only — comment now "services2internet: HTTPS
from any services host". Matches the same HTTPS-only narrowing already applied to
`octoprint`'s `iot2internet` exception (2026-09-11). **Confirmed via fresh dump** (`dumps/
mikrotik1-main.txt`): rule 45 now reads `dst-port=443 protocol=tcp`. The IPv6 equivalent
(`services2internet-v6`) was narrowed to match the same day — confirmed in a later fresh dump,
comment now "services2internet: HTTPS", `dst-port=443`. Both families are HTTPS-only, no
remaining asymmetry here.

**Immediate fallout, found the same day reviewing the next log:** Home Assistant
(`192.168.20.60`) has been continuously retrying plain HTTP (port 80) to three Cloudflare
edge IPs (`104.26.4.238`, `104.26.5.238`, `172.67.68.90`) — roughly one SYN every 20-25s per
destination, no backoff, unbroken across the entire ~4.5h capture (`09:22:03`-`13:52:09`,
729 drops total). Whatever integration/add-on is doing this needs identifying on the HA side
(check its own logs for connection errors to these IPs or their hostname) — see finding 29 in
`config-review.md`. Directly relevant to Guillaume's stated goal of moving `services2internet`
fully to HTTPS: this is the one known thing standing in the way right now.

### Finding 30 closed — Raspbian's apt mirror switched to init7's HTTPS mirror, on both Pi-hole and OctoPrint (2026-09-14)

Found the same day as the rule 45 narrowing: `apt install tcpdump` on Pi-hole failed against
`raspbian.raspberrypi.com:80` — Raspberry Pi OS's default mirror, plain HTTP only. Checked
whether it serves HTTPS at all: `curl -v https://raspbian.raspberrypi.com/raspbian` from an
unrestricted `vlan-users` client got `Connection refused` on port 443 for both address
families — the server genuinely doesn't listen there, not a firewall artifact. A same-host
scheme swap wasn't an option.

**Fixed differently: switched mirrors instead.** Guillaume found init7 (Switzerland) mirrors
Raspbian over HTTPS (`https://www.raspbian.com/RaspbianMirrors`) and repointed
`/etc/apt/sources.list` at it on both Pi-hole and OctoPrint:

```
deb [ arch=armhf ] https://mirror.init7.net/raspbian/raspbian/ bookworm main contrib non-free rpi
```

**A second source needed the same treatment on both hosts**, found while checking:
`/etc/apt/sources.list.d/raspi.list` (Raspberry Pi Foundation's own repo — Pi-specific
packages like firmware/`raspi-config`, not part of the Debian archive init7 mirrors) pointed
at `http://archive.raspberrypi.com/debian/`. Unlike the main archive, this one *does* serve
HTTPS directly (`curl -v https://archive.raspberrypi.com/debian/` — clean TLS 1.3 handshake,
valid Let's Encrypt cert, HTTP/2 200) — no mirror hunt needed, just the scheme swapped in
place:

```
deb https://archive.raspberrypi.com/debian/ bookworm main
```

**Verified on both hosts**, real `apt update` output, fully over HTTPS, no plain-HTTP fallback
anywhere:

```
# OctoPrint (vlan-iot, already HTTPS-only since 2026-09-11):
Get:1 https://mirror.init7.net/raspbian/raspbian bookworm InRelease [15.0 kB]
Get:2 https://archive.raspberrypi.com/debian bookworm InRelease [55.0 kB]
... (package indexes fetched cleanly over HTTPS)
254 packages can be upgraded.

# Pi-hole (vlan-services, HTTPS-only since today):
Hit:1 https://mirror.init7.net/raspbian/raspbian bookworm InRelease
Hit:2 https://archive.raspberrypi.com/debian bookworm InRelease
188 packages can be upgraded.
```

Both hosts now update/install packages entirely over HTTPS — `services2internet`'s HTTPS-only
narrowing (and `iot2internet`'s, already in place) hold with no known remaining apt gap.

**Noted, not investigated, low priority:** both `apt update` runs warn `Key is stored in
legacy trusted.gpg keyring (/etc/apt/trusted.gpg), see the DEPRECATION section in apt-key(8)`
— pre-existing apt hygiene, unrelated to HTTP vs. HTTPS, not something either mirror change
introduced.

### DHCP lease time restored from 5m to 1d on all three servers (2026-09-14)

`dhcp-home`/`dhcp-services`/`dhcp-iot` had all carried `lease-time=5m` since the VLAN
renumbering — needed then so re-leases happened quickly during the transition, never restored
afterward. Surfaced as a real symptom while chasing finding 29 (Home Assistant's HTTP traffic):
its DHCP lease was renewing every ~2.5 minutes in `ha host logs`, exactly 50% of 5m — briefly
suspected as related to the HTTP issue, then ruled out as an unrelated side effect of the
leftover short lease time once Guillaume confirmed the timing.

Applied via `scripts/restore-dhcp-lease-time.rsc` (deleted after verified, per convention).
**First attempt failed harmlessly**: `lease-time=1d` was rejected outright —
`invalid time value for argument lease-time` — RouterOS needs the fully-qualified `Nd00:00:00`
form for a bare day value, not just `1d`, on `set` (oddly, `5m`, a single-unit form, was
already valid and in place — RouterOS accepts single-unit shorthand but not `<n>d` alone).
Corrected to `1d00:00:00` and re-run.

1d chosen over RouterOS's factory default (3d) or the pre-project value: long enough to
eliminate the lease-renewal churn/log noise seen at 5m, short enough that a
disconnected/transient device (phones with randomised MACs on the dynamic pools, in
particular) reclaims its address reasonably promptly. Matches common home-router defaults.

**Verified:** `/ip/dhcp-server/print detail` on all three shows `lease-time=1d`.

### Finding 29 closed — Home Assistant's Supervisor connectivity check identified and given a scoped HTTP exception (2026-09-14)

Found the same day as the rule 45 narrowing: Home Assistant continuously retrying plain HTTP
to three Cloudflare edge IPs, blocked by `services2internet`'s new HTTPS-only policy (729
drops in one ~4.5h capture, no backoff, still going at capture end).

**Identification.** `ha core logs` and `ha supervisor logs` (pulled via `sync.sh`, extended
the same day to fetch both — see `home/home-assistant/changelog.md`) both came up completely
clean — neither Core nor Supervisor's own Python-level logging mentions this traffic at all.
`ha resolution info`'s checks/issues list also came up clean — no internet-connectivity issue
registered there either. The real signal came from a live functional failure Guillaume hit
independently: updating the Z-Wave JS add-on failed with `'AppManager.update' blocked from
execution, no host internet connection` — proof Supervisor has its own internet-connectivity
gate, entirely separate from the logging/resolution-center surfaces already checked, and that
it currently believes there is none. `dig checkonline.home-assistant.io +short` from an
unrestricted `vlan-users` client returned exactly the three IPs already seen blocked in the
firewall log — confirms this is Home Assistant Supervisor's own built-in connectivity check
(deliberately plain HTTP, by HA's own design, to reliably detect captive portals — HTTPS can't
do that as cleanly), not a third-party integration or rogue add-on.

**Fix, iterated once.** First draft was a `dst-address-list` scoped to the three known
Cloudflare IPs — rejected by Guillaume as too fragile (those IPs aren't guaranteed stable,
and an IP-list exception would need re-verifying every time Cloudflare's anycast addresses for
that hostname rotate — the project already learned this lesson once with the abandoned
TLS-SNI-allowlist attempt, 2026-09-11). Rewritten scoped to `src-address=192.168.20.60`
instead, unrestricted by destination — matching the existing precedent on
`services2iot`/`services2users`'s HA-specific rules (`firewall.md`: "any future \[need\] is
reachable ... without a firewall change"). Applied directly by Guillaume, comment
`services2internet: allow Home Assistant to connect on plain HTTP`.

**A first application was missing `connection-state=new`** — every other rule in this chain
has it, and README.md's hard-won lessons list its absence as a confirmed `I - INVALID` trigger.
No `I` flag was visible on the initial `print`, but that's consistent with the lessons list's
own caveat that the flag can be transient or not show on a basic query — fixed for consistency
regardless (`/ip/firewall/filter/set ... connection-state=new`), re-verified clean.

**Verified functionally, not just by print output:** the Z-Wave JS update that had failed with
"no host internet connection" was retried and succeeded.

**Firewall rule numbers shifted:** the new rule landed at real global position 49 (confirmed
via a fresh `dump-configs.sh` after the fact, not guessed), pushing the catch-all to 50 and
every rule in `iot2internet` through `internet2services` up by one (51-76, previously 50-72).
`firewall.md` fully renumbered to match, including filling in two rows (`iot2internet`'s
ceiling-fan-drop and iotawatt-NTP rules) that had carried a "—" placeholder since an earlier
insertion left their exact position uncertain — now known precisely from this dump.

IPv6 not given the equivalent exception — no log evidence yet that it's needed there.

### Finding 29's HTTP exception generalized to an address list, IPv4 + IPv6 (2026-09-15)

Rule 49 (`src-address=192.168.20.60`, HA-specific) replaced with an address-list-scoped
exception on both IPv4 and IPv6, anticipating more `vlan-services` hosts needing the same plain
HTTP exception (pihole named as a likely future candidate) without a firewall-rule edit each
time.

**A false start earlier the same day, caught before it did anything real:** an attempt to just
widen rule 45's *comment* to "HTTP / HTTPS from any services host" landed without also widening
its match criteria (still `dst-port=443` only) and without noticing rule 49 had been dropped —
net effect would have been *more* restrictive than before (no plain HTTP at all, comment
actively lying about what the rule did). Caught by re-diffing the fresh dump against
`firewall.md` before applying anything further; reverted by Guillaume back to the original
`services2internet: HTTPS from any services host` comment before this fix was drafted.

**Applied via `scripts/http-outbound-exception.rsc`** (deleted after verified, per convention),
idempotent (checked by `comment`/`address` before adding). Two new address lists,
`http-outbound` (IPv4) and `http-outbound-v6` (IPv6), seeded with only Home Assistant's address
for now — `192.168.20.60` and the same EUI-64 IPv6 address already pinned in `ha-v6`
(`2a02:1210:7621:9a41:da3a:ddff:fe31:e059`, from MAC `D8:3A:DD:31:E0:59`; that pinning still
depends on privacy extensions staying off on HA, see `README.md`'s hard-won lessons). Adding
another host later (pihole, or anything else) is a single `address-list add`, no firewall change
needed. One new accept rule per protocol family in `services2internet`
(`protocol=tcp dst-port=80 src-address-list=<list> connection-state=new`), placed before each
chain's catch-all deny via a freshly-evaluated `place-before=[find ...]` (not cached, per the
existing `place-before` caching gotcha).

**Verified by `print` only:** `/ip/firewall/address-list/print where list=http-outbound` and the
IPv6 equivalent both show Home Assistant's address, correct creation time.
`/ip/firewall/filter/print detail where chain=services2internet` and the IPv6 equivalent both
show the new rule in position 4 (immediately before the deny-all at 5), no `I - INVALID` flag on
either.

**Functional re-verification the same day found the IPv4 side working and the IPv6 side
still broken** (finding 31, opened and closed the same day — see below): Home Assistant's real
IPv6 traffic used a temporary (privacy-extensions) address that didn't match
`http-outbound-v6`'s EUI-64 entry, so every plain-HTTP attempt still hit the catch-all. Not this
fix's bug — the address list and rule were exactly as designed; the host's own IPv6 addressing
had never actually been confirmed correct for HA (unlike Pi-hole and OctoPrint, fixed
2026-09-11).

`firewall.md`'s tables, quick-reference row, and address-list section updated to match; IPv6
firewall table gets the same exception added for the first time (previously had none for plain
HTTP).

### Finding 31 closed — Home Assistant's IPv6 privacy extensions disabled via HAOS's `ha network` CLI (2026-09-15)

Found the same day, immediately after the `http-outbound-v6` change above surfaced it: every
plain-HTTP SYN from Home Assistant kept hitting `services2internet-v6`'s catch-all, source
`2a02:1210:7621:9a41:c988:6e5a:9958:c40f` — not the EUI-64 address (`...da3a:ddff:fe31:e059`)
pinned in `ha-v6`/`http-outbound-v6`. `src-mac D8:3A:DD:31:E0:59` in the same log lines confirmed
this really was Home Assistant, not misattribution.

**Same failure mode as finding 21 (Pi-hole/OctoPrint, 2026-09-11), but never actually checked on
HA at the time** — that entry explicitly says "(Home Assistant not checked or fixed ... whether
`ha-v6` has the same problem is still unknown)". `firewall.md`'s IPv6 section had been wrongly
asserting since then that all three hosts were fixed; corrected alongside this closure.

**HAOS-specific fix, not the generic Debian recipe.** Home Assistant runs as HAOS, confirmed by
checking the SSH & Web Terminal addon shell: no `nmcli`, no
`/etc/NetworkManager/system-connections/` (the addon runs in its own sandboxed netns, not the
host's). The durable, Supervisor-persisted equivalent is `ha network`, whose `network info`
output already exposes `ipv6.addr_gen_mode`/`ipv6.ip6_privacy` per interface (both `default` on
`end0` beforehand) — confirming this is a real, intentional Supervisor-modeled setting, not
something to fight around.

```
ha network update end0 --ipv6-addr-gen-mode eui64 --ipv6-privacy disabled
```

**First attempt failed harmlessly**: `Error: Can't update config on end0: ipv6.method: method
'manual' requires at least an address or a route` — the CLI does not merge unspecified fields
with the existing config; omitting `--ipv6-method` let it default to `manual` internally, which
then failed validation with no address supplied. Fixed by re-asserting the interface's existing
method explicitly:

```
ha network update end0 --ipv6-method auto --ipv6-addr-gen-mode eui64 --ipv6-privacy disabled
```

Succeeded immediately, no reboot needed — `end0`'s IPv4 config (`192.168.20.60/24`, gateway
`192.168.20.1`, nameserver `192.168.20.40`) confirmed unchanged in the same `ha network info`
output. **Verified functionally**: `ip -6 addr show scope global dev end0` immediately showed
the precomputed EUI-64 address in place of the temporary one — no waiting for a lease/RA cycle,
unlike the sysctl+reboot approach finding 21 needed. A fresh `dump-logs.sh` afterward showed the
`services2internet-v6` catch-all stopped logging Home Assistant's MAC entirely from that point
on, while unrelated traffic (Pi-hole's NTP) kept being logged normally in the same window —
confirms the fix, not a logging gap.

`services2users`'s HA-specific IPv6 rules (printer CUPS/631, Samsung TV/8002, both scoped to
`ha-v6`) were never separately retested — both already work over IPv4 regardless, so there was
no independent way to trigger IPv6-only traffic on that path, but they should now also match
real traffic given the same underlying address is fixed.

### OctoPrint's `iot2internet` exception re-widened to `dst-port=80,443` (2026-09-15)

Reopens the 2026-09-11 HTTPS-only narrowing (see above): OctoPrint was repeatedly retrying a
plain-HTTP connection to `185.15.58.224:80` (service/purpose unidentified — not investigated
further once the fix confirmed working), continuously hitting `iot2internet`'s catch-all.
Applied directly by Guillaume (`/ip/firewall/filter/set [find comment="iot2internet: octoprint
updates exception"] dst-port=80,443`).

**Verification needed a second, later log dump** — the first fresh log still showed drops for
`192.168.30.81` up to the same timestamp the dump was taken, making the fix look like it hadn't
taken effect. A second dump taken ~8 minutes later showed the drops had stopped entirely (last
one at `16:52:06`) while unrelated traffic kept logging normally in the same window — the first
dump simply caught the tail of pre-fix retries, not a failed fix. `/ip/firewall/filter/print
detail where chain=iot2internet` also confirmed no `I - INVALID` flag on the rule, and its
counter had moved (37 packets) by the time of the second check.

Also closes the standing IPv4/IPv6 asymmetry noted in `firewall.md`: `octoprint-v6` already
allowed both ports, so both address families now match.

### IotaWatt's `iot2internet` exception widened to `dst-port=80,443` (2026-09-15)

Same shape as OctoPrint's re-widening above, found the same session: IotaWatt (`192.168.30.50`)
was retrying an hourly, unencrypted connection to a fixed IP (`208.113.149.63:80`, purpose
unidentified — a separate check-in distinct from its HTTPS firmware-update path), 6-7 quick
retries then quiet for ~an hour, repeating — continuously hitting `iot2internet`'s catch-all.
Applied directly by Guillaume, widening the existing firmware-update exception rather than
adding a new one, since it's the same address-list/chain and there was no reason to keep them
separate.

**Verification took a full day, not a second dump.** Immediately after the change, the rule's
counter was still `0/0` and the log's last entry was itself a pre-fix failure — indistinguishable
from a broken fix at that point (same ambiguity as OctoPrint, worse here since IotaWatt's cycle
is hourly rather than every few minutes). Confirmed the next day: `/ip/firewall/filter/print
stats` showed the counter at 12 packets, and a fresh `dump-logs.sh` covering the intervening
~12 hours showed zero further catch-all hits for `192.168.30.50` — 12 packets over ~12 hours
matches one successful check-in per hour almost exactly, and rules out a fluke.

No `I - INVALID` flag observed on the rule at any point. `firewall.md`'s table, quick-reference
row, and prose updated to match.

### HA's `linux-monitor` HACS integration given SSH access to OctoPrint and the desktop, and a new `ssh-hosts` address list (2026-09-16)

Home Assistant's newly-added `linux-monitor` integration (jrackerby/linux-monitor, tracks
package/kernel updates over SSH) needs to reach OctoPrint (`vlan-iot`) and the desktop
(`vlan-users`) — both cross-VLAN from HA's own `vlan-services`, so both needed new
`chain=forward` jump-chain accept rules. Pi-hole needed none — same VLAN as HA, never reaches
mikrotik1's IP firewall at all (`use-ip-firewall=no`, confirmed on the bridge).

A new `ssh-hosts` address list (not the existing `octoprint` list, deliberately — Guillaume's
call, expecting more hosts to be added over time regardless of VLAN) holds every SSH-monitored
host: OctoPrint's wired + wifi addresses and the desktop's. One accept rule added to each of
`services2iot` (# 71) and `services2users` (# 66), both `src-address=192.168.20.60 (HA)
dst-address-list=ssh-hosts dst-port=22`. Destination-scoped via the list rather than port-only
like `services2iot`'s existing HA exceptions (Tuya/Tasmota/ESPHome) — SSH is full shell access,
not a single-purpose device protocol, so it gets the same per-device scoping precedent as
`services2users`' printer/TV rules instead. A single list spanning two VLANs is safe because
each chain's own dispatch rule already restricts it to that VLAN's traffic before the
address-list match is even evaluated — adding a future host on either already-covered VLAN is
then just an address-list entry, no rule change; a genuinely new VLAN still needs its own
one-line rule.

**A new, real RouterOS `import` bug found and worked around, not just a repeat of already-known
quirks.** The two accept-rule `/add` commands, every time they were run via `import` of a
`.rsc` file — regardless of path notation (`/ip/firewall/filter/...` vs `/ip firewall filter
...`), regardless of whether `place-before=[find ...]` was inline or precomputed into a local
variable first, regardless of whether a `:foreach` loop populating the address list ran earlier
in the same script or as a separate prior `import` entirely — created **two** copies of the
rule instead of one, from a verified-empty starting state each time (confirmed via
`/ip/firewall/filter/print detail where dst-address-list=ssh-hosts` showing nothing
immediately before each test). The address-list-population `:foreach` loop itself never
duplicated its own adds, across every single test — only these two specific `/add` commands did,
and only when run via `import`. **Typing the exact same single-line command directly at the CLI
prompt worked correctly first time, both times** — one clean rule, right position, no
`I - INVALID`. Root cause not identified (not file corruption — verified via `/file print
detail` showing correct single-copy contents at the exact moment of a duplicating run); worked
around by abandoning `import` entirely for these two specific commands and typing them by hand.
Added to `README.md`'s hard-won lessons.

Two rounds of cleanup were needed after each `import` attempt, since neither
`comment=""` nor `numbers=<n>` reliably isolated just the bad copy on the first try (an unset
comment isn't stored as literal empty string, so `find where comment=""` was a silent no-op
matching nothing; global rule numbers shift when removed out of order) — the working approach
was `/ip/firewall/filter/remove [find where dst-address-list=ssh-hosts]` (single condition,
removes every rule using the list at once, safe here since nothing else legitimately uses it
yet) followed by a clean re-add.

**Verified:** `/ip/firewall/address-list/print where list=ssh-hosts` shows exactly 3 entries
(`192.168.30.80`, `192.168.30.81`, `192.168.10.90`), no duplicates, across every test — this
part never had a problem. `/ip/firewall/filter/print detail` on both chains shows exactly one
`ssh-hosts` rule each, correctly placed before their catch-all, no `I - INVALID`. Real global
rule numbers confirmed via a fresh `dump-configs.sh` after the fact (63-67 for `services2users`,
68-72 for `services2iot`), not guessed — `iot2users` through `internet2services` all shifted up
by 2 as a result (73, 74-77, 78) and `firewall.md` fully renumbered to match.

HA-side setup (HACS install, dedicated `ha-monitor` unprivileged system accounts on all three
hosts with a fresh dedicated SSH keypair under `/config/ssh_keys/`, no sudo granted) and its own
troubleshooting (a wrong key path in the config flow, initially misdiagnosed as a host-key
verification problem) are Home Assistant-side, not network config — see
`home/home-assistant/changelog.md` if a parallel entry exists there, otherwise this is the only
record.

### Finding 27 closed for real — Pi-hole's hourly NTP traffic was pihole-FTL's own built-in NTP client, not systemd-timesyncd (2026-09-16)

Originally found 2026-09-13, closed 2026-09-14 on the strength of a `FallbackNTP=192.168.20.1`
fix, reopened the same day when the identical hourly burst continued unchanged against public
IPs. Real root cause found this session via a `/proc/net/udp` + PID-mapping probe (auditd's
syscall-level tracing caught nothing at all for this traffic across a 5-hour window, despite
catching unrelated `pihole-FTL` DNS traffic in the same minute — consistent with the sender
using `io_uring`, which bypasses the `connect`/`sendto`/`sendmsg`/`sendmmsg` syscalls auditd
hooks into, but still populates the same kernel socket table the `/proc/net/udp` probe reads):
**`pihole-FTL` itself** (PID 530), not a hidden process, not `systemd-timesyncd`, not cron, not
any systemd timer. Recent Pi-hole FTL versions (v6+) ship a built-in NTP client so the query
log gets accurate timestamps on Raspberry Pi hardware with no battery-backed RTC — entirely
independent of the OS's own time sync, which explains why every earlier `systemd-timesyncd` fix
attempt (found on `/etc/pihole/pihole.toml`'s `[ntp]` section) had zero effect on the live
problem.

Disabled directly by Guillaume via FTL's own TOML config (`/etc/pihole/pihole.toml`'s `[ntp]`
section). **Verified:** last hourly hit was 2026-09-16 15:00:21; a fresh `dump-logs.sh` taken
~5 hours later (20:02) shows zero further hits despite multiple expected cycles in that window
(16:00, 17:00, 18:00, 19:00, 20:00) — clean.

`auditd` (installed for this investigation, not previously part of this project, on Pi-hole
only) fully purged afterward, along with the temporary watch script and its log — nothing left
running or installed as a result of the investigation.

### Finding 32 closed — `users2services`/`iot2services` now allow DNS-over-TCP to Pi-hole (2026-09-22)

Found 2026-09-18 via firewall log review: only UDP/53 to Pi-hole (`192.168.20.40`) was allowed
from `users`/`iot`, so any client whose DNS response needed a TCP retry (large/DNSSEC-heavy
answers) would silently fail. Fixed by running `scripts/dns-tcp-pihole.rsc`, which added one
`protocol=tcp dst-address=192.168.20.40 dst-port=53 connection-state=new` accept to each of
`users2services` and `iot2services`, positioned before each chain's catch-all.

`users2services: DNS (TCP)` printed clean immediately. `iot2services: DNS to pi-hole (tcp)`
printed with `I - INVALID` immediately after creation despite being structurally identical to
its sibling rule — not one of the already-catalogued triggers (see `README.md`'s hard-won
lessons), and not caused by a cached/reused `find` result, since the script evaluates each
`place-before=[find ...]` fresh at its own `/add`. A later re-print showed the flag gone with no
action taken. **This is the same transient-then-clears behavior finding 21 saw on
`/ipv6/firewall/filter`, now confirmed on `/ip/firewall/filter` (IPv4) too** — `README.md`'s
existing note that the pattern "doesn't transfer cleanly" to IPv4 no longer holds; updated
there.

**Verified functionally, not just by print**, per the same standard finding 21 used:
- `nc -vz 192.168.20.40 53` from OctoPrint (a real `vlan-iot` host): `Connection to
  192.168.20.40 53 port [tcp/domain] succeeded!`
- `/ip/firewall/filter/print stats where comment="iot2services: DNS to pi-hole (tcp)"` on
  mikrotik1, taken right after: `60` bytes, `1` packet — real traffic hit the rule, not just a
  clean-looking print.

`scripts/dns-tcp-pihole.rsc` deleted per `README.md`'s one-shot-script convention.

### WireGuard road-warrior VPN applied and verified — `wireguard1` on mikrotik1 (2026-09-22)

Design in [vpn.md](vpn.md). `scripts/wireguard-road-warrior.rsc` created the interface
(`192.168.50.1/24`), the peer (`MrG Galaxy S24`, `192.168.50.2/32`), a `chain=input` accept for
UDP/51820 from `WAN`, and three `chain=forward` dispatch rules treating `wireguard1` exactly
like `vlan-users` (`users2internet`/`users2services`/`users2iot`, reused as-is). All four new
rules printed clean, no `I - INVALID` this run.

Endpoint ended up `home.ledcom.fr`, not the originally-designed MikroTik Cloud DDNS hostname —
`/ip/cloud`'s `dns-name` came back empty when the script ran, so that hostname wasn't usable
as-is anyway. Guillaume separately reported (same day) that `home.ledcom.fr` is kept current by
the Home Assistant Let's Encrypt add-on's Gandi integration, previously broken by an expired
API key that's now renewed — see `config-review.md` finding 25, left open pending full
reconciliation with the 2026-09-11 entry above, which had ruled that same mechanism out.

**Verified end-to-end from the phone, over mobile data (not home wifi):**
- `/interface/wireguard/peers/print detail`: `last-handshake=2m`,
  `rx=309.9KiB`/`tx=2330.5KiB` — real bidirectional traffic, not just a configured-looking
  peer. `current-endpoint-address=178.197.196.50:39400` — the phone's actual mobile-carrier
  egress, confirming the session came in over the real internet.
- A "what's my IP" check from the phone, made *through* the tunnel, reported `178.192.223.49`
  — matching the home's known real public IP from the 2026-09-11 box-swap entry above, and
  obtained independently of the router's own self-report.
- **`/ip/cloud/print`'s `public-address` was checked and explicitly distrusted** (Guillaume) —
  it read the old `188.61.18.91`, over a week stale, consistent with finding 25's own note that
  `ddns-update-interval: none` means this field doesn't reliably refresh. Not used as evidence;
  the phone-side external check above is the real verification.

`scripts/wireguard-road-warrior.rsc` deleted per `README.md`'s one-shot-script convention.

### DoT probes to Pi-hole now rejected quietly instead of silently dropped (2026-09-22)

Guillaume's request: Android's opportunistic Private-DNS probes to Pi-hole (`192.168.20.40:853`
— see `README.md`'s "DNS-over-TLS from clients to Pi-hole", not fixable, Pi-hole doesn't speak
DoT) were falling through to `users2services`/`iot2services`'s generic `drop, logged`
catch-alls — blackholed (client waits out its own timeout) and logged as noise on every attempt.
`scripts/reject-dot-quiet.rsc` added one `action=reject reject-with=tcp-reset` rule to each
chain, matched on `dst-port=853` to Pi-hole, with no `log=` set (so it won't appear in future
log collections the way the catch-all hits did).

`users2services` printed clean immediately. `iot2services` printed `I - INVALID` on creation
again — third occurrence of this transient pattern in this project, **second time specifically
in `iot2services`** (finding 32 was the first) — no longer looks like coincidence, though still
unexplained; noted in `README.md`'s hard-won lessons. Cleared on a later re-print with no action
taken, same as both previous times.

**Verified functionally:** `nc -vz 192.168.20.40 853` from OctoPrint (`vlan-iot`) returned
`Connection refused` immediately — not a hang — confirming the reject is real, not just a
clean-looking print. `users2services`'s twin rule wasn't independently functionally tested
(no `vlan-users` host was used to confirm it) — same rule shape, printed clean immediately
unlike its sibling, treated as sufficient given the pattern established across the last three
`iot2services`-vs-`users2services` comparisons, but worth a real check if this chain is ever
touched again.

`scripts/reject-dot-quiet.rsc` deleted per `README.md`'s one-shot-script convention.

### `mgmt` access extended to gimli (work laptop) and the phone (via `wireguard1`) (2026-09-28)

Guillaume's request: add the work laptop and the phone (over the road-warrior VPN, see
`vpn.md`) to the set of clients that can reach router management. Three scripts, run against
all three reachable devices:

- `scripts/add-mgmt-hosts.rsc` added `192.168.10.92` (gimli, already a static DHCP reservation
  — see `vlan.md`'s device inventory) and `192.168.50.2` (the phone's `wireguard1` tunnel
  address) to the `mgmt` address-list, identically on mikrotik1, mikrotik2 and mikrotik3 — kept
  in sync per `firewall.md`'s convention. Printed clean on all three.
- `scripts/wireguard2users.rsc` (mikrotik1 only) added a new `wireguard2users` forward-chain
  relationship — mirroring every other VLAN-pair jump chain's shape (mgmt-only accept, then a
  logged deny-all) — plus the `in-interface=wireguard1 out-interface=vlan-users` dispatch jump,
  placed before the forward chain's final catch-all. This didn't exist before: the existing
  `wireguard1` dispatch (from the VPN's own rollout) only reached
  `users2internet`/`users2services`/`users2iot`, never `vlan-users` itself, so the phone had no
  forwarded path to mikrotik2/mikrotik3 at all (mikrotik1's own management already worked over
  the tunnel via `chain=input`, which doesn't care which interface a `mgmt`-listed source
  arrives on). The dispatch jump printed `I - INVALID` immediately after creation — consistent
  with this project's established transient-flag pattern (see `README.md`'s hard-won lessons)
  — and cleared on a later print with no action taken.

**A second, unrelated gate surfaced during verification:** the phone could load mikrotik1's and
mikrotik2's login pages (firewall accepted the connection) but authentication was refused on
both. The `admin` user account carries its own `address=` restriction, entirely separate from
the firewall — confirmed `address=192.168.10.0/24` on all three devices via `dumps/`, never
widened for the VPN's tunnel subnet. `scripts/widen-admin-address.rsc` set it to
`192.168.10.0/24,192.168.50.0/24` on all three (purely additive, no existing access removed).
This is the same class of gotcha `README.md` already documented from the VLAN renumber (a user
account's `address=` restriction locking out management independently of any firewall rule) —
now confirmed to recur on *onboarding a new mgmt source*, not just on a renumber. Added as its
own hard-won lesson rather than folded into the existing one, since the trigger is different.

**Verified functionally, not just by print:** real logins from the phone, over the actual VPN
tunnel, succeeded on all three devices — mikrotik1 and mikrotik2 first, mikrotik3 confirmed
after. mikrotik2 and mikrotik3's logins are the strongest evidence available that the new
`wireguard2users` dispatch is genuinely enforced despite its transient `I - INVALID` flag: a
real authenticated session, not a synthetic `nc` probe.

All three scripts deleted per `README.md`'s one-shot-script convention.

## cAP XL ac build — now mikrotik4 (2026-10-06)

The previously-unused cAP XL ac (`RBcAPGi-5acD2nD`, serial `HDM08XPMC7M`) was brought up as a
CAPsMAN-managed access point, joined to mikrotik1's existing `/caps-man`. See `wifi.md` for the
full build narrative and the still-open follow-ups (physical relocation, baseline hardening, a
real 5 GHz client test); this entry is the verification record.

**Initial access was the hardest part.** Connecting to a device with no known IP or confirmed
password, over mac-telnet, from mikrotik1's own CLI, repeatedly looked like it was succeeding
(login prompt, "Welcome back!" banner) but actually wasn't — `/system/routerboard/print`
afterward kept reporting mikrotik1's *own* model and serial number, proving the session never
left mikrotik1. Root cause was never nailed down for certain (most likely a silent auth failure
dropping back to the local session with no clear error), but the fix was to stop chaining
through mikrotik1's CLI entirely and use the Linux `mactelnet-client` package (`mndp` and
`mactelnet`) directly from the desktop, on the same `vlan-users` L2 segment as mikrotik1's
`ether10` — which gave an honest "Connection failed" instead of a misleading fake success.

**That honest failure led to the real problem: a bad firmware update.** The device had been
reached once already, over its own default WiFi, via the HTTP quick-set interface, and a
firmware/package update was installed from there. After the reboot, the WiFi disappeared
entirely and the device stopped responding to MNDP, mac-telnet, and DHCP alike — while still
showing a live Ethernet link (its MAC was learned correctly on mikrotik1's `ether10` throughout,
confirmed via `/interface/bridge/host/print`) and solid, non-blinking power/user LEDs. That
combination — live link, no response to anything above it, non-blinking LEDs — pointed at a
device stuck at the RouterBOOT loader rather than a configuration problem.

**Fixed via Netinstall.** Using `netinstall-cli` (the Linux build) over a direct point-to-point
Ethernet cable from the desktop:
```
sudo ./netinstall-cli -i eno2 -v -e routeros-7.24.5-arm.npk
```
Completed cleanly — "Successfully finished installing device 48:A9:8A:2E:10:0C" — and booted
with RouterOS 7.24.5, empty config (no bridge, no addresses, no wireless package).

**Wireless driver installed and confirmed working.** This also settled `wifi.md`'s long-open
question of whether this hardware (`firmware-type: ipq4000L`, Qualcomm IPQ4019) needs the new
`wifi-qcom-ac` stack: it doesn't, at least not exclusively — `/system/package/print` showed no
wireless driver at all post-netinstall (`/interface/wireless/print` returned a syntax error,
package absent; `/interface/wifi/print` returned cleanly but empty). Installed
`wireless-7.24.5-arm.npk` via SCP to the device's root file list (reached over DHCP on `ether1`,
pool/reservation address `192.168.10.4`) and a reboot. `/interface/wireless/print` then showed
two live radios, `interface-type=IPQ4019`: `wlan1` (2.4 GHz, MAC `48:A9:8A:2E:10:0E`) and `wlan2`
(5 GHz, MAC `48:A9:8A:2E:10:0F`). A separate explicit `/system/routerboard/upgrade` was also
needed — plain reboots alone never applied the pending RouterBOARD firmware update
(`current-firmware` stayed at `7.12.1` against `upgrade-firmware: 7.24.5` through several
reboots until this command was run).

**Joined to mikrotik1's CAPsMAN (Branch A from `wifi.md`).** Gave the device a local bridge
(`ether1` as a member) and handed both radios over:
```
/interface/bridge/add name=bridge
/interface/bridge/port/add bridge=bridge interface=ether1
/interface/wireless/cap/set enabled=yes interfaces=wlan1,wlan2 discovery-interfaces=bridge \
    bridge=bridge caps-man-addresses=192.168.10.1
```
On mikrotik1, added a 2.4 GHz configuration on the previously-reserved-but-unused `ch6` channel
and a new 5 GHz channel/configuration (channel 42, 5210 MHz — see `wifi.md` for why `width=`
isn't a valid `/caps-man/channel` property), then provisioned both radios by MAC, each with
`caps_iot` as a slave for `LEDCOM-IoT`. The first provisioning attempt bound both radios under
the pre-existing catch-all rule (created before the specific rules existed) — `cap8` came up on
the wrong 2.4 GHz channel (`ch1`, duplicating mikrotik1's own) and `cap10`'s 5 GHz radio got a
2.4 GHz-only config, landing on `current-state="no-channel"`. Fixed by forcing re-provisioning:
`/caps-man/remote-cap/provision numbers=[find identity=RBcAPGi]` (the `numbers=` parameter needs
an ID from `/caps-man/remote-cap/print`, not a bare `[find ...]`). This recreated the dynamic
interfaces under new names (`cap11`-`cap14`) with the correct configs.

**Verified** — `/caps-man/interface/print detail` on mikrotik1, all four `current-state`
`running-ap`:
```
cap11  48:A9:8A:2E:10:0E  caps_ch6  2437/20/gn(20dBm)        — LEDCOM, 2.4 GHz
cap12  (slave of cap11)   caps_iot                            — LEDCOM-IoT, 2.4 GHz
cap13  48:A9:8A:2E:10:0F  caps_5g   5210/20-Ceee/ac/DP(20dBm) — LEDCOM, 5 GHz
cap14  (slave of cap13)   caps_iot                            — LEDCOM-IoT, 5 GHz
```
5 GHz (`cap13`) went through a `detecting-radar` state first both times it was provisioned —
expected, not a fault: `country=switzerland` requires a DFS Channel Availability Check across
the entire 5150-5350 MHz range (unlike the US, where low UNII-1 channels skip it), and it
cleared both times within about a minute. A real client (phone) associated and roamed correctly
between `cap11` and the two pre-existing 2.4 GHz radios during the reprovisioning bounce,
confirming real client handoff works. A real client on 5 GHz specifically was not yet confirmed
— still open, see `wifi.md`.

**Documentation error found and corrected, not a config change.** `wifi.md` and
`config-review.md` had both attributed the `192.168.10.4` DHCP reservation and MAC
`48:A9:8A:2E:10:0C` to the still-unbuilt SXTsq Lite2 (intended as mikrotik4). That MAC is
actually, confirmed from its physical label, the cAP XL ac's own `ether1` — meaning this device
has effectively always been mikrotik4 by address, the documentation just named the wrong
hardware. The reservation itself needed no change. The SXTsq Lite2 now has no device number
assigned and will need its own, once its real MAC is checked from its own label — not reused
from here.

**Physical location confirmed 2026-10-06: mikrotik1's `ether10` is final, not a bench setup.**
The `wifi.md` plan to power this device from mikrotik3 via injector (recorded 2026-09-05) is
superseded for the cAP — it stays on `ether10`. That plan still applies, unchanged, to the
SXTsq, which will go through mikrotik3 via injector in the office once built.

**Still open, tracked in `wifi.md` and `config-review.md`:**
- Confirm a real client association on 5 GHz specifically (not just `running-ap` state).
- Baseline hardening to match every other device (`mgmt` list + `admin` address restriction,
  services off, `ha` account, SSH hardening, proven MAC-Telnet recovery).
- RouterOS version drifted from the fleet (`7.24.5` vs `7.24.2`) during recovery — not urgent.

### Correction, 2026-10-07: the above "verified working" was wrong for 5 GHz

Everything above reported `running-ap` with real VHT rates on 5 GHz and a client associated on
2.4 GHz — reasonable to call "working" at the time, but 5 GHz never actually transmitted
anything. No client (phone, then a Linux desktop forced to a specific BSSID), at any range
including standing next to the device, under any regulatory domain, ever associated on 5 GHz
under the legacy `wireless` package. RouterOS's own state reporting was simply unreliable on
this chip for this driver — not a config mistake on either end.

**Fix: switched to `wifi-qcom-ac`, standalone.** Removed `wireless`, installed
`wifi-qcom-ac-7.24.5-arm.npk`, reconfigured `wifi1`/`wifi2` directly (no CAPsMAN — see below for
why that's now permanent, not just an interim state). 5 GHz worked immediately, confirmed by a
real client associating within seconds at close range — proof this was a driver limitation, not
a hardware fault or a regulatory/DFS issue (several of which were suspected and ruled out along
the way: Location services, self-managed regulatory domains, passive-scan timing).

**All CAPsMAN scaffolding from the entry above was torn back out of mikrotik1**, since
`wifi-qcom-ac` can't be managed by mikrotik1's legacy `/caps-man` at all — the two provisioning
rules (radio-mac `...0E`/`...0F`), the `caps_ch6` and `caps_5g` configurations, and the
`ch5g-42` channel were all removed. The dynamic `/caps-man/interface` entries for this device
had already cleared themselves once it disconnected. `ch1`/`ch6`/`ch11` and `caps_config`/
`caps_ch11`/`caps_iot` (long-standing, used by mikrotik1/mikrotik2's own radios) were untouched.

**`LEDCOM-IoT` is not offered on mikrotik4 — confirmed impossible, not unconfigured.** Wanted
a second SSID per band tagged onto VLAN 30, matching every other AP. Three distinct mechanisms
tried, each verified by packet capture on `ether1` rather than trusted on RouterOS's own
reporting (given the lesson above):
1. Bridge port `pvid=30` on the virtual SSID interface — no effect, traffic left untagged.
2. `datapath.vlan-id=30` (the mechanistically-correct approach, matching CAPsMAN's own
   `caps_iot`) — RouterOS rejected it as unsupported on this hardware, and actively disconnected
   any client that tried to associate while it was set.
3. MikroTik's own published workaround for this exact chip/package (`switch1` hardware VLAN
   table entry, `ingress-filtering=no`, `vlan-mode=fallback`, plus a full reboot since
   switch-chip VLAN config often needs one) — zero effect, confirmed by a second packet capture
   after reboot.

Removed `wifi1-iot`/`wifi2-iot` and their bridge ports (which don't auto-clean when the
interface is removed — left dangling, shown as `interface=*N`; had to be found via
`pvid=30` and removed separately), the VLAN 30 bridge-vlan entry, and the `switch1` VLAN 30
entry. mikrotik4 now serves `LEDCOM` only, both bands, correctly landing on `vlan-users`
(verified: a real client's DHCP lease moved from `dhcp-home` 192.168.10.x, which is what it was
incorrectly getting while `LEDCOM-IoT` was attempted, back to just that same correct pool now
that `LEDCOM-IoT` no longer exists to be confused with). `ingress-filtering=no` and
`vlan-mode=fallback` were left in place deliberately — harmless now, and reverting risks
re-triggering the wireless-settling disruption noted below for no benefit.

**SSH key auth added for `admin`** (`/user/ssh-keys/import`), password auth left enabled as
fallback.

**New hard-won lessons from this correction, worth README.md's collection:**
- Bridge-vlan `find` can match multiple rows for one `vlan-ids` (a real static entry plus
  RouterOS-auto-managed dynamic ones) — `/get`/`/set` against the unfiltered result fails
  (`invalid internal item number` / `can not change dynamic`). Filter on `dynamic=no`.
- `current-tagged`/`current-untagged` are the live, effective values; `tagged`/`untagged` are
  configured and can carry stale unparseable references (`*NN`). Rebuild from `current-*`.
- A property read via `/get` can come back as a native array; concatenating it with a string via
  `.` broadcasts the string onto every element instead of joining them — join arrays by hand.
- The bridge interface's own `pvid` (separate from any port's) governs VLAN tagging for the
  bridge's own locally-bound traffic. Leaving it at default broke reachability on its own, with
  every port otherwise correctly configured.
- A self-removing scheduled job can still fire twice — make the on-event idempotent, don't
  assume the removal is instantaneous relative to the next scheduled firing.
- `/interface/bridge/host`'s VLAN property is `vid`, not `vlan-id`, and comes back empty for
  ordinary wireless traffic regardless of VLAN — not a useful signal; go to a wire-level capture
  (`/tool/sniffer`) instead of guessing at more bridge-table properties.
- Don't trust `current-state`/`running-ap` on `wifi-qcom-ac`/IPQ4019 hardware without an actual
  client-association test — it can report full success for a radio that transmits nothing.

## mikrotik1 — findings 34 and 35 closed (2026-10-07)

Both found during the same-day fleet-wide config review (see the fork's findings, recorded in
`config-review.md` before this closure).

**Finding 34 — SNMP community reverted to wide-open.** `/snmp/community/print detail` showed
`addresses=0.0.0.0/0` on the default `public` community; `changelog.md`'s Round 1 (2026-09-03)
entry had explicitly narrowed this to `192.168.1.0/24`, so it had drifted back open at some
point since. Fixed:
```
/snmp/community/set [find default=yes] addresses=192.168.10.0/24
```
Verified: `/snmp/community/print detail` now shows `addresses=192.168.10.0/24`. SNMP itself
still doesn't show as an active listener in `/ip/service/print`, so this was precautionary —
closing the misconfiguration before SNMP is ever actually turned on, not fixing a live exposure.

**Finding 35 — unused BGP template and BFD config left enabled.** Both were explicitly enabled
defconf debris with no actual BGP peer or BFD-using protocol anywhere else in the config —
survived the original "dead debris" cleanup (findings 19/20, round 1). Fixed by disabling
rather than removing (reversible, same security/cleanliness benefit):
```
/routing/bgp/template/set default disabled=yes
/routing/bfd/configuration/set [find] disabled=yes
```
Verified: `/routing/bgp/template/print detail` now shows the `X` (disabled) flag on `default`;
`/routing/bfd/configuration/print detail` now shows `Flags: X - DISABLED, I - INACTIVE` on its
one entry. This also closes the long-open 2026-09-10 question in `config-review.md` about
`route_BFD` reappearing in `/ip/service/print` — it was this same genuinely-enabled, unused BFD
config, not a dump-collection artifact.

## mikrotik4 — S17 baseline hardening, first six items closed (2026-10-07)

Found during the same-day fleet-wide config review (S17 in `config-review.md`, still open for
the remaining items — MNDP discovery, NTP, IPv6 firewall, build-session debris). All done
directly on mikrotik4 over SSH (key auth, set up earlier the same day), each verified by
`print` immediately after, same discipline as the rest of today's work.

**DNS pointed at Pi-hole**, matching every other device:
```
/ip/dns/set servers=192.168.20.40
```

**`mgmt` address-list added**, mirroring the exact 7-host list already on mikrotik1/2/3 (cross-
checked live on all three first — confirmed mikrotik4 was already correctly a member of
*their* lists since the 2026-09-07 renumber, so only mikrotik4's own list needed creating):
```
/ip/firewall/address-list/add address=192.168.10.1 list=mgmt comment=mikrotik1
/ip/firewall/address-list/add address=192.168.10.2 list=mgmt comment=mikrotik2
/ip/firewall/address-list/add address=192.168.10.3 list=mgmt comment=mikrotik3
/ip/firewall/address-list/add address=192.168.10.4 list=mgmt comment=mikrotik4
/ip/firewall/address-list/add address=192.168.10.90 list=mgmt comment=desktop
/ip/firewall/address-list/add address=192.168.10.92 list=mgmt comment=gimli
/ip/firewall/address-list/add address=192.168.50.2 list=mgmt comment="phone via wireguard1"
```

**`admin`'s own address restriction widened** — the separate gate from the list above:
```
/user/set [find name=admin] address=192.168.10.0/24,192.168.50.0/24
```

**`ha` group and user created**, same shape as the other three (password matched to the
existing `homeassistant` credential already configured in Home Assistant's MikroTik
integration, not shown here):
```
/user/group/add name=ha policy=read,test,api
/user/add name=homeassistant group=ha address=192.168.20.60 password=<matching the other three>
```

**Firewall input chain added**, matching the exact shape documented in `firewall.md` for
mikrotik2/mikrotik3 (also the same shape used for the SXTsq build template in `wifi.md`) —
split into two steps on purpose, pure accepts first, catch-all drop last, with a fresh SSH
session checked in between:
```
/ip/firewall/filter/add chain=input action=accept connection-state=established,related comment=established
/ip/firewall/filter/add chain=input action=drop connection-state=invalid comment="drop invalid"
/ip/firewall/filter/add chain=input action=accept protocol=icmp comment=ICMP
/ip/firewall/filter/add chain=input action=accept src-address-list=mgmt comment="mgmt hosts to device"
/ip/firewall/filter/add chain=input action=accept protocol=tcp src-address=192.168.20.60 dst-port=8728 comment="HA API access"
/ip/firewall/filter/add chain=input action=drop comment="drop everything else"
```
Rules 1-4 briefly showed the transient `I`-invalid flag on the first `print`, gone by the next
one — the same already-documented pattern in `README.md`'s hard-won lessons, not a new issue.
SSH confirmed still working from a fresh session after the catch-all drop went in.

**`ftp`/`telnet`/`reverse-proxy`/`api-ssl` disabled:**
```
/ip/service/disable ftp,telnet,reverse-proxy,api-ssl
```

**SSH hardened** to match the other three:
```
/ip/ssh/set strong-crypto=yes host-key-size=4096
/ip/ssh/regenerate-host-key
```
Regenerating the host key changes its fingerprint, so the desktop's cached one needed clearing
(`ssh-keygen -R router4.home.ledcom.fr`) before reconnecting — expected, not a problem.
Confirmed working afterward.

## NTP client enabled on mikrotik2, mikrotik3, mikrotik4 (2026-10-07)

Checking mikrotik4's missing NTP client (part of S17) against the established baseline found
mikrotik1 was the *only* device running one — mikrotik2/mikrotik3 both had `enabled=no`.
Guillaume's call: all four devices should be NTP clients, not just mikrotik4, so this became a
fleet-wide fix rather than mikrotik4-only. Same command on all three, pointing at mikrotik1
(which already runs its own NTP server for exactly this, matching this network's existing
"DNS and NTP are both fully self-contained" design rather than every device reaching the
public internet independently):
```
/system/ntp/client/set enabled=yes servers=192.168.10.1
```
Verified: all three showed `status: waiting` immediately after, then `status: synchronized`
with `synced-server: 192.168.10.1` within a minute, confirmed live on all three.

## IPv6 disabled on mikrotik4 (2026-10-07)

Was going to build a real IPv6 input-chain firewall for mikrotik4 (part of S17 — IPv6 was
present but minimal, with no firewall at all behind it). Guillaume's call instead: disable
IPv6 entirely, matching mikrotik2/mikrotik3 — switches and standalone APs on this network
don't need it.
```
/ipv6/settings/set disable-ipv6=yes
```
Verified: `/ipv6/settings/print` shows `disable-ipv6: yes`. Makes the empty-firewall concern
moot rather than needing a fix.

## S17 closed: mikrotik4's build-session debris cleared (2026-10-07)

Last item from mikrotik4's baseline-hardening pass. `/tool/sniffer` still had
`file-name=iot-test2` left over from the previous night's packet captures:
```
/tool/sniffer/set file-name=""
```
Verified: `/tool/sniffer/print` shows `file-name:` empty. `file-limit=2000KiB` left as-is —
a reasonable cap on its own, not worth chasing a "true default" for.

Checked `add-dns-entries-suffix=lan` before touching it: `/ip/dhcp-server/print` is empty on
mikrotik4 (it doesn't run a DHCP server — that's mikrotik1's job), so the suffix setting has
nothing to apply to. Genuinely inert, not a finding. Left alone.

**S17 is now fully closed** — firewall, `admin`/`mgmt` access control, services disabled, `ha`
account, SSH hardening, DNS, NTP, IPv6 disabled, and build debris cleared. mikrotik1,
mikrotik2, mikrotik3, and mikrotik4 all confirmed clean against the 2026-10-07 review.

## Pi-hole PTR-lookup warning traced to Home Assistant's hourly full-subnet reverse sweep (2026-10-07)

Pi-hole's web UI diagnostics showed a recurring `DNSMASQ_WARN`: "Maximum number of concurrent
DNS queries to 168.192.in-addr.arpa reached (max: 150)" — i.e. something flooding reverse
lookups for the `192.168.x.x` range. Guillaume's working theory was Home Assistant's network
discovery.

No API token is configured on this Pi-hole, so pulled the on-disk logs directly instead (see
`dump-pihole-logs.sh`, added this session). `FTL.log` (Pi-hole v6's consolidated log, matches
the web UI) has the same warning but no client field, so used the actual per-query log,
`pihole.log` (dnsmasq-style, one line per query including `from <client-ip>`), instead.

**First pass was wrong.** A narrow sample (`grep ... | tail -20`) happened to catch a short
burst of `192.168.10.90` (Guillaume's desktop) reverse-resolving its own address and
`172.17.0.1` (Docker's default bridge gateway) — real traffic, but a small, one-off
contributor (142 PTR queries across the whole day), not the cause of the warning. Aggregating
a full day's log (`pihole.log`, ~133k lines) instead shows the actual dominant source:
```
$ grep 'query\[PTR\]' pihole.log | awk '{print $NF}' | sort | uniq -c | sort -rn
   4502 192.168.20.60
    219 127.0.0.1
    196 192.168.20.1
    142 192.168.10.90
    138 192.168.10.200
```
`192.168.20.60` is Home Assistant (see `firewall.md`). Its PTR queries are a complete,
sequential sweep of the entire `services` subnet, once per hour, every hour:
```
$ grep '192\.168\.20\.60' pihole.log | grep -oP '\d+\.20\.168\.192\.in-addr\.arpa' | sort -u | wc -l
254
$ grep '192\.168\.20\.60' pihole.log | grep 'in-addr.arpa' | awk '{print $1,$2,$3}' | cut -d: -f1 | uniq -c
    255 Oct 7 00
    254 Oct 7 01
    ...(254-ish every hour)...
    887 Oct 7 11
    254 Oct 7 12
```
The 11:00 hour's spike to 887 lines up exactly with the warning's timestamp
(`11:50:26`, both `FTL.log` and `pihole.log` agree) — the hourly sweep firing fast enough to
hit the 150-concurrent-query cap. So Guillaume's original theory was right; the first
(corrected) write-up of this entry was the one that got it wrong.

No static HA config found in `home/home-assistant/config/` (`core.config_entries`,
`configuration.yaml`, `custom_components/`) that obviously does active subnet-wide reverse-DNS
scanning — no `nmap_tracker`, no `device_tracker` platform, nothing scan-interval-configured
for the `services` subnet. The responsible mechanism isn't identified yet. Tracked as
`home/home-assistant`'s finding 17 for that follow-up — this repo's job (confirming the
source and the pattern) is done; narrowing which HA component causes it belongs over there.

## mikrotik5 build — second RB750Gr3 (hEX), living room switch (2026-10-08)

New device, received 2026-10-07. Assigned `mikrotik5`, `192.168.10.5`. Built VLAN-aware
(trunk carries 20/30 tagged) despite the role not strictly needing it — Guillaume's call, for
fleet consistency and so a future services/iot device on the spare port doesn't need a
re-cable. See `vlan.md`'s "Living room and workshop" section for the design decision.

**mikrotik5 itself, via `scripts/mikrotik5-build.rsc`:** networking/VLAN bring-up (`ether1`
trunk into the bridge, `pvid=10` on all five ports, bridge-vlan table for 10/20/30, static
`192.168.10.5/24` replacing the DHCP-assigned bench address, a default route to `192.168.10.1`
per the "pure L2 switch needs its own route" lesson, DNS/NTP/IPv6 baseline), then the same
S1-S17-shape baseline hardening as mikrotik2/3/4 (`mgmt` list, `admin` address restriction, `ha`
account, input-chain firewall, disabled services, SSH hardening). **Verified:**
`/interface/bridge/port/print detail` showed `pvid=10` on `ether1`-`ether5`; `/ip/firewall/
filter/print`, `/ip/service/print`, `/user/print detail`, `/ip/ssh/print` all matched the
intended shape (established/invalid/icmp/mgmt/HA-API accepts then a final drop; ftp/telnet/
reverse-proxy/api-ssl disabled, `reverse-proxy` simply absent from this RouterOS's service list
rather than erroring; `admin` restricted to `192.168.10.0/24,192.168.50.0/24`; `homeassistant`
user present; `strong-crypto=yes host-key-size=4096`).

**mikrotik2's side, via `scripts/mikrotik2-add-mikrotik5-uplink.rsc`:** `ether12-slave-local`
(the living-room patch-panel run) added to VLAN 20 and 30's tagged list, same shape as
`ether16-slave-local` (trunk to mikrotik3), plus mikrotik2's own `mgmt` entry for mikrotik5.
**Verified:** `/interface/bridge/vlan/print` shows `ether12-slave-local` in vlan 20 and vlan
30's `current-tagged`; `/ip/firewall/address-list/print where list=mgmt` shows 8 entries
including mikrotik5 (`192.168.10.5`, added `2026-10-08 09:51:17`).

**Two real scripting bugs found and fixed along the way, both now recorded in README's
hard-won lessons:**

1. `[find vlan-ids=$vid and dynamic=no]` in `/interface/bridge/vlan` silently matched nothing
   even though a matching static row existed — the following `/get` on the empty result threw
   "no such item." Same `[find prop1=X and prop2=Y]` unreliability already documented for
   `/ip/firewall/filter`, now confirmed in a second menu. Fixed by filtering on `vlan-ids=`
   alone and excluding dynamic rows in script logic (`:foreach` + `/get ... dynamic`) instead of
   combining both into the `find` query.
2. The MikroTik-wiki `:local f do={ :local x $1 ... }` / `[$f "arg"]` pseudo-function idiom
   didn't bind `$1` when the `do={}` block was defined and invoked from inside another named
   `/system/script`'s own `source=`, run via `/system/script/run` — `$1` came back empty with no
   error (`:error "...vlan-ids=" . $vid` printed as `...vlan-ids=` with nothing after the `=`).
   Root cause not identified. Fixed by dropping the function abstraction and duplicating the
   per-VLAN logic inline in both `mikrotik2-add-mikrotik5-uplink.rsc` and (pre-emptively, not
   yet re-run) `mikrotik5-build.rsc`.

The `homeassistant` account password and the admin SSH public key were filled in and applied
directly on the device; the placeholders in `scripts/mikrotik5-build.rsc` were cleared back out
afterward rather than committed.

**mikrotik1/3/4's own `mgmt`-list entries for mikrotik5 — run and confirmed by Guillaume
directly, 2026-10-08** (`scripts/mikrotik1-add-mikrotik5-mgmt.rsc`,
`scripts/mikrotik3-add-mikrotik5-mgmt.rsc`, `scripts/mikrotik4-add-mikrotik5-mgmt.rsc`).
**SSH key access to mikrotik5 confirmed working** by Guillaume the same day, closing the one
item from mikrotik5's own build that hadn't been directly verified yet.

**mikrotik5's full config build is now done and verified on every device involved** (mikrotik1,
2, 3, 4, and 5 itself). All five one-shot scripts for this build have been run, verified, and
deleted per this repo's scripts/ convention — this entry is the durable record.

**Physically relocated and connected, 2026-10-08.** Guillaume moved mikrotik5 to the living
room and connected it to mikrotik2's `ether12-slave-local`; the TV is plugged into `ether2`.

**TV connectivity verified via `/ip/dhcp-server/lease/print` on mikrotik1.** Both of the TV's
MACs picked up fresh `vlan-users` leases within minutes of the physical move:
`F4:DD:06:2A:FB:AF` at `.10.195` and `4C:57:39:2C:20:2C` at `.10.104` (both dynamic, `dhcp-home`,
hostname `Samsung`). Confirms the new wired link works end-to-end through the trunk chain
(mikrotik5 -> mikrotik2 -> mikrotik1).

**Static reservations added, then the MAC/interface pairing had to be corrected.** Asked to
reserve `.10.50` for "the TV" and `.10.51` for "the TV wifi," assumed `F4:DD:06:2A:FB:AF`
(the MAC `vlan.md` had always documented as "the TV's," from before this session) was the new
*wired* connection, since it was the one that showed up with the shortest `last-seen` right
after the physical move. **That assumption was wrong** — `vlan.md` had already documented that
exact MAC as the TV's *wireless* interface, from before any of this session's work; the short
`last-seen` was just its existing wifi link renewing, not evidence of anything new. The
genuinely new MAC was `4C:57:39:2C:20:2C`. Guillaume caught this by checking the TV's own
network settings directly (wifi showed `.50`, wired showed `.51` — the opposite of what was
configured). Fixed by removing both static leases and re-adding with the MACs swapped:
`.10.50` -> `4C:57:39:2C:20:2C` (wired), `.10.51` -> `F4:DD:06:2A:FB:AF` (wifi). Lesson: don't
infer "which interface is new" from DHCP lease recency alone — check what the device's own
MAC was already documented as, and when in doubt, check the device's own network settings
directly rather than inferring from timestamps.

**Found along the way, not yet reconciled:** the Onkyo amp's documented static reservation at
`.10.104` (`vlan.md`'s device inventory, MAC `00:09:B0...`) doesn't actually exist — no static
(non-dynamic) lease for that MAC appears anywhere in a 2026-10-08 `/ip/dhcp-server/lease/print`,
and `.10.104` was instead being held, dynamically, by the TV's wifi MAC at the time. Not
investigated further this session; `vlan.md` now flags the amp's address as stale rather than
restating it as fact.

## mikrotik5-mikrotik2 trunk capped at 100Mbps instead of Gigabit — accepted, not pursued further (2026-10-08)

Found while verifying the living-room move: `/interface/ethernet/monitor` on both ends showed
`rate: 100Mbps` on a link where both ports are Gigabit-capable hardware (CRS125's
`ether12-slave-local`, hEX's `ether1`) and both are configured to advertise it
(`/interface/ethernet/print detail` on mikrotik5 confirmed `advertise=` already included
`1G-baseT-half,1G-baseT-full`).

**Ruled out, in order:**
1. **Config mismatch** — both ends' configured `advertise=` already include Gigabit. Not the
   cause.
2. **Stale negotiation state from a soft bounce** — wrapped the risky management-path change
   in a `/system/script` (same technique as mikrotik3's S15 and this build's own address
   change, since a plain two-line `disable`/`enable` paste would drop the SSH session before
   the second line ever sent): `/interface/ethernet/disable ether1`, `:delay 3s`,
   `/interface/ethernet/enable ether1`. No change — `ether1`'s live `advertising:` list still
   excluded Gigabit afterward.
3. **A genuine physical unplug** (not just software admin-down, which doesn't necessarily drop
   the PHY link signal) — Guillaume disconnected the cable for 10 seconds and replugged it. No
   change either.

**Not root-caused.** One data point worth keeping: mikrotik5's `link-partner-advertising` (what
it sees mikrotik2 sending) correctly includes Gigabit both times, after the soft bounce and
after the real unplug — so mikrotik2's side of the wire is getting a clean Gigabit-capability
signal through. mikrotik5's own resolved `advertising:` list never does, despite its configured
value being correct throughout. Two live hypotheses, not distinguished: the patch-panel run
itself (a termination with only 2 good pairs would explain base link-pulse signaling getting
through fine while the full 4-pair 1000BASE-T handshake silently fails and falls back) or a
hardware/PHY issue specific to this mikrotik5 unit's `ether1`. The decisive test would be
plugging any other Gigabit-capable device into the same living-room wall jack and checking what
speed *it* negotiates — not done.

**Guillaume's call: not worth pursuing.** The TV/Nintendo Switch/amp don't need more than
100Mbps. Documented as an accepted limitation in `vlan.md`'s "Living room and workshop" section,
`config-review.md`, and `README.md`'s device table, rather than left as an open finding that
implies someone should still chase it.
