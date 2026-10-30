# Home MikroTik network

Working notes for a home network built on MikroTik hardware behind a Swisscom Internet-Box.
Written so that work can resume from these documents alone, with no session history.

## Start here

**Active work: Phase 4 (clean-up) of [rb5009-migration.md](rb5009-migration.md).** The RB5009
became the edge router on 2026-10-20 (`router`, `.10.1`, 865/858 Mbps). The RB2011 (old
mikrotik1) is off the LAN; its rollback week ended 2026-10-27, so wiping it is the next step.
Read that file's **Status** and **Resume here** first. Open findings are in
[config-review.md](config-review.md) (39, 42, 44, S22 and S23 as of 2026-10-30).

The devices were renamed on 2026-10-20. Older documents and all of `changelog.md` use the old
names:

| Name (identity, `<name>.home.ledcom.fr`) | Was | Model |
|---|---|---|
| `router` | mikrotik6 (and mikrotik1's role) | RB5009UPr+S+IN |
| `switch-main` | mikrotik2 | CRS125-24G-1S-2HnD |
| `switch-office` | mikrotik3 | RB750Gr3 (hEX) |
| `ap-main` | mikrotik4 | RBcAPGi-5acD2nD (cAP XL ac) |
| `switch-livingroom` | mikrotik5 | RB750Gr3 (hEX) |
| — | mikrotik1 | RB2011UiAS-2HnD, off the LAN, named when redeployed |

The `router1`-`router6` Pi-hole records stay as aliases until 2026-10-27.

## The network as it stands

| Device | Address | Role |
|---|---|---|
| router | `192.168.10.1` (also `.10.6` until the rollback week ends); WAN `ether1` `192.168.1.103` | edge router: firewall, NAT44 + NAT66, DHCP, DNS forwarder, NTP, WireGuard (`192.168.50.1`), legacy CAPsMAN manager |
| switch-main | `192.168.10.2` | L2 switch, 24×GE + SFP, VLAN trunks to router (`ether1`), switch-office (`ether16`) and switch-livingroom (`ether12`); Pi-hole, HA, OctoPrint wired; CAPsMAN CAP (2.4 GHz, `LEDCOM` + `LEDCOM-IoT`) |
| switch-office | `192.168.10.3` | L2 switch, office, 5×GE: desktop, printer |
| ap-main | `192.168.10.4` | standalone `wifi-qcom-ac` AP, 2.4 + 5 GHz, `LEDCOM` only; router `ether3`, 1 Gbps + PoE |
| switch-livingroom | `192.168.10.5` | L2 switch, living room, 5×GE: TV on `ether2`. **On the TV's switched power strip: only up while the TV is on, so "unreachable" is its normal state.** Uplink at 1G since the cables were replaced (2026-10-20) |

All on RouterOS 7.24.5 (stable; upgrade the whole fleet together with
`scripts/upgrade-fleet.sh`). Three VLANs: `users` (`192.168.10.0/24`), `services`
(`192.168.20.0/24`), `iot` (`192.168.30.0/24`), plus `wireguard1` (`192.168.50.0/24`) — see
[vlan.md](vlan.md). Upstream is a Swisscom Internet-Box at `192.168.1.1` with no bridge mode:
the router is its DMZ host, so IPv4 is double-NATed and IPv6 uses NAT66 on the delegated
`2a02:1210:7621:9ac0::/58` (see [ipv6.md](ipv6.md)).

**DNS and NTP are self-contained** — no LAN device needs the public internet for either.
Pi-hole (`192.168.20.40`) is every device's resolver. For anything it doesn't know, it
conditionally forwards to the router (`192.168.0.0/16` → `192.168.10.1`), which keeps a live
`<hostname>.home.ledcom.fr` entry for every bound DHCP lease, via a `lease-script` on all three
DHCP servers. NTP works the same way: the router runs an NTP server, `chain=input` accepts it
from all three VLANs, and every device should use its own VLAN's gateway for time (DHCP option
42 provides it but not every OS honors it, see finding 23's closure in `changelog.md`).

Raw device output lives in [dumps/](dumps/), collected with
[dump-configs.sh](scripts/dump-configs.sh) (one `<name>.txt` per device). Regenerate it
before any review — the files are a snapshot, not a source of truth.
switch-livingroom is powered with the TV, so `UNREACHABLE on port 22` in its file is normal:
dump while the TV is on to include it.

Logs live in `logs/` (gitignored), collected with [dump-logs.sh](scripts/dump-logs.sh): the
full log of every device, one file each. Firewall entries (the `log=yes` deny-all rules at
the end of every jump chain, see [firewall.md](firewall.md)) are in `logs/router.txt`.
RouterOS's log buffer is small and rotates, so run this regularly.

Pi-hole's own on-disk logs (no API token configured, so this reads straight off disk via
rsync+sudo) land in `logs/pihole/`, collected with
[dump-pihole-logs.sh](scripts/dump-pihole-logs.sh). `pihole.log` is the per-query log (shows
`from <client-ip>`); `FTL.log` matches the web UI's Diagnosis view but doesn't show the client.

