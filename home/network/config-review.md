# Config review — home MikroTik network

Covers every MikroTik on the network. Round 1 reviewed 2026-09-03, round 2 from 2026-09-04,
re-verified 2026-09-05 against [dumps/](dumps/), collected with
[dump-configs.sh](scripts/dump-configs.sh). **Round 3: 2026-09-08**, against fresh dumps taken
after Phase 4's firewall policy went live — the post-migration pass this document had flagged as
still needed. **Addresses below updated 2026-09-07** after the
VLAN segmentation renumber (Phases 0-2, see [vlan.md](vlan.md) / [changelog.md](changelog.md)) —
everything else in this document is a historical record from the original review dates and
intentionally still shows the addresses as they were *at the time each finding was made*.

The live firewall ruleset itself — every chain, in order, on all three devices — is documented
separately in [firewall.md](firewall.md), regenerated 2026-09-10 after Phase 5's jump-chain
reorg (see [changelog.md](changelog.md)) — a dump refresh, not a new full review round.

| Device | Model | Address | Role |
|---|---|---|---|
| mikrotik1 | RB2011UiAS-2HnD — 128 MB, 600 MHz single-core MIPS | `192.168.10.1/24`; `ether1` dynamic from the Internet-Box | edge router, CAPsMAN manager |
| mikrotik2 | CRS125-24G-1S-2HnD | `192.168.10.2/24` static on `bridge-local` | L2 bridge, 24 ports + SFP; CAPsMAN CAP (wlan1) |
| mikrotik3 | RB750Gr3 (hEX) — 256 MB, 880 MHz quad-core | `192.168.10.3/24` static on `bridge` | L2 bridge, 5 ports |
| mikrotik4 | — | `192.168.10.4` reserved, offline | being returned to service |

All three reachable devices run RouterOS 7.24.2, current as of 2026-09-08 (RouterBOOT current
on mikrotik1 too — re-checked this round). `bridge-fon` (`192.168.2.0/24`) no longer exists —
removed in Phase 0 of the VLAN work.

**Open findings only.** A finding leaves this document once it has been fixed **and**
verified against device output — never when it is reported done. Closed items move to
[changelog.md](changelog.md) with the output that verified them, so they are not re-raised.

Numbering is stable and never reused. Main-router findings are numbered `<n>`, switch
findings `S<n>`, so the two sets never collide.

## Open findings

### 21. IPv6 firewall was never extended to `vlan-services`/`vlan-iot` (low)

Found 2026-09-08. [ipv6.md](ipv6.md)'s "Migrated onto `vlan-users`" work moved the router's own
IPv6 address, RA and firewall rules from `bridge-main` onto `vlan-users` — but only `vlan-users`.
`/ipv6/firewall/filter/print` has an input and a forward accept for `vlan-users` and nothing at
all for `vlan-services` or `vlan-iot`, which both fall through to the chain's terminating drops
(the dead `bridge-main` twins of the `vlan-users` pair were cleaned up as part of finding 20's
debris removal, 2026-09-09).

**Not a security problem — it fails closed** — but it's an undocumented gap, not a decision: the
IPv4 policy explicitly grants `services -> internet: allow` (added deliberately during Pi-hole's
migration, [changelog.md](changelog.md)), while IPv6 silently gives `vlan-services` no internet
access at all. For `vlan-iot` the accidental result actually matches the intended "no internet of
any kind" policy — but for the wrong reason, and it would silently break the day someone adds a
real IPv6 rule to `vlan-iot` without realizing there was never a matching input accept either.

**2026-09-09: deliberately deferred, now unblocked (2026-09-10).** Guillaume wants full IPv6
for `vlan-services`/`vlan-iot` (addressing + RA + the IPv6 equivalent of the existing IPv4
policy matrix), not the minimal "add two accept rules" fix originally sketched above — but
decided the IPv4 forward chain needed cleaning up and reorganizing first. That reorg (Phase 5's
jump-chain work, see [changelog.md](changelog.md)) is now fully done and documented, so this is
next up.

