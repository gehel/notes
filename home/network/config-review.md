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
| mikrotik4 | RBcAPGi-5acD2nD (cAP XL ac) | `192.168.10.4/24` | Standalone `wifi-qcom-ac`, dual-band, not CAPsMAN-managed — built 2026-10-06/07, see `wifi.md`; not yet reviewed (see below) |
| mikrotik5 | RB750Gr3 (hEX), same as mikrotik3 | `192.168.10.5/24` static on `bridge` | L2 bridge, 5 ports — living-room switch, built and hardened 2026-10-08, in place and connected to mikrotik2's `ether12-slave-local` the same day, see `vlan.md` |

All three reachable devices run RouterOS 7.24.2, current as of 2026-09-08 (RouterBOOT current
on mikrotik1 too — re-checked this round). `bridge-fon` (`192.168.2.0/24`) no longer exists —
removed in Phase 0 of the VLAN work.

**Open findings only.** A finding leaves this document once it has been fixed **and**
verified against device output — never when it is reported done. Closed items move to
[changelog.md](changelog.md) with the output that verified them, so they are not re-raised.

Numbering is stable and never reused. Main-router findings are numbered `<n>`, switch
findings `S<n>`, so the two sets never collide.

## Open findings

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

### 25. No mechanism updates `home.ledcom.fr`'s DNS record when the public IP changes (medium, reported fixed 2026-09-22 — not yet verified/documented in full)

**Guillaume reports (2026-09-22):** the Let's Encrypt add-on's Gandi integration does update
this record, and was already configured — the record had gone stale because the API key it
uses had expired; renewed the same day, and DNS resolution is now confirmed correct externally.
This directly contradicts the "ruled out, not confirmed working" conclusion below from
2026-09-11 (that investigation found the add-on's Gandi token only used for DNS-01 ACME
domain-ownership proof, never for updating the A record) — not yet reconciled. Leaving this
finding open, and the section below as originally written, until the actual mechanism is
confirmed and documented properly; don't treat this as closed in the meantime.

Found 2026-09-11, during the Internet-Box replacement (see `changelog.md`). The record is a
plain A record at Gandi, manually maintained — nothing watches for the ISP-assigned public IP
changing and updates it. The box swap changed the public IP *twice* in one day (once from the
new box's own DHCP lease, confirmed via `/ip/cloud/print` at the time, and again later to
`178.192.223.49`), and both times `home.ledcom.fr` silently kept pointing at a stale address
until manually corrected. Not caught sooner because nothing alerts on this — external HTTPS to
Home Assistant just times out, indistinguishable at first glance from a NAT/firewall problem
(and this file's own investigation initially chased exactly that before finding the real
cause).

**A plausible mechanism was ruled out, not confirmed working.** Home Assistant runs the Let's
Encrypt add-on with the Gandi DNS-01 plugin (`dns-gandi`) — this uses the same Gandi API and
domain, but only to prove domain ownership for certificate renewal, never to update the A
record's IP. Its log (`Using Gandi personal access token` → cert type detected → "not yet due
for renewal") confirms the credential itself works fine; it was never a candidate for the DDNS
job in the first place, a misconception this finding also corrects.

**Options discussed, not yet decided:**
- Point `home.ledcom.fr` at mikrotik1's already-working MikroTik Cloud DDNS hostname
  (`<serial>.sn.mynetname.net`) via a CNAME at Gandi — no new credentials or scripts, but
  `/ip/cloud`'s `ddns-update-interval: none` means it may not refresh promptly on a mid-session
  IP change; `/ip/cloud force-update` could be scheduled periodically to close that gap.
- A mikrotik1 script calling Gandi's LiveDNS API directly via `/tool/fetch` on a schedule —
  keeps a plain A record, more moving parts, a Gandi API key to manage on the router.

### 28. Home Assistant losing connection-tracking state on a long-lived outbound connection to a Vultr-hosted host (144.202.82.88) (informational, needs more data)

Found 2026-09-13 reviewing `logs/mikrotik1-main.txt`. 11 packets from Home Assistant
(`192.168.20.60`), all sourced from local port 443 (not an ephemeral client port) toward
`144.202.82.88:61234`, hit `services2internet`'s catch-all and were dropped — in four episodes
roughly 2-2.5h apart on 2026-09-13 (02:05, 04:39, 07:14, 09:16). None of them are `SYN`s (all
`ACK`/`ACK,PSH`, i.e. carrying data), which means the underlying connection was already
established, not being attempted fresh — this looks like RouterOS's connection tracking aging
out an idle long-lived session and then dropping its genuine continuation traffic, rather than
Home Assistant actually initiating anything new. `144.202.0.0/16` is a Vultr range; a plausible
candidate given the source port and persistence is Nabu Casa's remote-access relay. Not enough
information yet to act on: worth checking Home Assistant's own Nabu Casa/cloud-connectivity log
for disconnects around those four timestamps, and, if this keeps recurring, mikrotik1's
`/ip/firewall/connection/tracking` timeouts for the relevant protocol.

