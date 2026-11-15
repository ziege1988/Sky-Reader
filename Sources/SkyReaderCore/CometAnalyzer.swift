import Foundation

/// Bahnelemente eines Kometen (MPC CometEls.txt)
public struct CometElements: Sendable {
    public var designation: String
    public var name: String
    public var perihelionJD: Double
    public var q: Double
    public var e: Double
    public var argPeri: Double
    public var node: Double
    public var incl: Double
    public var H: Double
    public var G: Double

    /// Parser für eine Zeile im MPC-Format (feste Spalten)
    public init?(mpcLine l: String) {
        let c = Array(l)
        guard c.count >= 103 else { return nil }
        func s(_ a: Int, _ b: Int) -> String { String(c[(a - 1)..<min(b, c.count)]).trimmingCharacters(in: .whitespaces) }
        guard let y = Int(s(15, 18)), let mo = Int(s(20, 21)), let d = Double(s(23, 29)),
              let q = Double(s(31, 39)), let e = Double(s(42, 49)), let w = Double(s(52, 59)),
              let n = Double(s(62, 69)), let i = Double(s(72, 79)) else { return nil }
        self.q = q; self.e = e; argPeri = w; node = n; incl = i
        H = Double(s(92, 95)) ?? 12
        G = Double(s(97, 100)) ?? 4
        perihelionJD = julianDay(year: y, month: mo, day: d)
        name = s(103, 158)
        designation = s(1, 12)
    }

    /// Heliozentrische Position (ekliptikal J2000, AE)
    public func heliocentric(jd: Double) -> Vec3 {
        let k = 0.01720209895
        let dt = jd - perihelionJD
        var nu = 0.0, r = 0.0
        if abs(e - 1) < 1e-6 {
            // Parabel: Barker-Gleichung
            let W = 3 * k / (2 * q).squareRoot() / q * dt
            let Y = cbrt(W / 2 + (W * W / 4 + 1).squareRoot())
            let s = Y - 1 / Y
            nu = 2 * atan(s); r = q * (1 + s * s)
        } else if e < 1 {
            let a = q / (1 - e)
            let n = k / pow(a, 1.5)
            var M = (n * dt).truncatingRemainder(dividingBy: 2 * .pi)
            if M > .pi { M -= 2 * .pi } else if M < -.pi { M += 2 * .pi }
            let E = solveKeplerElliptic(M: M, e: e)
            nu = 2 * atan2((1 + e).squareRoot() * sin(E / 2), (1 - e).squareRoot() * cos(E / 2))
            r = a * (1 - e * cos(E))
        } else {
            let a = q / (e - 1)
            let n = k / pow(a, 1.5)
            let M = n * dt
            var Hh = asinh(M / e)
            for _ in 0..<60 {
                let f = e * sinh(Hh) - Hh - M, fp = e * cosh(Hh) - 1
                let d = f / fp; Hh -= d
                if abs(d) < 1e-12 { break }
            }
            nu = 2 * atan(((e + 1) / (e - 1)).squareRoot() * tanh(Hh / 2))
            r = a * (e * cosh(Hh) - 1)
        }
        let O = deg2rad(node), w = deg2rad(argPeri), i = deg2rad(incl)
        let u = w + nu
        return Vec3(r * (cos(O) * cos(u) - sin(O) * sin(u) * cos(i)),
                    r * (sin(O) * cos(u) + cos(O) * sin(u) * cos(i)),
                    r * sin(u) * sin(i))
    }

    /// Geozentrische Position (RA/Dec J2000), Abstände und geschätzte Helligkeit
    public func ephemeris(jd: Double) -> (ra: Double, dec: Double, delta: Double, r: Double, mag: Double) {
        let p = heliocentric(jd: jd)
        let earth = earthHeliocentric(jd: jd)
        var g = p - earth
        // Lichtlaufzeit
        let lt = g.length * 0.0057755
        g = heliocentric(jd: jd - lt) - earth
        let eq = eclipticToEquatorial(g)
        let r = p.length, delta = g.length
        let mag = H + 5 * log10(delta) + 2.5 * G * log10(r)
        return (eq.ra, eq.dec, delta, r, mag)
    }

