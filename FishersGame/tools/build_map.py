#!/usr/bin/env python3
"""Turn the downloaded OpenStreetMap JSON into compact game map files.

Usage: python3 build_map.py <osm-dir> <out-dir>

Outputs (all little-endian, coordinates are int16 in half-metres from the
map origin, +x east, +z south):
  (each .bin below is written base64-encoded as <name>.b64.txt)
  roads.bin      road graph: nodes, then edges with polylines
  buildings.bin  building footprints with height and kind
  areas.bin      polygons (water, parks, woods, parking, fields ...)
  lines.bin      rivers, streams and rail lines
  meta.json      origin, bounds, street names, places and points of interest
"""
import glob
import json
import math
import os
import re
import struct
import sys

LAT0 = 39.9725
LON0 = -86.035
KX = 111320.0 * math.cos(math.radians(LAT0))
KZ = 110574.0
Q = 2.0  # units per metre


def proj(lat, lon):
    return ((lon - LON0) * KX, (LAT0 - lat) * KZ)


def q(v):
    v = int(round(v * Q))
    return max(-32767, min(32767, v))


# ---------------------------------------------------------------- geometry
def dp(pts, eps):
    """Douglas-Peucker simplification of an open polyline."""
    if len(pts) < 3:
        return pts
    keep = [False] * len(pts)
    keep[0] = keep[-1] = True
    stack = [(0, len(pts) - 1)]
    while stack:
        a, b = stack.pop()
        ax, az = pts[a]
        bx, bz = pts[b]
        dx, dz = bx - ax, bz - az
        ll = dx * dx + dz * dz
        best, bi = -1.0, -1
        for i in range(a + 1, b):
            px, pz = pts[i]
            if ll == 0:
                d = math.hypot(px - ax, pz - az)
            else:
                t = ((px - ax) * dx + (pz - az) * dz) / ll
                t = max(0.0, min(1.0, t))
                d = math.hypot(px - (ax + t * dx), pz - (az + t * dz))
            if d > best:
                best, bi = d, i
        if best > eps:
            keep[bi] = True
            stack.append((a, bi))
            stack.append((bi, b))
    return [p for p, k in zip(pts, keep) if k]


def ring_area(pts):
    s = 0.0
    n = len(pts)
    for i in range(n):
        x1, z1 = pts[i]
        x2, z2 = pts[(i + 1) % n]
        s += x1 * z2 - x2 * z1
    return s / 2.0


def clean_ring(pts, eps):
    if len(pts) > 1 and pts[0] == pts[-1]:
        pts = pts[:-1]
    if len(pts) < 3:
        return None
    # simplify as a closed loop: split at the farthest point from the start
    far = max(range(len(pts)), key=lambda i: (pts[i][0] - pts[0][0]) ** 2 + (pts[i][1] - pts[0][1]) ** 2)
    a = dp(pts[:far + 1], eps)
    b = dp(pts[far:] + [pts[0]], eps)
    out = a[:-1] + b[:-1]
    # drop repeated points after quantising
    res = []
    for p in out:
        qp = (q(p[0]), q(p[1]))
        if not res or res[-1] != qp:
            res.append(qp)
    if len(res) > 1 and res[0] == res[-1]:
        res.pop()
    if len(res) < 3:
        return None
    return res


def geom_pts(geometry):
    return [proj(g["lat"], g["lon"]) for g in geometry if g]


def assemble_rings(ways):
    """Join open member ways into closed rings."""
    rings = []
    open_ = []
    for w in ways:
        if len(w) < 2:
            continue
        if w[0] == w[-1]:
            rings.append(w)
        else:
            open_.append(list(w))
    while open_:
        cur = open_.pop()
        changed = True
        while changed and cur[0] != cur[-1]:
            changed = False
            for i, w in enumerate(open_):
                if close(w[0], cur[-1]):
                    cur += w[1:]
                elif close(w[-1], cur[-1]):
                    cur += w[::-1][1:]
                elif close(w[-1], cur[0]):
                    cur = w[:-1] + cur
                elif close(w[0], cur[0]):
                    cur = w[::-1][:-1] + cur
                else:
                    continue
                open_.pop(i)
                changed = True
                break
        if len(cur) >= 4:
            rings.append(cur)
    return rings


