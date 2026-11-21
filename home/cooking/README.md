# Cooking

Recipe collection and meal planning for the family. Started 2026-10-29. Read this first — it
holds the household constraints every meal plan has to respect, and links everything else.

## Household

- **Who eats:** 4 people — Guillaume, his companion France, and two kids: Oscar (10) and
  Augustin (7). No allergies; the family eats pretty much anything.
- **No kids' menus.** The kids eat anything, so elaborate meals are fine — even when
  Guillaume cooks for just the kids.
- **Portions:** Oscar eats an adult portion (sometimes more); Augustin slightly less in some
  cases. E.g. halloumi on 2026-10-29: Augustin ~80 g, Oscar a full portion and then some.
  Size meals as ~3 adults plus Augustin, not 2 adults plus 2 kids.
- **Known tastes:** Augustin doesn't love halloumi, but accepts it pan-fried.
- **Everything is homemade** — spätzli, etc. Baselines should assume cooking from scratch,
  not bought shortcuts.
- **Kitchen:** rice cooker, bread machine, Actifry — homemade bread doesn't tie up the oven.
- **Guillaume's diet: no carbs in the evening.** Everyone else does eat carbs. So a
  typical dinner is a shared low-carb main (protein + veg) that everyone eats, plus a carb
  side that only France and the kids eat. Guillaume makes up the missing volume with extra
  protein and cooked vegetables, not with a second dish to cook.
- **Guillaume wants plenty of vegetables at dinner** — beyond what's in a sauce. He almost
  never eats salad, so a cooked vegetable side is the default, not a green salad.
- **Not super strict:** it's about starches (pasta, spätzli, bread, potatoes, rice). Sweeter
  veg like beetroot are fine on his plate. **Legumes count as starches**: beans (green beans
  included), peas, lentils, etc. — never the vegetable side on his plate.
- **Watch the fat on his plate too:** the butter chicken of 2026-11-04 (40 g butter, 1.5 dl
  cream) was good but a bit too fatty.
- Lunch has no carb restriction.
- **Plant-based proteins, at least from time to time** (asked 2026-11-05, for the planet):
  meal proposals should regularly offer a non-animal protein, not default to meat or fish.
  Beans and lentils can't fill that role on Guillaume's evening plate (see above), but they
  can at lunch. Tofu is fine on his evening plate (confirmed 2026-11-05), even though it's
  soy. *(Unknown: tempeh.)*
- **Vegetarian doesn't mean tofu** (2026-11-09): vary the meat-free meals instead of making
  tofu the default. For Guillaume's evening plate that means eggs (omelette, frittata,
  shakshuka), cheese (halloumi, feta, gratins without the starch), seitan, or a vegetable
  main with one of those as the protein. Legumes stay a lunch option.

## Weekly rhythm

Recurring slots that constrain what to cook (from 2026-11-02). Days not listed: no known
constraint yet.

| Slot | Who's there | What it needs |
| --- | --- | --- |
| Mon lunch | Guillaume alone with the kids; France back later | Quick, and reheats well for France |
| Mon dinner | Guillaume eats before his Kendo lesson | Not too heavy |
| Tue lunch | Guillaume and France eat at a restaurant | Nothing to plan |
| Tue dinner | Guillaume alone with the kids; France works late and eats at work | Cook for 3 — no portion for France (confirmed 2026-11-17) |

## Layout

- `recipes/` — one file per dish, in French, reusable across meals (e.g. halloumi poêlé goes
  with more than spätzli). Each file says whether it fits Guillaume's evening plate
  (**Assiette du soir de Guillaume**), and whether it's **version de Guillaume** or still a
  **recette de base générique** waiting to be replaced by how he actually makes it. A
  `## Historique` section at the end logs each time the dish was cooked, with how it went —
  the raw material for learning what the family likes and for suggesting future meals.
- [`planning.md`](planning.md) — the meal plan, past and upcoming, from 2026-10-29 on: one
  `## YYYY-MM-DD` heading per day, one line per meal (midi/soir), linking the recipes eaten.
  It is the source for KitchenOwl's planner, which only stores a recipe and a date — the
  lunch/dinner split and the notes stay in this file. Every side gets a recipe (even plain
  [pâtes](recipes/pates.md)), so that it lands on the planner; sausages and ham stay as text.
  (It replaced `meal-log.md`; the meal feedback moved into the recipes' `## Historique`.)
- `scripts/kitchenowl.py` — syncs with the family's KitchenOwl household ("Cap 21" on
  app.kitchenowl.org, French catalog). `pull` writes a read-only snapshot to `kitchenowl/`
  (gitignored). `sync-recipes` pushes `recipes/*.md`. `sync-plan` pushes `planning.md` to the
  planner; it lists the planner entries that aren't in the file and removes them only with
  `--prune`. `shop DATE|recipe.md…` puts ingredients on the shopping list (a day skips meals
  marked `*(restes)*`). The write commands are dry runs unless given `--apply`. The token is
  `KITCHENOWL_TOKEN`. Inside the sandbox it comes from the keyring
  (`secret-tool … service nono username kitchenowl_token`). The script's header holds the
  details, including `PANTRY`: the staples (salt, oil, dried spices…) that `plan` never puts
  on the shopping list.

## Recipes

