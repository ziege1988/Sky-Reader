#!/usr/bin/env python3
"""
Sky Reader – Katalog-Generator.

Lädt die astronomischen Rohkataloge und erzeugt daraus die kompakten Dateien,
die Sky Reader offline mitliefert (Resources/Catalogs):

  stars.bin          Sternkatalog fuer das Plate Solving (Tycho-2 + HYG, bis ~11.5 mag)
  dso.json           Deep-Sky-Objekte (OpenNGC, LDN, Barnard, Sharpless, LBN, vdB, Cederblad)
  comets.txt         Bahnelemente der Kometen (Minor Planet Center, CometEls.txt)
  moon_craters.json  Benannte Mondkrater (IAU/USGS Gazetteer of Planetary Nomenclature)

Jede Quelle ist optional: schlaegt ein Download fehl, wird eine Warnung ausgegeben
und – falls vorhanden – die bisherige Datei beibehalten.

Aufruf:
  python3 Tools/build_catalogs.py --out Resources/Catalogs [--cache .catalog-cache] [--source-dir DIR]

Lizenzen / Quellen:
  OpenNGC (CC BY-SA 4.0, Mattia Verga), HYG v4.1 (CC BY-SA 4.0, astronexus),
  Tycho-2 (Hog et al. 2000, CDS I/259), LDN (Lynds 1962, VII/7A), Barnard (VII/220A),
  Sharpless (VII/20), LBN (VII/9), vdB (VII/21), Cederblad (VII/231),
  MPC CometEls, USGS Gazetteer of Planetary Nomenclature.
"""
import argparse
import csv
import gzip
import io
import json
import math
import os
import struct
import sys
import time
import urllib.request
import zipfile

UA = "SkyReader-catalog-builder/1.0"

OPENNGC = "https://raw.githubusercontent.com/mattiaverga/OpenNGC/master/database_files/{}"
HYG = "https://raw.githubusercontent.com/astronexus/HYG-Database/main/hyg/CURRENT/hygdata_v41.csv"
TYCHO = "https://cdsarc.cds.unistra.fr/ftp/I/259/tyc2.dat.{:02d}.gz"
VIZIER = ("https://vizier.cds.unistra.fr/viz-bin/asu-tsv?-source={}&-out.all"
          "&-out.add=_RAJ2000,_DEJ2000&-oc.form=d&-out.max=unlimited")
COMETS = "https://www.minorplanetcenter.net/iau/MPCORB/CometEls.txt"
CRATERS_SHP = "https://planetarynames.wr.usgs.gov/shapefiles/MOON_nomenclature_center_pts.zip"


def log(*a):
    print("[catalogs]", *a, flush=True)


def fetch(url, cache, name, source_dir=None, timeout=120, retries=3):
    """Download with simple caching. Returns bytes or None."""
    if source_dir:
        p = os.path.join(source_dir, name)
        if os.path.exists(p):
            with open(p, "rb") as f:
                return f.read()
    if cache:
        os.makedirs(cache, exist_ok=True)
        p = os.path.join(cache, name)
        if os.path.exists(p) and os.path.getsize(p) > 0:
            with open(p, "rb") as f:
                return f.read()
    last = None
    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=timeout) as r:
                data = r.read()
            if cache:
                with open(os.path.join(cache, name), "wb") as f:
                    f.write(data)
            return data
        except Exception as e:  # noqa
            last = e
            time.sleep(2 * (attempt + 1))
    log(f"WARNUNG: Download fehlgeschlagen {url}: {last}")
    return None


# --------------------------------------------------------------------------- helpers

def hms_to_deg(s):
    h, m, sec = s.split(":")
    return (float(h) + float(m) / 60 + float(sec) / 3600) * 15.0


def dms_to_deg(s):
    sign = -1 if s.strip().startswith("-") else 1
    d, m, sec = s.strip().lstrip("+-").split(":")
    return sign * (float(d) + float(m) / 60 + float(sec) / 3600)


def fnum(v):
    try:
        if v is None:
            return None
        v = str(v).strip()
        if v == "":
            return None
        return float(v)
    except ValueError:
        return None


# --------------------------------------------------------------------------- stars

