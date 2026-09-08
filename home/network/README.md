# Home MikroTik network

Working notes for a home network built on MikroTik hardware behind a Swisscom Internet-Box.
Written so that work can resume from these documents alone, with no session history.

## Start here

**Active work: [vlan.md](vlan.md) — VLAN segmentation, in progress.** Phases 0-2 are done and
closed to [changelog.md](changelog.md) — the LAN is renumbered onto `192.168.10.0/24` and every
device runs `vlan-filtering=yes`. Resume with **Phase 3**: creating the `services`/`iot` VLANs
and migrating devices onto them one at a time. Read `vlan.md`'s **Status** section first — it
carries forward the most expensive lesson from Phases 1-2 (config that references a device by
literal IP hides in more places than it looks, and several of those places broke silently).

## The network as it stands

| Device | Model | Address | Role |
|---|---|---|---|
| mikrotik1 | RB2011UiAS-2HnD | `192.168.10.1` | edge router, CAPsMAN manager, NAT44 + NAT66 |
| mikrotik2 | CRS125-24G-1S-2HnD | `192.168.10.2` | L2 switch, 24×GE + SFP, CAPsMAN CAP |
| mikrotik3 | RB750Gr3 (hEX) | `192.168.10.3` | L2 switch, office, 5×GE |
| mikrotik4 | SXTsq Lite2 | `192.168.10.4` (reserved) | offline; to become the garden AP |

All on RouterOS 7.24.2. One `192.168.10.0/24` segment for now (VLAN 10, `users`) — `services`
and `iot` VLANs are Phase 3, not yet created. Upstream is a Swisscom Internet-Box at
`10.1.1.1` doing a second layer of NAT.

Raw device output lives in [dumps/](dumps/), collected with
[dump-configs.sh](scripts/dump-configs.sh). Regenerate it before any review — the files are a
snapshot, not a source of truth.

## Documents

| File | What it holds |
|---|---|
| [vlan.md](vlan.md) | **Active, Phase 3 next.** VLAN design, device inventory, address plan, six-phase migration (0-2 done) |
| [wifi.md](wifi.md) | Wireless: the channel fix already applied, the 5 GHz plan, mikrotik4 build |
| [config-review.md](config-review.md) | Open findings and the hardware/architecture decisions |
| [changelog.md](changelog.md) | Every closed finding, with the output that verified it |
| [network.md](network.md) | The two diagrams and how to regenerate them |
| [performance.md](performance.md) | Throughput investigation — the MikroTik is not the cause |
| [qos.md](qos.md) | Closed by measurement: there is no bufferbloat to fix |
| [ipv6.md](ipv6.md) | IPv6 via DHCPv6-PD and the NAT66 workaround |

Diagrams: [network.svg](network.svg) is physical topology (Graphviz),
[network-addressing.svg](network-addressing.svg) is the address plan (nwdiag). Sources are
`network.dot` and `network-addressing.nwdiag`; render with `dot` and
[render-nwdiag.py](scripts/render-nwdiag.py) respectively.

## Everything currently open

**VLAN work** — [vlan.md](vlan.md). Phases 0-2 done (renumbered onto `192.168.10.0/24`,
`vlan-filtering=yes` everywhere, wireless CAPsMAN tagging fixed). Phase 3 next: create
`services`/`iot` VLANs, migrate Pi-hole/HA/printer/IoT devices one at a time. Two small open
items, neither blocking: the printer hasn't had an actual test print since the renumber, and
the "second laptop" from the device inventory is still unidentified. The kitchen light and the
TV's identity — both previously unconfirmed — are resolved (kitchen light's dead, reservation
deleted; the TV was actually misidentified, corrected in `vlan.md`).

**Rogue IPv6 router advertisement** — [config-review.md](config-review.md). Identified 2026-09-07
as Home Assistant's OpenThread Border Router (Thread/Matter mesh), working as designed — not a
bug, nothing to fix. Held open rather than closed pending a few more days of confirmed
stability, per that document's own note.

