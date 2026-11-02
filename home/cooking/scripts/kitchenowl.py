#!/usr/bin/env python3
"""Sync home/cooking with the family's KitchenOwl household.

Usage:
  ./kitchenowl.py pull                    # read-only snapshot into ../kitchenowl/
  ./kitchenowl.py sync-recipes [--apply] [--adopt] [recipe.md ...]
  ./kitchenowl.py sync-plan [--apply] [--prune]
  ./kitchenowl.py shop [--apply] (YYYY-MM-DD | recipe.md) ...

The recipes are in French, to match the household's French item catalog.
Each line under "## Ingrédients" is one item:

  - Article : quantité, précisions
  - Article : quantité, précisions (facultatif)
  - Article

"Article" must be the exact name of a catalog item (case does not matter),
otherwise KitchenOwl creates a new item. The sync-recipes dry run marks
these lines "NEW ITEM". An item can appear in several sub-groups of a
recipe. The script merges these lines into one item, because KitchenOwl
keeps only one entry per item in a recipe.

sync-recipes pushes recipes/*.md into KitchenOwl. A recipe it creates has
`source` set to "notes-home:home/cooking/recipes/<file>". Next runs find the
recipe by that marker and update it in place. KitchenOwl replaces the whole
ingredient list on update, so a second run gives the same result. A
KitchenOwl recipe with the same name but no marker was made by hand in the
app: it is skipped, unless --adopt says to take it over. The description
holds the "Étapes", "Notes" and "Historique" sections.

sync-plan pushes planning.md to the KitchenOwl planner. Each "## YYYY-MM-DD"
heading is a day. Each link to recipes/*.md under it is a recipe planned
on that day. The script finds each recipe by its `source` marker, or else
by its name (for a recipe made in the app). KitchenOwl's planner has days,
not meals, and no notes: the rest of each line stays local. sync-plan adds
the missing entries. It lists the KitchenOwl entries that are not in
planning.md, between its first and last day, and removes them only with
--prune. It ignores the entries outside that range.

shop adds the non-optional ingredients of recipes to the default shopping
list, without the items in PANTRY and the items already on the list. Give
recipe files, or days of planning.md: a day gives all its recipes, except
the meals marked "(restes)".

The write commands only print what they would do, unless --apply is given.

Environment:
  KITCHENOWL_TOKEN      long-lived token (required). Inside the nono
                        sandbox it comes from the keyring entry
                        `service nono username kitchenowl_token`.
  KITCHENOWL_BASE_URL   default https://app.kitchenowl.org
  KITCHENOWL_HOUSEHOLD  household id. Default: the only household.

Python standard library only.
"""

import argparse
import datetime as dt
import json
import os
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

COOKING = Path(__file__).resolve().parent.parent
RECIPES = COOKING / "recipes"
PLANNING = COOKING / "planning.md"
SNAPSHOT = COOKING / "kitchenowl"
SOURCE_PREFIX = "notes-home:home/cooking/recipes/"

# Always in stock: plan never puts these on the shopping list.
PANTRY = {name.casefold() for name in (
    "Eau", "Sel", "Poivre", "Sucre", "Huile", "Huile d'olive", "Vinaigre",
    "Cumin", "Curcuma", "Paprika", "Garam Masala", "Origan", "Noix de muscade",
)}


# --- HTTP -------------------------------------------------------------------

class Api:
    def __init__(self):
        self.token = os.environ.get("KITCHENOWL_TOKEN")
        if not self.token:
            sys.exit("KITCHENOWL_TOKEN is not set.")
        base = os.environ.get("KITCHENOWL_BASE_URL", "https://app.kitchenowl.org")
        self.base = base.rstrip("/") + "/api"

    def call(self, method, path, body=None):
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(self.base + path, data=data, method=method)
        req.add_header("Authorization", "Bearer " + self.token)
        req.add_header("Accept", "application/json")
        if data is not None:
            req.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                raw = resp.read()
        except urllib.error.HTTPError as e:
            sys.exit(f"{method} {path}: HTTP {e.code} {e.read()[:300]!r}")
        return json.loads(raw) if raw else None

    def get(self, path):
        return self.call("GET", path)

    def post(self, path, body):
        return self.call("POST", path, body)

    def delete(self, path, body):
        return self.call("DELETE", path, body)

    def household(self):
        if os.environ.get("KITCHENOWL_HOUSEHOLD"):
            hid = int(os.environ["KITCHENOWL_HOUSEHOLD"])
            return next(h for h in self.get("/household") if h["id"] == hid)
        households = self.get("/household")
        if len(households) != 1:
            names = ", ".join(f"{h['id']}={h['name']}" for h in households)
            sys.exit(f"Several households ({names}): set KITCHENOWL_HOUSEHOLD.")
        return households[0]


