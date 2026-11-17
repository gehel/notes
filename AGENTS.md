# AGENTS.md

This file provides guidance to agents working with this repository. It focuses on the key facts that would otherwise be missed or incorrectly inferred.

## Repository Overview

This is a personal notes repository for Wikimedia Foundation Data Platform Engineering (DPE) SRE work owned by Guillaume Lederrey. It contains operational notes, architecture diagrams, and project planning artifacts — not application source code.

Key areas:
- `planning/` — TaskJuggler project plans (.tjp files)
- `plantuml/` — Architecture diagrams (.puml files)
- Topic dirs (`elasticsearch/`, `wdqs/`, `maps/`, `mediawiki/`, etc.) — free-form .txt/.md notes
- `home/` — Personal home infrastructure notes (network, home-assistant, mealie)

## Key Commands and Tools

### Planning Files
- Render a project: `tj3 -o output/<project> planning/<project>.tjp` (from the `planning/` directory)
- Live-rebuild + publish loop: `planning/generate.sh`

### PlantUML Diagrams
- Render ad-hoc: `plantuml path/to/diagram.puml`
- Multiple @startuml/@enduml blocks in one file produce multiple output images

### Home Infrastructure
#### Network (home/network/)
- Raw device output lives in [dumps/](dumps/), collected with [dump-configs.sh](scripts/dump-configs.sh)
- Logs live in `logs/`, collected with [dump-logs.sh](scripts/dump-logs.sh)  
- Diagrams in [diagrams/](diagrams/) are generated with:
  - `dot -Tsvg network.dot -o network.svg` (physical topology)
  - `./render-nwdiag.py -T svg network-addressing.nwdiag -o network-addressing.svg` (VLAN/address plan)

#### Home Assistant (home/home-assistant/)
- Config sync: `scripts/sync.sh` pulls `/config` via rsync over SSH plus logs captures
- Raw config is never committed (gitignored) - only reviewed docs in tracked files

## Repository Structure Notes

- Most "work" here is editing text/markdown notes, PlantUML diagrams, and TaskJuggler planning files
- Shell scripts are operational helpers run by a human against production hosts — assume they require credentials/SSH access
- The team roster in `planning/resources.tji` is the source of truth for resource identifiers used in `.tji` task allocations

## Key Conventions

- Notes are intentionally informal and often link to Phabricator tickets (https://phabricator.wikimedia.org/T...)
- Changes get logged to area-specific changelog.md files as they happen, not batched at the end
- Device names follow role-location scheme (`router`, `switch-<place>`, `ap-<place>`)
- Finding numbers are stable and never reused (<n> for main router, S<n> for switches/APs)
- Finding leaves review documents only when fixed AND verified against device output
- Every change to MikroTik devices gets logged to changelog.md as it happens (RouterOS logs can't distinguish sessions)

## Special Considerations

### Home Network (MikroTik)
- RouterOS has many quirks around command execution, firewall rule validation, and VLAN handling
- Safe mode discards everything if session drops - use scheduled auto-rollback for risky changes
- A per-device VLAN port move is two commands, not one (bridge-vlan table membership and pvid are independent)
- `set [find ...]` against an empty result is a silent no-op - always re-print after a set
- Firewall rule packet/byte counters are cumulative since creation and are not reset by set operations
- RouterOS's DNS server does not translate DHCP leases into DNS records natively

### Home Assistant
- Raw config directory is never committed (gitignored) - only reviewed/redacted docs derived from it
- Config sync script `scripts/sync.sh` requires SSH key configured in Advanced SSH & Web Terminal add-on
- HA sweeps entire services subnet with reverse-DNS lookups hourly - this appears in firewall logs

## Important Paths

- Planning files: `/planning/`
- Network infrastructure: `/home/network/`
- Home Assistant: `/home/home-assistant/`
- Architecture diagrams: `/plantuml/`