**Wireless** — [wifi.md](wifi.md).
- The cAP XL ac is unused and is the only 5 GHz on the network. Blocked on one question:
  which driver it needs (`/system/package/print`, and whether `/interface/wifi` or
  `/interface/wireless` exists). Decided target is **B3** — both CAPsMAN managers on the
  RB5009 when it arrives; standalone in the interim if it needs `wifi-qcom-ac`.
- mikrotik4 (SXTsq Lite2) build procedure is written but not executed. Needs a PoE injector.
- Both existing APs are 2.4 GHz only. TX power rose 16 -> 20 dBm as a side effect of the
  channel fix; deliberately not adjusted yet.

**Main router** — [config-review.md](config-review.md).
- Finding 8: DNS can bypass Pi-hole. Folded into the VLAN work.
- mikrotik4 has never been reviewed. It needs the full S1-S16 pass when it returns.

**Hardware, pending the replacement Swisscom box.**
- RB5009UG+S+IN for the edge role. Check the new box's port speeds and whether it supports
  bridge mode when it arrives.
- Office PoE switch — must do **passive** PoE (the SXTsq needs it) and must not energise
  ports serving laptops. Candidate: CRS112-8P-4S-IN.
- Living room and workshop both need switches. Moving mikrotik3 to the living room covers one.

**Backup internet (future idea, not yet designed).** Noted 2026-09-08: use a phone in
access-point/tethering mode as a failover WAN on mikrotik1 if the Swisscom line goes down.
Likely shape — a second `/ip/dhcp-client` on whatever interface reaches the phone's hotspot
(wireless, or wired if tethered by USB/cable), plus `/tool/netwatch` or check-gateway-based
distance/route metrics so mikrotik1 prefers the primary WAN and only fails over when it's
actually down. Not scoped further than this — revisit before starting.

**Throughput** — [performance.md](performance.md). Download runs at roughly 30% of upload
(169.6 vs 565.3 Mbps, measured back-to-back) and is not caused by the MikroTik. The
outstanding test is a host plugged directly into the Internet-Box.

## Conventions

- A finding leaves a review document only when it is fixed **and** verified against device
  output — never when it is reported done. Closed items move to
  [changelog.md](changelog.md) with the evidence.
- Finding numbers are stable and never reused. `<n>` for the main router, `S<n>` for switches.
- Assumptions that have not been verified are labelled as such rather than stated as fact.
- **Every change to any MikroTik, in any session, gets logged to
  [changelog.md](changelog.md) as it happens** — not batched at the end, and not skipped for
  changes that feel small or exploratory. RouterOS's own logs cannot tell one Claude session
  apart from another (both show up as the same `admin@<ip>/terminal` client), so
  `changelog.md` is the only record that survives a session boundary. A change made and not
  logged here is effectively invisible to whichever session has to debug the next problem.
- **One-shot `.rsc` scripts in [scripts/](scripts/) are deleted once run and verified** —
  `changelog.md`'s entry (commands, output, verification) is the durable record, not the file.
  A filename referenced from `changelog.md` or `vlan.md` may therefore no longer exist on disk;
  that's expected, not a broken link to chase down. Keep only genuinely reusable tools
  (`dump-configs.sh`, `fetch-backups.sh`, `measure-bufferbloat.sh`, `render-nwdiag.py` as of
  this writing) — anything written for a single migration step gets cleaned up after.

## Hard-won lessons

- **Safe mode discards everything if the session drops.** It silently lost work twice here.
  For changes that cannot affect the management path, run them directly and verify
  immediately. For changes that can, use a scheduled auto-rollback instead — the pattern is
  in [vlan.md](vlan.md).
- **`set [find ...]` against an empty result is a silent no-op**, indistinguishable from
  success. Always re-print after a `set`.
- **Build the `mgmt` address list before the rule that references it.** Doing it the other
  way round caused a full lockout, recovered only via MAC-Telnet from another MikroTik.