## Documents

| File | What it holds |
|---|---|
| [rb5009-migration.md](rb5009-migration.md) | **Active.** Runbook for moving the edge role to the RB5009. Phases 0-3 done 2026-10-20, Phase 4 (clean-up) in progress |
| [config-review.md](config-review.md) | Open findings and the hardware/architecture decisions |
| [changelog.md](changelog.md) | Every change and closed finding, with the output that verified it |
| [vlan.md](vlan.md) | VLAN design, device inventory, address plan, port plans (done 2026-09-11) |
| [firewall.md](firewall.md) | Every live firewall rule on the router, in evaluation order |
| [wifi.md](wifi.md) | Wireless: channels, ap-main's build, the 5 GHz and CAPsMAN plans |
| [ipv6.md](ipv6.md) | IPv6 via DHCPv6-PD and the NAT66 workaround |
| [vpn.md](vpn.md) | WireGuard road-warrior VPN for the Android phone and x1 (work laptop) |
| [network.md](network.md) | The two diagrams and how to regenerate them |
| [performance.md](performance.md) | Throughput investigation — resolved 2026-10-20: the RB2011 was the limit |
| [qos.md](qos.md) | Bufferbloat: none, re-measured on the router 2026-10-20. No QoS needed |

Diagrams live in [diagrams/](diagrams/): [network.svg](diagrams/network.svg) is physical
topology (Graphviz), [network-addressing.svg](diagrams/network-addressing.svg) is the address
plan (nwdiag). Sources are `network.dot` and `network-addressing.nwdiag`; see
[network.md](network.md) for the commands.

## Everything currently open

**RB5009 migration, Phase 4** — [rb5009-migration.md](rb5009-migration.md): **the end of the
rollback week is due** (since 2026-10-27): wipe the RB2011, then remove `cutover`/`rollback`,
the `.10.6` address and the `router<N>` aliases. The log review and the throughput
re-baseline are done.

**Findings** — [config-review.md](config-review.md):
- 39: the router's leftovers. The deferred part is the end of the rollback week, above.
- 42: the router retries WireGuard handshakes after the phone has gone. Fix applied 2026-10-28
  (`responder=yes`, no router-side keepalive), tunnel confirmed from the phone; to verify in
  the router log over the next days.
- S22: ap-main's log reached back only 19 h. `memory-lines=10000` applied 2026-10-28; to verify
  with a later `dump-logs.sh`.
- S23: phones ping-pong between 2.4 and 5 GHz at the edge of 5 GHz coverage, one of them every
  minute all night. Access-list rule on `wifi2` applied 2026-10-28; check the log of the night
  to 10-29.
- 44: the router's `device-mode` `home` turns off the scheduler, fetch, the sniffer and RoMON.
  Proposal: `basic`, which needs a physical button press and a reboot. First, the next
  `dump-configs.sh` shows every device's mode.
- Older, informational: 22 (`connection-state=new` on `chain=input`), 25 (`home.ledcom.fr`
  DDNS, reported fixed, not reconciled; `vpn.ledcom.fr` is now a hand-kept A record).

