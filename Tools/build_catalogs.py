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
import urllib.error
import zipfile

UA = "SkyReader-catalog-builder/1.0"

OPENNGC = "https://raw.githubusercontent.com/mattiaverga/OpenNGC/master/database_files/{}"
HYG = "https://raw.githubusercontent.com/astronexus/HYG-Database/main/hyg/CURRENT/hygdata_v41.csv"
TYCHO_MIRRORS = [
    "https://cdsarc.cds.unistra.fr/ftp/I/259/tyc2.dat.{:02d}.gz",
    "https://cdsarc.u-strasbg.fr/ftp/I/259/tyc2.dat.{:02d}.gz",
    "http://cdsarc.u-strasbg.fr/ftp/I/259/tyc2.dat.{:02d}.gz",
    "https://vizier.cfa.harvard.edu/ftp/cats/I/259/tyc2.dat.{:02d}.gz",
    "https://vizier.cfa.harvard.edu/viz-bin/ftp-index?/ftp/cats/I/259/tyc2.dat.{:02d}.gz",
]
VIZIER_HOSTS = ["https://vizier.cds.unistra.fr", "https://vizier.u-strasbg.fr", "https://vizier.cfa.harvard.edu"]
VIZIER_PATTERNS = [
    "{host}/viz-bin/asu-tsv?-source={table}&-out.max=unlimited&-out.all=1&-out.add=_RAJ2000,_DEJ2000&-oc.form=d",
    "{host}/viz-bin/asu-tsv?-source={table}&-out.max=unlimited&-out=**&-out.add=_RAJ2000&-out.add=_DEJ2000&-oc.form=dec",
]
TAP_HOSTS = ["https://tapvizier.cds.unistra.fr/TAPVizieR/tap/sync", "https://tapvizier.u-strasbg.fr/TAPVizieR/tap/sync"]
COMETS = "https://www.minorplanetcenter.net/iau/MPCORB/CometEls.txt"
CRATERS_SHP = "https://planetarynames.wr.usgs.gov/shapefiles/MOON_nomenclature_center_pts.zip"


def log(*a):
    print("[catalogs]", *a, flush=True)


def fetch_any(urls, cache, name, source_dir=None, timeout=60, retries=2):
    for u in urls:
        d = fetch(u, cache, name, source_dir, timeout=timeout, retries=retries)
        if d:
            log(f"  OK: {u} ({len(d)} Bytes)")
            return d
    return None


def tap_query(adql, cache, name, source_dir=None):
    import urllib.parse
    q = urllib.parse.urlencode({"REQUEST": "doQuery", "LANG": "ADQL", "FORMAT": "tsv", "MAXREC": "4000000", "QUERY": adql})
    return fetch_any([f"{h}?{q}" for h in TAP_HOSTS], cache, name, source_dir, timeout=600, retries=1)


DEAD_HOSTS = set()


def fetch(url, cache, name, source_dir=None, timeout=120, retries=3):
    """Download with simple caching. Returns bytes or None. Nicht erreichbare Hosts werden danach übersprungen."""
    import urllib.parse
    host = urllib.parse.urlparse(url).netloc
    if source_dir and name:
        p = os.path.join(source_dir, name)
        if os.path.exists(p):
            with open(p, "rb") as f:
                return f.read()
    if cache and name:
        os.makedirs(cache, exist_ok=True)
        p = os.path.join(cache, name)
        if os.path.exists(p) and os.path.getsize(p) > 0:
            with open(p, "rb") as f:
                return f.read()
    if host in DEAD_HOSTS:
        return None
    last = None
    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=timeout) as r:
                data = r.read()
            if cache and name:
                with open(os.path.join(cache, name), "wb") as f:
                    f.write(data)
            return data
        except urllib.error.HTTPError as e:
            last = e
            break  # Server antwortet – andere URL-Variante probieren
        except Exception as e:  # noqa
            last = e
            if "timed out" in str(e) or "Connection refused" in str(e) or "Name or service" in str(e) or "unreachable" in str(e):
                DEAD_HOSTS.add(host)
                log(f"  Host nicht erreichbar, wird übersprungen: {host}")
                break
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
    ok = True
    for i in range(20):
        raw = fetch_any([m.format(i) for m in TYCHO_MIRRORS], cache, f"tyc2.dat.{i:02d}.gz", source_dir, timeout=40, retries=1)
        if raw is None:
            ok = False
            break
        try:
            text = gzip.decompress(raw).decode("ascii", "replace")
        except OSError:
            ok = False
            break
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
    if ok:
        return stars
    log("Tycho-2 per FTP nicht erreichbar – versuche TAP-Abfrage")
    raw = tap_query(f'SELECT RAmdeg, DEmdeg, BTmag, VTmag FROM "I/259/tyc2" WHERE VTmag < {maxmag + 0.3}', cache, "tyc2_tap.tsv", source_dir)
    if raw is None:
        log("Tycho-2 nicht verfuegbar – nur HYG")
        return []
    stars = []
    lines = raw.decode("utf-8", "replace").splitlines()
    log(f"  TAP-Kopf: {lines[:2]}")
    for line in lines[1:]:
        f = line.split("\t")
        if len(f) < 4:
            continue
        ra, dec, bt, vt = fnum(f[0]), fnum(f[1]), fnum(f[2]), fnum(f[3])
        if ra is None or dec is None or vt is None:
            continue
        mag = vt - 0.090 * (bt - vt) if bt is not None else vt
        if mag <= maxmag:
            stars.append((ra, dec, mag))
    log(f"Tycho-2 (TAP): {len(stars)} Sterne")
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


