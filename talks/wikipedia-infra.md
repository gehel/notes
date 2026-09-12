# Wikipedia Infrastructure: Values as Load-Bearing Architecture

**Event:** DevOpsDays Geneva 2027
**Length:** 45 minutes
**Audience:** European DevOpsDays - technically literate, culture-aware, skeptical of corporate fluff
**Speaker:** Guillaume Lederrey, SRE Manager, Data Platform Engineering, Wikimedia Foundation

## Thesis

Movement values (privacy, participation, community-driven decision-making, open source, transparency) and the technical values they generate (independence, boring tech, replicability) are not decoration on top of Wikipedia's infrastructure. They are *load-bearing*: the architecture would have to be fundamentally different — or not work at all — if those values were removed. This talk shows what that looks like in practice, where the load is hardest, and where we hold the values imperfectly.

## Talk arc

| # | Section | Time | Role |
|---|---|---|---|
| 0 | Hook: you already work value-driven (CAMS) | ~3 min | Connect |
| 1 | Opening: scale | ~8 min | Wow + orient |
| 2 | Data platform deep dive — privacy in practice | ~10 min | Value case study |
| 3 | Stressor: scrapers — we refuse Cloudflare | ~7 min | Load test #1 |
| 4 | Community as co-architect | ~5–7 min | Why we can refuse |
| 5 | Stressor: cloud-avoidance — we refuse AWS | ~7 min | Load test #2 |
| 6 | Replicability: dumps, Airflow, and what isn't copyable | ~6–7 min | Climax |
| 7 | Honesty close | ~2–3 min | Land |

---

## 0. Hook: you already work value-driven (CAMS) (~3 min)

**Goal:** Open on the audience, not on Wikipedia. Build connection in the first three minutes by reminding the room that they already operate in a value-driven environment — and that DevOps started as a values movement before it was a toolchain. This is a handshake, not a foundation; the talk doesn't rest on it.

**Beats:**
- Don't open on Wikipedia. Open on *them*: "Before I show you our stack, let's talk about yours."
- DevOps was a culture movement first. **CAMS** (John Willis & Damon Edwards, ~2010): **C**ulture, **A**utomation, **M**easurement, **S**haring — one quick gloss each. [^0]
- The point of naming it: CAMS are values about *how you work*. They're real, and they already shape your architecture — whether or not anyone decided that on purpose.
- Bridge: that's the lens for the next 40 minutes. Wikimedia layers a second kind of value on top — values about *what we're for* (privacy, participation, openness) — and those turn out to be load-bearing. Keep your own values in the back of your mind while I walk you through ours.

---

## 1. Opening: scale + architecture map (~8 min)

**Goal:** Establish that Wikimedia is serious infrastructure (load the gun), then give the audience a map so the rest of the talk has a frame.

**Beats:**
- Wikipedia ranks among the most-visited sites on the internet [^1]
- Traffic: pageviews per month / per second [^2]
- Topology: two primary DCs (eqiad, codfw) + caching POPs (esams, ulsfo, eqsin, drmrs) [^3]
- ~N physical servers, all owned [^4]
- Architecture map: edge caching → MediaWiki app layer → data layer → analytics / data platform. Point at the box we're going to spend the rest of the talk in.
- Speaker positioning: SRE manager for the data platform — that box right there. 5 engineers + 1 manager on the SRE side, supporting a larger Data Engineering / Data Science / Analyst org.

---

## 2. Data platform deep dive — privacy in practice (~10 min)

**Section thesis:** Most websites have a privacy policy. Wikimedia has privacy as an *architectural constraint*. Here's what that looks like in the data layer.

