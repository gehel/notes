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
- **Kitchen:** rice cooker, bread machine — homemade bread doesn't tie up the oven.
- **Guillaume's diet: no carbs in the evening.** Everyone else does eat carbs. So a
  typical dinner is a shared low-carb main (protein + veg) that everyone eats, plus a carb
  side that only France and the kids eat. Guillaume makes up the missing volume with extra
  protein and cooked vegetables, not with a second dish to cook.
- **Guillaume wants plenty of vegetables at dinner** — beyond what's in a sauce. He almost
  never eats salad, so a cooked vegetable side is the default, not a green salad.
- **Not super strict:** it's about starches (pasta, spätzli, bread, potatoes, rice). Sweeter
  veg like beetroot are fine on his plate.
- Lunch has no carb restriction.

## Weekly rhythm

Recurring slots that constrain what to cook (from 2026-11-02). Days not listed: no known
constraint yet.

| Slot | Who's there | What it needs |
| --- | --- | --- |
| Mon lunch | Guillaume alone with the kids; France back later | Quick, and reheats well for France |
| Mon dinner | Guillaume eats before his Kendo lesson | Not too heavy |
| Tue lunch | Guillaume and France eat at a restaurant | Nothing to plan |
| Tue dinner | Guillaume alone with the kids; France works late | A portion kept for France |

*(Unknown: whether France eats at home after working late on Tuesday — the plans keep a
portion aside just in case.)*

## Layout

- `recipes/` — one file per dish, in French, reusable across meals (e.g. halloumi poêlé goes
  with more than spätzli). Each file says whether it fits Guillaume's evening plate
  (**Assiette du soir de Guillaume**), and whether it's **version de Guillaume** or still a
  **recette de base générique** waiting to be replaced by how he actually makes it.
- [meal-log.md](meal-log.md) — dated log of what was cooked, with how it went, in French. The
  raw material for learning what the family likes and for suggesting future meals. Upcoming
  meals go in too, marked *(prévu)*, and become regular entries once cooked.
- `scripts/kitchenowl.py` — syncs with the family's KitchenOwl household ("Cap 21" on
  app.kitchenowl.org, French catalog). `pull` writes a read-only snapshot to `kitchenowl/`
  (gitignored). `sync-recipes` and `plan` (planner + shopping list from the *(prévu)* meal-log
  entries) are dry runs unless given `--apply`. The token is `KITCHENOWL_TOKEN`. Inside the
  sandbox it comes from the keyring (`secret-tool … service nono username kitchenowl_token`).
  The script's header holds the details, including `PANTRY`: the staples (salt, oil, dried
  spices…) that `plan` never puts on the shopping list.

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
| [Polenta](recipes/polenta.md) | No — starch | Baseline |
| [Ragoût de champignons, poireau et épinards](recipes/ragout-champignons.md) | Yes (add a protein) | Baseline |
| [Poulet au beurre](recipes/poulet-au-beurre.md) | Yes (without the rice) | Baseline |
| [Saumon au four et brocoli](recipes/saumon-brocoli.md) | Yes | Baseline |
| [Boulettes de viande à la sauce tomate](recipes/boulettes-sauce-tomate.md) | Yes (without the pasta) | Baseline |

## Conventions

- **Recipes and the meal log are in French** (since 2026-11-02), to match the KitchenOwl
  household's French item catalog. This README stays in English. Recipe file names are
  French slugs of the title, ASCII only.
- **One ingredient per line, `Article : quantité, précisions`**, e.g.
  `- Carottes : ~500 g, en bâtonnets`. `Article` is the exact name of a catalog item (it's
  matched ignoring case, but not accents: the catalog spells it "Cèleri-rave"). The quantity
  comes first after the colon: `plan` keeps only that part (up to the first `, `) on the
  shopping list. Mark optional items `(facultatif)`. An item used in two sub-groups (garlic in
  the meatballs and in the sauce) can appear twice; the script merges the lines. Run
  `sync-recipes` without `--apply` to see which names would create new catalog items.
- Meal-log headings are `## YYYY-MM-DD (lun) — midi|soir`, plus `*(prévu)*` until cooked.
  Planned entries list the recipes in an `**Au menu :**` line and become `**Cuisiné :**`
  once cooked. "midi"/"soir" rather than "dîner"/"souper", which mean different meals in
  Switzerland and in France. A "reste" in the `Au menu` line keeps that meal's ingredients
  off the shopping list.
- When Guillaume describes how he makes a dish, his version replaces the baseline and the
  status flips to "version de Guillaume". Never present a baseline as his recipe.
- Quantities are for the whole family unless stated otherwise; carb sides are sized for the
  people who eat them (not Guillaume).
- Log every meal cooked to `meal-log.md` with family feedback when there is any — "kids
  wouldn't touch it" is worth recording.

## Lessons

*(Empty so far — things learned the hard way about cooking for this family go here.)*