def parse_tap_tsv(data):
    lines = data.decode("utf-8", "replace").splitlines()
    if not lines:
        return []
    cols = [c.strip().strip('"') for c in lines[0].split("\t")]
    log(f"  Spalten (TAP): {cols}")
    rows = []
    for l in lines[1:]:
        vals = [v.strip().strip('"') for v in l.split("\t")]
        rows.append(dict(zip(cols, vals)))
    return rows


def load_vizier_catalog(cache, source_dir, table, fname, builder):
    urls = [p.format(host=h, table=table) for p in VIZIER_PATTERNS for h in VIZIER_HOSTS]
    raw = fetch_any(urls, cache, fname, source_dir, timeout=40, retries=1)
    rows = parse_vizier_tsv(raw) if raw else []
    if not rows:
        raw = tap_query(f'SELECT * FROM "{table}"', cache, fname + ".tap", source_dir)
        rows = parse_tap_tsv(raw) if raw else []
    out = []
    for r in rows:
        ra = fnum(first(r, "_RAJ2000", "RAJ2000", "RA_ICRS", "_RA"))
        dec = fnum(first(r, "_DEJ2000", "DEJ2000", "DE_ICRS", "_DE"))
        if ra is None or dec is None:
            ra, dec = sexa_radec(r)
        if ra is None or dec is None:
            continue
        o = builder(r, ra, dec)
        if o:
            out.append(o)
    log(f"{table}: {len(out)} Objekte")
    return out


def sexa_radec(r):
    """RA/Dec aus sexagesimalen Spalten (RAJ2000 '05 40 59.0') oder B1950 (RA1950/DE1950) – letzteres praezediert."""
    for rk, dk, b1950 in (("RAJ2000", "DEJ2000", False), ("RA2000", "DE2000", False), ("RAB1950", "DEB1950", True), ("RA1950", "DE1950", True)):
        if rk in r and dk in r and r[rk] and r[dk]:
            try:
                p = r[rk].replace(":", " ").split()
                q = r[dk].replace(":", " ").split()
                ra = (float(p[0]) + (float(p[1]) if len(p) > 1 else 0) / 60 + (float(p[2]) if len(p) > 2 else 0) / 3600) * 15
                sign = -1 if q[0].startswith("-") else 1
                dec = sign * (abs(float(q[0])) + (float(q[1]) if len(q) > 1 else 0) / 60 + (float(q[2]) if len(q) > 2 else 0) / 3600)
                if b1950:
                    ra, dec = precess_b1950(ra, dec)
                return ra, dec
            except (ValueError, IndexError):
                return None, None
    return None, None


def precess_b1950(ra, dec):
    """B1950 -> J2000 (Standardmatrix, ohne E-Terme; Genauigkeit ~1" ausreichend)."""
    a, d = math.radians(ra), math.radians(dec)
    x, y, z = math.cos(d) * math.cos(a), math.cos(d) * math.sin(a), math.sin(d)
    m = [[0.9999256782, -0.0111820611, -0.0048579477],
         [0.0111820610, 0.9999374784, -0.0000271765],
         [0.0048579479, -0.0000271474, 0.9999881997]]
    X = m[0][0] * x + m[0][1] * y + m[0][2] * z
    Y = m[1][0] * x + m[1][1] * y + m[1][2] * z
    Z = m[2][0] * x + m[2][1] * y + m[2][2] * z
    return math.degrees(math.atan2(Y, X)) % 360, math.degrees(math.asin(Z))


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