    public var displayName: String {
        name.isEmpty ? designation : name
    }
}

func solveKeplerElliptic(M: Double, e: Double) -> Double {
    var E = e > 0.8 ? (M >= 0 ? .pi : -.pi) * 0.5 + M * 0.5 : M
    for _ in 0..<100 {
        let f = E - e * sin(E) - M, fp = 1 - e * cos(E)
        let d = f / max(fp, 1e-12)
        E -= max(-0.5, min(0.5, d))
        if abs(d) < 1e-13 { break }
    }
    return E
}

public func julianDay(year: Int, month: Int, day: Double) -> Double {
    var y = year, m = month
    if m <= 2 { y -= 1; m += 12 }
    let a = y / 100, b = 2 - a + a / 4
    return Double(Int(365.25 * Double(y + 4716))) + Double(Int(30.6001 * Double(m + 1))) + day + Double(b) - 1524.5
}

public func julianDay(_ date: Date) -> Double { date.timeIntervalSince1970 / 86400 + 2440587.5 }
public func dateFromJD(_ jd: Double) -> Date { Date(timeIntervalSince1970: (jd - 2440587.5) * 86400) }

/// Erde heliozentrisch, ekliptikal J2000 (genähert, ~0,01°)
func earthHeliocentric(jd: Double) -> Vec3 {
    let n = jd - 2451545.0
    let L = 280.460 + 0.9856474 * n
    let g = deg2rad(357.528 + 0.9856003 * n)
    var lam = L + 1.915 * sin(g) + 0.020 * sin(2 * g)
    lam -= 1.3972 * n / 36525  // Präzession zurück auf J2000
    let R = 1.00014 - 0.01671 * cos(g) - 0.00014 * cos(2 * g)
    let l = deg2rad(lam + 180)
    return Vec3(R * cos(l), R * sin(l), 0)
}

func eclipticToEquatorial(_ v: Vec3) -> (ra: Double, dec: Double) {
    let eps = deg2rad(23.4392911)
    let x = v.x, y = v.y * cos(eps) - v.z * sin(eps), z = v.y * sin(eps) + v.z * cos(eps)
    let e = Vec3(x, y, z)
    return (e.ra, e.dec)
}

public struct CometCandidate: Sendable {
    public var x: Double, y: Double          // Kopf (Analysebild)
    public var tailAngle: Double             // Richtung des Schweifs (Bildkoordinaten, Grad)
    public var tailLength: Double            // Pixel
    public var comaRadius: Double
    public var score: Double
}

public enum CometAnalyzer {
    nonisolated(unsafe) static var cachedElements: [CometElements]?

    public static func elements() -> [CometElements] {
        if let c = cachedElements { return c }
        guard let u = ResourceLocator.catalogURL("comets.txt"), let s = try? String(contentsOf: u, encoding: .utf8) else { return [] }
        let list = s.split(separator: "\n").compactMap { CometElements(mpcLine: String($0)) }
        cachedElements = list
        return list
    }

