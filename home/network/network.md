# Network diagrams

Two diagrams, because they answer different questions and neither tool does both well. Sources,
render script and rendered output all live in [diagrams/](diagrams/).

| Diagram | Question it answers | Source | Tool |
|---|---|---|---|
| [diagrams/network.svg](diagrams/network.svg) | what is plugged into what | [diagrams/network.dot](diagrams/network.dot) | Graphviz |
| [diagrams/network-addressing.svg](diagrams/network-addressing.svg) | which device is on which VLAN | [diagrams/network-addressing.nwdiag](diagrams/network-addressing.nwdiag) | nwdiag |

```
cd diagrams
dot -Tsvg network.dot -o network.svg
dot -Tpng -Gdpi=140 network.dot -o network.png

./render-nwdiag.py -T svg network-addressing.nwdiag -o network-addressing.svg
./render-nwdiag.py -T png network-addressing.nwdiag -o network-addressing.png
```

Regenerate after any change and commit the sources alongside the output — the `.dot` and
`.nwdiag` files are the things worth diffing.

## Why `render-nwdiag.py` and not `nwdiag3`

nwdiag 2.0.0 aborts on this diagram with

```
TypeError: '<' not supported between instances of 'Network' and 'Network'
```

The cause is upstream, in `nwdiag/metrics.py:162`:

```python
networks = group.nodes[0].networks[:]
networks.sort(key=lambda a: a.xy.y)
network = min(networks)
```

The list is already sorted by vertical position, so the intent is "take the topmost network"
— `networks[0]`. The `min()` is redundant, `Network` defines no ordering, and on Python 3 it
raises. It survives unnoticed because `min()` on a one-element list never invokes `__lt__`:
the bug only appears once a node belongs to **two** networks, which is exactly what a router
does.

[render-nwdiag.py](diagrams/render-nwdiag.py) defines `__lt__` on the same key the sort already
uses, so `min()` agrees with the sort rather than papering over it, then calls the normal CLI. It
takes the same arguments as `nwdiag3`. Nothing is patched on the system, so a package upgrade
cannot silently undo it — and if upstream ever fixes this, the shim becomes a harmless no-op.

Re-checked 2026-09-10 against plain `nwdiag3` on the current `network-addressing.nwdiag`
(the edge router sits on every VLAN network, which is exactly the two-networks-per-node case that
triggers this): still raises the same `TypeError`. The shim is still required.

Note the shebang is `/usr/bin/python3`: `nwdiag` is installed in the system
`dist-packages`, which the default `python3` on this machine does not see.

## Reading it

Edge style carries meaning, because a diagram that mixes what is true with what is planned
is worse than no diagram:

| Style | Meaning |
|---|---|
| **solid** | verified from device output — neighbour tables, link flags, the dumps |
| **dashed** | inferred; consistent with the evidence but not directly confirmed |
| **dotted** | planned, not yet cabled |
| **green** | CAPsMAN control relationship, not a cable |

Node fill: blue = MikroTik infrastructure, green = `vlan-users` clients and radios, purple =
`vlan-services` hosts, orange = `vlan-iot` devices, yellow = a known constraint, red = the
current bottleneck, grey dashed = planned.

**What is verified.** `router -> switch-main`, `switch-main -> switch-office` and
`switch-main -> switch-livingroom` come from the neighbour tables on both ends and from the
ports' running flags (2026-10-20 dumps). `router -> ap-main` is verified by
`/interface/ethernet/monitor ether3` (1 Gbps) and the PoE monitor on the router. Pi-hole
(`switch-main ether23`), Home Assistant (`ether21`), OctoPrint wired (`ether24`), the printer
(`switch-office ether2`) and the TV (`switch-livingroom ether2`) are verified by link flags and
by a DHCP lease bound at the expected address. `switch-office -> desktop` on `ether3` is still
inferred: the desktop is in the office and `ether3` has link, but no neighbour entry proves it.
Every wireless edge is dashed, because wireless attachment is "on this SSID/VLAN", not "on this
port", so there is no port to verify.

## Why these two tools

**Graphviz** was already installed (`dot - graphviz version 2.43.0`), which settled it. Beyond that:
the source is plain text and diffs cleanly in git, rendering is a single offline command with
no runtime, and DOT is stable enough that this file will still render in ten years.

The alternatives, all text-based and all capable of local SVG output:

| Tool | Renders via | Worth choosing when |
|---|---|---|
| **Graphviz** (`dot`) | native C binary | general topology; already present; smallest dependency |
| **D2** | single Go binary | nicer default output, containers and nesting; better looking with less fiddling |
| **nwdiag** | Python (blockdiag) | the diagram is *subnet*-centric — it draws networks as horizontal buses with hosts hanging off them, which is exactly the VLAN picture |
| **PlantUML** | Java | you also want sequence and deployment diagrams in the same syntax |
| **Mermaid** | Node + headless Chromium | the diagram should render inline on GitHub or in a markdown viewer without a build step |
| **Diagrams** (mingrammer) | Python + Graphviz | you want vendor icon sets; oriented at cloud architecture rather than home LAN |

Mermaid is the one to reach for if inline rendering matters more than fidelity — but its CLI
pulls in Chromium, which is a heavy dependency for a diagram. D2 is the strongest upgrade
path if this ever needs to look polished.

**nwdiag** turned out to be worth having alongside rather than instead. It draws each subnet
as a horizontal bus with hosts hanging off it, which makes address-plan questions obvious —
who is static, who is in `mgmt`, which devices are destined for the IoT VLAN — and makes
physical questions impossible, since it has no notion of a cable. Graphviz is the reverse.

It is the right tool for a VLAN diagram: the groups in `network-addressing.nwdiag` are
`vlan-users`, `vlan-services` and `vlan-iot` directly, matching [vlan.md](vlan.md)'s device
inventory and trunk/port plan.

## What the diagrams record

**Regenerated 2026-10-20**, after the RB5009 cutover and the device rename (`router`,
`switch-main`, `switch-office`, `ap-main`, `switch-livingroom`; the README maps the old
`mikrotik<N>` names). Facts worth calling out:

- **The Internet-Box has no bridge mode.** The router sits behind it as its DMZ host, so IPv4 is
  double-NATed and IPv6 needs NAT66 (see [ipv6.md](ipv6.md)). Measured 865 Mbps down and
  858 Mbps up through the router on 2026-10-20 (see [performance.md](performance.md)).
- **The RB2011 (old mikrotik1) is drawn dotted**: still on the box's WAN but off the LAN, the
  rollback path until about 2026-10-27, then wiped and redeployed.
- **ap-main is standalone**, not CAPsMAN-managed, and serves only `LEDCOM`: VLAN-tagged
  multi-SSID is not supported on its driver (see [wifi.md](wifi.md)). `LEDCOM-IoT` is only on
  switch-main's 2.4 GHz radio.
- **switch-office has no PoE-out**, so the planned garden SXTsq needs an injector.
- The printer is drawn on `vlan-users`, not `vlan-services`. It was migrated and then
  deliberately reverted (mDNS repeater defect, see [vlan.md](vlan.md)'s Decisions).
- The address diagram shows `wireguard1` (`192.168.50.0/24`) as a fourth network. The phone
  gets the `users` policy outbound, and only `mgmt` hosts may reach `users` through it.

Keep them current: regenerate after any change to the trunk/port plan, the device inventory, or
the wireless build-out, and commit the sources alongside the rendered output.
