# Wireless — current state, the garden AP, and what to fix

Opened 2026-09-05.

## Fixed 2026-09-05: both APs were on the same channel

**Baseline, recorded before the fix** — from `/interface/wireless/print detail` on
mikrotik1 and mikrotik2, 2026-09-05. Keep these numbers; they are what any later comparison
is measured against.

```
mikrotik1  wlan1  E4:8D:8C:19:6F:3B   channel: 2452/20-Ce/gn(16dBm)  SSID: LEDCOM
mikrotik2  wlan1  4C:5E:0C:91:51:99   channel: 2452/20-Ce/gn(16dBm)  SSID: LEDCOM
```

Identical. Both radios sit on **2452 MHz — channel 9 — at 40 MHz width**, in the same part
of the house. This is not a subtle misconfiguration; it is two access points deliberately
sharing one channel.

Two APs on the same channel do not add capacity. They share airtime through carrier sense:
each one defers while the other transmits, so a client on either AP waits for both. Two APs
on the same channel are, at best, one AP with two antennas in different rooms — and at worst
worse than one, because clients near the midpoint hear both and retry constantly.

The cause is that the CAPsMAN configuration specifies no channel at all:

```
/caps-man configuration
0  name="caps_config" ssid="LEDCOM" guard-interval=long country=switzerland
   security.authentication-types=wpa2-psk datapath.bridge=bridge-main
```

No `channel=` property, and no `/caps-man channel` entries exist. Both radios were left to
pick for themselves and both picked the same thing.

**40 MHz width on 2.4 GHz makes it worse.** The 2.4 GHz band has room for three
non-overlapping 20 MHz channels (1, 6, 11). A 40 MHz channel consumes most of the usable
band, so it collides with the other AP *and* with every neighbouring network. On 2.4 GHz,
40 MHz is almost always a net loss — it roughly doubles theoretical rate while multiplying
collisions.

**Supporting evidence.** `/interface/print detail` on mikrotik1 shows `cap3` (mikrotik2's
radio) with `link-downs=45`, against `link-downs=0` for `cap2`. That radio has been
flapping. And the registration table shows several clients at -79 dBm, which is poor:

```
cap2  A8:48:FA:F2:40:4D  -61      cap3  F4:DD:06:2A:FB:AF  -65
cap2  D8:BC:38:99:44:68  -79      cap3  EA:84:28:98:BF:6A  -69
cap2  00:09:B0:B6:A9:69  -79      cap3  BC:CE:25:5E:7F:8A  -78
```

## There is no 5 GHz anywhere on this network

Both radios are `band=2ghz-b/g/n` on `Atheros AR9300` hardware. Every wireless client in the
house — phones, laptops, tablets — is sharing 2.4 GHz 802.11n, on one channel, with each
other and with every neighbour.

This is very likely the dominant cause of "WiFi tends to not be very good", ahead of AP
placement and well ahead of anything about the router.

## The cAP XL ac changes the plan

An unused **cAP XL ac** (`RBcAPGi-5acD2nD-XL`) is available. It is dual-band —
2.4 GHz 802.11n *and* 5 GHz 802.11ac — with high-gain antennas.

This supersedes the earlier suggestion in [config-review.md](config-review.md) to buy cAP ax
or hAP ax³ units. There is already a dual-band AC access point on the shelf, and deploying
it is free.

### The driver question, and the decision

RouterOS has two mutually incompatible wireless stacks:

| | Legacy | New |
|---|---|---|
| Package | `wireless` | `wifi-qcom` / `wifi-qcom-ac` |
| Config menu | `/interface/wireless` | `/interface/wifi` |
| Central manager | `/caps-man` | `/interface/wifi/capsman` |
| Chips | Atheros AR9xxx era | Qualcomm IPQ4019, IPQ807x |
| Architectures | all, including mipsbe | **ARM/ARM64 only** |