def load_hyg(data):
    stars = []
    named = []
    rdr = csv.DictReader(io.StringIO(data.decode("utf-8", "replace")))
    for row in rdr:
        if row["id"] == "0":
            continue  # Sonne
        mag = fnum(row["mag"])
        ra = fnum(row["ra"])
        dec = fnum(row["dec"])
        if mag is None or ra is None or dec is None:
            continue
        stars.append((ra * 15.0, dec, mag))
        if row.get("proper") and mag < 3.5:
            named.append({"name": row["proper"], "ra": round(ra * 15.0, 5),
                          "dec": round(dec, 5), "mag": mag})
    log(f"HYG: {len(stars)} Sterne")
    return stars, named


def load_tycho(cache, source_dir, maxmag):
    stars = []
    for i in range(20):
        raw = fetch(TYCHO.format(i), cache, f"tyc2.dat.{i:02d}.gz", source_dir, timeout=300)
        if raw is None:
            log("Tycho-2 unvollstaendig – wird uebersprungen")
            return []
        text = gzip.decompress(raw).decode("ascii", "replace")
        for line in text.splitlines():
            f = line.split("|")
            if len(f) < 26:
                continue
            ra = fnum(f[2]) if f[2].strip() else fnum(f[24])
            dec = fnum(f[3]) if f[3].strip() else fnum(f[25])
            bt = fnum(f[17])
            vt = fnum(f[19])
            if ra is None or dec is None:
                continue
            if vt is not None and bt is not None:
                mag = vt - 0.090 * (bt - vt)
            elif vt is not None:
                mag = vt
            elif bt is not None:
                mag = bt - 0.5
            else:
                continue
            if mag <= maxmag:
                stars.append((ra, dec, mag))
        log(f"Tycho-2 Teil {i:02d}: gesamt {len(stars)}")
    return stars


def merge_stars(tycho, hyg, maxmag):
    if not tycho:
        return sorted([s for s in hyg if s[2] <= maxmag], key=lambda s: s[1])
    # HYG-Sterne nur ergaenzen, wenn kein Tycho-Stern innerhalb 30" liegt (helle Sterne fehlen in Tycho-2 teils)
    grid = {}
    cell = 0.05
    for (ra, dec, mag) in tycho:
        grid.setdefault((int(dec / cell), int(ra / cell)), []).append((ra, dec))
    added = 0
    out = list(tycho)
    for (ra, dec, mag) in hyg:
        if mag > 8.0:
            continue
        key = (int(dec / cell), int(ra / cell))
        found = False
        for dd in (-1, 0, 1):
            for dr in (-1, 0, 1):
                for (r2, d2) in grid.get((key[0] + dd, key[1] + dr), []):
                    if abs(d2 - dec) < 0.0084 and abs((r2 - ra) * math.cos(math.radians(dec))) < 0.0084:
                        found = True
                        break
        if not found:
            out.append((ra, dec, mag))
            added += 1
    log(f"Merge: {added} helle HYG-Sterne ergaenzt")
    out.sort(key=lambda s: s[1])
    return out


def write_stars(path, stars):
    with open(path, "wb") as f:
        f.write(b"SRST")
        f.write(struct.pack("<II", 1, len(stars)))
        for (ra, dec, mag) in stars:
            f.write(struct.pack("<ffh", ra % 360.0, dec, int(round(max(-30.0, min(30.0, mag)) * 1000))))
    log(f"stars.bin: {len(stars)} Sterne, {os.path.getsize(path) / 1e6:.1f} MB")


# --------------------------------------------------------------------------- deep sky

TYPE_MAP = {
    "OCl": "openCluster", "GCl": "globularCluster", "Cl+N": "clusterNebula", "*Ass": "association",
    "G": "galaxy", "GPair": "galaxyGroup", "GTrpl": "galaxyGroup", "GGroup": "galaxyGroup",
    "PN": "planetaryNebula", "HII": "emissionNebula", "EmN": "emissionNebula", "Neb": "nebula",
    "RfN": "reflectionNebula", "SNR": "supernovaRemnant", "DrkN": "darkNebula", "Nova": "nova",
}


def pretty_openngc(name):
    for pre, lab in (("NGC", "NGC "), ("IC", "IC "), ("Mel", "Mel "), ("Cl", "Cr "), ("B", "B "),
                     ("C", "C "), ("H", "H ")):
        if name.startswith(pre) and name[len(pre):len(pre) + 1].isdigit():
            num = name[len(pre):]
            core = num.lstrip("0") or "0"
            return lab + core
    return name