# --- Markdown parsing -------------------------------------------------------

LINK = re.compile(r"\[([^\]]*)\]\([^)]*\)")
OPTIONAL = re.compile(r"\s*\(facultatif\)", re.IGNORECASE)


def plain(text):
    """Remove Markdown links and emphasis, keep the text."""
    text = LINK.sub(r"\1", text)
    return text.replace("**", "").replace("*", "")


def sections(md):
    """Split a Markdown file into {"## heading": [lines]}."""
    out, current = {}, None
    for line in md.splitlines():
        if line.startswith("## "):
            current = line[3:].strip()
            out[current] = []
        elif current:
            out[current].append(line)
    return out


def bullets(lines):
    """Join each "- " bullet with its indented continuation lines."""
    items = []
    for line in lines:
        if line.startswith("- "):
            items.append(line[2:].strip())
        elif line.startswith("  ") and items:
            items[-1] += " " + line.strip()
    return items


def parse_ingredient(text):
    """Parse "Article : quantité, précisions (facultatif)"."""
    text = plain(text).strip()
    optional = bool(OPTIONAL.search(text))
    text = OPTIONAL.sub("", text)
    name, _, description = (p.strip() for p in text.partition(":"))
    return {"name": name, "description": description, "optional": optional}


def merge_items(items):
    """Merge the lines that name the same item into one item."""
    merged = {}
    for item in items:
        key = item["name"].casefold()
        if key not in merged:
            merged[key] = dict(item)
            continue
        m = merged[key]
        m["description"] = " + ".join(d for d in (m["description"], item["description"]) if d)
        m["optional"] = m["optional"] and item["optional"]
    return list(merged.values())


DAY = re.compile(r"## (\d{4}-\d{2}-\d{2})\b")
RECIPE_LINK = re.compile(r"\]\(recipes/([^)]+\.md)\)")
LEFTOVERS = re.compile(r"\(restes\)", re.IGNORECASE)


def parse_planning(path=PLANNING):
    """Return {date: [(recipe file, leftovers?)]} from planning.md."""
    days, current = {}, None
    for line in path.read_text().splitlines():
        m = DAY.match(line)
        if m:
            current = dt.date.fromisoformat(m.group(1))
            days[current] = []
        elif line.startswith("## "):
            current = None
        elif current:
            days[current].append(line)
    out = {}
    for date, lines in days.items():
        out[date] = []
        for meal in bullets(lines):
            leftovers = bool(LEFTOVERS.search(meal))
            out[date] += [(name, leftovers) for name in RECIPE_LINK.findall(meal)]
    return out


def parse_recipe(path):
    md = path.read_text()
    title = next(l[2:].strip() for l in md.splitlines() if l.startswith("# "))
    secs = sections(md)
    items = merge_items(parse_ingredient(b) for b in bullets(secs.get("Ingrédients", [])))
    parts = []
    for heading in ("Étapes", "Notes", "Historique"):
        if heading in secs:
            body = "\n".join(secs[heading]).strip()
            parts.append(f"## {heading}\n\n{plain(body)}")
    header = [plain(b) for b in bullets(md.split("## ", 1)[0].splitlines())]
    if header:
        parts.insert(0, "\n".join("- " + h for h in header))
    return {
        "name": title,
        "description": "\n\n".join(parts),
        "source": SOURCE_PREFIX + path.name,
        "items": items,
    }


# --- Commands ---------------------------------------------------------------