- **MAC-Telnet is the recovery path, but verify it works before you need it.** mikrotik3 had
  no working out-of-band access for months because its uplink port sat in the `WAN` interface
  list, which excluded it from discovery and MAC-server.
- **A long pasted command can silently truncate with no error.** Over SSH, a long single line
  (or a `\`-continued one) can get wrapped and re-submitted as fragments by the terminal, and
  RouterOS happily accepts whatever fragment parsed as a complete command — seen here as a
  25-port VLAN membership list silently cut to 8, with no error at all. For anything with a
  long argument list, build it from several short `:global` lines instead (`:local` does not
  persist between separately-typed prompt lines — see `changelog.md`'s VLAN segmentation
  entry), and always `print detail` afterward to count what actually landed rather than
  trusting a clean exit.
- **`/interface/bridge/port/set [find bridge=X]` fails outright if the match includes a
  dynamic port** (e.g. a CAPsMAN `ap-*` interface) — "can not change dynamic port" — and
  aborts before processing the rest of the batch, silently skipping every port after the
  dynamic one in ID order. Filter with `dynamic=no`.
- **`print where` on an interface-name field is not trustworthy.** `/ip/firewall/filter/print
  where in-interface=bridge-main` came back completely empty on mikrotik1 when the unfiltered
  `print` showed two rules that plainly said `in-interface=bridge-main`. Cause unconfirmed —
  don't spend time debugging the query syntax, just don't use `print where` for anything
  where a false "no matches" would matter. Use an unfiltered `print` and read it yourself.
- **Moving a device's own management IP off a VLAN-filtered bridge needs a real `/interface
  vlan` sub-interface, not just VLAN-table membership.** A plain bridge interface (address
  bound directly to `bridge`/`bridge-main`/`bridge-local`) has no way to associate an incoming
  802.1Q-tagged frame with its IP stack. `tagged=bridge` in the VLAN table is necessary but
  not sufficient without the paired `/interface/vlan` object holding the address — confirmed
  by two live outages on mikrotik3 before finding this in MikroTik's own documentation (their
  manual site was unreachable until the sandbox proxy allowlist was updated and the session
  restarted — worth doing early if a live network problem needs primary-source verification).
  See `changelog.md`'s VLAN segmentation entry for the full working pattern and why the
  address move, DHCP server rebind, and `vlan-filtering=yes` have to land atomically.
- **Flipping `vlan-filtering` on a bridge disrupts wireless clients on any CAPsMAN AP whose
  dynamic port lives on that bridge**, not just the data plane after association. Every port,
  including the dynamic `ap-*` ports, bounces through a `detect LAN` → `detect SLAVE` cycle the
  instant filtering toggles. Confirmed by mikrotik1's log: a Hombli device got stuck
  reassociating every 20-40s for 20+ minutes, and a Samsung TV hit a `reassociating` event that
  never completed and needed a manual reconnect later. Settled on its own within ~30 minutes.
  Warn people in the house before any `vlan-filtering=yes`/`=no` change, not just before
  changes to the wireless config itself.
- **`[find prop1=X and prop2=Y]` can silently match nothing, even when each condition alone
  works.** `/ip/firewall/filter/remove [find comment="..." and src-address=...]` ran with no
  error and removed nothing, on three separate devices identically. Dropping the redundant
  second condition (the comment alone was already unique) fixed it immediately. Prefer the
  single most-specific condition over combining several with `and`, and always `print` after
  a `remove`/`set` to confirm — this is now the fourth distinct `find`/`print where`
  reliability surprise in this file alone.
- **When renumbering a device, "grep the config for its literal old IP" beats "remember which
  rules reference it."** Hit three times in one renumber: a user account's own `address=`
  restriction (separate from any firewall rule) locked out both router management and Home
  Assistant's API; a NAT rule's `to-addresses=` and its *paired* forward-chain accept rule
  turned out to be two separate things to update, not one, and missing the second one produced
  a silent drop (a timeout, no error) rather than an obvious failure; and a forward-chain `drop`
  rule blocking a specific IoT device by IP silently stopped enforcing once that device's own
  address changed — a renumber can quietly *remove* a security restriction, not just break
  connectivity. In each case the actual list of references was longer than what was remembered
  going in. See `changelog.md`'s VLAN segmentation entry for the full account.
- **A pure L2 switch whose only IP is a management address needs its own default route the
  moment a management client can be on a different subnet than that address** — not just
  correct bridge/VLAN forwarding. mikrotik2 and mikrotik3 had only their directly-connected
  route; every prior management connection to them had come from within their own subnet, so
  the gap stayed invisible until Home Assistant's VLAN migration made it the first cross-subnet
  client. The failure is silent: the switch accepts the incoming SYN (confirmed live in the
  firewall counters) but has no route to send the reply, so the TCP handshake never completes
  and **nothing at all gets logged** — not even a failed-login line. That absence of any log
  entry, on a service that *does* clearly log both successes and failures otherwise (see next
  point), is itself the tell that this is a routing problem, not a credentials or firewall one.
- **RouterOS logs a failed API/web/ssh login clearly, but not under the `account` topic** —
  it's `system,error,critical login failure for user X from Y via api`, filed under
  `error,critical`. Filtering `/log/print` by `topics~"account"` (which does catch successful
  logins) will show nothing for failures and can wrongly suggest a connection never arrived at
  all.
- **Firewall rule packet/byte counters are cumulative since the rule's creation and are not
  reset by a `/set` that changes its match criteria.** A nonzero counter on a rule that existed
  before you retargeted it (e.g. changing `src-address=`) proves nothing about whether *current*
  traffic matches — it may be entirely leftover from the old criteria. `reset-counters` before
  a retry is the only way to get a clean signal.
- **RouterOS's `I - INVALID` flag on a forward-chain rule (silently unenforced, no error) has
  more than one trigger, still not fully characterized — treat it as "always print and check
  after any rule with multiple matchers," not as a single fixable rule.** Confirmed triggers so
  far, found across the printer/Pi-hole/HA/ceiling-fan work:
  - An `accept` rule missing `connection-state=new`.
  - An `accept` *or* `drop` rule combining `src-address=`/`dst-address=`/`dst-port=`/`port=`
    with only *one* of `in-interface=`/`out-interface=` — needs both together, or neither.
  - An `accept` *or* `drop` rule combining **both** `src-address=` and `dst-address=` together
    with *no* interface matcher at all — also needs both interfaces added, even though a rule
    with only one of the two addresses and no interface is fine.
  - **Also important: RouterOS does not evaluate/show `I - INVALID` on a `disabled=yes` rule.**
    The ceiling fan's DNS-drop rules were created disabled, looked clean, and only revealed the
    flag once enabled for real — so a disabled rule's cleanliness proves nothing about whether
    it'll be valid once turned on. Enable and re-check, don't just trust the print from while
    it was off.
  - **Checked on `chain=input`, 2026-09-08: no `I` flag** on an `input` rule combining
    `in-interface=` with `dst-port=` and `connection-state=new` (`iot: NTP from gateway`) —
    the interface-completeness half of this seems specific to `chain=forward`, consistent with
    `chain=input` having no `out-interface=` concept to be incomplete about.
  - **A completely different trigger, found applying Phase 4, 2026-09-08: reusing a cached
    `find` result across multiple sequential `/add` operations in the same script.** A script
    that did `:local catchall [/ip/.../find where comment=...]` once, then referenced
    `place-before=$catchall` across nine separate `/add` calls, produced `I - INVALID` on the
    *last* of those nine — a rule structurally identical (drop, both interfaces, no
    address/port matcher, no `connection-state`) to an earlier one in the same batch that was
    valid. Removing and re-adding the same rule with a freshly-evaluated
    `place-before=[/ip/.../find where comment=...]` (not a cached variable) fixed it
    immediately, with no other change. **Always re-evaluate `find` fresh at each `/add`, even
    within a single script — don't cache and reuse a `place-before=`/`place-after=` target
    across multiple inserts.**