def load_openngc(ngc, add):
    objs = []
    for data in (ngc, add):
        if data is None:
            continue
        rdr = csv.DictReader(io.StringIO(data.decode("utf-8", "replace")), delimiter=";")
        for row in rdr:
            t = TYPE_MAP.get(row["Type"])
            if t is None or not row["RA"] or not row["Dec"]:
                continue
            name = row["Name"]
            if name.startswith(("ESO", "PGC", "UGC", "HCG", "MWSC")):
                continue
            ident = pretty_openngc(name)
            if ident.startswith("C "):
                continue  # Caldwell-Eintraege sind Duplikate
            aliases = []
            if row["M"]:
                aliases.append("M " + row["M"].lstrip("0"))
            if row["Identifiers"]:
                for a in row["Identifiers"].split(","):
                    a = a.strip()
                    if a.startswith(("LBN ", "SH 2-", "LDN ", "B ", "Cr ", "Mel ", "vdB ", "C ")):
                        aliases.append(a.replace("SH 2-", "Sh2-"))
            mag = fnum(row["V-Mag"]) or fnum(row["B-Mag"])
            z = fnum(row["Redshift"])
            o = {
                "id": ident, "aliases": aliases, "type": t,
                "ra": round(hms_to_deg(row["RA"]), 5), "dec": round(dms_to_deg(row["Dec"]), 5),
                "maj": fnum(row["MajAx"]), "min": fnum(row["MinAx"]), "pa": fnum(row["PosAng"]),
                "mag": mag, "con": row["Const"],
                "common": row["Common names"] or None,
                "hubble": row["Hubble"] or None,
                "z": z, "src": "OpenNGC",
            }
            objs.append(o)
    log(f"OpenNGC: {len(objs)} Objekte")
    return objs


def parse_vizier_tsv(data):
    """Parse VizieR asu-tsv output (possibly multiple tables). Returns largest table as list of dicts."""
    tables = []
    cur = None
    state = 0
    for line in data.decode("utf-8", "replace").splitlines():
        if line.startswith("#"):
            continue
        if not line.strip():
            if cur:
                tables.append(cur)
            cur = None
            state = 0
            continue
        if state == 0:
            cur = {"cols": [c.strip() for c in line.split("\t")], "rows": []}
            state = 1
        elif state == 1:
            state = 2  # Einheiten
        elif state == 2:
            state = 3  # ----
        else:
            vals = line.split("\t")
            cur["rows"].append(dict(zip(cur["cols"], [v.strip() for v in vals])))
    if cur:
        tables.append(cur)
    if not tables:
        return []
    best = max(tables, key=lambda t: len(t["rows"]))
    log(f"  Spalten: {best['cols']}")
    return best["rows"]


def first(row, *keys):
    for k in keys:
        if k in row and row[k] != "":
            return row[k]
    return None


def load_vizier_catalog(cache, source_dir, source, fname, builder):
    raw = fetch(VIZIER.format(source), cache, fname, source_dir, timeout=300)
    if raw is None:
        return []
    rows = parse_vizier_tsv(raw)
    out = []
    for r in rows:
        ra = fnum(first(r, "_RAJ2000", "RAJ2000"))
        dec = fnum(first(r, "_DEJ2000", "DEJ2000"))
        if ra is None or dec is None:
            continue
        o = builder(r, ra, dec)
        if o:
            out.append(o)
    log(f"{source}: {len(out)} Objekte")
    return out


def build_ldn(r, ra, dec):
    num = first(r, "LDN", "Seq")
    if not num:
        return None
    area = fnum(first(r, "Area"))  # Quadratgrad
    maj = 2 * math.sqrt(area / math.pi) * 60 if area else None
    op = first(r, "Opacity", "Opac", "op")
    return {"id": f"LDN {int(float(num))}", "aliases": [], "type": "darkNebula", "ra": round(ra, 5),
            "dec": round(dec, 5), "maj": round(maj, 1) if maj else None, "min": None, "pa": None,
            "mag": None, "opacity": fnum(op), "src": "LDN"}