**In progress.** Phase 1 (`vlan-users`'s own IPv6 firewall restructured to the same
per-VLAN-pair dispatch shape as IPv4, closing an incidental gap where router management was
reachable from `vlan-users` over IPv6 with none of IPv4's `mgmt`-list scoping) and phase 2
(`vlan-services` addressing + a matching, narrower firewall) both done and verified 2026-09-10
— see [changelog.md](changelog.md). Phase 3 (`vlan-iot`) next; expected to be small, since most
IoT devices here don't speak IPv6 at all.


### 22. `chain=input` accepts are inconsistent about `connection-state=new` (informational)

Found 2026-09-08, the exact audit this document had planned to run. Every `chain=forward` accept
already declares `connection-state=new` consistently. On `chain=input`, only "iot: NTP from
gateway" does; the DHCP, `mgmt`, DNS and HA-API accepts don't. Not exploitable — `chain=input`
rule 1 (`accept established,related`) already intercepts non-new traffic before any of these are
reached — but worth tidying to the same standard as the forward chain, since the whole reason
this document tracks `connection-state=new` is that RouterOS's own `I - INVALID` behavior punishes
inconsistency here on other chains. Low priority; no known live impact.

**Home Assistant's MikroTik integration reports mikrotik2 as running RouterOS 7.23.3** (noted
2026-09-08, still true). Checked directly against this round's dump — mikrotik2 is actually
already on 7.24.2. Stale integration-side cached state, not a real gap; still worth investigating
why HA hasn't refreshed it, and whether the integration's upgrade-trigger feature actually works
(test on a device/moment where an unexpected reboot is low-risk).

### mikrotik4 has never been reviewed

`192.168.10.4` has been unreachable on port 22 on every dump run through 2026-09-08, so no
finding in this document or in the changelog says anything about its configuration.

When it returns to service it needs the full pass the switches got — input-chain firewall,
FTP/Telnet off, `admin` bound to the LAN, resolver closed, defconf debris cleared, static
address, SSH hardened, and a proven MAC-Telnet recovery path. It is already in the `mgmt`
address list on every device and holds a `.4` reservation on mikrotik1, so it will come up
reachable.

Nothing else is open. mikrotik2 and mikrotik3 are clear; mikrotik1 has findings 21-22 above
(19, 20, 23, 24 all closed — see [changelog.md](changelog.md)).

**Two minor things noticed 2026-09-10 while regenerating `firewall.md` against a fresh
dump, not investigated further — neither looked urgent enough to chase down mid-pass:**
`cpu-load: 100%` in that snapshot (vs. the ~30-50% this document has previously measured under
real load) — most likely just the dump script's own burst of SSH commands rather than a
sustained condition, but worth a second look if it recurs on a quieter dump. And `route_BFD`
reappearing in `/ip/service/print` as a dynamic listener, which the original finding 11 closure
(round 1) recorded as gone once OSPF/BGP/BFD config was removed — `dump-configs.sh` doesn't
currently collect `/routing/bfd/configuration/print`, so this couldn't be re-verified from the
dump alone; worth a live check next time (`/routing/bfd/configuration/print` should still be
empty) rather than assuming either way.

## The architectural item: VLAN segmentation

See [vlan.md](vlan.md) for the design, decisions and migration plan, and
[changelog.md](changelog.md) for the full history. What follows is future hardware work the
VLAN migration didn't need and hasn't touched.

### Hardware for the edge role

**Recommendation (2026-09-04): RB5009UG+S+IN.**

Quad-core ARM64 Cortex-A72 at 1.4 GHz, 1 GB RAM, 7x gigabit plus a 2.5G SFP+ cage,
passively cooled.

Reasoning, in the order the constraints actually bind:

1. **QoS is the binding constraint, not raw throughput.** Shaped traffic cannot be
   fasttracked (see [qos.md](qos.md)), so it must be forwarded in the CPU path. The RB2011
   already sits at 30-50% CPU for 111 Mbps *with* fasttrack. The RB5009 has headroom to run
   CAKE at gigabit without it. Nothing cheaper does.
2. **Silent.** Passive cooling. CCR2004-class hardware has fans, and this lives in a home.
3. **Right-sized uplink.** Measured reality is 842 Mbps up on gigabit ports; the whole LAN
   is gigabit and no known device has a faster NIC. 2.5G is 2.5x headroom over anything
   currently usable, and the SFP+ cage takes an ONT module if the handoff is fibre.
4. **Fixes IPv6 properly.** At the edge the full /56 is delegated directly, NAT66 disappears,
   and the measured ~25% IPv6 penalty goes with it.
5. **No onboard WiFi, correctly.** Wireless is CAPsMAN-managed from separate APs.

**Accepted limitation:** if the replacement Swisscom box delivers genuine 10 Gbps and more
than 2.5 Gbps is ever wanted, this caps it. That would mean CCR2004 class — roughly double
the price plus fan noise. Judged a good trade given current usage is under 1 Gbps.

### Redeployment: nothing is retired

| Device | New role |
|---|---|
| RB5009 (new) | edge router |
| CRS125-24G (mikrotik2) | main switch — real switch chip, hardware VLAN support, right device to carry tagged VLANs at line rate |
| RB2011UiAS (current main) | media switch by the TV, or CAPsMAN-only box |
| RB750Gr3 (mikrotik3) | office switch, unchanged |