# Korrekturen offensichtlicher Katalogwerte (sichtbare Ausdehnung statt Gesamtausdehnung)
OVERRIDES = {
    # Barnards Loop: Sharpless gibt 1200' an; Kreisfit an den sichtbaren Bogen: Radius 7,0° um RA 82,1°, Dec -3,2°
    "Sh2-276": {"ra": 82.1, "dec": -3.2, "maj": 845.0, "common": "Barnard's Loop"},
}


def apply_overrides(objs):
    for o in objs:
        if o["id"] in OVERRIDES:
            o.update(OVERRIDES[o["id"]])
    return objs


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


ROBBINS_PAGES = [
    "https://astrogeology.usgs.gov/search/map/moon_crater_database_v1_robbins",
    "https://astrogeology.usgs.gov/search/map/Moon/Research/Craters/lunar_crater_database_robbins_2018",
]
ROBBINS_URLS = [
    "https://asc-astropedia.s3.us-west-2.amazonaws.com/Moon/Research/Craters/lunar_crater_database_robbins_2018.zip",
    "https://asc-astropedia.s3.us-west-2.amazonaws.com/Moon/Research/Craters/lunar_crater_database_robbins_2018.csv",
    # offizieller Download laut USGS-Produktseite „Moon Crater Database v1 Robbins“ (ca. 93 MB)
    "https://astropedia.astrogeology.usgs.gov/download/Moon/Research/Craters/lunar_crater_database_robbins_2018.zip",
    "https://astropedia.astrogeology.usgs.gov/download/Moon/Research/Craters/lunar_crater_database_robbins_2018",
    "https://astropedia.astrogeology.usgs.gov/download/Moon/Research/Craters/lunar_crater_database_robbins_2018.csv",
    "https://pdsimage2.wr.usgs.gov/Individual_Investigations/moon_lro.kaguya_multi_craterdatabase_robbins_2018/data/lunar_crater_database_robbins_2018.csv",
    "https://pdsimage2.wr.usgs.gov/Individual_Investigations/moon_lro.kaguya_multi_craterdatabase_robbins_2018/data/lunar_crater_database_robbins_2018_bundle/data/lunar_crater_database_robbins_2018.csv",
    "https://astrogeology.usgs.gov/ckan/dataset/a2bd2e4c-4c35-4e6e-a6fc-bc1d3ff9f8c6/resource/2b7bdb41-3a0d-4d53-9c4e-bfc4dd4a5c3a/download/lunar_crater_database_robbins_2018.csv",
]
ROBBINS_INDEX = [
    "https://pdsimage2.wr.usgs.gov/Individual_Investigations/moon_lro.kaguya_multi_craterdatabase_robbins_2018/",
    "https://pdsimage2.wr.usgs.gov/Individual_Investigations/moon_lro.kaguya_multi_craterdatabase_robbins_2018/data/",
]

# Typen der IAU-Nomenklatur, die als Regionsbezeichnung dienen (Maria, Gebirge, …)
REGION_TYPES = {"mare": "Mare", "oceanus": "Oceanus", "lacus": "Lacus", "sinus": "Sinus", "palus": "Palus",
                "mons": "Mons", "montes": "Montes", "vallis": "Vallis", "promontorium": "Promontorium",
                "rupes": "Rupes", "rima": "Rima", "catena": "Catena", "dorsum": "Dorsum"}