**Beats:**
- Movement value: reader privacy. We don't surveil readers — no ads, no behavioral personalization, no engagement-maximization metrics.
- Concrete consequences in the data platform:
  - **Data retention:** 90 days for non-aggregated event data, with documented exceptions for incident response and legal hold [^5]
  - **Minimal collection:** EventLogging sanitization at ingest [^6] (note: contrary to what one might assume, we do *not* do IP minimization — worth being precise about what we do and don't do, see open questions)
  - **A/B testing without cross-experiment tracking:** our experimentation platform deliberately does *not* maintain identifiers across experiments. Contrast with the industry norm where the same user-id threads every experiment in flight [^7]
  - **Tracking cookies:** what we set, what we read, what we ship is constrained by policy and code [^8]
  - **Annual privacy report:** we publish what we collected and what we did with it [^9]
- **Honest limit:** our experimentation platform runs on the *commercial* version of GrowthBook. The OSS edition didn't fit our needs at scale; we picked the trade-off and we're transparent about it.
- Why the data platform? It's where the privacy implications are strongest, where we differ most visibly from other websites at our scale, and (full disclosure) it's the team I run.

---

## 3. Stressor: scrapers — we refuse Cloudflare (~7 min)

**Section thesis:** The naive fix would compromise the privacy value. The architecture absorbs the load instead. *This is what "load-bearing" means.*

**Beats:**
- The stressor: scrapers and AI training crawlers are hammering us — request rates, bandwidth, donor-funded budget pressure, technical stability [^10]
- The obvious answer: put it all behind Cloudflare. Most of the internet does this.
- Why we refuse: Cloudflare would see every reader request. That breaks reader privacy. The value forbids the easy solution.
- What we do instead: own edge, traffic shaping, abuse detection, rate-limiting. Harder. More expensive in engineering time.
- **Transparency, with limits:** some post-mortems are kept private because publishing them tips off the scrapers. Transparency is a value *and* it has limits *for good reasons*. These aren't in tension — they're both downstream of the same set of values.
- Financial framing: every TB the scrapers consume is donor money spent serving a non-reader.

---

## 4. Community as co-architect (~5–7 min)

**Section thesis:** Volunteer community is not a user-base. It's part of the production system — including its code path. That changes the security model and the decision model.

**Beats:**
- The RFC process: architecture decisions happen on public Phabricator, with community participation [^11]
- **Volunteer-owned MediaWiki extensions deployed in production:** community members write and maintain code that runs in our hot path. Code review and security review on our side, but the *ownership* sits with them, not us [^12]
- AI summaries as an example of listening: part of the community is reticent toward AI; we adjusted what we shipped and how [^13]
- Why this matters for the rest of the talk: community is *why* we can refuse Cloudflare and refuse AWS. We're not the only ones holding up the system. The community shares the load.

---

## 5. Stressor: cloud-avoidance — we refuse AWS (~7 min)

**Section thesis:** Same shape as scrapers. The naive fix would compromise the independence value. We eat the complexity ourselves.

**Beats:**
- The stressor: everyone our size runs on AWS / GCP / Azure. We don't.
- The obvious answer: migrate.
- Why we refuse — independence from external providers, with reasons stacked:
  - **Privacy:** third-party processors see traffic and metadata.
  - **Reliability:** no vendor between us and the production system.
  - **Sustainability:** no lock-in, predictable cost curve aligned with donations rather than with a vendor's pricing roadmap.
  - **Sovereignty:** not subject to a single vendor's policy decisions.
- What it costs us: own DCs, own metal, own network ops, slower than buying-a-managed-service for any given problem.
- Why we can afford to: **boring tech.** We choose components we can run for 20 years. Long upgrade cycles, conservative choices, no chasing the new shiny thing [^14]
- The honest framing: this is *more expensive in engineering time* than cloud. We've decided that's the right trade-off. We are aware it might not be the right trade-off forever.

---

## 6. Replicability: dumps, Airflow, and what isn't copyable (~6–7 min)

**Section thesis:** Open everything = anyone could rebuild Wikipedia. No one has. The thing you can't fork is the part that matters.

**Beats:**
- What we publish:
  - **Wikipedia dumps:** full XML of every article, every edit, every revision, generated on a regular schedule [^15]
  - **The Airflow pipeline managing dumps generation** — itself worth a technical aside. At our scale, producing consistent dumps is a real engineering problem [^16]
  - **Code:** MediaWiki, our Puppet, our configuration, our infrastructure-as-code [^17]
  - **Kiwix:** offline Wikipedia for low-connectivity contexts, built by a separate organization using our dumps. A concrete proof-of-reuse [^18]
- **Why we publish:** to keep ourselves honest. If WMF stops being a good steward of free knowledge, *someone else can pick this up*. Replicability is a check on us.
- **The punchline:** despite all of this — open code, public dumps, third-party-runnable architecture — no one has built a competing Wikipedia. The code isn't the moat. The infrastructure isn't the moat. **The community is the moat.** That's the part you can't fork.
- Implication: community-driven is the deepest value on the list, because it's the only one we can't replace with engineering effort. Everything else in this talk is downstream of having a community that shows up.

---

## 7. Honesty close (~2–3 min)

We refuse cloud — but we use commercial GrowthBook.
We're transparent — but we hide post-mortems from scrapers.
We don't track readers — but we set some cookies because the alternative is broken.
We are community-driven — but a small team in San Francisco still makes a lot of calls.

We hold these values *imperfectly*. The architecture doesn't deliver them perfectly. The OSS commitment isn't perfectly OSS. The community isn't perfectly in charge.

What we do have is the willingness to make those trade-offs *visible* — written down, code-reviewed in public, filed on Phabricator, named in the place where the value bent.

So that's the actual takeaway: your stack already has values baked in. The honest question isn't *whether* — it's whether you put them there on purpose, and whether you can name the places they bend.

---

## Citations / sources

| # | Claim | Source / candidate                                   | Status                     |
|---|---|------------------------------------------------------|----------------------------|
| 0 | CAMS (DevOps values) | John Willis & Damon Edwards, 2010 DevOps culture posts | gap — find canonical URL   |
| 1 | Wikipedia ranking by traffic | Similarweb #13 / Cloudflare Radar #54    | done                       |
| 2 | Pageviews per month/second | https://stats.wikimedia.org/                         | gap — pull specific figure |
| 3 | Data centers + caching POPs | https://wikitech.wikimedia.org/wiki/Data_centers     | gap — verify current list  |
| 4 | Server count | wikitech / SRE landing                               | gap                        |
| 5 | 90-day retention policy | https://foundation.wikimedia.org/wiki/Policy:Privacy_policy | gap — exact URL            |
| 6 | EventLogging sanitization | wikitech EventLogging docs                           | gap                        |
| 7 | A/B testing without cross-experiment IDs | internal architecture doc / public RFC if any        | gap                        |
| 8 | Cookie policy | Foundation cookie statement                          | gap                        |
| 9 | Annual privacy report | https://wikimediafoundation.org/about/transparency/  | gap                        |
| 10 | Scraper / AI crawler impact | WMF blog posts on AI scraping (2024–2026)            | gap                        |
| 11 | RFC process | wikitech RFC documentation                           | gap                        |
| 12 | Community-owned extensions in prod | concrete examples to pick (1–2 names)                | gap                        |
| 13 | AI-summaries community response | WMF / community discussion thread                    | gap                        |
| 14 | Boring tech / data stack choices | internal architecture doc                            | gap                        |
| 15 | Wikipedia dumps | https://dumps.wikimedia.org/                         | gap — confirm              |
| 16 | Airflow pipeline for dumps | internal / wikitech                                  | gap                        |
| 17 | Public Puppet / Gerrit | https://gerrit.wikimedia.org/                        | gap                        |
| 18 | Kiwix | https://kiwix.org/                                   | gap                        |

---

## Open questions / things to revisit

- Specific Airflow anecdote for section 6 (the technically interesting bit)
- Concrete community-owned extension names for section 4 (need 1–2 well-known ones)
- Whether to include a slide on the data platform's technical stack (Hadoop, Spark, etc.) in section 2 or section 5
- Speaker bio framing — formal title vs. "I'm an SRE who…"
- Visual style — reuse existing PlantUML diagrams in `/plantuml/` for the architecture map?
- Section 5: do we name a specific cloud RFP / migration evaluation we ran (if any are public)?
- Pacing pass: if 45 min runs short, where to cut first? (Suggest: section 5 → 5 min by collapsing the "stacked reasons" list)
- **Section 2 — what data minimization actually exists.** We don't do IP minimization. So what *do* we do, precisely? Be careful not to overclaim. Candidates to verify: EventLogging schema-level allowlists, retention boundaries, geographic aggregation in published stats, anonymization in the dumps. Need a definitive list before the talk.
- **GrowthBook decision deep-dive.** The talk currently treats it as a one-line honest caveat. Worth digging into the actual decision: what OSS options were evaluated, what made GrowthBook commercial win, what privacy guarantees we got contractually, what we'd switch to if those changed. May warrant a sidebar slide rather than just a name-check.
- **Mission statement + AI-summaries tension (structural).** The WMF mission — *"Imagine a world in which every single human being can freely share in the sum of all knowledge. That's our commitment."* — needs to be quoted somewhere early (probably opening, between scale and architecture map, as the frame all values derive from). It also introduces a real tension currently underplayed in the talk: **AI summaries are arguably the most efficient way ever invented to "share in the sum of all knowledge" — and they hurt our operations** (load, attribution, funding model, community engagement). Per the mission, AI summary providers are *succeeding at our goal*. Per operations, they are an existential threat. That tension is currently buried inside section 4 as a community-listening example. Options to reconsider:
  - (i) Add a mission-quote slide in section 1, surface the tension explicitly there, then let section 3 (scrapers) and section 4 (community) inherit it as backdrop. *Lightest touch.*
  - (ii) Promote AI summaries from "example inside community section" to a third stressor: "we are stressed by something that is *successfully accomplishing our stated mission* — what does that mean for us?" Structurally bigger; would need to cut elsewhere.
  - (iii) Make the mission + AI-tension the *closing frame* instead of (or in addition to) the "community is the moat" punchline — turning the talk's question into "what do you owe a mission that's bigger than your organization?"
  - Decision deferred — flag for next drilling pass.