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
  **recette de base générique** waiting to be replaced by how he actually makes it. A
  `## Historique` section at the end logs each time the dish was cooked, with how it went —
  the raw material for learning what the family likes and for suggesting future meals.
- **KitchenOwl is the meal plan** (since 2026-11-02; the repo's `meal-log.md` was migrated
  into it and deleted — see git history for the original). Its planner holds what is eaten
  on which day, past and upcoming, from 2026-10-29 on. It only stores a recipe and a date: no
  lunch/dinner, no notes, no dishes without a recipe (sausages, ham, boiled potatoes, plain
  pasta). Run `pull` to read the current plan before planning or logging anything.
- `scripts/kitchenowl.py` — syncs with the family's KitchenOwl household ("Cap 21" on
  app.kitchenowl.org, French catalog). `pull` writes a read-only snapshot to `kitchenowl/`
  (gitignored). `sync-recipes` pushes `recipes/*.md`. `plan DATE recipe.md…` puts recipes on
  the planner and their ingredients on the shopping list (`--no-shopping` for leftovers or
  past meals). Both write commands are dry runs unless given `--apply`. The token is
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
| [Polenta](recipes/polenta.md) | No — starch | Baseline |
| [Ragoût de champignons, poireau et épinards](recipes/ragout-champignons.md) | Yes (add a protein) | Baseline |
| [Poulet au beurre](recipes/poulet-au-beurre.md) | Yes (without the rice) | Baseline |
| [Saumon au four et brocoli](recipes/saumon-brocoli.md) | Yes | Baseline |
| [Boulettes de viande à la sauce tomate](recipes/boulettes-sauce-tomate.md) | Yes (without the pasta) | Baseline |

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
- **Planning a meal:** `plan DATE recipe.md… --apply`, with `--no-shopping` when it uses
  leftovers. Sides with no recipe (boiled potatoes, pasta) aren't on the planner or the
  shopping list: say so when proposing the meal.
- **Logging a meal once cooked:** add a line to each recipe's `## Historique`, as
  `- YYYY-MM-DD midi|soir — avec quoi. Bilan, retours de la famille.`, then
  `sync-recipes --apply`. If the meal changed from the plan, fix the planner too. "midi"/"soir"
  rather than "dîner"/"souper", which mean different meals in Switzerland and in France.
  Family feedback is always worth recording — "les enfants n'y ont pas touché" included.
- When Guillaume describes how he makes a dish, his version replaces the baseline and the
  status flips to "version de Guillaume". Never present a baseline as his recipe.
- Quantities are for the whole family unless stated otherwise; carb sides are sized for the
  people who eat them (not Guillaume).

## Lessons

*(Empty so far — things learned the hard way about cooking for this family go here.)*