def load_moon_nomenclature(cache, source_dir):
    """IAU/USGS Gazetteer: Krater inkl. Nebenkrater ("Atlas A") und Regionsnamen (Maria, Montes, …)."""
    raw = fetch(CRATERS_SHP, cache, "MOON_nomenclature_center_pts.zip", source_dir, timeout=300)
    if raw is None:
        return [], []
    z = zipfile.ZipFile(io.BytesIO(raw))
    dbf = [n for n in z.namelist() if n.lower().endswith(".dbf")]
    if not dbf:
        log("WARNUNG: keine DBF im Krater-Archiv")
        return [], []
    rows = parse_dbf(z.read(dbf[0]))
    types = {}
    for r in rows:
        t = ({k.lower(): v for k, v in r.items()}.get("type") or "")
        types[t] = types.get(t, 0) + 1
    log(f"  Nomenklatur-Typen: {sorted(types.items(), key=lambda kv: -kv[1])[:25]}")
    craters, regions = [], []
    for r in rows:
        low = {k.lower(): v for k, v in r.items()}
        ftype = (low.get("type") or "").lower()
        name = low.get("clean_name") or low.get("name")
        lat = fnum(low.get("center_lat") or low.get("lat"))
        lon = fnum(low.get("center_lon") or low.get("lon"))
        dia = fnum(low.get("diameter") or low.get("diam"))
        if not name or lat is None or lon is None or not dia:
            continue
        if lon > 180:
            lon -= 360
        if "crater" in ftype or "satellite" in ftype:
            c = {"name": name, "lat": round(lat, 3), "lon": round(lon, 3), "d": round(dia, 1)}
            if "satellite" in ftype:
                c["sat"] = 1
            else:
                c["origin"] = (low.get("origin") or "")[:160]
            craters.append(c)
            continue
        for key, label in REGION_TYPES.items():
            if ftype.startswith(key):
                regions.append({"name": name, "type": label, "lat": round(lat, 3), "lon": round(lon, 3), "d": round(dia, 1),
                                "origin": (low.get("origin") or "")[:160]})
                break
    craters.sort(key=lambda c: -c["d"])
    regions.sort(key=lambda c: -c["d"])
    log(f"Mondkrater: {len(craters)} (davon Nebenkrater {sum(1 for c in craters if c.get('sat'))}), Regionen: {len(regions)}")
    return craters, regions


ROBBINS_SEEDS = [
    "https://pdsimage2.wr.usgs.gov/Individual_Investigations/",
    "https://astrogeology.usgs.gov/search/map/moon_crater_database_v1_robbins",
    "https://astrogeology.usgs.gov/search/map/Moon/Research/Craters/lunar_crater_database_robbins_2018",
    "https://planetarymaps.usgs.gov/mosaic/",
    "https://pds-geosciences.wustl.edu/missions/lro/",
]


def discover_robbins():
    """Sucht den Download der Robbins-Datenbank über Verzeichnis- und Projektseiten (Tiefe 3)."""
    import re, urllib.parse
    seen, found = set(), []
    frontier = [(u, 0) for u in ROBBINS_SEEDS]
    while frontier and len(seen) < 60:
        u, depth = frontier.pop(0)
        if u in seen:
            continue
        seen.add(u)
        page = fetch(u, None, None, None, timeout=45, retries=1)
        if not page:
            continue
        html = page.decode("utf-8", "replace")
        for h in re.findall(r'href="([^"#?]+)"', html):
            full = urllib.parse.urljoin(u, h)
            low = full.lower()
            if "robbins" not in low and "crater" not in low:
                continue
            if re.search(r"\.(csv|zip|gz|tab|txt)$", low):
                found.append(full)
            elif depth < 3 and full.startswith(("http://", "https://")) and full not in seen:
                frontier.append((full, depth + 1))
    # USGS-STAC-Katalog (maschinenlesbar) nach Sammlungen mit „crater“ durchsuchen
    for api in ("https://stac.astrogeology.usgs.gov/api/collections", "https://stac.astrogeology.usgs.gov/api/search?q=robbins"):
        page = fetch(api, None, None, None, timeout=60, retries=1)
        if not page:
            continue
        try:
            j = json.loads(page)
            cols = j.get("collections") or j.get("features") or []
            for c in cols:
                cid = c.get("id", "")
                if "crater" in cid.lower() or "robbins" in json.dumps(c).lower():
                    hrefs = [l.get("href") for l in c.get("links", [])] + [a.get("href") for a in (c.get("assets") or {}).values()]
                    log(f"  STAC: {cid}: {[h for h in hrefs if h][:12]}")
                    found += [h for h in hrefs if h and re.search(r"\.(csv|zip|gz)$", h.lower())]
        except Exception as ex:  # noqa
            log(f"  STAC-Fehler: {ex}")
    log(f"  Robbins-Suche: {len(seen)} Seiten besucht, Kandidaten: {found[:30]}")
    return found