mikrotik1 runs the legacy stack (`/system/package/print` shows `wireless 7.24.2`; both
radios are `Atheros AR9300`). The cAP XL ac is IPQ-4018/4019 ARM hardware — the generation
MikroTik moved to the new driver. If it needs `wifi-qcom-ac`, **mikrotik1 cannot manage it**:
the package does not exist for mipsbe, so the RB2011 cannot run the new manager at all.

**Resolved for real 2026-10-06/07, the hard way: it needs `wifi-qcom-ac` after all.** First
attempt installed legacy `wireless` and it looked like a clean win — `/interface/wireless/print`
showed two live radios, `interface-type=IPQ4019`, both reporting `running-ap` with full VHT
rates on 5 GHz. That was false. Over several real-world tests (phone and desktop, close range,
different regulatory domains ruled out, a full reboot) **the 5 GHz radio never actually
transmitted anything** under `wireless` — RouterOS's own state reporting was simply wrong, not
lying maliciously, just not reflecting reality on this chip. Swapping to `wifi-qcom-ac` (the
table above was right the first time) fixed 5 GHz immediately, confirmed by a real client
associating at close range within seconds. The two packages can't coexist, so this device is now
fully on `wifi-qcom-ac`, both bands. See "Built 2026-10-06/07" below for the full account,
including why that also means standalone, not CAPsMAN — Branch B, not A.

**Decision 2026-09-05: target B3 — consolidate both managers onto the RB5009.**

Being precise about what that means, because it is easy to over-read: RouterOS does not merge
the two stacks. B3 puts `/caps-man` and `/interface/wifi/capsman` side by side **on one box**.
Two configuration systems, one place to log in — a real simplification over running them on
separate devices, but not a single configuration.

The reason to aim there anyway is what comes after. If the two 2.4-GHz-only APs are eventually
replaced with ax units, everything moves to the new stack, legacy `/caps-man` disappears, and
it becomes genuinely unified. B3 is the path that ends there; standalone or two-box
arrangements are detours that get unwound.

**Verify before committing to it:** the RB5009 must be able to install the legacy `wireless`
package alongside `wifi-qcom-ac`. Both should be available for arm64 — a radio-less router
running CAPsMAN for legacy CAPs is a documented MikroTik configuration — but MikroTik has been
steadily deprecating the legacy stack, so confirm the package exists for arm64 on the
RouterOS version in use before the purchase depends on it.

**Fallback if it does not:** the RB2011 keeps running `/caps-man` for the two legacy radios
after it is redeployed as a switch or CAPsMAN box, and the RB5009 runs the new manager. That
is B2 by another name, and it costs nothing extra since the RB2011 is being kept regardless.

### Interim, until the RB5009 exists

B3 is future-dated and does not deliver 5 GHz this week. The interim depends on the driver
check:

- **If the cAP runs `wireless`:** join it to the existing `/caps-man` on mikrotik1 now — add a
  5 GHz channel and a slave configuration, provision by radio MAC exactly as the 2.4 GHz
  channel split was done. When the RB5009 arrives it inherits the same CAPsMAN unchanged, and
  B3 costs nothing extra.
- **If the cAP needs `wifi-qcom-ac`:** configure it standalone — SSID, PSK, channel set
  locally. This is a smaller compromise than it sounds: **CAPsMAN provides central
  configuration, not roaming.** Roaming is a client-side decision on signal strength, so three
  APs sharing an SSID, PSK and security settings roam identically with or without a manager.
  Convert it to managed when the RB5009 lands.

Either way 5 GHz is available as soon as the AP is mounted and powered. The driver answer
decides only whether it is centrally managed.

### Built 2026-10-06/07: this is now mikrotik4, standalone on `wifi-qcom-ac` (Branch B)

**This device is mikrotik4** — `192.168.10.4`. That address was always held by a static DHCP
reservation keyed to MAC `48:A9:8A:2E:10:0C`; this document previously, incorrectly, attributed
that reservation to the SXTsq (see the renamed section below). It's actually always been the cAP
XL ac's own `ether1` MAC. The reservation itself was correct and needed no change — only the
documentation describing it was wrong. The SXTsq still has no device number; its real MAC needs
checking against its own label before it gets one (see below).

