---
marp: true
theme: default
paginate: true
title: "Values as Load-Bearing Architecture"
author: Guillaume Lederrey
---

<!--
Slides for "Values as Load-Bearing Architecture"
DevOpsDays Geneva 2027 — Guillaume Lederrey

Format: Marp markdown (https://marp.app/).
  - `---` (with blank lines around it) separates slides.
  - HTML comments are presenter/speaker notes (Marp presenter view).
  - One idea per slide; the words on screen are the headline, the notes carry the talk.
  - Render: `marp talks/wikipedia-infra-slides.md` (add --pdf / --pptx as needed).

Source outline: wikipedia-infra.md
-->

# Values as Load-Bearing Architecture

## What are the DevOps values?

Guillaume Lederrey · Wikimedia Foundation · DevOpsDays Geneva 2027

<!--
[ON SCREEN DURING THE MC INTRO — this slide is already working the room before I say a word.]

Narration:
"We're at DevOpsDays. We're all part of this movement — that's what brings us together. And it's a movement with strong values. What are they?"

Then genuinely turn to the room and invite answers. Take whatever comes — ten hands or zero — and reflect a couple back if they come.

Universal pivot (say this EVERY time, whether I got answers or silence — then flip to CAMS):
"Here's the funny thing about a movement built on strong values — most of us have never actually written them down. Someone did, back in 2010. They called it CAMS."

→ Slide 2: CAMS.
-->

---

# CAMS

**C**ulture · **A**utomation · **M**easurement · **S**haring

<!--
The payoff to the question. Flip to this right after "...they called it CAMS."

Coined ~2010 by John Willis & Damon Edwards. Talk through the four briefly — don't lecture:
- Culture — collaboration over silos; you build it, you run it.
- Automation — engineer away the toil.
- Measurement — you can't improve what you don't measure.
- Sharing — share tools, knowledge, feedback openly; e.g. blameless post-mortems.

(Some add an L for Lean → CALMS. Mention only if it comes up; not needed.)

[Slide footnote source: Willis & Edwards, 2010 — find canonical URL.]
-->

---

![h:500](assets/guillaume.jpg)

<!--
[TODO asset: a personal, un-corporate photo of me — ideally with the kids / the bass.]

The late intro — deliberately after CAMS, so it reads as a comedic beat, not a CV.

Narration:
"Sorry — I haven't actually introduced myself yet. I'm Guillaume. I have two kids, I live in Lausanne, and I'm trying to learn bass — I'm really bad at it."

Keep it light and self-deprecating. Don't mention work yet — that's the next slide.

→ Slide 4: the credential lands when the photo flips to the Wikipedia logo.
-->

---

![h:400](assets/wikipedia-logo.svg)

<!--
[TODO asset: Wikipedia (or WMF) logo. Marp has no fragments, so this is a separate slide —
the visual swap from my face to this logo IS the punchline.]

Narration (the turn):
"...I also happen to work as an engineering manager at the Wikimedia Foundation — the foundation responsible for the infrastructure behind Wikipedia — in the Data Platform Engineering group."

Let the logo do the work. Beat. Then move on toward the talk's real thesis.
-->

---

# One of the ~15 most-visited sites on Earth

~24B pageviews / month · ~800M unique devices for English Wikipedia

~2,000 servers · 7 datacenters · all on prem

<small>every one of these numbers is public — stats.wikimedia.org</small>

<!--
The "wow." Let the numbers hang. Mostly don't editorialize — except for
the two seeds planted below, which pay off later.

Numbers (sourced):
- Ranking: Similarweb ~#13. If pushed, be honest that Cloudflare Radar
  ranks us lower (~#54) — different methodology (Radar counts DNS
  traffic, not human visits). "~15" is safe across sources.
- ~24B pageviews/month — stats.wikimedia.org (#/all-projects).
- ~2,000 servers, 7 datacenters, all on prem — wikitech Data_centers.

SEED 1 — "unique devices, not people":
"You'll notice I said unique *devices*, not people. That's deliberate —
we don't track people. I can't tell you how many *people* read English
Wikipedia, because we built the measurement so that we can't follow a
person across visits. Hold that thought." → pays off shortly as the
first worked value→decision example (privacy).

SEED 2 — "all on prem":
Plant it quietly. Don't say "no cloud" yet — that's the §5 reveal. Just
let "all on prem" sit next to the scale and move on.

CLOSER — "every number is public":
The metrics invitation doubles as a Sharing (CAMS) callback and a
transparency seed: "I'm not asking you to take my word for any of this.
Go dig."

Beat, then: "...and that last number — devices, not people — is not an
accident. But to explain why, I have to start one level up." → vision.
-->

---

# "Imagine a world in which every single human being can freely share in the sum of all knowledge."

<small>— the Wikimedia vision</small>

<!--
The root. Everything else in this talk hangs off this one sentence — so
I read it slowly and I lean on one word.

Source: wikimediafoundation.org/who-we-are/vision/ (full statement ends
"That's our commitment." — kept off-screen so the first sentence
breathes; say it aloud if it lands).

Narration:
"This is the vision — not the mission, not a strategy doc, the vision.
Listen to the word in the middle: *freely*. Not 'can access.' Not 'are
allowed to.' *Freely.*"

Set up the derivation WITHOUT resolving it yet:
"A vision like this doesn't stay a poster on the wall. It generates
concrete values — and those values generate architecture. That's the
whole talk: watch a lofty sentence turn into a load-bearing decision.
Let's do the first one."

Do NOT tie back to device-counting here — that belongs on the next
slide, as a *consequence* of the value, not of the vision directly. The
arrow is vision → value (privacy) → decision (devices, not people).

PAYOFF LATER: this same sentence is where the hardest tension in the
talk lives — an AI summary is arguably the most efficient way ever built
to let a human "freely share in the sum of all knowledge," and it's also
an existential threat to how we operate. Plant nothing now; this quote
is the hook we come back to at the close.
-->

---

# "Freely" requires privacy.

You don't read freely if someone is watching.

→ so we count **devices**, not **people**

<!--
The first worked example: vision → value → decision. This is the pattern
the whole talk repeats, so land it cleanly here.

THE DERIVATION (say it as a chain, slowly):
"Go back to that word: freely. Picture what people actually look up — a
diagnosis, a religion they're questioning, a sexuality, a political
movement their government doesn't like. They only do that *freely* if
they trust that no one is recording who they are. So 'freely' in the
vision isn't a nice-to-have. It *requires* privacy. Privacy is what that
word means once it hits a database."

THE DECISION (pay off slide 5's seed):
"That's why, when I showed you 800 million unique *devices*, I didn't
say people. We built the measurement so that we *cannot* follow a person
across visits. We could collect more. We chose an architecture that
can't."

PEOPLE, NOT USERS (the values point under the wording):
"And notice I keep saying 'people,' not 'users.' 'Users' is the
vocabulary of engagement metrics — a number you grow. 'People' is the
vocabulary of service. We're not here to grow a user count; we're here
to serve people. The word came first, and the metric follows the word."

This is the template. Next values get the same treatment: name the value,
trace it to the vision, then show the architectural decision it forced.
-->

---

# So how *do* you count a device without identifying anyone?

The cookie stores exactly one thing:

# `14-Dec-2015`

<small>a date. no ID, no session, no name.</small>

<!--
Direct continuation of "devices, not people" — now show the mechanism.
The reveal is the punchline: the entire cookie is a date.

THE MECHANISM (WMF-Last-Access):
"We set a cookie called WMF-Last-Access, one per project. Here is its
complete contents." [point at the date] "That's it. The day you last
visited. No identifier, no session token, no name, nothing that points
back to you."

HOW COUNTING WORKS FROM JUST A DATE:
"On any given day, when a request comes in, we look at that date. If it's
older than today, this device hasn't been seen today — so we count it
once as a unique, and stamp today's date. No cookie at all? You still get
counted, through a careful statistical offset on the side. We never have
to know *who* you are to know *how many*."

LAND ON THE TENSION (this is the pivot into the next slide — say it out
loud here, don't give it its own slide):
"So that's the bargain we've struck. We want to protect the privacy of
the people who read Wikipedia — really protect it, down to the cookie.
But we ALSO need some understanding of our traffic: to spot abuse, to
A/B test, to validate that the work we ship actually helps. Those two
things pull in opposite directions. So how do we get the second one
without giving up the first?"

Sources:
- wikitech — Unique_Devices/Last_access_solution (mechanism).
- diff.wikimedia.org/2016/03/30/unique-devices-dataset/ (the public
  announcement of the dataset — good to cite live: the numbers are open,
  and here's the blog post that opened them).
On-screen date string is the real format from the docs.

→ slide 9 answers the question: edge uniques (WMF-Uniq) — A/B testing
  where the raw ID is never stored.
-->

---

# Yes — every browser gets a real unique ID.

We just never keep it.

> "The complete set of identifiers we've handed out
> is a mathematical concept.
> It does not exist as data."

<!--
The payoff to slide 8's question, and the climax of the privacy section.
Structure the narration as a fake-out: concede the scary part first,
then reveal the trick.

THE FAKE-OUT:
"Here's the part that sounds like I'm contradicting everything I just
said. We assign every single browser a real, unique, cryptographically
random identifier. It's a cookie called WMF-Uniq. It lasts about a year."
[let the room think 'gotcha — that's tracking']

THE TURN:
"...and we are architecturally incapable of building a profile from it.
Here's why. That cookie is only ever read at the CDN edge — the very
outer layer. The raw value is used, then discarded on the spot. It is
never written to a log, never stored in a database, never forwarded to
analytics. Nothing downstream ever sees it."

HOW A/B TESTING STILL WORKS:
"When an experiment needs to keep you in the same test group across
visits, it doesn't get your ID. It gets a one-way hash of (your ID + that
specific test's name). That hash only goes to the handful of people in
that one experiment, and only for as long as the experiment runs. A
different experiment computes a different hash — the two can't be linked.
So we get stable A/B groups, abuse detection, DDoS defense... and the
thread that would tie your visits together into a 'you' never exists
anywhere we could query."

THE QUOTE (on screen, tightened — exact wording in source):
Exact: "the full data set of all the raw unique identifiers we've handed
out to actual user agents is just a mathematical concept. It does not
exist as an actual collection of data." (wikitech — Edge_uniques)

RESOLVE THE TENSION, BACK TO THE TEMPLATE:
"That's the answer to the question I left you with. Privacy here was
never 'collect nothing.' It's: engineer the data path so that the
identity can't be reconstructed — not by an attacker, not by us, not by
a court order. The value didn't stay a policy. It became cryptography at
the edge. THAT is what load-bearing means."

Worth a mention if asked: it's HttpOnly (no JS access), not cross-domain
(doesn't follow you between projects), not required to read or edit, and
the whole thing is open-source Varnish VMOD code with keys rotated
annually.

Source: wikitech — Edge_uniques.
→ closes the privacy section. Next: second value (participation /
  "every single human being").
-->