def load_robbins(cache, source_dir, min_d=3.0):
    """Robbins (2018) Lunar Crater Database – alle Krater ab min_d km als kompakte Binärdatei."""
    raw = None
    # 1. selbst bereitgestellte Datei (Release „katalog-quellen“ → --source-dir), beliebiger Dateiname mit „robbins“
    if source_dir and os.path.isdir(source_dir):
        for fn in sorted(os.listdir(source_dir)):
            if "robbins" in fn.lower() or "crater_database" in fn.lower():
                with open(os.path.join(source_dir, fn), "rb") as f:
                    raw = f.read()
                log(f"  Robbins aus bereitgestellter Datei: {fn} ({len(raw) / 1e6:.0f} MB)")
                if raw[:2] == b"PK":
                    z = zipfile.ZipFile(io.BytesIO(raw))
                    names = [n for n in z.namelist() if n.lower().endswith(".csv")]
                    log(f"  ZIP-Inhalt: {z.namelist()[:10]}")
                    raw = z.read(max(names, key=lambda n: z.getinfo(n).file_size)) if names else None
                elif raw[:2] == b"\x1f\x8b":
                    raw = gzip.decompress(raw)
                if raw:
                    break
    urls = [] if raw else discover_links(ROBBINS_PAGES, ["robbins", "crater"]) + ROBBINS_URLS + [u for u in discover_robbins() if "robbins" in u.lower()]
    for u in urls:
        raw = fetch(u, cache, "robbins_2018" + os.path.splitext(u)[1], source_dir, timeout=900, retries=2)
        if raw:
            log(f"  Robbins OK: {u} ({len(raw) / 1e6:.0f} MB)")
            if raw[:2] == b"PK":
                z = zipfile.ZipFile(io.BytesIO(raw))
                names = [n for n in z.namelist() if n.lower().endswith(".csv")]
                log(f"  ZIP-Inhalt: {z.namelist()[:10]}")
                raw = z.read(max(names, key=lambda n: z.getinfo(n).file_size)) if names else None
            elif raw[:2] == b"\x1f\x8b":
                raw = gzip.decompress(raw)
            elif raw[:200].lstrip().lower().startswith((b"<!doctype", b"<html")):
                log(f"  {u}: HTML statt Daten – übersprungen")
                raw = None
            if raw:
                break
    if not raw:
        log("WARNUNG: Robbins-Kraterdatenbank nicht erreichbar")
        return []
    text = raw.decode("utf-8", "replace").splitlines()
    head = [h.strip() for h in text[0].split(",")]
    log(f"  Robbins-Spalten: {head[:20]}")
    def col(*names):
        for n in names:
            if n in head:
                return head.index(n)
        return None
    ila, ilo, idi = col("LAT_CIRC_IMG", "LAT_CIRC_TOPO"), col("LON_CIRC_IMG", "LON_CIRC_TOPO"), col("DIAM_CIRC_IMG", "DIAM_CIRC_TOPO")
    if None in (ila, ilo, idi):
        log("WARNUNG: Robbins-Spalten nicht gefunden")
        return []
    out = []
    for line in text[1:]:
        f = line.split(",")
        try:
            la, lo, d = float(f[ila]), float(f[ilo]), float(f[idi])
        except (ValueError, IndexError):
            continue
        if d < min_d:
            continue
        if lo > 180:
            lo -= 360
        out.append((la, lo, d))
    log(f"Robbins: {len(out)} Krater ≥ {min_d} km")
    return out


def write_robbins(path, craters):
    craters.sort(key=lambda c: c[0])   # nach Breite sortiert
    with open(path, "wb") as f:
        f.write(b"SRMC")
        f.write(struct.pack("<II", 1, len(craters)))
        for (la, lo, d) in craters:
            f.write(struct.pack("<fff", la, lo, d))
    log(f"moon_robbins.bin: {len(craters)} Krater, {os.path.getsize(path) / 1e6:.1f} MB")


# --------------------------------------------------------------------------- Geologie (Kraterzeitalter)

GEOLOGY_PAGES = [
    "https://astrogeology.usgs.gov/search/map/unified_geologic_map_of_the_moon_1_5m_2020",
    "https://astrogeology.usgs.gov/search/map/Moon/Geology/Unified_Geologic_Map_of_the_Moon_GIS",
]
GEOLOGY_URLS = [
    "https://astropedia.astrogeology.usgs.gov/download/Moon/Geology/Unified_Geologic_Map_of_the_Moon_GIS_v2.zip",
    "https://astropedia.astrogeology.usgs.gov/download/Moon/Geology/Unified_Geologic_Map_of_the_Moon_GIS.zip",
]
PERIODS = ("pN", "C", "E", "I", "N")