    /// Morphologische Suche: diffuser, heller Kopf mit länglichem Schweif
    public static func detect(_ img: GrayImage, stars: [DetectedStar]) -> CometCandidate? {
        let f = 4
        let small = img.downsampled(by: f)
        let w = small.width, h = small.height
        guard w > 40, h > 40 else { return nil }
        // Sterne durch Medianfilter (5×5) entfernen
        var med = small
        var buf = [Float](repeating: 0, count: 25)
        for y in 2..<(h - 2) { for x in 2..<(w - 2) {
            var k = 0
            for dy in -2...2 { for dx in -2...2 { buf[k] = small[x + dx, y + dy]; k += 1 } }
            buf.sort(); med[x, y] = buf[12]
        } }
        let bg = BackgroundModel(image: med, cell: max(16, min(w, h) / 6))
        var resid = GrayImage(width: w, height: h)
        var sigs: [Float] = []
        for y in 0..<h { for x in 0..<w {
            resid[x, y] = med[x, y] - bg.level(at: x, y)
            if x % 4 == 0 && y % 4 == 0 { sigs.append(bg.sigma(at: x, y)) }
        } }
        let noise = max(median(sigs), 1e-4)
        // hellster diffuser Punkt
        var best = (0, 0), bv: Float = 0
        for y in 4..<(h - 4) { for x in 4..<(w - 4) where resid[x, y] > bv { bv = resid[x, y]; best = (x, y) } }
        if bv < 8 * noise { return nil }
        // Ist es ein heller Stern? (Stern-Detektion mit kleiner Fläche in der Nähe)
        let hx = Double(best.0 * f) + Double(f) / 2, hy = Double(best.1 * f) + Double(f) / 2
        if stars.prefix(30).contains(where: { hypot($0.x - hx, $0.y - hy) < 6 && $0.area < 150 && $0.elongation < 1.4 }) { return nil }
        // Region oberhalb 15 % des Spitzenwerts
        let thr = max(bv * 0.15, 3 * noise)
        var stack = [best.1 * w + best.0]
        var seen = Set<Int>(stack)
        var sx = 0.0, sy = 0.0, sw = 0.0, sxx = 0.0, syy = 0.0, sxy = 0.0
        var count = 0
        while let p = stack.popLast(), count < 200_000 {
            let px = p % w, py = p / w
            let v = Double(resid[px, py]); count += 1
            sx += v * Double(px); sy += v * Double(py); sw += v
            sxx += v * Double(px * px); syy += v * Double(py * py); sxy += v * Double(px * py)
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let nx = px + dx, ny = py + dy
                guard nx >= 0, ny >= 0, nx < w, ny < h else { continue }
                let q = ny * w + nx
                if !seen.contains(q) && resid[nx, ny] > thr { seen.insert(q); stack.append(q) }
            }
        }
        if count < 12 || sw <= 0 { return nil }
        let cx = sx / sw, cy = sy / sw
        let vxx = sxx / sw - cx * cx, vyy = syy / sw - cy * cy, vxy = sxy / sw - cx * cy
        let tr = vxx + vyy, det = vxx * vyy - vxy * vxy
        let disc = max(0, tr * tr / 4 - det).squareRoot()
        let l1 = tr / 2 + disc, l2 = max(tr / 2 - disc, 1e-6)
        let elong = (l1 / l2).squareRoot()
        // Schweifrichtung: vom Kopf zum Schwerpunkt der Region
        let ang = rad2deg(atan2(cy - Double(best.1), cx - Double(best.0)))
        let offset = hypot(cx - Double(best.0), cy - Double(best.1))
        let length = 2 * l1.squareRoot()
        // Bewertung: länglich + Kopf am Ende (asymmetrisch) + hell
        let asym = min(1, offset / max(1, l1.squareRoot()))
        let score = min(1, max(0, (elong - 1.3) / 2.5)) * 0.5 + asym * 0.35 + min(1, Double(bv / noise) / 60) * 0.15
        return CometCandidate(x: hx, y: hy, tailAngle: ang, tailLength: length * Double(f),
                              comaRadius: max(6, min(30, l2.squareRoot() * Double(f))), score: score)
    }

    /// Identifikation über Bahnelemente: mit Datum direkt, ohne Datum Suche entlang der Bahnen
    static func identify(candidate: CometCandidate?, wcs: WCS, factor: Double, date: Date?, dsos: [FoundObject],
                         log: (String) -> Void, isCancelled: () -> Bool) -> FoundObject? {
        let els = elements()
        guard !els.isEmpty else { log("Keine Kometen-Bahndaten vorhanden."); return nil }
        let w = Double(wcs.imageWidth), h = Double(wcs.imageHeight)
        let center = wcs.center
        let radius = wcs.fieldSize.w * 0.75 + wcs.fieldSize.h * 0.25
        // Zielposition: Kopf des Kandidaten oder (mit Datum) ganzes Feld
        let target: (ra: Double, dec: Double)? = candidate.map { wcs.pixelToSky($0.x, $0.y) }
        var best: (CometElements, Double, Double, Double, Double, Double)?  // el, jd, x, y, mag, dist
        if let date = date {
            let jd = julianDay(date)
            for el in els {
                let eph = el.ephemeris(jd: jd)
                if eph.mag > 14 { continue }
                if angularDistance(ra1: center.ra, dec1: center.dec, ra2: eph.ra, dec2: eph.dec) > radius { continue }
                guard let p = wcs.skyToPixel(eph.ra, eph.dec), p.x >= 0, p.y >= 0, p.x < w, p.y < h else { continue }
                var dist = 0.0
                if let t = target { dist = angularDistance(ra1: t.ra, dec1: t.dec, ra2: eph.ra, dec2: eph.dec) }
                if best == nil || eph.mag < best!.4 { best = (el, jd, p.x, p.y, eph.mag, dist) }
            }
            if let b = best { log(String(format: "Bahnberechnung: %@ im Bildfeld (berechnete Helligkeit %.1f mag).", b.0.displayName, b.4)) }
        } else if let t = target, let cand = candidate, cand.score > 0.45 {
            log("Kein Aufnahmedatum – durchsuche die Bahnen von \(els.count) Kometen nach einem Durchgang durch diese Himmelsposition …")
            let now = julianDay(Date())
            let tol = max(0.4, wcs.pixelScaleArcsec * 40 / 3600)
            for el in els {
                if isCancelled() { return nil }
                if el.H > 11 { continue }
                if el.perihelionJD < now - 365.25 * 12 || el.perihelionJD > now + 400 { continue }
                var jd = el.perihelionJD - 240
                while jd < el.perihelionJD + 240 {
                    let eph = el.ephemeris(jd: jd)
                    let d = angularDistance(ra1: t.ra, dec1: t.dec, ra2: eph.ra, dec2: eph.dec)
                    if eph.mag < 9 && d < tol * 6 {
                        var fj = jd - 2
                        while fj < jd + 2 {
                            let e2 = el.ephemeris(jd: fj)
                            let d2 = angularDistance(ra1: t.ra, dec1: t.dec, ra2: e2.ra, dec2: e2.dec)
                            if d2 < tol && (best == nil || d2 + e2.mag * 0.02 < best!.5 + best!.4 * 0.02) {
                                best = (el, fj, cand.x, cand.y, e2.mag, d2)
                            }
                            fj += 0.05
                        }
                    }
                    jd += d < 5 ? 0.5 : 2
                }
            }
            if let b = best {
                let df = DateFormatter(); df.locale = Locale(identifier: "de_DE"); df.dateFormat = "d. MMMM yyyy"
                log(String(format: "Bahn passt: %@ – Position stimmt am %@ überein (Abweichung %.2f°).", b.0.displayName, df.string(from: dateFromJD(b.1)), b.5))
            }
        }
        guard let b = best else { return nil }
        let el = b.0
        let eph = el.ephemeris(jd: b.1)
        let df = DateFormatter(); df.locale = Locale(identifier: "de_DE"); df.dateFormat = "d. MMMM yyyy"
        let periDate = df.string(from: dateFromJD(el.perihelionJD))
        let periodText: String = el.e < 1 ? String(format: "%.0f Jahre", pow(el.q / (1 - el.e), 1.5)) : "keine (offene Bahn – kehrt nicht zurück)"
        var facts = [
            InfoFact("Objekttyp", "Komet"),
            InfoFact("Bezeichnung", el.displayName),
            InfoFact("Abstand zur Erde", String(format: "%.2f AE (%.0f Mio. km)", eph.delta, eph.delta * 149.6).replacingOccurrences(of: ".", with: ",")),
            InfoFact("Abstand zur Sonne", String(format: "%.2f AE", eph.r).replacingOccurrences(of: ".", with: ",")),
            InfoFact("Perihel", periDate + String(format: " (%.3f AE)", el.q).replacingOccurrences(of: ".", with: ",")),
            InfoFact("Exzentrizität", String(format: "%.5f", el.e).replacingOccurrences(of: ".", with: ",")),
            InfoFact("Bahnneigung", formatDegrees(el.incl, digits: 1)),
            InfoFact("Umlaufzeit", periodText),
            InfoFact("Berechnete Helligkeit", String(format: "%.1f mag", eph.mag).replacingOccurrences(of: ".", with: ",")),
        ]
        if date == nil { facts.append(InfoFact("Rekonstruiertes Aufnahmedatum", "um den " + df.string(from: dateFromJD(b.1)))) }
        let cur = Descriptions.shared.cometEntry(el.displayName)
        let r = (candidate?.comaRadius ?? 12) * 1.6
        let p = candidate.map { ($0.x * factor, $0.y * factor) } ?? (b.2 * factor, b.3 * factor)
        let info = ObjectInfo(
            title: el.displayName, subtitle: "Komet",
            facts: facts,
            scientific: cur?.scientific ?? "Kometen sind Körper aus Eis, Staub und Gestein aus der Frühzeit des Sonnensystems. Nähern sie sich der Sonne, verdampft Eis und bildet die Koma sowie den Gasschweif (vom Sonnenwind gerade nach außen geblasen, bläulich) und den Staubschweif (gekrümmt, gelblich-weiß). Diese Position wurde aus den Bahnelementen des Minor Planet Center berechnet.",
            latest: cur?.latest ?? "Bahnelemente: Minor Planet Center (Stand der in Sky Reader enthaltenen Daten).",
            layman: cur?.layman ?? "Ein Komet ist ein „schmutziger Schneeball“, der auf seiner Bahn um die Sonne gerade aufgetaut ist. Der lange Schweif zeigt immer von der Sonne weg und kann Millionen Kilometer lang sein.")
        return FoundObject(id: "comet-\(el.designation)", label: shortCometLabel(el.displayName), type: .comet,
                           x: p.0, y: p.1, radius: r * factor, number: nil, drawCircle: true, info: info,
                           confidence: date != nil ? 0.95 : 0.8, ra: eph.ra, dec: eph.dec)
    }

    static func shortCometLabel(_ n: String) -> String {
        // „C/2023 A3 (Tsuchinshan-ATLAS)“ → bleibt; nur sehr lange Namen kürzen
        n.count > 40 ? String(n.prefix(40)) + "…" : n
    }

    static func unidentifiedObject(_ c: CometCandidate, factor: Double, wcs: WCS? = nil) -> FoundObject {
        let sky = wcs?.pixelToSky(c.x * factor, c.y * factor)
        var facts = [InfoFact("Objekttyp", "Komet (nicht identifiziert)"),
                     InfoFact("Schweiflänge im Bild", String(format: "ca. %.0f Pixel", c.tailLength * factor))]
        if let s = sky { facts.append(InfoFact("Position Kopf (J2000)", formatRA(s.ra) + "  " + formatDec(s.dec))) }
        return FoundObject(id: "comet-unknown", label: "Komet", type: .comet, x: c.x * factor, y: c.y * factor,
                           radius: c.comaRadius * 1.6 * factor, number: nil, drawCircle: true,
                           info: ObjectInfo(title: "Komet (unbekannt)", subtitle: "Komet", facts: facts,
                                            scientific: "Ein diffuses Objekt mit Koma und Schweif wurde erkannt. Eine Zuordnung zu einer bekannten Kometenbahn war nicht möglich – entweder fehlt das Aufnahmedatum, das Sternfeld konnte nicht bestimmt werden oder der Komet ist in den enthaltenen Bahndaten nicht vorhanden (Update installieren).",
                                            latest: "",
                                            layman: "Hier ist sehr wahrscheinlich ein Komet zu sehen: ein eisiger Körper, dessen Schweif von der Sonne weg zeigt."),
                           confidence: c.score, ra: sky?.ra, dec: sky?.dec)
    }
}

extension Descriptions {
    /// Kuratierter Text für bekannte Kometen (Schlüssel = Teil des Namens)
    func cometEntry(_ name: String) -> CuratedEntry? {
        for key in ["Tsuchinshan-ATLAS", "C/2023 A3", "NEOWISE", "C/2020 F3", "Hale-Bopp", "Halley", "12P", "C/2022 E3", "Pons-Brooks"] where name.contains(key) {
            if let e = curatedEntry(id: "COMET:" + key) { return e }
        }
        return nil
    }
}