**MACs, confirmed from the physical label and cross-checked against the board:** `ether1` = `...0C`,
`ether2` (unused, this board has two) = `...0D`, `wifi1`/2.4 GHz = `...0E`, `wifi2`/5 GHz = `...0F`.

**Getting here needed an unplanned recovery.** First boot (over its own default WiFi, HTTP
quick-set) triggered a RouterOS package/firmware update that left the device unable to fully
boot — solid, non-blinking power/user LEDs, no response to MNDP or MAC-Telnet despite a live
Ethernet link (confirmed via `/interface/bridge/host/print` on mikrotik1 — its MAC was learned
on `ether10` the whole time, so the link layer was fine; nothing above it was running). Recovered
via `netinstall-cli` (the Linux build, not the Windows GUI tool) over a direct point-to-point
Ethernet link, reflashing RouterOS `7.24.5` (arm) with an empty config. **Lesson for next time:**
if a MikroTik stops responding to every management protocol right after a firmware/package
update, while still showing a live link and solid (non-blinking) LEDs, suspect a bad flash before
anything else — Netinstall is the fix, not more config troubleshooting.

**First driver attempt (`wireless`, legacy) looked successful and wasn't.** After the reflash,
`/system/package/print` showed only `routeros` — no wireless driver, the empty-config netinstall
doesn't bundle one. Installed `wireless-7.24.5-arm.npk`, joined mikrotik1's `/caps-man` (full
CAPsMAN scaffolding built: new channels/configurations/provisioning rules, both bands reporting
`running-ap` with real VHT rates). It was all fake for 5 GHz: no client, on any device, at any
range, under any regulatory domain, ever actually associated to the 5 GHz radio — RouterOS's own
state reporting was simply wrong on this chip, not maliciously, just unreliable. This was only
caught because testing kept insisting on real end-to-end confirmation rather than trusting
`running-ap`. **Don't trust `current-state`/`running-ap` on this hardware without an actual
client association test — it can report success for a radio that never transmits anything.**

**Fix: `wifi-qcom-ac`, standalone — and that forces Branch B, not A.** Removed `wireless`,
installed `wifi-qcom-ac-7.24.5-arm.npk`, reconfigured `wifi1`/`wifi2` directly
(`configuration.mode=ap`, `configuration.ssid=LEDCOM`, `security.authentication-types=wpa2-psk-sha2`).
5 GHz worked immediately — a real client associated at close range within seconds, something that
had never once happened under `wireless` no matter how long it ran. Since the two wireless
packages can't coexist, and mikrotik1 only has legacy `/caps-man` (no `/interface/wifi/capsman`),
**this device cannot be CAPsMAN-managed at all until the RB5009 exists with the new-stack
manager** — exactly the Branch B fallback this document described months ago, now actually in
effect rather than theoretical. All the CAPsMAN scaffolding built for Branch A was torn back out
of mikrotik1 once this became clear.

**Needed fixing along the way, all confirmed live, all worth remembering:**
- Bridge/VLAN work needs the ports *and* interfaces to already exist before referencing them in
  a `/interface/bridge/vlan` entry — creating the VLAN entry first, interfaces second, errors out.
- A bridge-vlan `find` can match more than one row for the same `vlan-ids` (a real static entry
  plus rows RouterOS auto-manages dynamically, e.g. "added by pvid") — `/get`/`/set` against the
  unfiltered result fails ("invalid internal item number" / "can not change dynamic"). Filter on
  `dynamic=no` explicitly.
- `current-tagged`/`current-untagged` reflect the *live* list; `tagged`/`untagged` are what's
  *configured* and can carry stale, unparseable leftover references (shown as `*NN`) that break
  a naive read-modify-write round trip. Rebuild from `current-*`, not the configured property.
- A property read via `/get` can come back as a native array, not a string — concatenating it
  with `.` silently broadcasts the string onto every element instead of joining them, producing
  garbage. Join arrays by hand with an explicit loop; never trust `.` between a string and
  something that might not be one.
