#!/usr/bin/env python3
"""Pull wine data from Vivino's site API for whole countries.

Phase 1: enumerate wineries per country  -> vivino_data/wineries_<cc>.json
Phase 2: pull each winery's wines        -> vivino_data/wines_<cc>.jsonl (checkpointed)

Resumable: rerunning skips wineries already present in the jsonl.
Merge into the app catalog is a separate script (vivino_merge.py) so the
bundled sqlite is only touched after the pull is inspected.

Usage: python3 vivino_pull.py cl ar
"""

import json
import subprocess
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

BASE = "https://www.vivino.com/api"
HEADERS = {
    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                  "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15",
    "Accept": "application/json",
    "Accept-Language": "en-US,en;q=0.9",
}
DATA_DIR = Path(__file__).parent / "vivino_data"
DELAY = 0.8          # seconds between requests
MAX_RETRIES = 3
MAX_CONSECUTIVE_FAILURES = 10


def get_json(url, consecutive_failures=[0]):
    # curl subprocess instead of urllib: a long-lived python process wedges in
    # SSL waits after Mac sleep/wake; a fresh curl per request cannot, and the
    # subprocess timeout hard-caps any hang
    for attempt in range(MAX_RETRIES):
        try:
            r = subprocess.run(
                ["curl", "-s", "--fail", "--max-time", "30",
                 "-A", HEADERS["User-Agent"],
                 "-H", "Accept: application/json",
                 "-H", "Accept-Language: en-US,en;q=0.9",
                 url],
                capture_output=True, timeout=40)
            if r.returncode != 0:
                raise RuntimeError(f"curl exit {r.returncode}")
            data = json.loads(r.stdout)
            consecutive_failures[0] = 0
            time.sleep(DELAY)
            return data
        except Exception as e:
            wait = 15 * (attempt + 1)
            print(f"  error on {url}: {e} - retry in {wait}s", flush=True)
            time.sleep(wait)
    consecutive_failures[0] += 1
    if consecutive_failures[0] >= MAX_CONSECUTIVE_FAILURES:
        print(f"aborting: {MAX_CONSECUTIVE_FAILURES} consecutive failures", flush=True)
        sys.exit(1)
    return None


def fetch_wineries(cc):
    """All wineries for a country code, cached to disk."""
    cache = DATA_DIR / f"wineries_{cc}.json"
    if cache.exists():
        wineries = json.loads(cache.read_text())
        print(f"[{cc}] wineries cached: {len(wineries)}", flush=True)
        return wineries

    wineries = {}
    page = 1
    expected = None
    while True:
        qs = urllib.parse.urlencode({"country_codes[]": cc, "page": page})
        d = get_json(f"{BASE}/wineries?{qs}")
        if d is None:
            page += 1
            continue
        if expected is None:
            expected = d.get("records_matched")
            print(f"[{cc}] wineries expected: {expected}", flush=True)
        matches = d.get("matches") or []
        if not matches:
            break
        for m in matches:
            wineries[m["id"]] = {
                "id": m["id"],
                "name": m["name"],
                "seo_name": m.get("seo_name"),
                "wines_count": (m.get("statistics") or {}).get("wines_count", 0),
            }
        if page % 20 == 0:
            print(f"[{cc}] winery page {page}, collected {len(wineries)}", flush=True)
        page += 1
        if expected and len(wineries) >= expected:
            break

    result = list(wineries.values())
    cache.write_text(json.dumps(result))
    print(f"[{cc}] wineries collected: {len(result)}", flush=True)
    return result


def fetch_wines(cc, wineries):
    out_path = DATA_DIR / f"wines_{cc}.jsonl"
    done = set()
    if out_path.exists():
        with out_path.open() as f:
            for line in f:
                try:
                    done.add(json.loads(line)["winery_id"])
                except (json.JSONDecodeError, KeyError):
                    pass
    print(f"[{cc}] wineries already pulled: {len(done)}/{len(wineries)}", flush=True)

    with out_path.open("a") as out:
        for i, w in enumerate(wineries):
            if w["id"] in done:
                continue
            # One request per winery: the endpoint ignores its page parameter
            # (every page returns the same rows) but honors big per_page values
            d = get_json(f"{BASE}/wineries/{w['id']}/wines?per_page=1000")
            wines = (d.get("wines") or []) if d else []
            if len(wines) == 1000:
                print(f"  warning: {w['name']} may exceed the 1000-wine request cap", flush=True)
            slim = []
            for x in wines:
                stats = x.get("statistics") or {}
                region = x.get("region") or {}
                country = (region.get("country") or {}) if isinstance(region, dict) else {}
                style = x.get("style") if isinstance(x.get("style"), dict) else {}
                slim.append({
                    "name": x.get("name"),
                    "winery": w["name"],
                    "type_id": x.get("type_id"),
                    "region": region.get("name") if isinstance(region, dict) else None,
                    "country": country.get("name"),
                    "country_code": country.get("code"),
                    "rating": stats.get("ratings_average"),
                    "ratings_count": stats.get("ratings_count"),
                    "variety": (style or {}).get("varietal_name"),
                    "body": (style or {}).get("body_description"),
                    "acidity": (style or {}).get("acidity_description"),
                    "natural": x.get("is_natural"),
                })
            out.write(json.dumps({"winery_id": w["id"], "winery": w["name"],
                                  "wines": slim}) + "\n")
            out.flush()
            if (len(done) + i) % 100 == 0:
                print(f"[{cc}] winery {i + 1}/{len(wineries)}: {w['name']} "
                      f"({len(slim)} wines)", flush=True)
    print(f"[{cc}] wines pull complete -> {out_path}", flush=True)


def main():
    codes = [c.lower() for c in sys.argv[1:]] or ["cl"]
    DATA_DIR.mkdir(exist_ok=True)
    for cc in codes:
        wineries = fetch_wineries(cc)
        fetch_wines(cc, wineries)
    print("ALL DONE", flush=True)


if __name__ == "__main__":
    main()
