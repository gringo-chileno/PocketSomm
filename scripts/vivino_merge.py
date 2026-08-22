#!/usr/bin/env python3
"""Merge pulled Vivino wines (vivino_data/wines_<cc>.jsonl) into the app's
bundled catalog (PocketSomm/Resources/wines_catalog.sqlite).

Skips rows already in the catalog by (name, winery), case-insensitive.
Run after vivino_pull.py finishes: python3 vivino_merge.py cl ar
"""

import json
import sqlite3
import sys
import unicodedata
from pathlib import Path

DATA_DIR = Path(__file__).parent / "vivino_data"
CATALOG = Path(__file__).parent.parent / "PocketSomm" / "Resources" / "wines_catalog.sqlite"

TYPE_MAP = {1: "Red", 2: "White", 3: "Sparkling", 4: "Rosé", 7: "Dessert", 24: "Dessert/Port"}

COUNTRY_NAME = {"cl": "Chile", "ar": "Argentina", "fr": "France", "it": "Italy", "es": "Spain"}

# Export countries only take established wines (rating above X with at least
# N ratings); home countries take everything so boutique menus still match
WINE_FILTERS = {"fr": (3.8, 50), "it": (3.8, 50), "es": (3.8, 50)}

# Longest-first so "Cabernet Sauvignon" wins over "Cabernet"
GRAPES = sorted([
    "Cabernet Sauvignon", "Cabernet Franc", "Sauvignon Blanc", "Pinot Noir",
    "Pinot Grigio", "Pinot Gris", "Chardonnay", "Merlot", "Syrah", "Shiraz",
    "Malbec", "Carmenere", "Carménère", "Carignan", "Cinsault", "Riesling",
    "Semillon", "Sémillon", "Viognier", "Torrontés", "Torrontes", "Moscatel",
    "Muscat", "Tempranillo", "Sangiovese", "Garnacha", "Grenache", "Mourvèdre",
    "Petit Verdot", "Petite Sirah", "Tannat", "Bonarda", "País", "Pais",
    "Albariño", "Albarino", "Gewürztraminer", "Zinfandel", "Nebbiolo",
    "Pedro Ximénez", "Pedro Jimenez", "Chenin Blanc", "Verdejo", "Pinot Blanc",
], key=len, reverse=True)


def fold(s):
    return "".join(c for c in unicodedata.normalize("NFD", s or "")
                   if unicodedata.category(c) != "Mn").lower()


def infer_variety(name):
    folded = fold(name)
    for g in GRAPES:
        if fold(g) in folded:
            return g
    return None


def main():
    codes = [c.lower() for c in sys.argv[1:]] or ["cl", "ar"]
    db = sqlite3.connect(CATALOG)
    cur = db.cursor()

    existing = set()
    for name, winery in cur.execute("SELECT name, winery FROM wines"):
        existing.add((fold(name), fold(winery or "")))
    print(f"catalog rows before: {len(existing)}")

    added = skipped_dup = skipped_bad = skipped_filter = 0
    for cc in codes:
        path = DATA_DIR / f"wines_{cc}.jsonl"
        if not path.exists():
            print(f"missing {path}, skipping")
            continue
        flt = WINE_FILTERS.get(cc)
        with path.open() as f:
            for line in f:
                rec = json.loads(line)
                for w in rec["wines"]:
                    name, winery = w.get("name"), w.get("winery")
                    if not name or not winery:
                        skipped_bad += 1
                        continue
                    if flt and ((w.get("rating") or 0) <= flt[0]
                                or (w.get("ratings_count") or 0) < flt[1]):
                        skipped_filter += 1
                        continue
                    key = (fold(name), fold(winery))
                    if key in existing:
                        skipped_dup += 1
                        continue
                    existing.add(key)
                    rating = w.get("rating") or None
                    if rating is not None and not (1 <= rating <= 5):
                        rating = None
                    # A rating built from a handful of opinions isn't a rating —
                    # keep the wine for menu matching, show a dash in the app
                    if (w.get("ratings_count") or 0) < 5:
                        rating = None
                    cur.execute(
                        "INSERT INTO wines (name, winery, variety, region, country,"
                        " vintage, rating, price, type, body, acidity, food_pairings)"
                        " VALUES (?,?,?,?,?,NULL,?,NULL,?,?,?,NULL)",
                        (name, winery,
                         w.get("variety") or infer_variety(name),
                         w.get("region"),
                         w.get("country") or COUNTRY_NAME.get(cc),
                         rating,
                         TYPE_MAP.get(w.get("type_id")),
                         w.get("body"), w.get("acidity")))
                    added += 1
    db.commit()
    total = cur.execute("SELECT COUNT(*) FROM wines").fetchone()[0]
    db.close()
    print(f"added {added}, duplicates skipped {skipped_dup}, bad rows {skipped_bad}, "
          f"filtered out {skipped_filter}")
    print(f"catalog rows after: {total}")


if __name__ == "__main__":
    main()