def cmd_pull(api, args):
    h = api.household()
    hid, lid = h["id"], h["default_shopping_list"]["id"]
    SNAPSHOT.mkdir(exist_ok=True)
    data = {
        "household": h,
        "recipes": api.get(f"/household/{hid}/recipe"),
        "planner": api.get(f"/household/{hid}/planner"),
        "shoppinglists": api.get(f"/household/{hid}/shoppinglist"),
    }
    for name, value in data.items():
        (SNAPSHOT / f"{name}.json").write_text(
            json.dumps(value, ensure_ascii=False, indent=2) + "\n")
    print(f"Household {h['name']} ({hid}), language {h.get('language')}.")
    print(f"Recipes ({len(data['recipes'])}):")
    for r in sorted(data["recipes"], key=lambda r: r["name"]):
        mark = " [notes-home]" if (r.get("source") or "").startswith(SOURCE_PREFIX) else ""
        print(f"  {r['id']:>7}  {r['name']}{mark}")
    print("Planner:")
    for p in sorted(data["planner"], key=lambda p: p["cooking_date"]):
        day = dt.datetime.fromtimestamp(p["cooking_date"] / 1000, dt.timezone.utc).date()
        print(f"  {day}  {p['recipe']['name']}")
    for sl in data["shoppinglists"]:
        print(f"Shopping list {sl['name']} ({sl['id']}{', default' if sl['id'] == lid else ''}):")
        for i in sl.get("items", []):
            print(f"  {i['name']}" + (f" — {i['description']}" if i.get("description") else ""))
    print(f"Snapshot written to {SNAPSHOT}/")


def managed(recipes):
    return {r["source"][len(SOURCE_PREFIX):]: r for r in recipes
            if (r.get("source") or "").startswith(SOURCE_PREFIX)}


def cmd_sync_recipes(api, args):
    hid = api.household()["id"]
    existing = api.get(f"/household/{hid}/recipe")
    by_file = managed(existing)
    by_name = {r["name"].casefold(): r for r in existing}
    catalog = {i["name"].casefold() for i in api.get(f"/household/{hid}/item")}
    new_items = set()
    paths = [Path(p).resolve() for p in args.recipes] or sorted(RECIPES.glob("*.md"))
    for path in paths:
        recipe = parse_recipe(path)
        target = by_file.get(path.name)
        if not target and recipe["name"].casefold() in by_name:
            other = by_name[recipe["name"].casefold()]
            if not args.adopt:
                print(f"SKIP   {path.name}: KitchenOwl already has '{other['name']}' "
                      f"({other['id']}), made in the app. Use --adopt to replace it.")
                continue
            target = other
        verb = f"UPDATE {target['id']}" if target else "CREATE"
        print(f"{verb} {path.name} → '{recipe['name']}'")
        for i in recipe["items"]:
            opt = " (optional)" if i["optional"] else ""
            new = "" if i["name"].casefold() in catalog else "   ← NEW ITEM"
            if new:
                new_items.add(i["name"])
            print(f"         {i['name']}" + (f" — {i['description']}" if i["description"] else "")
                  + opt + new)
        if not args.apply:
            continue
        if target:
            api.post(f"/recipe/{target['id']}", recipe)
        else:
            api.post(f"/household/{hid}/recipe", recipe)
    if new_items:
        print(f"\nNot in the catalog yet, KitchenOwl creates them: {', '.join(sorted(new_items))}")
    if not args.apply:
        print("\nDry run. Run again with --apply to write.")


def quantity(description):
    """Keep only the quantity of each merged part ("2, râpées + ~500 g" → "2 + ~500 g").

    The quantity stops at the first ", " outside brackets. The rest is
    preparation, and the shopping list does not need it. "~6,5 dl" has no
    space after its comma, so it stays whole.
    """
    parts = []
    for part in description.split(" + "):
        depth = 0
        for i, c in enumerate(part):
            depth += (c == "(") - (c == ")")
            if depth == 0 and part.startswith(", ", i):
                part = part[:i]
                break
        parts.append(part.strip())
    return " + ".join(p for p in parts if p)


def midnight_ms(date):
    """KitchenOwl stores a planner day as milliseconds at UTC midnight."""
    return int(dt.datetime.combine(date, dt.time(), dt.timezone.utc).timestamp() * 1000)


def find_recipes(existing):
    """Return a function: recipe file name -> KitchenOwl recipe, or None."""
    by_file = managed(existing)
    by_name = {r["name"].casefold(): r for r in existing}

    def find(name):
        if name in by_file:
            return by_file[name]
        path = RECIPES / name
        return by_name.get(parse_recipe(path)["name"].casefold()) if path.exists() else None
    return find