This likely removes the need to buy the CSS610-8G-2S+IN suggested earlier for the media
segment — the RB2011 can fill that role.

### Physical wiring: patch panel and room runs

Recorded 2026-09-06, not yet acted on. mikrotik1 and mikrotik2 are co-located. A patch panel
routes the cable run to each room in the house, and every room currently lands on mikrotik2.
Rewiring at the patch panel is trivial — it is just re-terminating which room lands on which
switch port — so a room could be moved to land on mikrotik1 directly instead, removing one hop
(mikrotik2) for that room's traffic.

Worth revisiting once the edge role moves to the RB5009 and mikrotik2 becomes the main switch
(see redeployment table above) — the right answer depends on which device ends up carrying the
switch chip with hardware VLAN offload, not on which one happens to be reachable from the
patch panel today.

### Office switch: PoE requirements

Recorded 2026-09-05. mikrotik3 (RB750Gr3) has no PoE-out, and both planned access points —
the cAP XL ac and the SXTsq Lite2 — will hang off it. Injectors work in the interim; the
replacement should remove them.

Requirements, in order of how badly getting them wrong hurts:

1. **Passive PoE-out, not only 802.3af/at.** The SXTsq Lite2 is passive-only, 10-30 V, with
   no 802.3af/at support. A switch that negotiates 802.3at and nothing else will not power
   it, which defeats the purpose. This rules out the otherwise attractive CSS610-8P-2S+IN.
   **Verify against the SXTsq label before ordering** — the whole choice hangs on it.
2. **It must not put voltage on ports serving non-PoE devices.** A desktop and two laptops
   share this switch with two APs. Passive PoE energises the pairs unconditionally — there is
   no negotiation and no detection — so a laptop in a passive-PoE port can have its NIC
   damaged. PoE-out must be per-port controllable, set explicitly rather than left at a
   default, and the AP ports labelled physically:

   ```
   /interface/ethernet/poe/set [find] poe-out=off
   /interface/ethernet/poe/set [find name=etherX] poe-out=auto-on   # AP ports only
   /interface/ethernet/poe/print
   ```

3. **At least 8 ports.** Six are already spoken for — uplink to mikrotik2, desktop, two
   laptops, two APs. A switch with no spare ports acquires an unmanaged switch hanging off it
   within a year.

**Candidate: CRS112-8P-4S-IN** — 8×GE with PoE-out on every port, 4×SFP, own PSU, fanless,
RouterOS, and it supports passive as well as 802.3af/at. Cheaper alternative: hEX PoE
(RB960PGS), definitely passive, but only 5 copper ports, so the uplink would have to move to
SFP and there would be no spares.

Power draw is not a constraint either way: the SXTsq is around 4 W and the cAP maybe 7-11 W.

### Probably a bigger constraint than the router: the wireless

Both APs are **2.4 GHz 802.11n only**, there is no 5 GHz anywhere on this network, and as of
2026-09-05 both radios were found sitting on the **same channel** (2452, 40 MHz). That is
very likely a larger day-to-day limitation than anything about the router.

A cAP XL ac is already available and unused, which supersedes the earlier suggestion here to
buy cAP ax or hAP ax³ units.

Full analysis, the channel plan, and the mikrotik4 garden-AP build are in [wifi.md](wifi.md).

### Before ordering

A replacement Swisscom box was ordered 2026-09-04. Check three things when it arrives:

- **Port speeds it actually offers.** Determines whether 2.5G is a real constraint.
- **Whether it supports bridge or modem mode.** If it can bridge, the edge migration is much
  simpler.
- **Whether it can forward port 80 inward.** That is what RouterOS's built-in ACME needs for
  HTTP-01, and it is the only thing standing between the current state and Let's Encrypt
  certificates without an external host. See the TLS note below.

### The TLS question, deliberately parked

Guillaume prefers Let's Encrypt certificates over self-signed, and wants a solution the
router sustains on its own with no dependency on another host. RouterOS's built-in ACME
(`/certificate/enable-ssl-certificate`) supports **HTTP-01 only**, which needs port 80
reachable from the internet through the Internet-Box — the exposure closed in finding 5.
DNS-01 would avoid that but requires an external ACME client, which conflicts with the
self-contained requirement. `ledcom.fr` is at an EU registrar (Gandi/OVH class).

**Accepted in the meantime:** plaintext management traffic *within the LAN* is an accepted
risk. `www` on 80 stays enabled and in use, and the API on 8728 stays plaintext. Do not
re-raise either as a finding.

If the edge role moves to an RB5009 and the Internet-Box goes to bridge mode, HTTP-01
becomes available on the router itself and this unblocks without an external host — worth
revisiting then, not before.

## Closed findings

In [changelog.md](changelog.md), with the verifying output for each.