| Recipe | Evening plate for Guillaume? | Status |
| --- | --- | --- |
| [Spätzli](recipes/spatzli.md) | No — carb side | Baseline |
| [Halloumi poêlé](recipes/halloumi-poele.md) | Yes | Baseline |
| [Betteraves rouges poêlées](recipes/betteraves-poelees.md) | Yes | Baseline |
| [Chou rouge aux lardons](recipes/chou-rouge-lardons.md) | Yes | Guillaume's version |
| [Riz](recipes/riz.md) | No — carb side | Guillaume's version (rice cooker) |
| [Courge rôtie au four](recipes/courge-rotie.md) | Yes | Baseline |
| [Spaghetti primavera](recipes/spaghetti-primavera.md) | No — pasta (lunch dish) | Baseline, steps incomplete |
| [Soupe de courge](recipes/soupe-courge.md) | Yes | Guillaume's version (coconut milk) |
| [Pain](recipes/pain.md) | No — carb side | Guillaume's version (bread machine) |
| [Poulet rôti aux légumes](recipes/poulet-roti-legumes.md) | Yes | Baseline |
| [Pommes de terre rôties](recipes/pommes-de-terre-roties.md) | No — carb side | Baseline |
| [Pommes de terre bouillies](recipes/pommes-de-terre-bouillies.md) | No — carb side | Baseline |
| [Pâtes](recipes/pates.md) | No — carb side (fine at lunch) | Baseline |
| [Polenta](recipes/polenta.md) | No — starch | Baseline |
| [Ragoût de champignons, poireau et épinards](recipes/ragout-champignons.md) | Yes (add a protein) | Baseline |
| [Poulet au beurre](recipes/poulet-au-beurre.md) | Yes (without the rice) | Baseline |
| [Saumon au four et brocoli](recipes/saumon-brocoli.md) | Yes | Baseline |
| [Cabillaud au four et brocoli](recipes/cabillaud-brocoli.md) | Yes | Baseline |
| [Boulettes de viande à la sauce tomate](recipes/boulettes-sauce-tomate.md) | Yes (without the pasta) | Baseline |
| [Tofu fumé rôti](recipes/tofu-fume-roti.md) | Yes | Baseline |
| [Choux de Bruxelles rôtis](recipes/choux-de-bruxelles-rotis.md) | Yes | Baseline |
| [Tarte aux poireaux](recipes/tarte-aux-poireaux.md) | No — pastry (lunch dish) | Guillaume's ingredients, baseline steps |
| [Hachis parmentier](recipes/hachis-parmentier.md) | Bolognese only, without the mash | Baseline (France cooks it) |
| [Tofu sauté aux légumes](recipes/tofu-saute-legumes.md) | Yes (without the rice) | Baseline |
| [Frittata aux poireaux, champignons et épinards](recipes/frittata-poireaux-champignons.md) | Yes | Baseline |
| [Carottes et chou-fleur rôtis](recipes/carottes-chou-fleur-rotis.md) | Yes | Baseline |
| [Poulet basquaise](recipes/poulet-basquaise.md) | Yes (without the bread) | Baseline |
| [Curry de paneer, épinards et chou-fleur](recipes/curry-paneer-epinards-chou-fleur.md) | Yes (without the rice) | Baseline |
| [Ailes de poulet à l'Actifry](recipes/ailes-de-poulet-actifry.md) | Yes | Baseline |

## Conventions

- **Recipes are in French** (since 2026-11-02), to match the KitchenOwl household's French
  item catalog. This README stays in English. Recipe file names are
  French slugs of the title, ASCII only.
- **One ingredient per line, `Article : quantité, précisions`**, e.g.
  `- Carottes : ~500 g, en bâtonnets`. `Article` is the exact name of a catalog item (it's
  matched ignoring case, but not accents: the catalog spells it "Cèleri-rave"). The quantity
  comes first after the colon: `plan` keeps only that part (up to the first `, `) on the
  shopping list. Mark optional items `(facultatif)`. An item used in two sub-groups (garlic in
  the meatballs and in the sauce) can appear twice; the script merges the lines. Run
  `sync-recipes` without `--apply` to see which names would create new catalog items.
- **Planning a meal:** add it to `planning.md`, then `sync-recipes --apply` for any new
  recipe, `sync-plan --apply`, and `shop DATE --apply` if it needs shopping. Run `pull` first:
  the family also edits the planner and the shopping list in the app. A planner change made
  in the app goes back into `planning.md` (or `sync-plan` re-adds what was removed).
- **Logging a meal once cooked:** add a line to each recipe's `## Historique`, as
  `- YYYY-MM-DD midi|soir — avec quoi. Bilan, retours de la famille.`, then
  `sync-recipes --apply`. If the meal changed from the plan, fix `planning.md` and
  `sync-plan --prune --apply`. "midi"/"soir"
  rather than "dîner"/"souper", which mean different meals in Switzerland and in France.
  Family feedback is always worth recording — "les enfants n'y ont pas touché" included.
- When Guillaume describes how he makes a dish, his version replaces the baseline and the
  status flips to "version de Guillaume". Never present a baseline as his recipe.
- Quantities are for the whole family unless stated otherwise; carb sides are sized for the
  people who eat them (not Guillaume).

## Lessons

*(Empty so far — things learned the hard way about cooking for this family go here.)*