def cmd_sync_plan(api, args):
    hid = api.household()["id"]
    find = find_recipes(api.get(f"/household/{hid}/recipe"))
    days = parse_planning()
    first, last = min(days), max(days)
    wanted, missing = {}, False
    for date, meals in sorted(days.items()):
        for name, _ in meals:
            recipe = find(name)
            if not recipe:
                print(f"{date}: {name} is not in KitchenOwl yet. Run sync-recipes first.")
                missing = True
                continue
            wanted[(recipe["id"], midnight_ms(date))] = (date, recipe["name"])
    if missing:
        sys.exit("Nothing written.")
    remote = {}
    outside = 0
    for p in api.get(f"/household/{hid}/planner"):
        date = dt.datetime.fromtimestamp(p["cooking_date"] / 1000, dt.timezone.utc).date()
        if first <= date <= last:
            remote[(p["recipe"]["id"], p["cooking_date"])] = (date, p["recipe"]["name"])
        else:
            outside += 1
    for key in sorted(wanted.keys() - remote.keys(), key=lambda k: k[1]):
        date, name = wanted[key]
        print(f"ADD    {date}  {name}")
        if args.apply:
            api.post(f"/household/{hid}/planner/recipe",
                     {"recipe_id": key[0], "cooking_date": key[1]})
    for key in sorted(remote.keys() - wanted.keys(), key=lambda k: k[1]):
        date, name = remote[key]
        if args.prune:
            print(f"REMOVE {date}  {name}")
            if args.apply:
                api.delete(f"/household/{hid}/planner/recipe/{key[0]}", {"cooking_date": key[1]})
        else:
            print(f"ONLY IN KITCHENOWL {date}  {name}: add it to planning.md, or use --prune.")
    print(f"{len(wanted.keys() & remote.keys())} entries already in sync, "
          f"{outside} outside {first}..{last} ignored.")
    if not args.apply:
        print("\nDry run. Run again with --apply to write.")


def cmd_shop(api, args):
    h = api.household()
    hid, lid = h["id"], h["default_shopping_list"]["id"]
    find = find_recipes(api.get(f"/household/{hid}/recipe"))
    names = []
    for arg in args.what:
        try:
            date = dt.date.fromisoformat(arg)
        except ValueError:
            names.append(Path(arg).name)
            continue
        meals = parse_planning().get(date)
        if meals is None:
            sys.exit(f"{date} is not in planning.md.")
        names += [name for name, leftovers in meals if not leftovers]
    on_list = {i["id"] for i in api.get(f"/shoppinglist/{lid}/items")}
    to_buy = {}
    for name in names:
        recipe = find(name)
        if not recipe:
            print(f"{name} is not in KitchenOwl yet. Run sync-recipes first.")
            continue
        print(f"Recipe '{recipe['name']}'.")
        for item in recipe["items"]:
            if (item["optional"] or item["id"] in on_list
                    or item["name"].casefold() in PANTRY):
                continue
            description = quantity(item.get("description") or "")
            if item["id"] in to_buy:
                # Used by several recipes: one list entry, all quantities.
                old = to_buy[item["id"]]["description"]
                to_buy[item["id"]]["description"] = " + ".join(d for d in (old, description) if d)
                continue
            to_buy[item["id"]] = {"id": item["id"], "name": item["name"],
                                  "description": description, "optional": False}
    if to_buy:
        print(f"Add to shopping list '{h['default_shopping_list']['name']}':")
        for i in to_buy.values():
            print(f"  {i['name']}" + (f" — {i['description']}" if i["description"] else ""))
        if args.apply:
            api.post(f"/shoppinglist/{lid}/recipeitems", {"items": list(to_buy.values())})
    else:
        print("Nothing to add.")
    if not args.apply:
        print("\nDry run. Run again with --apply to write.")


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("pull", help="read-only snapshot into ../kitchenowl/")
    p = sub.add_parser("sync-recipes", help="push recipes/*.md to KitchenOwl")
    p.add_argument("recipes", nargs="*", help="recipe files (default: all)")
    p.add_argument("--apply", action="store_true", help="write (default: dry run)")
    p.add_argument("--adopt", action="store_true",
                   help="replace a same-name recipe that was made in the app")
    p = sub.add_parser("sync-plan", help="push planning.md to the KitchenOwl planner")
    p.add_argument("--apply", action="store_true", help="write (default: dry run)")
    p.add_argument("--prune", action="store_true",
                   help="remove the planner entries that are not in planning.md")
    p = sub.add_parser("shop", help="put ingredients on the shopping list")
    p.add_argument("what", nargs="+", help="YYYY-MM-DD days of planning.md, or recipe files")
    p.add_argument("--apply", action="store_true", help="write (default: dry run)")
    args = parser.parse_args()
    commands = {"pull": cmd_pull, "sync-recipes": cmd_sync_recipes, "sync-plan": cmd_sync_plan,
                "shop": cmd_shop}
    commands[args.command](Api(), args)


if __name__ == "__main__":
    main()
