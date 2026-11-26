#!/usr/bin/env python3
"""Download OpenStreetMap data for the game map from the Overpass API.

Usage: python3 fetch_osm.py <output-dir>

Writes roads.json, buildings_*.json, areas.json, lines.json and pois.json.
The map covers Fishers, Indiana and the edges of Carmel, Noblesville,
McCordsville and Lawrence. Map data (c) OpenStreetMap contributors, ODbL.
"""
import json
import os
import sys
import time
import urllib.parse
import urllib.request

# south, west, north, east
BBOX = (39.875, -86.165, 40.070, -85.905)
SERVERS = ["https://overpass.kumi.systems/api/interpreter",
           "https://overpass-api.de/api/interpreter",
           "https://overpass.private.coffee/api/interpreter"]


FAILED = []


def bbox_str(b):
    return f"{b[0]},{b[1]},{b[2]},{b[3]}"


def run(query, path):
    if os.path.exists(path) and os.path.getsize(path) > 100:
        print("have", path)
        return
    body = urllib.parse.urlencode({"data": query}).encode()
    last = None
    for attempt in range(4):
        url = SERVERS[attempt % len(SERVERS)]
        try:
            print("fetch", os.path.basename(path), "from", url, flush=True)
            req = urllib.request.Request(url, data=body, headers={
                "User-Agent": "fishers-game-map-builder/1.0"})
            with urllib.request.urlopen(req, timeout=400) as r:
                data = r.read()
            json.loads(data)  # validate
            with open(path, "wb") as f:
                f.write(data)
            print("  ok", len(data) // 1024, "KB", flush=True)
            return
        except Exception as e:  # noqa: BLE001
            last = e
            print("  failed:", e, flush=True)
            time.sleep(5 + attempt * 5)
    print(f"could not fetch {os.path.basename(path)}: {last}", flush=True)
    FAILED.append(path)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "osm"
    os.makedirs(out, exist_ok=True)
    b = bbox_str(BBOX)
    run(f'[out:json][timeout:300];way["highway"]({b});out body geom qt;',
        os.path.join(out, "roads.json"))
    # Areas in four quarters so each request finishes before the server gives up.
    s0, w0, n0, e0 = BBOX
    for a in range(2):
        for c in range(2):
            qb = bbox_str((s0 + (n0 - s0) * a / 2, w0 + (e0 - w0) * c / 2,
                           s0 + (n0 - s0) * (a + 1) / 2, w0 + (e0 - w0) * (c + 1) / 2))
            run(f'''[out:json][timeout:300];
(
  way["natural"~"^(water|wood|scrub|wetland|grassland|beach|sand)$"]({qb});
  relation["natural"~"^(water|wood|wetland)$"]({qb});
  way["landuse"~"^(forest|farmland|meadow|grass|recreation_ground|cemetery|commercial|retail|industrial|reservoir|basin|orchard|farmyard|village_green|construction)$"]({qb});
  relation["landuse"~"^(forest|farmland|reservoir|basin|retail|commercial)$"]({qb});
  way["leisure"~"^(park|golf_course|pitch|playground|garden|nature_reserve|sports_centre|stadium|track|dog_park|swimming_pool)$"]({qb});
  relation["leisure"~"^(park|golf_course|nature_reserve)$"]({qb});
  way["amenity"~"^(parking|school)$"]({qb});
  way["water"]({qb});
  relation["water"]({qb});
);
out tags geom qt;''', os.path.join(out, f"areas_{a}{c}.json"))
    run(f'''[out:json][timeout:300];
(
  way["waterway"~"^(river|stream|canal|drain|ditch)$"]({b});
  way["railway"~"^(rail|abandoned|disused)$"]({b});
);
out tags geom qt;''', os.path.join(out, "lines.json"))
    run(f'''[out:json][timeout:300];
(
  node["name"]["amenity"]({b});
  node["name"]["shop"]({b});
  node["name"]["tourism"]({b});
  node["name"]["leisure"]({b});
  node["name"]["place"]({b});
  node["name"]["historic"]({b});
  way["name"]["amenity"]({b});
  way["name"]["shop"]({b});
  way["name"]["tourism"]({b});
  way["name"]["leisure"]({b});
  way["name"]["building"]({b});
  way["name"]["landuse"~"retail|commercial"]({b});
  relation["name"]["leisure"]({b});
  relation["name"]["tourism"]({b});
  relation["name"]["natural"="water"]({b});
  node["amenity"="bicycle_parking"]({b});
  way["amenity"="bicycle_parking"]({b});
);
out tags center qt;''', os.path.join(out, "pois.json"))
    # Buildings in a 3x3 grid; a cell that has not been fetched yet is
    # requested as four smaller pieces, which survive flaky connections better.
    s, w, n, e = BBOX
    k = 3
    for i in range(k):
        for j in range(k):
            whole = os.path.join(out, f"buildings_{i}{j}.json")
            if os.path.exists(whole):
                print("have", whole)
                continue
            for a in range(2):
                for c in range(2):
                    sub = (s + (n - s) * (i + a / 2) / k, w + (e - w) * (j + c / 2) / k,
                           s + (n - s) * (i + (a + 1) / 2) / k, w + (e - w) * (j + (c + 1) / 2) / k)
                    run(f'[out:json][timeout:300];way["building"]({bbox_str(sub)});out tags geom qt;',
                        os.path.join(out, f"buildings_{i}{j}_{a}{c}.json"))


if __name__ == "__main__":
    main()
    if FAILED:
        raise SystemExit(f"{len(FAILED)} downloads failed; run again to retry them")