**Recurred 2026-09-14** (10:42:11, 10:42:46, both `ACK`, same shape) — consistent with the
original description, no new information.

**Recurred repeatedly 2026-09-15/16** — same shape (`src-port=443`, `ACK`, `connection-state:new`,
always 640 bytes), now against three destinations: `144.202.82.88:61234` six more times
(03:53, 03:53, 03:54, 09:29, 09:29, 11:49, 11:50 — note some pairs only ~25-45s apart, tighter
than the original 2-2.5h spacing), plus two new ones in a `216.180.246.x` range —
`216.180.246.56:21707` (2026-09-15 18:18) and `216.180.246.54:21801` (2026-09-16 20:02, twice,
43s apart). The new IPs support the working theory: a small pool of front-end addresses (Vultr
range for one, a second /24-ish range for the others) is consistent with a relay service like
Nabu Casa rotating endpoints, not a single fixed remote host. Still not enough to act on
directly — the connection-tracking-timeout theory remains unconfirmed (RouterOS's default TCP
established timeout is generous, on the order of a day, which sits oddly with drops recurring
within tens of seconds to a few hours) — but the volume of evidence now makes it worth actually
checking Home Assistant's own Nabu Casa/cloud connectivity log for disconnect/reconnect events
at these exact timestamps, rather than continuing to only observe it from the firewall side.

**Recurred again, 2026-09-18/19/20** (from `logs/mikrotik1-main.txt`, collected 2026-09-22 —
same shape throughout, `src-port=443`, `ACK`/`ACK,PSH`, `connection-state:new`, 640 bytes):
`144.202.82.88:61234` five more times (2026-09-18 01:00:48, 01:01:16, 01:02:09, 03:40:56,
03:41:25) and three more times 2026-09-20 (19:24:24, 19:24:46, 19:25:29); three more
`216.180.246.x` destinations — `216.180.246.31:21050` (2026-09-18 18:15:47, 18:16:07,
18:16:48), `216.180.246.176:21764` (2026-09-19 19:37:52, 19:38:16), `216.180.246.179:21824`
(2026-09-20 18:16:58, 18:17:08, 18:17:29, 18:18:10). Same rotating-front-end pattern within the
`216.180.246.0/24` range, now five distinct addresses in it across three recurrences. This has
now recurred in every single log collection since 2026-09-13 (five separate windows) with no
exception — **this is no longer a "maybe" pattern, it's a standing one.** The one
recommended-but-not-yet-done action from the original write-up is still outstanding: check Home
Assistant's own Nabu Casa/cloud-connectivity log for disconnect/reconnect events at the
timestamps above. This session has no access to Home Assistant to do that directly — needs
doing from a session/device that does.

### 33. Samsung TV → Home Assistant return traffic occasionally not recognized as established (informational, needs more data)

Found 2026-09-22 reviewing `logs/mikrotik1-main.txt` (collected same day). Six packets from
the Samsung TV (`192.168.10.195`, MAC `F4:DD:06:2A:FB:AF`) — all `192.168.10.195:8002 ->
192.168.20.60:57906`, `ACK,PSH` (carrying real payload, 1500 bytes — near-MTU, not a bare ACK),
`connection-state:new` — hit `users2services`'s catch-all and were dropped, all within 6
seconds (2026-09-21 23:59:16 through 23:59:22).

Same shape as finding 28: established-looking traffic (not a `SYN`) logged as `new` and
dropped, on a path that should already be tracked. `services2users` rule 65 accepts exactly the
forward direction of this (`HA -> Samsung TV, dst-port 8002`) — port 8002 as the *source* here,
toward Home Assistant's own high ephemeral port, is consistent with this being the TV's side of
that same integration's traffic, not a new connection attempt. If conntrack isn't recognizing
this as part of the already-accepted flow, `users2services` (which only allows `mgmt`/DNS/HA-web)
has no reason to let it through — correctly enforcing the policy as written, but possibly
breaking the HA/Samsung TV integration if this repeats and Home Assistant needed that return
traffic. One episode so far, not enough to diagnose the cause (conntrack timeout, NAT/asymmetric
path, or something in how the TV re-uses port 8002 as both a server and client port). Worth
checking Home Assistant's own Samsung TV integration log for errors/retries around 23:59:16 on
2026-09-21, and watching whether this recurs in future log collections the way finding 28 did.