def close(a, b):
    return abs(a[0] - b[0]) < 0.05 and abs(a[1] - b[1]) < 0.05


def point_in_ring(p, ring):
    x, z = p
    inside = False
    n = len(ring)
    j = n - 1
    for i in range(n):
        xi, zi = ring[i]
        xj, zj = ring[j]
        if (zi > z) != (zj > z) and x < (xj - xi) * (z - zi) / (zj - zi + 1e-12) + xi:
            inside = not inside
        j = i
    return inside


# ---------------------------------------------------------------- roads
ROAD_TYPES = {
    "motorway": 1, "motorway_link": 2, "trunk": 3, "trunk_link": 4,
    "primary": 5, "primary_link": 6, "secondary": 7, "secondary_link": 8,
    "tertiary": 9, "tertiary_link": 10, "residential": 11, "unclassified": 12,
    "living_street": 13, "service": 14, "track": 15,
    "footway": 16, "path": 16, "cycleway": 16, "pedestrian": 16, "steps": 16,
    "bridleway": 16,
}


def build_roads(osm, names, name_idx):
    with open(os.path.join(osm, "roads.json")) as f:
        data = json.load(f)
    ways = []
    use = {}
    coords = {}
    for el in data["elements"]:
        if el.get("type") != "way":
            continue
        tags = el.get("tags", {})
        t = ROAD_TYPES.get(tags.get("highway"))
        if not t:
            continue
        if tags.get("area") == "yes":
            continue
        if tags.get("access") in ("private", "no") and t not in (14, 16):
            pass
        nodes = el.get("nodes", [])
        geom = el.get("geometry", [])
        if len(nodes) != len(geom) or len(nodes) < 2:
            continue
        for nid, g in zip(nodes, geom):
            if g:
                coords[nid] = proj(g["lat"], g["lon"])
        if any(n not in coords for n in nodes):
            continue
        flags = 0
        ow = tags.get("oneway")
        if tags.get("junction") in ("roundabout", "circular"):
            flags |= 1 | 8
        if ow in ("yes", "1", "true") or t in (1, 2):
            flags |= 1
        if ow == "-1":
            flags |= 1
            nodes = nodes[::-1]
        if ow == "no":
            flags &= ~1
        if tags.get("bridge") not in (None, "no"):
            flags |= 2
        if tags.get("tunnel") not in (None, "no"):
            flags |= 4
        if tags.get("footway") in ("sidewalk", "crossing"):
            flags |= 16
        if tags.get("service") == "driveway":
            flags |= 32
        if tags.get("service") in ("parking_aisle", "drive-through"):
            flags |= 64
        nm_l = (tags.get("name") or "").lower()
        if t == 16 and (tags.get("highway") == "cycleway" or "trail" in nm_l or tags.get("bicycle") == "designated"):
            flags |= 128  # paved trail / bike path
        nm = tags.get("name") or tags.get("ref") or ""
        ways.append((t, flags, nm, nodes))
        for i, n in enumerate(nodes):
            use[n] = use.get(n, 0) + (2 if i in (0, len(nodes) - 1) else 1)
    graph_nodes = {}
    node_list = []

    def gid(n):
        if n not in graph_nodes:
            graph_nodes[n] = len(node_list)
            x, z = coords[n]
            node_list.append((q(x), q(z)))
        return graph_nodes[n]

    edges = []
    for t, flags, nm, nodes in ways:
        ni = name_idx(nm)
        start = 0
        for i in range(1, len(nodes)):
            if i == len(nodes) - 1 or use.get(nodes[i], 0) > 1:
                seg = nodes[start:i + 1]
                pts = [coords[n] for n in seg]
                pts = dp(pts, 0.6 if t < 16 else 1.0)
                qp = []
                for p in pts:
                    v = (q(p[0]), q(p[1]))
                    if not qp or qp[-1] != v:
                        qp.append(v)
                if len(qp) >= 2:
                    a, b = gid(seg[0]), gid(seg[-1])
                    if a != b or len(qp) > 2:
                        edges.append((t, flags, ni, a, b, qp))
                start = i
    out = bytearray()
    out += struct.pack("<I", len(node_list))
    for x, z in node_list:
        out += struct.pack("<hh", x, z)
    out += struct.pack("<I", len(edges))
    for t, flags, ni, a, b, pts in edges:
        out += struct.pack("<BBHIIH", t, flags, ni, a, b, len(pts))
        for x, z in pts:
            out += struct.pack("<hh", x, z)
    print("roads:", len(node_list), "nodes", len(edges), "edges", len(out) // 1024, "KB")
    return bytes(out)


# ---------------------------------------------------------------- buildings
HOUSE = {"house", "detached", "semidetached_house", "bungalow", "terrace", "residential", "yes_house"}


def building_kind(tags):
    b = tags.get("building", "yes")
    amen = tags.get("amenity", "")
    if b in HOUSE:
        return 1
    if b in ("apartments", "dormitory", "hotel"):
        return 2
    if b in ("commercial", "retail", "office", "supermarket", "kiosk", "store", "mall") or tags.get("shop"):
        return 3
    if b in ("industrial", "warehouse", "manufacture", "hangar", "data_center"):
        return 4
    if b in ("school", "university", "college", "public", "civic", "government", "library", "fire_station",
             "kindergarten") or amen in ("school", "library", "townhall", "fire_station", "police"):
        return 5
    if b in ("church", "chapel", "cathedral", "religious", "mosque", "synagogue", "temple") or amen == "place_of_worship":
        return 6
    if b in ("garage", "garages", "shed", "carport", "roof", "hut", "cabin", "storage_tank", "greenhouse",
             "parking", "service", "transformer_tower"):
        return 7
    if b in ("hospital",) or amen in ("hospital", "clinic"):
        return 8
    if b in ("farm", "barn", "farm_auxiliary", "stable", "silo", "cowshed"):
        return 9
    if b in ("stadium", "sports_hall", "sports_centre", "grandstand"):
        return 10
    return 0


def parse_height(tags):
    h = tags.get("height")
    if h:
        m = re.match(r"[\d.]+", h)
        if m:
            try:
                v = float(m.group(0))
                if "ft" in h or "'" in h:
                    v *= 0.3048
                return v
            except ValueError:
                pass
    lv = tags.get("building:levels")
    if lv:
        m = re.match(r"[\d.]+", lv)
        if m:
            try:
                return float(m.group(0)) * 3.3 + 0.5
            except ValueError:
                pass
    return 0.0


def build_buildings(osm):
    out = bytearray(b"\0\0\0\0")
    n = 0
    seen = set()
    for path in sorted(glob.glob(os.path.join(osm, "buildings_*.json"))):
        with open(path) as f:
            data = json.load(f)
        for el in data["elements"]:
            if el.get("type") != "way" or el["id"] in seen:
                continue
            seen.add(el["id"])
            tags = el.get("tags", {})
            if tags.get("building") in ("no", "construction", "proposed", "demolished"):
                continue
            if tags.get("location") == "underground":
                continue
            pts = geom_pts(el.get("geometry", []))
            ring = clean_ring(pts, 0.35)
            if not ring:
                continue
            area = abs(ring_area(ring)) / (Q * Q)
            if area < 7:
                continue
            if ring_area(ring) < 0:  # make winding consistent (clockwise in x/z = CCW seen from above)
                ring = ring[::-1]
            if len(ring) > 400:
                ring = ring[:400]
            h = parse_height(tags)
            hq = max(0, min(255, int(round(h * 2))))
            kind = building_kind(tags)
            out += struct.pack("<BBH", hq, kind, len(ring))
            for x, z in ring:
                out += struct.pack("<hh", x, z)
            n += 1
    struct.pack_into("<I", out, 0, n)
    print("buildings:", n, len(out) // 1024, "KB")
    return bytes(out)


# ---------------------------------------------------------------- areas
def area_kind(tags):
    nat = tags.get("natural", "")
    lu = tags.get("landuse", "")
    le = tags.get("leisure", "")
    am = tags.get("amenity", "")
    if nat == "water" or lu in ("reservoir", "basin") or "water" in tags or le == "swimming_pool":
        return 15 if le == "swimming_pool" else 1
    if nat == "wood" or lu in ("forest", "orchard"):
        return 2
    if le == "golf_course":
        return 4
    if le in ("pitch", "track", "stadium"):
        return 18 if le == "track" else 5
    if le == "playground":
        return 12
    if le in ("park", "garden", "nature_reserve", "dog_park") or lu in ("recreation_ground", "village_green"):
        return 3
    if lu in ("farmland", "meadow"):
        return 6
    if lu == "grass" or nat == "grassland":
        return 19
    if am == "parking":
        return 7
    if lu in ("commercial", "retail"):
        return 8
    if lu == "industrial":
        return 9
    if lu == "cemetery":
        return 10
    if am == "school":
        return 11
    if nat in ("wetland", "scrub"):
        return 13
    if nat in ("beach", "sand"):
        return 14
    if lu == "construction":
        return 16
    if lu == "farmyard":
        return 17
    if le == "sports_centre":
        return 5
    return 0


def load(osm, name):
    path = os.path.join(osm, name)
    if not os.path.exists(path):
        print("missing", name, "- skipping")
        return {"elements": []}
    with open(path) as f:
        return json.load(f)


def build_areas(osm):
    seen = set()
    elements = []
    for path in sorted(glob.glob(os.path.join(osm, "areas*.json"))):
        with open(path) as f:
            for el in json.load(f)["elements"]:
                key = (el["type"], el["id"])
                if key not in seen:
                    seen.add(key)
                    elements.append(el)
    data = {"elements": elements}
    polys = []
    for el in data["elements"]:
        tags = el.get("tags", {})
        kind = area_kind(tags)
        if not kind:
            continue
        eps = 0.6 if kind in (7, 15, 5, 12, 18) else 1.5
        if el["type"] == "way":
            pts = geom_pts(el.get("geometry", []))
            if len(pts) < 4 or not close(pts[0], pts[-1]):
                continue
            r = clean_ring(pts, eps)
            if r:
                polys.append((kind, [r]))
        elif el["type"] == "relation":
            outers, inners = [], []
            for m in el.get("members", []):
                if m.get("type") != "way" or "geometry" not in m:
                    continue
                pts = geom_pts(m["geometry"])
                (inners if m.get("role") == "inner" else outers).append(pts)
            outer_rings = [clean_ring(r, eps) for r in assemble_rings(outers)]
            inner_rings = [clean_ring(r, eps) for r in assemble_rings(inners)]
            inner_rings = [r for r in inner_rings if r]
            for o in outer_rings:
                if not o:
                    continue
                holes = [h for h in inner_rings if point_in_ring(h[0], o)]
                polys.append((kind, [o] + holes[:200]))
    out = bytearray(struct.pack("<I", len(polys)))
    for kind, rings in polys:
        out += struct.pack("<BB", kind, min(255, len(rings)))
        for r in rings[:255]:
            r = r[:65000]
            out += struct.pack("<H", len(r))
            for x, z in r:
                out += struct.pack("<hh", x, z)
    print("areas:", len(polys), len(out) // 1024, "KB")
    return bytes(out)


# ---------------------------------------------------------------- lines
def build_lines(osm):
    data = load(osm, "lines.json")
    items = []
    for el in data["elements"]:
        if el.get("type") != "way":
            continue
        tags = el.get("tags", {})
        ww = tags.get("waterway")
        rw = tags.get("railway")
        if tags.get("tunnel") in ("culvert", "yes"):
            continue
        if ww == "river":
            kind, w = 1, 30
        elif ww == "stream":
            kind, w = 2, 3
        elif ww == "canal":
            kind, w = 3, 8
        elif ww in ("drain", "ditch"):
            kind, w = 4, 2
        elif rw == "rail":
            kind, w = 5, 3
        elif rw in ("abandoned", "disused"):
            kind, w = 6, 3
        else:
            continue
        pts = dp(geom_pts(el.get("geometry", [])), 1.0)
        qp = []
        for p in pts:
            v = (q(p[0]), q(p[1]))
            if not qp or qp[-1] != v:
                qp.append(v)
        if len(qp) >= 2:
            items.append((kind, w, qp))
    out = bytearray(struct.pack("<I", len(items)))
    for kind, w, pts in items:
        out += struct.pack("<BBH", kind, w, len(pts))
        for x, z in pts:
            out += struct.pack("<hh", x, z)
    print("lines:", len(items), len(out) // 1024, "KB")
    return bytes(out)


# ---------------------------------------------------------------- pois
def build_pois(osm):
    data = load(osm, "pois.json")
    pois = []
    places = []
    seen = set()
    for el in data["elements"]:
        tags = el.get("tags", {})
        name = tags.get("name")
        if not name:
            continue
        if el["type"] == "node":
            lat, lon = el["lat"], el["lon"]
        else:
            c = el.get("center")
            if not c:
                continue
            lat, lon = c["lat"], c["lon"]
        x, z = proj(lat, lon)
        if tags.get("place") and el["type"] == "node":
            places.append([name, tags["place"], round(x, 1), round(z, 1)])
            continue
        kind = ""
        for k in ("amenity", "shop", "tourism", "leisure", "historic", "natural", "landuse", "building"):
            if k in tags:
                kind = f"{k}={tags[k]}"
                break
        key = (name, round(x / 30), round(z / 30))
        if key in seen:
            continue
        seen.add(key)
        pois.append([name, kind, round(x, 1), round(z, 1)])
    print("pois:", len(pois), "places:", len(places))
    return pois, places


def main():
    osm, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    names = [""]
    index = {"": 0}

    def name_idx(nm):
        if nm not in index:
            index[nm] = len(names)
            names.append(nm)
        return index[nm]

    files = {
        "roads.bin": build_roads(osm, names, name_idx),
        "buildings.bin": build_buildings(osm),
        "areas.bin": build_areas(osm),
        "lines.bin": build_lines(osm),
    }
    import base64
    for k, v in files.items():
        # stored as base64 text so any static host (including Claude artifacts) serves it
        with open(os.path.join(out, k.replace(".bin", ".b64.txt")), "wb") as f:
            f.write(base64.b64encode(v))
        old = os.path.join(out, k)
        if os.path.exists(old):
            os.remove(old)
    pois, places = build_pois(osm)
    if not any(p[1] in ("city", "town", "village") for p in places):
        # fallback town centres when place data is missing
        for name, lat, lon in [("Fishers", 39.9556, -86.0139), ("Carmel", 39.9784, -86.1180),
                               ("Noblesville", 40.0456, -86.0086), ("McCordsville", 39.9081, -85.9228),
                               ("Lawrence", 39.8387, -86.0253), ("Castleton", 39.9081, -86.0525),
                               ("Geist", 39.9356, -85.9497)]:
            x, z = proj(lat, lon)
            places.append([name, "town" if name in ("Castleton", "Geist") else "city", round(x, 1), round(z, 1)])
    s, w, n, e = 39.875, -86.165, 40.070, -85.905
    x0, z0 = proj(n, w)
    x1, z1 = proj(s, e)
    meta = {
        "origin": {"lat": LAT0, "lon": LON0, "kx": KX, "kz": KZ, "q": Q},
        "bounds": [round(x0), round(z0), round(x1), round(z1)],
        "names": names,
        "places": places,
        "pois": pois,
        "attribution": "Map data © OpenStreetMap contributors (ODbL)",
    }
    with open(os.path.join(out, "meta.json"), "w") as f:
        json.dump(meta, f, separators=(",", ":"), ensure_ascii=False)
    print("meta:", os.path.getsize(os.path.join(out, "meta.json")) // 1024, "KB")


if __name__ == "__main__":
    main()
