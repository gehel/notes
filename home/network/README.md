# Home MikroTik network

Working notes for a home network built on MikroTik hardware behind a Swisscom Internet-Box.
Written so that work can resume from these documents alone, with no session history.

## Start here

**Active work: [vlan.md](vlan.md) — VLAN segmentation, Phases 0-5 done.** Three VLANs
(`users`/`services`/`iot`), full renumber, real firewall policy — all live. The forward chain
is reorganized into one jump-chain per VLAN pair, log-reviewed and tightened, with the old
rules fully cleaned up. **Finding 21 (IPv6 up to the same shape on every VLAN) closed
2026-09-11** — all three phases verified end-to-end from real clients; see `ipv6.md` and
`changelog.md`, including a real bug found along the way (IPv6 privacy extensions on
Pi-hole/OctoPrint silently broke the EUI-64 address pinning, fixed per-host). IotaWatt is back
online and verified the same day, and now has its own `iotawatt` internet exception for
firmware updates. Read `vlan.md`'s **Status** section first.

## The network as it stands

| Device | Model | Address | Role |
|---|---|---|---|
| mikrotik1 | RB2011UiAS-2HnD | `192.168.10.1` | edge router, CAPsMAN manager, NAT44 + NAT66 |
| mikrotik2 | CRS125-24G-1S-2HnD | `192.168.10.2` | L2 switch, 24×GE + SFP, CAPsMAN CAP |
| mikrotik3 | RB750Gr3 (hEX) | `192.168.10.3` | L2 switch, office, 5×GE |
| mikrotik4 | RBcAPGi-5acD2nD (cAP XL ac) | `192.168.10.4` | CAPsMAN CAP, dual-band — built 2026-10-06, see `wifi.md`; final location, powered from mikrotik1 `ether10`; baseline hardening (S17) closed 2026-10-07 |
| mikrotik5 | RB750Gr3 (hEX) | `192.168.10.5` | L2 switch, living room, 5×GE — built and hardened 2026-10-08, in place and connected to mikrotik2 the same day; TV wired to `ether2`. Uplink was capped at 100Mbps on the original patch cable, root-caused and confirmed fixable with a spare cable (full Gigabit) — permanent replacement still needed |

All on RouterOS 7.24.2. Three VLANs: `users` (`192.168.10.0/24`), `services`
(`192.168.20.0/24`), `iot` (`192.168.30.0/24`) — see [vlan.md](vlan.md) for the full design.
Upstream is a Swisscom Internet-Box at `10.1.1.1` doing a second layer of NAT.

**DNS and NTP are both fully self-contained as of 2026-09-10** — no LAN device should ever
need to reach the public internet for either. Pi-hole (`192.168.20.40`) is every device's
resolver; for anything it doesn't already know, it conditionally forwards to mikrotik1
(`192.168.0.0/16` → `192.168.10.1`), which in turn maintains a live DNS entry
(`<hostname>.home.ledcom.fr`, both directions — forward and reverse) for every currently-bound
DHCP lease via a `lease-script` on all three DHCP servers. NTP works the same way: mikrotik1
runs its own NTP server, `chain=input` accepts it from all three VLANs, and every device should
be pointed at its own VLAN's gateway address for time (DHCP option 42 provides this but isn't
reliably honored by every OS — see `README.md`'s hard-won lessons and `changelog.md`'s finding
23 closure for why explicit configuration beat relying on it, at least for Pi-hole).

Raw device output lives in [dumps/](dumps/), collected with
[dump-configs.sh](scripts/dump-configs.sh). Regenerate it before any review — the files are a
snapshot, not a source of truth.

Firewall log evidence — the `log=yes` deny-all rules at the end of every Phase 5 jump chain,
see [firewall.md](firewall.md) — lives in `logs/` (also gitignored), collected with
[dump-logs.sh](scripts/dump-logs.sh). RouterOS's own log buffer is small and rotates, so run
this regularly rather than only once something's already suspected.