Nothing is open on mikrotik1, mikrotik2, mikrotik3, mikrotik4, or mikrotik5 as of 2026-10-08 —
mikrotik4's full baseline-hardening pass (firewall, `admin`/`mgmt` access control, services,
`ha` account, SSH hardening, DNS, NTP, IPv6 disabled) closed 2026-10-07, see `changelog.md`'s
2026-10-07 entries; mikrotik5's build included the same baseline hardening from the start and
closed 2026-10-08, see `changelog.md`'s "mikrotik5 build" entry. mikrotik2/mikrotik3 reviewed
against the same fresh dump set and confirmed to still match the established baseline. **IPv6
is explicitly disabled on all four non-edge devices** (`disable-ipv6=yes`) — confirmed as the
deliberate, wanted state: switches and standalone APs on this network don't need it.

**Two minor things noticed 2026-09-10 while regenerating `firewall.md` against a fresh
dump, not investigated further — neither looked urgent enough to chase down mid-pass:**
`cpu-load: 100%` in that snapshot (vs. the ~30-50% this document has previously measured under
real load) — most likely just the dump script's own burst of SSH commands rather than a
sustained condition, but worth a second look if it recurs on a quieter dump. And `route_BFD`
reappearing in `/ip/service/print` as a dynamic listener — **explained and closed, see
`changelog.md`'s 2026-10-07 entry**: BFD was genuinely configured and enabled, left over from
defconf, not a dump-collection artifact; now disabled.

## The architectural item: VLAN segmentation

See [vlan.md](vlan.md) for the design, decisions and migration plan, and
[changelog.md](changelog.md) for the full history. What follows is future hardware work the
VLAN migration didn't need and hasn't touched.

### Hardware for the edge role

**Recommendation (2026-09-04): RB5009UG+S+IN. Corrected 2026-10-07: ordered
RB5009UPr+S+IN instead — the PoE-out variant.** The original recommendation missed that
mikrotik4 needs PoE from whatever occupies the edge role (it's currently powered from
mikrotik1's `ether10`, which is also the box's only PoE-out port). `UPr` adds PoE-out across
its ports (its own power budget, not relying on an injector) without changing anything else
below — same CPU, same port count/speed, same passive cooling. This also cleanly resolves the
100M-link trade-off already recorded in `wifi.md`: mikrotik4 was stuck choosing between
mikrotik1's one Fast-Ethernet-only PoE port or a genuinely Gigabit port with no PoE. Every
`RB5009UPr+S+IN` port is Gigabit, so once it lands, mikrotik4 can get both PoE and full
Gigabit from the same cable, no separate injector needed.

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

**Two-box plan confirmed over consolidation (2026-09-22).** Considered replacing mikrotik1 and
mikrotik2 (currently co-located, both provide 2.4 GHz wifi) with a single ~16-port router+switch
box, on the reasoning that mikrotik2 only has 8 of its 24 ports actually in use. No clean
MikroTik SKU was found for this: high port count with a real switch chip (CRS family) and real
routing CPU with wifi (nothing above the low-port "hAP" tier) don't show up together: the
closest fit for port count plus a 10G-capable SFP+, something like a CCR2004-16G-2S+, is the
same CCR2004 class already rejected above for fan noise, and still has no onboard wifi either
way. mikrotik2 (CRS125) is already owned and already does the job wanted of it (real hardware
VLAN offload) — the two-box plan needs no additional switch purchase, consolidation would need
a new switch-capable router *and* a new home (or retirement) for CRS125. Guillaume's call:
stay with the two-box plan below. Wifi for either box's onboard radios is unaffected by this —
already covered by target B3 in `wifi.md` (RB5009 as CAPsMAN manager only, cAP XL ac as the
actual radio) regardless of how many boxes carry the router/switch role.

A future 10G-capable SFP+ for a possible direct-fiber-into-the-router setup, if the Swisscom
handoff is ever fibre, is already satisfied by the RB5009's SFP+ cage (reasoning point 3 above)
— no additional requirement.

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

### Office switch: PoE requirements — dropped, no purchase needed