def build_barnard(r, ra, dec):
    num = first(r, "Barn", "B", "Seq")
    if not num:
        return None
    d = fnum(first(r, "Diam", "Dia"))
    return {"id": f"B {num.strip()}", "aliases": [], "type": "darkNebula", "ra": round(ra, 5),
            "dec": round(dec, 5), "maj": d, "min": None, "pa": None, "mag": None, "src": "Barnard"}


def build_sh2(r, ra, dec):
    num = first(r, "Sh2", "Sh", "Seq")
    if not num:
        return None
    d = fnum(first(r, "Diam", "Dia"))
    return {"id": f"Sh2-{int(float(num))}", "aliases": [], "type": "emissionNebula", "ra": round(ra, 5),
            "dec": round(dec, 5), "maj": d, "min": None, "pa": None, "mag": None,
            "bright": fnum(first(r, "Bright")), "src": "Sharpless"}


def build_lbn(r, ra, dec):
    num = first(r, "LBN", "Seq")
    if not num:
        return None
    d1 = fnum(first(r, "Diam1", "Dim1"))
    d2 = fnum(first(r, "Diam2", "Dim2"))
    return {"id": f"LBN {int(float(num))}", "aliases": [], "type": "nebula", "ra": round(ra, 5),
            "dec": round(dec, 5), "maj": d1, "min": d2, "pa": None, "mag": None,
            "bright": fnum(first(r, "Bright")), "src": "LBN"}


def build_vdb(r, ra, dec):
    num = first(r, "VdB", "vdB", "Seq")
    if not num:
        return None
    d = fnum(first(r, "BRadMax", "RRadMax"))
    return {"id": f"vdB {int(float(num))}", "aliases": [], "type": "reflectionNebula", "ra": round(ra, 5),
            "dec": round(dec, 5), "maj": 2 * d if d else None, "min": None, "pa": None, "mag": None,
            "src": "vdB"}


def build_ced(r, ra, dec):
    num = first(r, "Ced", "Seq")
    if not num:
        return None
    d1 = fnum(first(r, "Dim1", "Diam1"))
    d2 = fnum(first(r, "Dim2", "Diam2"))
    return {"id": f"Ced {num.strip()}", "aliases": [], "type": "nebula", "ra": round(ra, 5),
            "dec": round(dec, 5), "maj": d1, "min": d2, "pa": None, "mag": None, "src": "Cederblad"}


def dedupe(objs):
    """Entfernt Objekte, die bereits unter einem Alias in OpenNGC vorhanden sind."""
    known = {}
    for o in objs:
        known[o["id"]] = o
    out = []
    seen = set()
    alias_owner = {}
    for o in objs:
        if o["src"] == "OpenNGC":
            for a in o.get("aliases", []):
                alias_owner[a] = o
    for o in objs:
        if o["id"] in seen:
            continue
        if o["src"] != "OpenNGC" and o["id"] in alias_owner:
            owner = alias_owner[o["id"]]
            if owner.get("maj") is None and o.get("maj"):
                owner["maj"] = o["maj"]
            continue
        seen.add(o["id"])
        out.append(o)
    return out


def compact(o):
    return {k: v for k, v in o.items() if v not in (None, [], "")}


# --------------------------------------------------------------------------- moon

def parse_dbf(data):
    n = struct.unpack("<I", data[4:8])[0]
    hlen, rlen = struct.unpack("<HH", data[8:12])
    fields = []
    off = 32
    while data[off] != 0x0D:
        name = data[off:off + 11].split(b"\x00")[0].decode("ascii")
        ftype = chr(data[off + 11])
        flen = data[off + 16]
        fields.append((name, ftype, flen))
        off += 32
    rows = []
    pos = hlen
    for _ in range(n):
        rec = data[pos:pos + rlen]
        pos += rlen
        if not rec or rec[0:1] == b"*":
            continue
        p = 1
        row = {}
        for (name, ftype, flen) in fields:
            row[name] = rec[p:p + flen].decode("utf-8", "replace").strip()
            p += flen
        rows.append(row)
    return rows