**x1 road-warrior VPN** — [vpn.md](vpn.md)'s "x1" section. Worked from outside the LAN
2026-10-30, then failed again: the endpoint `vpn.ledcom.fr` is being changed from a CNAME to a
plain A record (see the lesson on `home.ledcom.fr` endpoints). x1 is gimli reimaged, same
`.10.92` reservation. Also left: add `192.168.50.3` to switch-livingroom's `mgmt` when the TV is
on (the two lines are in `changelog.md`'s 2026-10-29 entry).

**switch-office is on the office's power for now** (Guillaume, 2026-10-28): it goes off when
the office does, which is expected. The separate power strip decided 2026-10-20 is not in
place yet. Like switch-livingroom, switch-office being down is not a failure until then.

**Routine reviews, no urgency — good places to start a fresh session:**
- Re-run `dump-logs.sh` and read the router's firewall log for anything worth tuning. Last full
  pass: 2026-10-28 (covers 2026-10-20 to 10-28).
- Review all DHCP leases and reservations: name every known device, drop stale reservations
  (decided 2026-10-20, when `.10.91` was removed unnamed).
- Review Pi-hole's query log as a general health check (`dump-pihole-logs.sh`). One known item:
  HA's hourly reverse-DNS sweep of its own subnet, see `home/home-assistant`'s finding 17.

**Wireless** — [wifi.md](wifi.md).
- ap-main serves only `LEDCOM`: VLAN-tagged multi-SSID is unsupported on its hardware/driver.
  `LEDCOM-IoT` is only on switch-main's 2.4 GHz radio.
- ap-main under the new `/interface/wifi/capsman` on the router (target B3) is possible now, but
  low value (`rb5009-migration.md` Phase 5).
- The SXTsq Lite2 (garden AP) is not built and has no name yet. Check its own label for its real
  MAC first; see `wifi.md`.
- switch-main's radio reports 16 dBm again under the router's CAPsMAN (2026-10-20 dump). Under
  mikrotik1 it had run at 20 dBm since the channel fix (`wifi.md`). Nothing was changed on
  purpose: check client signal before deciding whether to pin `tx-power`.

**Hardware.**
- The workshop still needs a switch, VLAN-aware if it carries more than `iot`. The RB2011 is a
  candidate once wiped.

**Backup internet (future idea, not yet designed).** Noted 2026-09-08: a phone in tethering mode
as a failover WAN on the router — a second `/ip/dhcp-client` on the interface that reaches the
phone, plus `/tool/netwatch` or check-gateway route distances so the primary WAN is preferred.
Revisit before starting.

**DNS-over-TLS from clients to Pi-hole (future idea, not yet designed).** Noted 2026-09-18:
clients (most likely Android's "Private DNS: Automatic") try TCP/853 to Pi-hole, and the
firewall rejects it quietly. Pi-hole's FTL does not serve DoT, so a TLS-terminating layer on the
Pi-hole host (`stunnel`, `dnsdist` or `cloudflared`) is needed first. Then the firewall side is
one accept each in `users2services`/`iot2services`. IPv6 has no such chains yet.

## Conventions

- A finding leaves a review document only when it is fixed **and** verified against device
  output — never when it is reported done. Closed items move to
  [changelog.md](changelog.md) with the evidence.
- Finding numbers are stable and never reused. `<n>` for the main router, `S<n>` for switches
  and APs.
- Device names are role-location (`router`, `switch-<place>`, `ap-<place>`), used for the
  RouterOS identity, the Pi-hole hostname and the dump file. A new device gets a name in the
  same scheme, not a number.
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
  (`dump-configs.sh`, `dump-logs.sh`, `fetch-backups.sh`, `upgrade-fleet.sh`,
  `measure-bufferbloat.sh`, `dump-pihole-logs.sh` in `scripts/`, [render-nwdiag.py](diagrams/render-nwdiag.py) in
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
  - **Not limited to `chain=forward`.** An equivalent input rule was once confirmed clean,
    consistent with `input` having no `out-interface=` concept to be incomplete about. But on
    2026-10-20, `DHCP server (vlan-iot)` (`chain=input`) printed `I - INVALID` right after it was
    added, while its twin for `vlan-services` did not, then cleared on its own. So the
    transient flag (below) happens on `input` too.
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
  - **A bulk import can show it on almost the whole ruleset at once.** Right after
    `mikrotik6-p2-firewall.rsc` added 89 rules (mikrotik6, 2026-10-19), 88 of them printed
    `I - INVALID`, even matcher-less ones like `Drop anything else!`. Only the first rule added
    was clean. A later print showed none invalid, with no action taken. Wait and re-print
    before debugging.
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
- **The Internet-Box web UI hangs over IPv6; use `https://192.168.1.1`.** Seen 2026-10-19:
  `internetbox.swisscom.ch` resolves to `192.168.1.1` *and* `2a02:a90:400e::1`, so browsers
  and curl try IPv6 first. Over IPv6 the TLS handshake completes, then the box never answers
  the HTTP request (`curl -6` timed out after 15 s with 0 bytes). `curl -4` returned
  `HTTP/1.1 200 OK` right away. It is not a routing or MTU problem: the multi-KB certificate
  chain came back fine. The AAAA is in public DNS (`dig AAAA @1.1.1.1` and Pi-hole both
  return it), so this happens from any client with IPv6.
- **`remove [find ...]` fails as a whole if the match includes a dynamic entry.** Every
  `/ip/firewall/filter` and `/ipv6/firewall/filter` has a dynamic "special dummy rule to show
  fasttrack counters" in `chain=forward`. On switch-livingroom (2026-10-20),
  `/ip/firewall/filter/remove [find chain=forward]` and `/ipv6/firewall/filter/remove [find]`
  each removed nothing, because the dummy rule cannot be removed. Match on something that
  excludes it, such as `comment~"defconf"`. This is the same shape as the bridge-port lesson
  above. Always print afterwards.
- **After a CAPsMAN manager change or a CAP re-join, ESP-based IoT devices may not reconnect
  on their own.** After the 2026-10-20 cutover, IotaWatt stayed off `LEDCOM-IoT` for 47 minutes,
  with no association attempt in the router's log, until it was power-cycled. The Tasmota
  light rejoined by itself. Before any change that restarts CAPsMAN, save
  `/caps-man/registration-table/print`, then compare against it after the change.
- **Renaming an interface does not bounce its link, and RouterOS updates every reference** to
  it (bridge ports, the bridge VLAN table, interface lists). switch-main's 25 ports were renamed
  in one loop on 2026-10-20 with no disruption. A CAP's identity change does not make it re-join
  either: the router's dynamic `ap-*` interfaces keep their old names until the next re-join.
- **A deny-all log line with `ACK`/`ACK,PSH`, `connection-state:new` and a server port as the
  source is a late retransmission, not a policy gap.** After a FIN or RST, conntrack keeps a
  TCP entry for only 10 s (the `tcp-*-timeout` defaults). A server still retransmitting after
  that gets a new entry (`loose-tcp-tracking=yes` calls a mid-stream packet `new`), so the
  chain's deny-all logs it. It comes in short bursts with doubling gaps (25 s, 47 s...) and
  harms nothing: the connection had already ended. Findings 28 and 33 stayed open for weeks
  on this shape. Closed 2026-10-28, with a clear example: OctoPrint's replies to the desktop
  that had just gone to sleep (`changelog.md`).
- **The router cannot run `/tool/sniffer`: its `device-mode` is `home`.** It answers `failure:
  not allowed by device-mode` (2026-10-30). Changing device-mode needs a physical confirmation
  at the router. Per MikroTik's docs, `home` also turns off the **scheduler** and fetch, so
  the scheduled auto-rollback in the first lesson is not available on the router (finding 44). To see whether traffic crosses a WireGuard tunnel, read the peer's `rx`/`tx`
  in `/interface/wireguard/peers/print detail` before and after a known burst (`ping -c10`)
  instead. The sniffer advice in the lesson above applies to the switches and APs.
- **A full-tunnel WireGuard client must not use `home.ledcom.fr`, or any name under it, as its
  endpoint if it can look the name up again.** Pi-hole answers `home.ledcom.fr` with HA's LAN
  address (`192.168.20.60`, a local record) and forwards everything under it to the router, never
  to Gandi. NetworkManager looks the endpoint up again after activation, by then through the
  tunnel: x1's tunnel came up, then sent every packet to `192.168.20.60` over the internet. The
  signs: a handshake on the router, then `rx` frozen while the client's "sent" grows, made of
  148-byte handshake retries (`tcpdump -ni any udp port 51820` shows the destination). **A CNAME
  to `home.ledcom.fr` is not enough either:** Pi-hole serves stale answers (`EDE: 3 (Stale
  Answer)`, TTL 0) once a TTL has expired, and builds them by following the cached CNAME to its
  own local record, so now and then it answers `192.168.20.60`. A first check right after a
  cache flush cannot catch this. Wait past the TTL and query again. Clients use `vpn.ledcom.fr`,
  a plain A record at Gandi. The phone's app resolves once, at tunnel start, so the phone works
  with either name (2026-10-30).