- The **bridge interface itself** has its own `pvid`, separate from any port's `pvid` — it
  governs VLAN tagging for the bridge's *own* locally-bound traffic (e.g. a management address
  bound directly to `bridge`). Leaving it at the default while every port is correctly configured
  is enough on its own to break reachability.
- A scheduled job that removes itself from inside its own `on-event` can still fire a second time
  — don't assume "fires once" for a self-deleting scheduler/script pair; make the on-event body
  itself idempotent/harmless to re-run, don't rely on the removal being instantaneous.
- `/interface/bridge/host`'s real VLAN-related property is `vid`, not `vlan-id` — and it comes
  back empty for ordinary wireless client traffic regardless of VLAN, so it's not a useful signal
  for this kind of diagnosis at all. When bridge-table introspection gives ambiguous answers,
  go straight to a wire-level capture (`/tool/sniffer`) instead of guessing at more properties.

**`LEDCOM-IoT` cannot be VLAN-isolated on this device — confirmed, not a configuration gap.**
Wanted: a second SSID on each band, tagged onto `iot` (VLAN 30), matching every other AP on this
network. Tried, in order, all confirmed by packet capture on `ether1` (not just by trusting
RouterOS's own reporting, given the lesson above):
1. **Bridge port `pvid=30`** on the virtual multi-SSID interface (`wifi1-iot`/`wifi2-iot`,
   `master-interface=wifi1`/`wifi2`) — silently had no effect. Traffic left `ether1` completely
   untagged, identical to plain `LEDCOM`/VLAN 10 traffic.
2. **`datapath.vlan-id=30`** (the correct mechanism in principle — it's exactly what CAPsMAN's
   own `caps_iot` slave configuration uses) — RouterOS rejected it outright: `;;; vlan-id
   configured, but interface does not support assigning vlans`, and worse, it then **actively
   disconnected any client that tried to associate** (`;;; client was disconnected because could
   not assign vlan`) rather than just ignoring the unsupported setting.
3. **MikroTik's own published workaround for exactly this chip/package** (hardware switch-chip
   VLAN table entry on `switch1`, `ingress-filtering=no` on the bridge and `ether1`,
   `vlan-mode=fallback` on the switch ports) — applied in full, including a reboot (switch-chip
   VLAN config is a category that often needs one to take effect). Zero change: traffic was still
   leaving `ether1` untagged, confirmed by a fresh packet capture after the reboot.

With every documented mechanism exhausted, decided 2026-10-07: **`LEDCOM-IoT` is not offered on
mikrotik4 at all.** Both virtual interfaces and their now-dangling bridge-port entries, the
VLAN 30 bridge-vlan entry, and the switch1 VLAN entry were all removed. mikrotik4 now serves
`LEDCOM` only, on both bands, landing correctly on `vlan-users`. IoT wifi coverage in this AP's
area still comes from mikrotik1/mikrotik2's radios, which remain properly isolated — this gap
is specific to mikrotik4's hardware/driver combination, not a network-wide regression.
`ingress-filtering=no` and `vlan-mode=fallback` were deliberately left in place rather than
reverted — they're harmless now and reverting them risks re-triggering the wireless-settling
disruption below for no benefit.