def load_craters(cache, source_dir):
    raw = fetch(CRATERS_SHP, cache, "MOON_nomenclature_center_pts.zip", source_dir, timeout=300)
    if raw is None:
        return []
    z = zipfile.ZipFile(io.BytesIO(raw))
    dbf = [n for n in z.namelist() if n.lower().endswith(".dbf")]
    if not dbf:
        log("WARNUNG: keine DBF im Krater-Archiv")
        return []
    rows = parse_dbf(z.read(dbf[0]))
    if rows:
        log(f"  Krater-Spalten: {list(rows[0].keys())}")
    out = []
    for r in rows:
        low = {k.lower(): v for k, v in r.items()}
        ftype = (low.get("type") or low.get("feature_ty") or low.get("ftype") or "").lower()
        if "crater" not in ftype:
            continue
        name = low.get("clean_name") or low.get("name")
        lat = fnum(low.get("center_lat") or low.get("lat"))
        lon = fnum(low.get("center_lon") or low.get("lon"))
        dia = fnum(low.get("diameter") or low.get("diam"))
        if not name or lat is None or lon is None or not dia:
            continue
        if lon > 180:
            lon -= 360
        out.append({"name": name, "lat": round(lat, 3), "lon": round(lon, 3), "d": round(dia, 1),
                    "origin": (low.get("origin") or "")[:160]})
    out.sort(key=lambda c: -c["d"])
    log(f"Mondkrater: {len(out)}")
    return out


# --------------------------------------------------------------------------- main

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="Resources/Catalogs")
    ap.add_argument("--cache", default=".catalog-cache")
    ap.add_argument("--source-dir", default=None, help="Verzeichnis mit bereits heruntergeladenen Quellen")
    ap.add_argument("--maxmag", type=float, default=11.5)
    ap.add_argument("--no-remote", action="store_true", help="nur GitHub-Quellen (OpenNGC, HYG)")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    cache, sd = a.cache, a.source_dir

    hyg_raw = fetch(HYG, cache, "hygdata_v41.csv", sd, timeout=300)
    hyg, named = load_hyg(hyg_raw) if hyg_raw else ([], [])
    tycho = [] if a.no_remote else load_tycho(cache, sd, a.maxmag)
    if tycho or hyg:
        stars = merge_stars(tycho, hyg, a.maxmag)
        write_stars(os.path.join(a.out, "stars.bin"), stars)
    with open(os.path.join(a.out, "bright_stars.json"), "w") as f:
        json.dump(named, f, ensure_ascii=False, separators=(",", ":"))

    objs = load_openngc(fetch(OPENNGC.format("NGC.csv"), cache, "NGC.csv", sd),
                        fetch(OPENNGC.format("addendum.csv"), cache, "addendum.csv", sd))
    if not a.no_remote:
        objs += load_vizier_catalog(cache, sd, "VII/7A", "ldn.tsv", build_ldn)
        objs += load_vizier_catalog(cache, sd, "VII/220A", "barnard.tsv", build_barnard)
        objs += load_vizier_catalog(cache, sd, "VII/20", "sh2.tsv", build_sh2)
        objs += load_vizier_catalog(cache, sd, "VII/9", "lbn.tsv", build_lbn)
        objs += load_vizier_catalog(cache, sd, "VII/21", "vdb.tsv", build_vdb)
        objs += load_vizier_catalog(cache, sd, "VII/231", "ced.tsv", build_ced)
    objs = dedupe(objs)
    srcs = {}
    for o in objs:
        srcs[o["src"]] = srcs.get(o["src"], 0) + 1
    log(f"dso.json: {len(objs)} Objekte {srcs}")
    if objs:
        with open(os.path.join(a.out, "dso.json"), "w") as f:
            json.dump([compact(o) for o in objs], f, ensure_ascii=False, separators=(",", ":"))

    if not a.no_remote:
        com = fetch(COMETS, cache, "CometEls.txt", sd)
        if com:
            with open(os.path.join(a.out, "comets.txt"), "wb") as f:
                f.write(com)
            log(f"comets.txt: {len(com.splitlines())} Kometen")
        craters = load_craters(cache, sd)
        if craters:
            with open(os.path.join(a.out, "moon_craters.json"), "w") as f:
                json.dump(craters, f, ensure_ascii=False, separators=(",", ":"))

    with open(os.path.join(a.out, "VERSION.txt"), "w") as f:
        f.write(time.strftime("%Y-%m-%d") + "\n")
    log("fertig")


if __name__ == "__main__":
    sys.exit(main())