Pi-hole's own on-disk logs (no API token configured, so this reads straight off disk via
rsync+sudo instead of the web UI's API) land in `logs/pihole/` (also gitignored), collected
with [dump-pihole-logs.sh](scripts/dump-pihole-logs.sh). `pihole.log` is the per-query
dnsmasq-style log (shows `from <client-ip>` on query lines); `FTL.log` is Pi-hole v6's own
consolidated log (matches the web UI's Diagnosis/Messages view) but doesn't show the
requesting client — check `pihole.log` when tracking down who's generating particular
queries.

## Documents

| File | What it holds |
|---|---|
| [vlan.md](vlan.md) | **Phases 0-5 done, finding 21 (IPv6) closed 2026-09-11.** VLAN design, device inventory, address plan, migration reference |
| [wifi.md](wifi.md) | Wireless: the channel fix already applied, the 5 GHz plan, mikrotik4 build |
| [config-review.md](config-review.md) | Open findings and the hardware/architecture decisions |
| [firewall.md](firewall.md) | Every live firewall rule, in evaluation order, on all three devices |
| [changelog.md](changelog.md) | Every closed finding, with the output that verified it |
| [network.md](network.md) | The two diagrams and how to regenerate them |
| [performance.md](performance.md) | Throughput investigation — the MikroTik is not the cause |
| [qos.md](qos.md) | Closed by measurement: there is no bufferbloat to fix |
| [ipv6.md](ipv6.md) | IPv6 via DHCPv6-PD and the NAT66 workaround |
| [vpn.md](vpn.md) | WireGuard road-warrior VPN for the Android phone — applied and verified 2026-09-22 |

Diagrams live in [diagrams/](diagrams/): [network.svg](diagrams/network.svg) is physical
topology (Graphviz), [network-addressing.svg](diagrams/network-addressing.svg) is the VLAN
address plan (nwdiag). Sources are `network.dot` and `network-addressing.nwdiag`; render with
`dot` and [render-nwdiag.py](diagrams/render-nwdiag.py) respectively — see
[network.md](network.md) for the exact commands.

## Everything currently open

**VLAN work** — [vlan.md](vlan.md). Phases 0-5 done, OctoPrint and IotaWatt both verified.
Finding 21 (IPv6 for every VLAN) closed 2026-09-11. The "second laptop" from
the device inventory is still
unidentified.

**Routine reviews, no urgency — good places to start a fresh session, not things that broke:**
- Re-run `dump-logs.sh` and read through the mikrotik firewall log for anything else worth
  tuning (silencing expected noise, like the ceiling fan 2026-09-11, or catching a real gap,
  like Pi-hole's IPv6 DNS the same day). Last full pass: **2026-09-22** — covered
  2026-09-17 through 2026-09-22, found three things: the finding-32 TCP/53-to-Pi-hole gap
  (already fixed and closed the same day, see `changelog.md`), finding 28's connection-tracking
  drop recurring for a third time (now in every log collection since 2026-09-13 — see
  `config-review.md`, still needs someone with Home Assistant access to check its Nabu Casa
  log), and a new one, finding 33: a short burst of Samsung-TV-to-Home-Assistant return traffic
  also dropped as `connection-state:new`, same shape as finding 28 but a different path —
  one episode so far, watch for recurrence.
- Review Pi-hole's own query log to confirm DNS is working well for every device generally —
  not chasing a specific known problem, just a health check. Not yet done as a general pass;
  `dump-pihole-logs.sh` now exists for pulling `pihole.log`/`FTL.log` offline for this. One
  specific thing already checked this way (2026-10-07): the `DNSMASQ_WARN` about hitting the
  150-concurrent-query cap for `168.192.in-addr.arpa` PTR lookups — traced to Home Assistant
  (`192.168.20.60`) doing a complete, sequential reverse-DNS sweep of its own `services`
  subnet every hour (confirmed from a full day's `pihole.log`; see `changelog.md` — a first,
  narrower sample pointed at the desktop instead and was wrong). Which HA-side mechanism
  causes the sweep isn't identified yet — see `home/home-assistant`'s finding 17.
- Whether Home Assistant has the same IPv6 privacy-extensions problem Pi-hole and OctoPrint had
  (finding 21's `ha-v6` address-list) — never checked either way, since no
  `services2users`-triggering traffic from HA has been observed in a log yet.

**Wireless** — [wifi.md](wifi.md).
- **The cAP XL ac is now mikrotik4, built 2026-10-06/07.** Driver question resolved for real
  this time: it needs `wifi-qcom-ac`, standalone — not legacy `wireless` (which looked like a
  working fix, reporting `running-ap` on 5 GHz with full VHT rates, but never actually
  transmitted anything; only caught by insisting on real client tests). Standalone means **not**
  CAPsMAN-managed — mikrotik1 only has legacy `/caps-man`, which can't manage a `wifi-qcom-ac`
  device, so this is Branch B, not A, until the RB5009 exists. Needed an unplanned `netinstall`
  recovery along the way — see `wifi.md` for the full account. Final location: mikrotik1
  `ether10` (not mikrotik3 — that plan was superseded; it still applies to the SXTsq).
  **`LEDCOM-IoT` is not offered on this AP** — VLAN tagging for multi-SSID virtual interfaces is
  confirmed unsupported on this hardware/driver combination, every documented mechanism
  exhausted (see `wifi.md`); only plain `LEDCOM` is served, on both bands. SSH key auth added
  for `admin`. **Baseline hardening (S17) closed 2026-10-07** — see `changelog.md`.
- The SXTsq Lite2 (garden AP) has **no device number yet** — it was previously, incorrectly,
  recorded as mikrotik4 with the cAP's MAC. Check its own label for its real MAC before building
  it; see `wifi.md`.
- Both 2.4 GHz-only original APs' TX power rose 16 -> 20 dBm as a side effect of the channel fix;
  deliberately not adjusted yet.

**Main router** — [config-review.md](config-review.md). Open findings: a minor
`connection-state=new` inconsistency on `chain=input` (22, informational, no known impact),
and finding 25 (`home.ledcom.fr` DNS staleness) — reported fixed 2026-09-22 via the Home
Assistant Let's Encrypt add-on's Gandi DDNS (an expired API key, renewed), but this directly
contradicts a 2026-09-11 investigation that ruled that exact mechanism out; not yet
reconciled, see `config-review.md`. mikrotik4's full baseline pass (S17) closed 2026-10-07 —
see `changelog.md`. mikrotik2/mikrotik3 have no open findings either as of the same review.

**Hardware.**
- Swisscom box replaced 2026-09-11 (10G-capable, no bridge mode, mikrotik1 set as its DMZ
  host) — broke the HA HTTPS NAT rule and IPv6 delegation, both fixed same day, see
  `changelog.md`. **RB5009UPr+S+IN** (the PoE-out variant — corrected 2026-10-07 from the
  original `RB5009UG+S+IN` recommendation, which missed that mikrotik4 needs PoE from the edge
  role) ordered for the edge role, still a separate, not-yet-arrived step — see
  `config-review.md`'s hardware section for what the box swap did and didn't resolve.
  **This also resolves the mikrotik4 uplink speed trade-off**: `ether10` is Fast-Ethernet-only
  on mikrotik1 (confirmed 2026-10-07, a real hardware ceiling, not a bug — see `wifi.md`),
  capping mikrotik4's link at 100M despite mikrotik4's own port being gigabit-capable. Every
  `RB5009UPr+S+IN` port is Gigabit, so once it lands mikrotik4 gets both PoE and full Gigabit
  from the same cable — no separate injector needed, no trade-off to make. **2026-10-07: the
  wrong unit (`RB5009UG+S+IN`) arrived and was returned; the correct `RB5009UPr+S+IN` is
  in transit, expected 2026-10-08.**
- Office PoE switch — **dropped 2026-10-06**, a PoE injector covers the SXTsq permanently, no
  purchase needed. mikrotik3 stays in the office; see `config-review.md`'s hardware section.
- Living room switch (second RB750Gr3/hEX, originally for the TV/Nintendo Switch/amp, all
  wireless before this — see `config-review.md`) — **received 2026-10-07, built 2026-10-08,
  moved to the living room and connected the same day.** Assigned mikrotik5, `192.168.10.5`,
  built VLAN-aware (fleet consistency, Guillaume's call) despite not strictly needing it.
  Config build verified on every device involved (mikrotik1-5) — see `vlan.md`'s "Living room
  and workshop" section and `changelog.md`'s "mikrotik5 build" entry (2026-10-08), which also
  records two real RouterOS scripting bugs found and fixed along the way (now in this file's
  hard-won lessons below). TV is wired to `ether2`, confirmed working (verified `vlan-users`
  DHCP lease). Nintendo Switch and amp still wireless.
- **Living-room patch cable — root-caused 2026-10-08, replacement needed.** The
  mikrotik2-mikrotik5 trunk's 100Mbps-instead-of-Gigabit cap (see `changelog.md`) turned out to
  be a bad patch cable at the living-room end, not the in-wall run or either device's port —
  confirmed by swapping in a spare cable, which immediately negotiated a full Gigabit link. A
  permanent replacement is still needed; the spare isn't meant to stay in place.
- Workshop still needs a switch too, VLAN-aware if it carries more than just `iot`.

**Backup internet (future idea, not yet designed).** Noted 2026-09-08: use a phone in
access-point/tethering mode as a failover WAN on mikrotik1 if the Swisscom line goes down.
Likely shape — a second `/ip/dhcp-client` on whatever interface reaches the phone's hotspot
(wireless, or wired if tethered by USB/cable), plus `/tool/netwatch` or check-gateway-based
distance/route metrics so mikrotik1 prefers the primary WAN and only fails over when it's
actually down. Not scoped further than this — revisit before starting.

**DNS-over-TLS from clients to Pi-hole (future idea, not yet designed).** Noted 2026-09-18:
firewall logs show `users`/`iot` clients (most likely Android's "Private DNS: Automatic"
opportunistic probe) attempting TCP/853 to Pi-hole (`192.168.20.40`), currently dropped by
`users2services`/`iot2services`'s catch-all. **Checked same day: Pi-hole doesn't serve DoT** —
its FTL resolver only speaks plain DNS; the existing 853 firewall exceptions
(`services2internet`'s Pi-hole rule, `pihole-v6`) are for Pi-hole's own *outbound* upstream
queries only, unrelated to this. Opening the firewall alone would do nothing but let the TCP
SYN through to a closed TLS handshake. Needed first: a TLS-terminating layer in front of FTL
(`stunnel`, `dnsdist`, or `cloudflared`, handing plaintext to FTL's `53`) on the Pi-hole host —
not yet designed or scoped. Once that exists, the firewall side is a small, well-understood
addition (`users2services`/`iot2services` each get one `dst-address=192.168.20.40 dst-port=853`
accept, mirroring `services2internet`'s existing Pi-hole DoT rule) — IPv6 has no
`users2services`/`iot2services` chains at all yet, so DoT over IPv6 would be new scope on top
of that, not just extending an existing rule.

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
  (`dump-configs.sh`, `dump-logs.sh`, `fetch-backups.sh`, `measure-bufferbloat.sh`,
  `dump-pihole-logs.sh` in `scripts/`, [render-nwdiag.py](diagrams/render-nwdiag.py) in
  `diagrams/` as of this writing) — anything written for a single migration step gets cleaned
  up after.

## Hard-won lessons

- **Safe mode discards everything if the session drops.** It silently lost work twice here.
  For changes that cannot affect the management path, run them directly and verify
  immediately. For changes that can, use a scheduled auto-rollback instead — see the
  `mikrotik-routeros-rsc` skill for the idempotent-scripting pattern this project now follows.
- **A per-device VLAN port move is two commands, not one.** Bridge-vlan table membership and
  `pvid` are independent, and `untagged=` on the bridge-vlan table takes the full replacement
  port list, not an add/remove delta. For a long list (mikrotik2's VLAN 10 untagged list ran to
  25 ports), read and rebuild it programmatically in the script rather than hand-retyping — a
  transcription error at that size is easy to miss.
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
  several distinct triggers, not fully characterized — always print and check after any rule
  with multiple matchers.** Confirmed triggers, found across the printer/Pi-hole/HA/ceiling-fan/
  Phase 4 work:
  - Missing `connection-state=new` on an `accept` rule.
  - `src-address=`/`dst-address=`/`dst-port=`/`port=` combined with only *one* of
    `in-interface=`/`out-interface=` — needs both together, or neither.
  - **Both** `src-address=` and `dst-address=` together with no interface matcher — also needs
    both interfaces (one address with no interface is fine).
  - **Not evaluated at all on `disabled=yes` rules.** A rule created disabled looks clean and
    only reveals the flag once enabled for real — enable and re-check, don't trust a print from
    while it was off.
  - **Does not apply to `chain=input`** — confirmed clean on an otherwise-equivalent input rule,
    consistent with `input` having no `out-interface=` concept to be incomplete about.
  - **Reusing a cached `find` result across multiple sequential `/add` calls in one script.**
    Caching `:local catchall [find where comment=...]` and reusing it as `place-before=$catchall`
    across nine `/add`s produced `I - INVALID` on the last one, despite it being structurally
    identical to an earlier, valid rule. Fix: re-evaluate `find` fresh at every `/add` — never
    cache and reuse a `place-before=`/`place-after=` target across multiple inserts.
  - **A transient `I - INVALID` right after creation, clearing on its own with no action taken,
    isn't unique to IPv6 — confirmed on plain `/ip/firewall/filter` too (finding 32,
    `iot2services: DNS to pi-hole (tcp)`, 2026-09-22).** First seen on IPv6: a `jump` dispatch
    rule and its target chain's `accept connection-state=new` rule, identically shaped to a
    long-working IPv4 `users2internet` pair, both showed `I - INVALID` immediately after
    creation the first time this was tried on IPv6 (`vlan-users` hardening, finding 21 phase 1)
    — but the flag was gone on a later print with no action taken, and the rules were
    functionally confirmed enforced throughout (internet access worked, the blocked management
    port actually timed out). Finding 32 hit the same thing on IPv4: an `accept` rule added by
    an idempotent script (no cached/reused `find`, not `disabled=yes`, `connection-state=new`
    present) printed `I - INVALID` once, cleared on a later print, and a real client
    (`nc`/counter-verified) confirmed it was enforced the whole time. Don't assume either
    protocol is immune — keep verifying functionally against a real client, and re-print rather
    than trust the flag state from immediately after an `/add`.
  - **`iot2services` specifically has now shown this same transient `I - INVALID` twice in a
    row, on two unrelated scripts, while an identically-shaped sibling rule added to
    `users2services` in the same run printed clean both times** (finding 32's TCP/53 accept,
    2026-09-22; the DoT-probe `reject` rule, same day). Two-for-two is no longer obviously
    coincidence, but the cause still isn't identified — not a cached `find`, not
    `disabled=yes`, `connection-state=new` present where applicable. If `iot2services` is
    touched again and shows this, it's expected, not a new problem — re-print and verify
    functionally as always, but don't spend time chasing it as if it were novel.
- **Clearing a property back to default/empty is trickier than it looks — three distinct
  failure modes found in one session.** `property=""` on an interface-typed field
  (`in-interface=`/`out-interface=`) is treated as an ambiguous wildcard match against every
  interface, not "no value" — RouterOS refuses with "ambiguous value of interface."
  `!property` (the documented way to unset) works, but only when paired with at least one
  other real assignment in the same `/set` command — used completely alone (`!property` and
  nothing else) it's a syntax error. And some string properties enforce their own minimum
  length regardless of technique — `add-dns-entries-suffix=""` was rejected outright ("should
  not be shorter than 1"), no way found to make it empty; the working fix there was pointing it
  at a real value instead of fighting the clear. Try `!property` paired with something harmless
  first, and don't assume every property can be made empty.
- **`/ip/dhcp-server`'s `lease-script` only fires on a genuine new bind or a deassign, not an
  in-place lease renewal.** A script set on all three DHCP servers looked completely inert for
  ~25 minutes despite multiple 5-minute lease cycles elapsing — zero invocations in
  `/log/print`. Forcing one lease to actually rebind (`/ip/dhcp-server/lease/remove`) fired it
  immediately. Don't conclude a lease-script is broken just because it's quiet — force a fresh
  bind before troubleshooting further.
- **RouterOS's DNS server does not translate DHCP leases into DNS records at all, in either
  direction, natively.** Confirmed empirically (`dig` against the router returned `NXDOMAIN`
  for both a named static reservation and a plain dynamic lease) and via MikroTik's own docs:
  `/ip/dns/static` has no `PTR` record type. What does work: "for each static A and AAAA
  record, in cache automatically is added a PTR record" — so a `lease-script` maintaining
  static A records gives real reverse resolution as a side effect. `add-dns-entries-suffix` on
  `/ip/dhcp-server` looks like it should provide this automatically; confirmed inert regardless
  of its configured value — don't rely on it.
- **Pinning `NTP=` in a LAN client's `/etc/systemd/timesyncd.conf` is not sufficient on its
  own — `FallbackNTP=` must also be set explicitly empty.** Left at its commented-out default
  (`debian.pool.ntp.org`), `systemd-timesyncd` silently falls back to it whenever the pinned
  server is even briefly slow to answer, which the IoT/services firewall policy then correctly
  blocks — the fix looks like it worked (verified once, working at the time) and then quietly
  stops, with no error and no symptom short of reading the firewall log. Hit twice in one day
  on two different devices (Pi-hole, re-opening a previously "closed" finding 23; OctoPrint,
  the first time its NTP was ever configured) — always set both together, not just `NTP=`.
  **Correction, found 2026-09-14 re-opening finding 23 a second time:** an empty `FallbackNTP=`
  assignment does not reliably clear the compiled-in default on this systemd build
  (`252.33-1~deb12u1+rpi1`, Raspberry Pi OS/Debian 12) — `timedatectl show-timesync --all`
  showed `FallbackNTPServers=0.debian.pool.ntp.org ...` still active days after the empty
  assignment had been applied and "verified," with no drop-in anywhere overriding it
  (`systemd-analyze cat-config systemd/timesyncd.conf` confirmed the plain file was the only
  effective config). The original verification only ever checked `timedatectl
  timesync-status` (the *active* server only) — that can never catch this, since the fallback
  list simply isn't exercised while the primary keeps answering. **`show-timesync --all`
  (`FallbackNTPServers=`) is the only way to actually confirm the fallback list is what you
  think it is.** The durable fix: don't rely on empty-clears-list semantics at all — point
  `FallbackNTP=` at the same real server as `NTP=` instead, so there's no path to the public
  internet regardless of how this quirk behaves. Applied and verified on Pi-hole
  (2026-09-14); OctoPrint reconfigured the same way the same day (Guillaume confirmed) —
  both devices with a `FallbackNTP=` pin are now on the durable, same-server form.
- **IPv6 privacy extensions (RFC 4941 temporary addresses) can't be assumed off on a "fixed
  appliance" host — verify against real traffic, not just the device's role.** A firewall rule
  scoped to a computed EUI-64 address can look completely correct on `print` while matching
  nothing real, because the host's actual outbound address is a rotating temporary one instead.
  Confirmed on two different hosts (Pi-hole, OctoPrint) the same day this assumption was first
  made (finding 21 phases 2-3) — check `ip -6 addr show scope global` against what the firewall
  expects before trusting an EUI-64-pinned rule, and remember that disabling temporary addresses
  alone isn't enough either: modern NetworkManager/systemd-networkd defaults often use RFC 7217
  "stable-privacy" addressing for the *permanent* address too, so `addr_gen_mode` needs forcing
  to EUI-64 explicitly, not just `use_tempaddr=0`.
- **A `/ip firewall filter add ... place-before=[find ...]` command can silently create two
  copies of the rule when run via `import` of a `.rsc` file, but not when typed directly at the
  CLI.** Found adding HA's `linux-monitor` SSH exceptions (2026-09-16): from a verified-empty
  starting state, a single `import` run produced two identical accept rules every time, one
  correctly commented and one with no comment at all — reproduced across four attempts, ruling
  out file corruption (`/file print detail` showed correct single-copy contents each time),
  slash- vs space-separated menu paths, inline vs precomputed `place-before`, and a `:foreach`
  loop earlier in the same script (moved to a separate prior `import` — still duplicated). Typing
  the exact same single-line command directly at the CLI prompt worked correctly, both times, on
  the first try. Root cause not identified. If an idempotent `.rsc` script's `/add` with
  `place-before=[find ...]` produces an unexplained duplicate, don't keep varying the script —
  try the same command typed directly instead.
- **Adding a source to the `mgmt` firewall address-list is not enough on its own to grant
  login** — the `admin` user account carries its own `address=` restriction, entirely separate
  from the firewall. A source outside it can pass every firewall rule (the login page loads)
  and still be refused at authentication. Already known from the VLAN renumber (a user
  account's `address=` restriction locked out management then too — see the "grep the config
  for its literal old IP" lesson above), but that was triggered by *changing* an existing
  host's address; this is the same gate blocking a *new* mgmt source that was never in the
  restriction to begin with. Confirmed 2026-09-28 adding the phone's WireGuard tunnel address
  to `mgmt`: firewall accepted the connection on all three devices, login still failed on all
  three, until `/user set [find name=admin] address=...` was widened to include the tunnel
  subnet. **Whenever a new source is added to `mgmt`, check `/user print detail` too** — the
  firewall list and the user's own restriction are two independent things to update, not one.
- **An unset `comment` isn't stored as an empty string.** `/ip/firewall/filter/remove [find
  where comment=""]` was a silent no-op against a rule with genuinely no comment set — same
  "empty `find` result" failure class already catalogued above, new trigger. When isolating a
  rule by "no comment," match by every *other* distinguishing property instead (or remove every
  rule sharing some other unique property, like a newly-added address-list, and re-add the one
  you want to keep) rather than testing for comment absence directly.
- **Don't trust `current-state`/`running-ap` (CAPsMAN) or a radio's own reported state
  (standalone `wifi-qcom-ac`) as proof a radio is actually transmitting.** mikrotik4's 5 GHz
  radio reported `running-ap` with full VHT rates under the legacy `wireless` package for an
  entire build session, while never once actually being associable by any real client at any
  range. Only caught by insisting on a real client test instead of trusting the print. If a
  "working" radio seems to have zero clients ever, test with a real device before concluding
  it's just unused — don't assume the state report is honest on IPQ4019/`wifi-qcom-ac`.
  Resolved by switching to the `wifi-qcom-ac` package, which worked immediately — see
  `wifi.md` and `changelog.md`'s 2026-10-07 correction entry for the full account.
- **Bridge-vlan `find` can match more than one row for the same `vlan-ids`** — a real static
  entry plus rows RouterOS auto-manages dynamically (seen with comments like "added by wifi" or
  "added by pvid"). `/get`/`/set` against the unfiltered result fails outright (`invalid
  internal item number` / `can not change dynamic`). Filter explicitly on `dynamic=no`.
- **A bridge-vlan entry's `current-tagged`/`current-untagged` are the live, effective values;
  `tagged`/`untagged` are what's configured and can carry stale, unparseable leftover
  references** (displayed as `*NN`, confirmed to be dangling references to since-removed
  interfaces). Rebuilding a `tagged=`/`untagged=` value from the configured property can
  silently fail the `/set`; rebuild from `current-*` instead.
- **A property read via `/get` can come back as a native RouterOS array, not a pre-joined
  string**, even when `print` displays it as comma-separated text. Concatenating it with a
  string using `.` does not join the array into a string — it broadcasts the string onto every
  element instead, silently producing garbage. Join arrays into a real string by hand
  (`:foreach` + manual concatenation) before using them in any further string operation.
- **The bridge interface itself has its own `pvid`, separate from any port's `pvid`** — it
  governs VLAN tagging for the bridge's *own* locally-bound traffic (e.g. a management IP bound
  directly to `bridge` rather than to a dedicated `/interface vlan`). Leaving it at the default
  while every port's own `pvid` is already correct is enough on its own to break reachability.
- **A scheduled job that removes itself from inside its own `on-event` can still fire a second
  time** — confirmed live, same idempotent action run twice, 3 minutes apart, despite the first
  firing's own cleanup removing the scheduler entry. Don't rely on "fires exactly once because
  it deletes itself"; make the on-event body safe to run more than once instead.
- **`/interface/bridge/host`'s VLAN-related property is `vid`, not `vlan-id`** (the latter errors
  with "input does not match any value of value-name"), and it comes back empty for ordinary
  wireless client traffic regardless of which VLAN that traffic is actually on — not a useful
  signal for diagnosing VLAN misclassification. Go to a wire-level capture (`/tool/sniffer`,
  pulled off and read with `tcpdump -e` for the real 802.1Q tag) instead of guessing at more
  bridge-table properties when `print`-level introspection gives ambiguous or empty answers.
- **VLAN tagging for a multi-SSID virtual `wifi-qcom-ac` interface (`master-interface=`) is not
  achievable on IPQ4019 cAP-family hardware** — confirmed by exhausting every documented
  mechanism (bridge port `pvid`, `datapath.vlan-id`, and MikroTik's own published switch-chip
  workaround for this exact chip/package) and verifying each by packet capture rather than
  trusting any RouterOS state report. `datapath.vlan-id` doesn't just silently fail here, it
  actively disconnects any client that tries to associate while it's set. If a multi-SSID
  VLAN-tagged AP is needed on this hardware, it has to be CAPsMAN-managed on the legacy
  `wireless` stack instead — which brings back that stack's own 5 GHz unreliability (see above),
  so on current hardware the two requirements (working 5 GHz, VLAN-tagged multi-SSID) can't
  both be satisfied on the same radio.
- **`[find prop1=X and prop2=Y]` silently matching nothing is not limited to
  `/ip/firewall/filter`** (where it was first documented above) — confirmed live 2026-10-08 in
  `/interface/bridge/vlan` too: `[find vlan-ids=$vid and dynamic=no]` matched nothing even
  though a matching static row existed, and the following `/interface/bridge/vlan/get` on the
  empty result threw "no such item." Assume this `and`-combination risk applies fleet-wide
  across menus, not just the one menu it was first caught in; filter on a single condition and
  do any further narrowing (e.g. excluding dynamic rows) in script logic instead.
- **The MikroTik-wiki `:local f do={ :local x $1 ... }` / `[$f "arg"]` pseudo-function idiom does
  not reliably bind `$1`/`$2` when the `do={}` block is defined and invoked from inside another
  named `/system/script`'s own `source=`, run via `/system/script/run`** — confirmed live
  2026-10-08: `$1` came back empty inside the nested block, even though the call site passed a
  literal value (`[$addTagged 20 "ether12-slave-local"]`). Root cause not identified — RouterOS
  gave no error, the argument was just silently absent. Don't use this idiom for anything
  beyond the console/a top-level script's own body; duplicate the logic per call site instead
  of parameterizing it.