**One real, repeatable side effect of touching `vlan-filtering` on this bridge** (confirmed
across several reprovisions tonight, same shape as the already-documented CAPsMAN-side version
of this in `README.md`'s hard-won lessons): every port, including the wifi interfaces, briefly
drops to `I`/inactive and the wifi interfaces lose their `R`/running flag, settling back on their
own within a minute or so. Expected, not a fault — but worth a real wait-and-recheck rather than
assuming either success or failure immediately after.

**SSH key auth added for `admin`**, to make the rest of this kind of session less painful —
`/user/ssh-keys/import` from a key copied over via SCP. Password auth left enabled as a fallback,
not yet disabled.

**Still open:**
- Baseline hardening to match every other device — `mgmt` address-list plus the separate
  `admin` user `address=` restriction, ftp/telnet/www-ssl disabled, `ha` account, broader SSH
  hardening beyond the key, proven MAC-Telnet recovery path. Not yet done; `config-review.md`'s
  "mikrotik4 has never been reviewed" section has the full checklist.
- RouterOS package version drifted from the rest of the fleet during recovery (`7.24.5` vs the
  fleet's `7.24.2`) — not urgent, just a known inconsistency.
- `wifi1`'s bridge port has shown `I`/inactive in the most recent check — likely still settling
  per the note above, but worth a fresh look rather than assuming.

## Recommended order of work

1. ~~**Channel plan first.**~~ **Done 2026-09-05**, see below.
2. **Deploy the cAP XL ac**, once the driver question is settled. 5 GHz is the real fix for
   indoor performance.
3. **Re-site the existing APs.** Two APs in the same area is the wrong shape regardless of
   channel; they want to be far apart.
4. **Then** judge whether more hardware is needed. It may not be.

### The channel plan — applied 2026-09-05

Three 2.4 GHz radios once mikrotik4 joins, and exactly three non-overlapping channels, so
the assignment wrote itself. Width dropped to 20 MHz at the same time.

```
/caps-man/channel/add name=ch1  band=2ghz-g/n frequency=2412 extension-channel=disabled
/caps-man/channel/add name=ch6  band=2ghz-g/n frequency=2437 extension-channel=disabled
/caps-man/channel/add name=ch11 band=2ghz-g/n frequency=2462 extension-channel=disabled

/caps-man/configuration/set [find name=caps_config] channel=ch1
/caps-man/configuration/add name=caps_ch11 ssid=LEDCOM country=switzerland \
    guard-interval=long channel=ch11 \
    security.authentication-types=wpa2-psk security.passphrase="<LEDCOM passphrase>" \
    datapath.bridge=bridge-main

/caps-man/provisioning/add action=create-dynamic-enabled radio-mac=4C:5E:0C:91:51:99 \
    master-configuration=caps_ch11 place-before=0
/caps-man/interface/remove [find name=cap1]
/caps-man/remote-cap/provision [find]
```

`extension-channel=disabled` is what drops 40 MHz to 20 MHz. `ch6` is unused, reserved for
mikrotik4. mikrotik1's radio falls through to the original catch-all rule, which now carries
`channel=ch1`.

`cap1` was a static CAPsMAN interface with `radio-mac=00:00:00:00:00:00`, not running, left
from an earlier setup. A zero radio-mac is a wildcard slot that can capture the next CAP to
connect — it would have caught mikrotik4.

**Verified** — `/caps-man/interface/print detail`, both radios bound, running, serving
clients:

```
MDBR  cap6  E4:8D:8C:19:6F:3B  caps_config  "2412/20/gn(20dBm)"  4 clients
MDBR  cap7  4C:5E:0C:91:51:99  caps_ch11    "2462/20/gn(20dBm)"  1 client
```

Same SSID on both, which is what lets clients roam between them.

#### Two things went wrong, both worth remembering

**A CAPsMAN configuration with `wpa2-psk` and no passphrase fails silently.** The first
`add` lost its `security.passphrase` line to a mangled paste. The AP came up
(`current-state="running-ap"`) and reported its correct channel, but no client could
associate: `cap5` sat at `current-registered-clients=0` and lacked the `R` flag while the
other radio had four clients. Nothing in `/caps-man/configuration/print detail` reveals it —
**the passphrase is hidden there**, so a config with no passphrase looks identical to a
correct one. The tell is on the interface, not the configuration: no `R` flag and no
clients. Fixed with `/caps-man/configuration/set [find name=caps_ch11]
security.passphrase="..."`.

**An interrupted `add` leaves a live rule.** A first attempt without
`master-configuration=` created a third provisioning rule with
`master-configuration=*FFFFFFFF` — matching mikrotik2's radio but pointing at no
configuration. Inert only because the correct rule sorted ahead of it; had that rule ever
been deleted, mikrotik2 would have been provisioned with nothing. Removed. Check
`/caps-man/provisioning/print` after any edit and confirm the rule count is what you expect.

#### Side effect: TX power rose from 16 to 20 dBm

The channel objects specify no `tx-power`, so both radios defaulted to the maximum for
`country=switzerland` — previously they ran at 16 dBm.

Not obviously an improvement. For two APs this close together, more power enlarges both
cells and widens the overlap region, and it makes clients cling to a distant AP they can
hear but cannot answer at equal strength. Deliberately left alone for now: changing it in
the same step would make the channel result unreadable. Revisit after judging the channel
change on its own, with `/caps-man/channel/set [find] tx-power=16` if wanted.

#### What to watch

Judge this after a day, not ten minutes. Clients hold an association well past the point
where another AP would serve them better, and some need their WiFi toggled once.

Two clients are still weak — `D8:BC:38:99:44:68` at -81 dBm and `F6:42:66:E4:55:03` at
-82 dBm, both on `cap6`. Both are stationary, so they will not roam on their own. If they
stay poor, they are candidates for the placement question below rather than for more
channel tuning.

Client distribution landed at 4 on `cap6` and 1 on `cap7`, which is lopsided but not by
itself a problem — clients choose, and these had all reassociated seconds earlier.

## Powering the cAP XL ac

**Superseded 2026-10-06: final location is mikrotik1's `ether10`, not mikrotik3.** The
2026-09-05 reasoning below (mikrotik3 via injector; `ether10` is "the wrong end of the house")
no longer holds — confirmed with Guillaume that `ether10` is this AP's real, final location,
not a bench/test setup. It already has what it needs: `poe-out=auto-on`, and it's the same port
used throughout the 2026-10-06 build (see above).

**Known trade-off, parked until the RB5009 swap, 2026-10-07: the link runs at 100M, not
1G, and that's a real hardware ceiling, not a bug.** `/interface/ethernet/monitor ether10 once`
on mikrotik1 shows its `supported` list tops out at `100M-baseT-full` — no gigabit at all,
despite the `advertise=` property (configuration, not capability) listing it. This matches the
RB2011UiAS-2HnD's documented hardware split across its two switch groups: the high-numbered
ports, `ether10` among them, are Fast Ethernet only. mikrotik4's own `ether1` is genuinely
gigabit-capable (`supported` includes both `1G-baseT-half`/`full`) — the cap is entirely on
mikrotik1's side. Since `ether10` is also mikrotik1's PoE-out port (the whole reason it was
picked), there's a real trade-off here, not just a missing config: getting mikrotik4 onto a
genuinely Gigabit port on mikrotik1 would mean giving up `ether10`'s built-in PoE-out and adding
a separate injector instead. Practical impact: irrelevant for 2.4 GHz (802.11n tops out well
under 100 Mbps anyway), real for 5 GHz 802.11ac (`wifi2` can theoretically exceed 100 Mbps, up to
~867 Mbps PHY for 2-stream 80 MHz) — this uplink caps real-world 5 GHz throughput for anything
connecting to this AP. **Decided 2026-10-07: leave as-is, revisit when the RB5009 replaces
mikrotik1** — that swap is the natural point to re-evaluate port/PoE assignment for this link
rather than re-cabling mikrotik1 now for a router that's about to be replaced anyway.

**Resolved, same day, once the order was corrected:** the original edge-role recommendation
(`RB5009UG+S+IN`, see `config-review.md`) missed that mikrotik4 needs PoE from whatever runs
the edge role — fixed by ordering `RB5009UPr+S+IN` instead, the PoE-out variant. Every port on
it is Gigabit, so this trade-off disappears entirely once it arrives: mikrotik4 gets both PoE
and full Gigabit from the same cable, no injector needed. Nothing to re-cable on mikrotik1 in
the meantime; this was already a "wait for the swap" item.

Kept below for history, since it no longer applies to the cAP: the original plan was to power
it from mikrotik3 via a passive PoE injector, on the reasoning that placement should be decided
by coverage, not by which port happens to have power. **That reasoning still applies to the
SXTsq** (garden AP, device number not yet assigned) — it's the one still planned to go through
mikrotik3 via injector, in the office location, eventually. The now-dropped office PoE switch
requirement in [config-review.md](config-review.md) was about this same injector need.

### Where to mount it: ceiling, not wall

The `cAP` name is literal — ceiling AP. Its internal antennas are omnidirectional, which
means a toroidal pattern with nulls along the antenna axis. Mounted flat against a ceiling,
the null points up and down and the strong lobe spreads horizontally across the floor below,
which is the intended geometry.

Wall-mounting rotates that pattern ninety degrees. The null then points horizontally, out
into the room you are trying to cover, while the strong lobe spreads up, down and sideways
along the wall — into the ceiling, the floor, and the neighbour's side of the wall.
Reflections fill in some of the loss, so it is not catastrophic, but it wastes a good AP.

The **XL** variant makes this more pronounced, not less: higher-gain omni antennas flatten
the donut further, trading vertical reach for horizontal. Better across one floor, worse
between floors.

Practical placement:

- **Ceiling, as central as possible**, on the floor where the wireless is used most. Not a
  corner, not a cupboard, not the office if the office is at one end of the house.
- **5 GHz penetrates walls and floors noticeably worse than 2.4 GHz.** Placement matters more
  for this AP than for the two existing ones, and a badly-sited AC access point will
  underperform a well-sited N one.
- Avoid metal: ducts, foil-backed insulation, metal junction boxes, water pipes, large
  mirrors.
- For two floors, the ceiling of the lower floor near a stairwell is usually the best single
  compromise — the stairwell is the one path with no floor slab in it.
- If a wall mount is unavoidable, mount high, near the ceiling. Acceptable, measurably worse.

## SXTsq Lite2 as the garden AP — device number not yet assigned

`RBSXTsq2nD`. 2.4 GHz 802.11b/g/n, integrated **directional** panel antenna, single 10/100
Ethernet port, PoE-in only, QCA9531 MIPSBE, 64 MB RAM. To be plugged into mikrotik3 and
aimed at the garden.

**This device is not mikrotik4.** Everything below originally called it that and gave it the
`.4` reservation and MAC `48:A9:8A:2E:10:0C` — both wrong. That MAC and address belong to the
cAP XL ac (see above; confirmed from its physical label 2026-10-06). This section's build
procedure was never actually run, so nothing on-device needs correcting, but the plan below
does: **check the SXTsq's own label for its real MAC before building it**, don't reuse anything
recorded here, and it'll need its own fresh device number and reservation (likely mikrotik5,
next in sequence) once that's done. The `192.168.1.x` addressing throughout this section also
predates the VLAN migration — translate to `192.168.10.x` (`users`) when actually building this.

Four things worth knowing before mounting it:

**mikrotik3 has no PoE-out.** It is an RB750Gr3 (plain hEX) — `/interface/ethernet/print
detail` shows no PoE properties on any port. The SXT needs the passive PoE injector that
ships with it, inline between mikrotik3 and the SXT. This is a physical prerequisite, not a
configuration step.

**The antenna is directional.** Unlike the two indoor APs, this covers a cone, not a sphere.
Aim it at the garden and accept that it contributes nothing indoors. That is the right shape
for the stated goal, but it is not a general-purpose third AP.

**It is a third 2.4 GHz radio** joining two that already collide. Do the channel plan above
at the same time, or this makes the indoor situation measurably worse while improving the
garden.

**Same architecture as the manager.** Both the RB2011 and the SXTsq2nD are mipsbe, and the
manager runs `upgrade-policy=suggest-same-version` with an empty `package-path`, so CAPsMAN
will offer its own 7.24.2 packages to the CAP automatically once it joins. No manual upgrade
path needed unless it arrives on something older than 6.44, which cannot jump straight to 7.

The 10/100 port is not a constraint: a 2.4 GHz 802.11n radio tops out well below 100 Mbps in
practice.

### Build procedure

Reset into CAP mode, which produces exactly the intended starting shape — all ethernet
bridged, wireless handed to CAPsMAN, DHCP client for management:

```
/system/reset-configuration caps-mode=yes skip-backup=yes
```

If it is unreachable, hold the reset button through boot instead, then use MAC-Telnet.

It will come up on a DHCP lease on `vlan-users` — check `/ip/dhcp-server/lease/print` on
mikrotik1 for its actual address once connected; **don't reuse `.4` or
`mac-address=48:A9:8A:2E:10:0C`**, both belong to the cAP XL ac (mikrotik4, see above). Then
apply the same baseline every other device now has — static address, locked-down input chain,
services off, HA account — plus the explicit CAP configuration.

Build the `mgmt` list **before** the input rules. That ordering caused a lockout on the main
router once already.

```
/ip/firewall/address-list/add address=192.168.1.90 list=mgmt comment=desktop
/ip/firewall/address-list/add address=192.168.1.1  list=mgmt comment=mikrotik1
/ip/firewall/address-list/add address=192.168.1.2  list=mgmt comment=mikrotik2
/ip/firewall/address-list/add address=192.168.1.3  list=mgmt comment=mikrotik3
/ip/firewall/address-list/add address=192.168.1.4  list=mgmt comment=mikrotik4
/ip/firewall/address-list/print where list=mgmt

/ip/firewall/filter/add chain=input action=accept connection-state=established,related comment=established
/ip/firewall/filter/add chain=input action=drop   connection-state=invalid comment="drop invalid"
/ip/firewall/filter/add chain=input action=accept protocol=icmp comment=ICMP
/ip/firewall/filter/add chain=input action=accept src-address-list=mgmt comment="mgmt hosts to device"
/ip/firewall/filter/add chain=input action=accept protocol=tcp src-address=192.168.1.60 \
    dst-port=8728 comment="HA API access"
/ip/firewall/filter/add chain=input action=drop comment="drop everything else"
```

Services, accounts and SSH, matching the other three:

```
/ip/service/disable ftp,telnet,reverse-proxy,api-ssl,www-ssl
/ip/dns/set allow-remote-requests=no servers=192.168.1.40
/user/set admin address=192.168.1.0/24
/user/group/add name=ha policy=read,test,api
/user/add name=homeassistant group=ha address=192.168.1.60 password=<same as the others>
/ip/ssh/set strong-crypto=yes host-key-size=4096 password-authentication=yes
/ip/ssh/regenerate-host-key
```

Keep MAC-Telnet reachable — this is the lesson from S16, where mikrotik3's uplink port sat
in the `WAN` list and silently had no recovery path:

```
/tool/mac-server/set allowed-interface-list=all
/tool/mac-server/mac-winbox/set allowed-interface-list=all
/ip/neighbor/discovery-settings/set discover-interface-list=all
```

Point it at CAPsMAN explicitly rather than relying on discovery, mirroring mikrotik2:

```
/interface/wireless/cap/set enabled=yes interfaces=wlan1 discovery-interfaces=bridge \
    bridge=bridge caps-man-addresses=192.168.1.1
/interface/wireless/cap/print
```

Finally convert to a static address, as a script so the session drop does not abort it —
the same technique that worked for mikrotik3:

```
/system/script/add name=make-static source={
    /ip/dhcp-client/disable [find];
    /ip/address/add address=192.168.1.4/24 interface=bridge comment="static management";
    /ip/route/add dst-address=0.0.0.0/0 gateway=192.168.1.1 comment="static default";
}
/system/script/run make-static
```

### Verification

From mikrotik1:

```
/caps-man/remote-cap/print              # mikrotik4 present
/caps-man/registration-table/print      # clients appearing on its interface
/ip/neighbor/print                      # discoverable, so MAC-Telnet works
```

On mikrotik4 after a reboot, to prove persistence rather than current state:

```
/ip/address/print       # 192.168.1.4/24, no D flag
/ip/route/print         # As, not DAd
/ip/dhcp-client/print   # X
/system/script/remove make-static
```

And the negative test from Pi-hole (`192.168.1.40`, outside `mgmt`), which is what actually
proves the firewall rather than merely showing it exists:

```
timeout 5 nc -zv 192.168.1.4 22    # expect exit 124
timeout 5 nc -zv 192.168.1.4 8291  # expect exit 124
```