def discover_links(pages, must):
    """Sucht Datei-Links (auch in eingebettetem JSON der Seite) mit bestimmten Schlüsselwörtern."""
    import re
    found = []
    for u in pages:
        page = fetch(u, None, None, None, timeout=60, retries=1)
        if not page:
            continue
        html = page.decode("utf-8", "replace").replace("\\/", "/")
        for h in re.findall(r"https?://[^\"'\s<>\\]+?\.(?:zip|gpkg|7z)", html):
            if any(m in h.lower() for m in must) and h not in found:
                found.append(h)
    log(f"  Gefundene Links: {found[:20]}")
    return found


def unit_period(sym):
    """Periode aus dem Einheitensymbol (z. B. „Cc“ → C, „pNc“ → pN, „Ic2“ → I); Kratereinheit, wenn danach ein „c“ folgt."""
    sym = (sym or "").strip()
    for p in PERIODS:
        if sym.startswith(p):
            rest = sym[len(p):]
            return p, rest[:1] == "c"
    return None, False


def load_geology_ages(cache, source_dir, craters):
    """USGS Unified Geologic Map of the Moon (2020): geologisches Zeitalter je benanntem Krater."""
    try:
        import geopandas as gpd, pyogrio, shapely
    except ImportError:
        log("WARNUNG: geopandas fehlt – Kraterzeitalter werden übersprungen")
        return {}
    raw = None
    for fn in (sorted(os.listdir(source_dir)) if source_dir and os.path.isdir(source_dir) else []):
        if "geolog" in fn.lower():
            raw = open(os.path.join(source_dir, fn), "rb").read()
            log(f"  Geologie aus bereitgestellter Datei: {fn}")
            break
    if raw is None:
        for u in discover_links(GEOLOGY_PAGES, ["geolog"]) + GEOLOGY_URLS:
            raw = fetch(u, cache, "moon_geology.zip", source_dir, timeout=900, retries=2)
            if raw and raw[:2] == b"PK":
                log(f"  Geologie OK: {u} ({len(raw) / 1e6:.0f} MB)")
                break
            raw = None
    if not raw:
        log("WARNUNG: Geologische Mondkarte nicht erreichbar")
        return {}
    import tempfile
    tmp = tempfile.mkdtemp()
    zipfile.ZipFile(io.BytesIO(raw)).extractall(tmp)
    # Datenquellen: Shapefiles, GeoPackages oder File-Geodatabases
    sources = []
    for root, dirs, files in os.walk(tmp):
        for d in dirs:
            if d.lower().endswith(".gdb"):
                sources.append(os.path.join(root, d))
        for f in files:
            if f.lower().endswith((".shp", ".gpkg")):
                sources.append(os.path.join(root, f))
    log(f"  Geologie-Quellen: {[os.path.relpath(x, tmp) for x in sources][:30]}")
    best = None
    for src in sources:
        try:
            layers = [l[0] for l in pyogrio.list_layers(src)]
        except Exception as ex:  # noqa
            log(f"  {src}: {ex}")
            continue
        for layer in layers:
            try:
                info = pyogrio.read_info(src, layer=layer)
            except Exception:
                continue
            geom = str(info.get("geometry_type", ""))
            fields = list(info.get("fields", []))
            log(f"  Ebene {os.path.basename(src)}:{layer} {geom} n={info.get('features')} Felder={fields[:15]}")
            if "Polygon" not in geom:
                continue
            symf = next((f for f in fields if f.lower() in ("firstunit", "first_unit", "unitsymbol", "unit_symbol", "unit", "symbol", "unitsym")), None)
            if symf and (best is None or info.get("features", 0) > best[3]):
                best = (src, layer, symf, info.get("features", 0))
    if not best:
        log("WARNUNG: keine Einheiten-Ebene gefunden")
        return {}
    src, layer, symf, n = best
    gdf = gpd.read_file(src, layer=layer, columns=[symf])
    log(f"  Einheiten-Ebene: {layer} ({n} Polygone), Feld {symf}, CRS {gdf.crs}")
    try:
        if gdf.crs is not None and gdf.crs.is_projected:
            gdf = gdf.to_crs(gdf.crs.geodetic_crs)
    except Exception as ex:  # noqa
        log(f"  CRS-Umrechnung fehlgeschlagen: {ex}")
        return {}
    b = gdf.total_bounds
    log(f"  Ausdehnung: {b}")
    shift = 360 if b[2] > 181 else 0   # 0…360°-Längen
    sidx = gdf.sindex
    syms = gdf[symf].astype(str).tolist()
    km_per_deg = 1737.4 * math.pi / 180
    # Fläche jedes Polygons in km² (geografische Koordinaten, Breitenkorrektur am Schwerpunkt)
    areas = [g.area * km_per_deg ** 2 * max(0.02, math.cos(math.radians(g.centroid.y))) for g in gdf.geometry]
    ages, counts = {}, {}
    for c in craters:
        lat, lon, r = c["lat"], c["lon"], c["d"] / 2
        if r < 2:
            continue
        crater_area = math.pi * r * r
        # Proben auf Wall und Innenhang (nicht in der Mitte: dort liegen oft jüngere Kleinkrater oder Mare-Lava)
        pts = []
        for f in (0.6, 0.85, 1.0, 1.15):
            for k in range(12):
                a_ = k * math.pi / 6
                dlat = f * r / km_per_deg * math.sin(a_)
                dlon = f * r / km_per_deg * math.cos(a_) / max(0.05, math.cos(math.radians(lat)))
                pts.append((lon + dlon, lat + dlat))
        votes = {}
        for (x, y) in pts:
            x = x % 360 if shift else ((x + 180) % 360) - 180
            if not -90 < y < 90:
                continue
            for h in sidx.query(shapely.Point(x, y), predicate="intersects")[:1]:
                per, is_crater = unit_period(syms[h])
                # nur Kratermaterial, dessen Fläche zum Krater passt (kein Kleinkrater im Kraterinneren)
                if per and is_crater and areas[h] >= 0.25 * crater_area:
                    votes[per] = votes.get(per, 0) + 1
        total = sum(votes.values())
        if total >= 6:
            per = max(votes, key=votes.get)
            if votes[per] >= 0.5 * total:
                ages[c["name"]] = per
                counts[per] = counts.get(per, 0) + 1
    for n in ("Tycho", "Copernicus", "Eratosthenes", "Plato", "Archimedes", "Ptolemaeus", "Clavius", "Theophilus", "Hercules", "Langrenus"):
        log(f"  Kontrolle {n}: {ages.get(n, '–')}")
    log(f"Kraterzeitalter: {len(ages)} Krater {counts}")
    return ages


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
        objs += load_vizier_catalog(cache, sd, "VII/7A/ldn", "ldn.tsv", build_ldn)
        objs += load_vizier_catalog(cache, sd, "VII/220A/barnard", "barnard.tsv", build_barnard)
        objs += load_vizier_catalog(cache, sd, "VII/20/catalog", "sh2.tsv", build_sh2)
        objs += load_vizier_catalog(cache, sd, "VII/9/catalog", "lbn.tsv", build_lbn)
        objs += load_vizier_catalog(cache, sd, "VII/21/catalog", "vdb.tsv", build_vdb)
        objs += load_vizier_catalog(cache, sd, "VII/231/catalog", "ced.tsv", build_ced)
    objs = apply_overrides(dedupe(objs))
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
        craters, regions = load_moon_nomenclature(cache, sd)
        if craters:
            with open(os.path.join(a.out, "moon_craters.json"), "w") as f:
                json.dump(craters, f, ensure_ascii=False, separators=(",", ":"))
        if regions:
            with open(os.path.join(a.out, "moon_regions.json"), "w") as f:
                json.dump(regions, f, ensure_ascii=False, separators=(",", ":"))
        if craters:
            ages = load_geology_ages(cache, sd, craters)
            if ages:
                with open(os.path.join(a.out, "moon_crater_ages.json"), "w") as f:
                    json.dump(ages, f, ensure_ascii=False, separators=(",", ":"))
        robbins = load_robbins(cache, sd)
        if robbins:
            write_robbins(os.path.join(a.out, "moon_robbins.bin"), robbins)

    with open(os.path.join(a.out, "VERSION.txt"), "w") as f:
        f.write(time.strftime("%Y-%m-%d") + "\n")
    log("fertig")


if __name__ == "__main__":
    sys.exit(main())