Recorded 2026-09-05, **dropped 2026-10-06**. mikrotik3 (RB750Gr3) has no PoE-out, and both
planned access points — the cAP XL ac and the SXTsq Lite2 — hang off it. The original plan was
to replace mikrotik3 with a PoE-capable switch so injectors wouldn't be needed. Guillaume has a
PoE injector that covers the SXTsq from the office, so the injector-in-the-interim case is now
just the permanent case — no replacement switch is needed here, and mikrotik3 stays in the
office unchanged. This also means mikrotik3 does **not** free up to move to the living room
(see the living room switch item below, and `vlan.md`'s "Living room and workshop" section).

Requirements record kept for reference, in case this is revisited (e.g. if a second PoE device
shows up in the office):

1. **Passive PoE-out, not only 802.3af/at.** The SXTsq Lite2 is passive-only, 10-30 V, with
   no 802.3af/at support. A switch that negotiates 802.3at and nothing else will not power
   it, which defeats the purpose. This rules out the otherwise attractive CSS610-8P-2S+IN.
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

Candidate that was under consideration: CRS112-8P-4S-IN (8×GE with PoE-out on every port,
4×SFP, own PSU, fanless, RouterOS, passive as well as 802.3af/at). No longer needed.

### Living room switch

Recorded 2026-10-06. TV, Nintendo Switch and amplifier are all wireless today and all live on
`users` (see `vlan.md`) — no VLAN-awareness or PoE strictly needed, just a handful of wired
ports to get them off wifi. Port count: uplink + 3 devices + a spare = 5.

**Recommendation: a second RB750Gr3 (hEX)** — same model as mikrotik3, full RouterOS, exactly
the port count needed. Keeps the fleet uniform (one management model, one set of known
quirks/lessons already documented in `README.md`) rather than introducing CSS610-8G-2S+IN,
which was the earlier candidate for this role but runs **SwOS**, not RouterOS — a different,
lighter management model (web/WinBox-lite only, no scripting, no CAPsMAN) than everything else
on this network. The SFP+ headroom CSS610 offers isn't needed for three gigabit media devices.

**Received 2026-10-07, built and fully configured 2026-10-08, moved to the living room and
connected the same day.** Assigned mikrotik5, `192.168.10.5`, uplink confirmed and live as
mikrotik2 `ether12-slave-local`. Despite the "no VLAN-awareness needed" framing above,
Guillaume's call was to build it VLAN-aware anyway (trunk uplink tagged 20/30, matching
mikrotik3) for fleet consistency and to avoid re-cabling later if a services/iot device ever
lands on the spare port — see `vlan.md`'s "Living room and workshop" section for the full
breakdown and `changelog.md`'s "mikrotik5 build" entry for the build account, including two
real RouterOS scripting bugs found and fixed along the way. Config build (mikrotik1-5, all
verified) is done. TV is plugged into `ether2`, not yet confirmed from a real client; Nintendo
Switch and amp aren't connected yet.

### Probably a bigger constraint than the router: the wireless

Both APs are **2.4 GHz 802.11n only**, there is no 5 GHz anywhere on this network, and as of
2026-09-05 both radios were found sitting on the **same channel** (2452, 40 MHz). That is
very likely a larger day-to-day limitation than anything about the router.

A cAP XL ac is already available and unused, which supersedes the earlier suggestion here to
buy cAP ax or hAP ax³ units.

Full analysis, the channel plan, the cAP XL ac build (now mikrotik4), and the still-unbuilt
garden AP (SXTsq Lite2, no device number assigned yet) are all in [wifi.md](wifi.md).

### Replacement Swisscom box — arrived and installed 2026-09-11

Ordered 2026-09-04, 10G-capable per spec. Of the three things flagged to check when it
arrived:

- **Port speeds it actually offers.** Not yet directly confirmed. Doesn't matter yet either
  way: mikrotik1 (RB2011, GigE ports) still caps WAN throughput near 1 Gbps regardless of what
  the box offers, until the RB5009 edge migration below actually happens. Re-baseline
  throughput (`scripts/measure-bufferbloat.sh`, see `performance.md`) once that's done, not
  before.
- **Whether it supports bridge or modem mode — no.** Checked directly in the box's admin UI.
  mikrotik1 is configured as its DMZ host instead (full port-forwarding to one LAN device),
  which is why the edge migration below still needs its own WAN-facing DHCP client rather than
  inheriting a public IP directly.
- **Whether it can forward port 80 inward.** Not yet directly tested, but plausible now: DMZ
  hosting forwards every port to mikrotik1, port 80 included. Worth testing explicitly before
  revisiting the TLS question below — DMZ and "forwards port 80 specifically" aren't quite the
  same claim.

The swap itself broke two things — a hardcoded WAN IP in the HA HTTPS NAT rule, and the
IPv6 delegation needing to be re-established with the box's PD setting explicitly enabled and
mikrotik1's DHCPv6 client force-released — both found and fixed the same day; full account in
`changelog.md`.

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
