import Foundation

public struct MoonDetection: Sendable {
    public var threshold: Float
    public var brightFraction: Double
    public var moonLevel: Float
    public var mask: [Bool]
}

public struct LimbCircle: Sendable {
    public var cx: Double, cy: Double, r: Double
    public var inliers: Int
}

public struct DetectedCrater: Sendable {
    public var x: Double, y: Double, r: Double
    public var strength: Double
    public var shadowFraction: Double
}

public enum MoonAnalyzer {
    public static let moonRadiusKm = 1737.4

    // MARK: Erkennung

    /// Erkennt, ob das Bild (überwiegend) die Mondoberfläche zeigt
    public static func detectMoon(_ img: GrayImage) -> MoonDetection? {
        let n = img.pixels.count
        // Normierung auf 99,8-%-Quantil
        var sample: [Float] = []
        sample.reserveCapacity(n / 9)
        var i = 0
        while i < n { sample.append(img.pixels[i]); i += 9 }
        sample.sort()
        let white = max(sample[Int(Double(sample.count - 1) * 0.998)], 1e-3)
        // Otsu
        var hist = [Double](repeating: 0, count: 256)
        for v in sample { hist[min(255, Int(v / white * 255))] += 1 }
        let total = Double(sample.count)
        var sumAll = 0.0
        for k in 0..<256 { sumAll += Double(k) * hist[k] }
        var wB = 0.0, sumB = 0.0, best = 0.0, thrBin = 0
        for k in 0..<256 {
            wB += hist[k]; if wB == 0 { continue }
            let wF = total - wB; if wF == 0 { break }
            sumB += Double(k) * hist[k]
            let mB = sumB / wB, mF = (sumAll - sumB) / wF
            let between = wB * wF * (mB - mF) * (mB - mF)
            if between > best { best = between; thrBin = k }
        }
        let thr = Float(thrBin) / 255 * white
        var bright = 0.0, mb = 0.0, md = 0.0, darkN = 0.0
        for v in sample { if v > thr { bright += 1; mb += Double(v) } else { darkN += 1; md += Double(v) } }
        let frac = bright / total
        mb /= max(bright, 1); md /= max(darkN, 1)
        // Kriterien: großflächig hell, klar vom (schwarzen) Himmel getrennt
        let contrast = (mb + 1e-4) / (md + 1e-4)
        guard frac > 0.12, mb > Double(white) * 0.25 else { return nil }
        guard contrast > 4 || md < Double(white) * 0.04 else { return nil }
        // Zusammenhang prüfen: Anteil der hellen Pixel in der größten Komponente (auf verkleinertem Raster)
        let s = img.downsampled(by: 8)
        var m = [Bool](repeating: false, count: s.pixels.count)
        for k in 0..<m.count { m[k] = s.pixels[k] > thr }
        let largest = largestComponent(m, s.width, s.height)
        let brightCount = m.filter { $0 }.count
        guard brightCount > 0, Double(largest) / Double(brightCount) > 0.75 else { return nil }
        // Sterne als Gegenprobe: Deep-Sky-Bilder haben viele kleine helle Komponenten
        // Mondfläche inkl. Schatten in Kratern: geglättetes Bild über halber Schwelle
        let blurred = img.boxBlurred(radius: max(4, min(img.width, img.height) / 60))
        var mask = [Bool](repeating: false, count: n)
        for k in 0..<n { mask[k] = blurred.pixels[k] > thr * 0.5 }
        return MoonDetection(threshold: thr, brightFraction: frac, moonLevel: Float(mb), mask: mask)
    }

    static func largestComponent(_ m: [Bool], _ w: Int, _ h: Int) -> Int {
        var seen = [Bool](repeating: false, count: m.count)
        var best = 0
        for s in 0..<m.count where m[s] && !seen[s] {
            var stack = [s]; seen[s] = true; var c = 0
            while let p = stack.popLast() {
                c += 1
                let x = p % w, y = p / w
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let nx = x + dx, ny = y + dy
                    guard nx >= 0, ny >= 0, nx < w, ny < h else { continue }
                    let q = ny * w + nx
                    if m[q] && !seen[q] { seen[q] = true; stack.append(q) }
                }
            }
            best = max(best, c)
        }
        return best
    }

    // MARK: Mondrand

    /// RANSAC-Kreisanpassung an die scharfe Hell-Dunkel-Kante zum schwarzen Himmel
    public static func fitLimb(_ img: GrayImage, det: MoonDetection) -> LimbCircle? {
        let w = img.width, h = img.height
        let sm = img.boxBlurred(radius: 1)
        var pts: [(Double, Double)] = []
        let dark = det.threshold * 0.35
        let step = 2
        for y in stride(from: 4, to: h - 4, by: step) {
            for x in stride(from: 4, to: w - 4, by: step) {
                let v = sm[x, y]
                if v <= det.threshold { continue }
                // Nachbar in 4 px Abstand sehr dunkel → Kantenpunkt
                var edge = false
                for (dx, dy) in [(4, 0), (-4, 0), (0, 4), (0, -4)] where sm[x + dx, y + dy] < dark { edge = true }
                if !edge { continue }
                // Kante muss scharf sein (Terminator ist weich): Gradient über 3 px
                var sharp = false
                for (dx, dy) in [(3, 0), (-3, 0), (0, 3), (0, -3)] where sm[x, y] - sm[x + dx, y + dy] > det.threshold * 0.8 { sharp = true }
                if sharp { pts.append((Double(x), Double(y))) }
            }
        }
        guard pts.count >= 30 else { return nil }
        var rng = SystemRandomNumberGenerator()
        var best: LimbCircle?
        let minR = Double(min(w, h)) * 0.15, maxR = Double(max(w, h)) * 25
        let tol = 2.5
        for _ in 0..<1500 {
            let a = pts[Int.random(in: 0..<pts.count, using: &rng)]
            let b = pts[Int.random(in: 0..<pts.count, using: &rng)]
            let c = pts[Int.random(in: 0..<pts.count, using: &rng)]
            guard let circ = circleFrom(a, b, c), circ.r > minR, circ.r < maxR else { continue }
            var n = 0
            for p in pts where abs(hypot(p.0 - circ.cx, p.1 - circ.cy) - circ.r) < tol { n += 1 }
            if best == nil || n > best!.inliers { best = LimbCircle(cx: circ.cx, cy: circ.cy, r: circ.r, inliers: n) }
        }
        guard var b = best, b.inliers >= max(30, pts.count / 5) else { return nil }
        // Verfeinern (algebraischer Fit auf Inliern)
        let inl = pts.filter { abs(hypot($0.0 - b.cx, $0.1 - b.cy) - b.r) < tol }
        if let r = kasaFit(inl) { b = LimbCircle(cx: r.cx, cy: r.cy, r: r.r, inliers: inl.count) }
        // Mittelpunkt muss auf der hellen Seite liegen
        let mx = inl.map { $0.0 }.reduce(0, +) / Double(inl.count), my = inl.map { $0.1 }.reduce(0, +) / Double(inl.count)
        let dx = b.cx - mx, dy = b.cy - my, l = hypot(dx, dy)
        let probe = (mx + dx / l * 20, my + dy / l * 20)
        if probe.0 >= 0, probe.1 >= 0, probe.0 < Double(w), probe.1 < Double(h), img.sample(probe.0, probe.1) < det.threshold * 0.5 {
            return nil
        }
        return b
    }

    static func circleFrom(_ a: (Double, Double), _ b: (Double, Double), _ c: (Double, Double)) -> (cx: Double, cy: Double, r: Double)? {
        let d = 2 * (a.0 * (b.1 - c.1) + b.0 * (c.1 - a.1) + c.0 * (a.1 - b.1))
        if abs(d) < 1e-9 { return nil }
        let a2 = a.0 * a.0 + a.1 * a.1, b2 = b.0 * b.0 + b.1 * b.1, c2 = c.0 * c.0 + c.1 * c.1
        let ux = (a2 * (b.1 - c.1) + b2 * (c.1 - a.1) + c2 * (a.1 - b.1)) / d
        let uy = (a2 * (c.0 - b.0) + b2 * (a.0 - c.0) + c2 * (b.0 - a.0)) / d
        return (ux, uy, hypot(a.0 - ux, a.1 - uy))
    }

    static func kasaFit(_ p: [(Double, Double)]) -> (cx: Double, cy: Double, r: Double)? {
        guard p.count >= 3 else { return nil }
        let rows = p.map { [$0.0, $0.1, 1.0] }
        let y = p.map { $0.0 * $0.0 + $0.1 * $0.1 }
        guard let s = leastSquares(rows: rows, y: y) else { return nil }
        let cx = s[0] / 2, cy = s[1] / 2
        let r2 = s[2] + cx * cx + cy * cy
        return r2 > 0 ? (cx, cy, r2.squareRoot()) : nil
    }

    // MARK: Krater

    /// Geschätzte Richtung zur Sonne in Bildkoordinaten (Einheitsvektor): vom unbeleuchteten zum beleuchteten Teil
    public static func sunDirection(_ img: GrayImage, det: MoonDetection) -> (Double, Double) {
        let s = img.downsampled(by: max(1, min(img.width, img.height) / 200))
        let bl = s.boxBlurred(radius: max(3, min(s.width, s.height) / 8))
        var sx = 0.0, sy = 0.0
        for y in 1..<(s.height - 1) { for x in 1..<(s.width - 1) {
            let v = s[x, y]
            if v < det.threshold * 0.5 { continue }  // nur Mondfläche
            sx += Double(bl[x + 1, y] - bl[x - 1, y]); sy += Double(bl[x, y + 1] - bl[x, y - 1])
        } }
        // Die Helligkeit steigt zur Sonne hin (weg vom Terminator)
        let l = hypot(sx, sy)
        return l > 1e-9 ? (sx / l, sy / l) : (-1, 0)
    }

    /// Kratererkennung über das Licht-Schatten-Muster: Schatten auf der sonnenzugewandten Innenseite,
    /// beleuchtete Innenwand gegenüber. Mehrskalig über eine Bildpyramide.
    public static func detectCraters(_ img: GrayImage, det: MoonDetection, limb: LimbCircle?, maxCount: Int) -> [DetectedCrater] {
        let sun = sunDirection(img, det: det)
        var all: [DetectedCrater] = []
        var f = 1
        while Double(min(img.width, img.height)) / Double(f) > 48 {
            let lv = img.downsampled(by: f)
            let found = detectCratersLevel(lv, full: img, f: f, det: det, limb: limb, sun: sun, rMin: f == 1 ? 3.5 : 5, rMax: 11)
            all += found
            f *= 2
        }
        all.sort { $0.strength > $1.strength }
        var out: [DetectedCrater] = []
        for c in all {
            if out.contains(where: { o in
                let d = hypot(o.x - c.x, o.y - c.y)
                let ratio = min(o.r, c.r) / max(o.r, c.r)
                return (ratio > 0.5 && d < max(o.r, c.r) * 0.8) || (d < max(o.r, c.r) * 0.5)
            }) { continue }
            out.append(c)
        }
        if maxCount <= 15 {
            // „Nur die größten“: große, deutliche Krater (Stärke × Größe)
            let strong = out.filter { $0.strength >= 0.3 }
            out = strong.sorted { $0.strength * $0.r > $1.strength * $1.r }
        } else {
            out = out.filter { $0.strength >= 0.25 }
        }
        out = Array(out.prefix(maxCount))
        out.sort { $0.r > $1.r }
        return out
    }

    static func gauss(_ img: GrayImage, sigma: Double) -> GrayImage {
        let r = max(1, Int((sigma * sigma / 3 * 4 + 1).squareRoot().rounded() / 2 + 0.5))
        return img.boxBlurred(radius: r).boxBlurred(radius: r).boxBlurred(radius: r)
    }

    static func detectCratersLevel(_ img: GrayImage, full: GrayImage, f: Int, det: MoonDetection, limb: LimbCircle?,
                                   sun: (Double, Double), rMin: Double, rMax: Double) -> [DetectedCrater] {
        let w = img.width, h = img.height
        let ff = Double(f)
        let floorL = det.moonLevel * 0.12
        var out: [DetectedCrater] = []
        var r = rMin
        while r <= rMax {
            let inner = gauss(img, sigma: r * 0.38)
            let outer = gauss(img, sigma: r * 1.6)
            let off = r * 0.55
            let ox = sun.0 * off, oy = sun.1 * off
            var resp = [Float](repeating: 0, count: w * h)
            let m = Int(r * 1.3) + 2
            if w - 2 * m < 3 || h - 2 * m < 3 { break }
            for y in m..<(h - m) {
                for x in m..<(w - m) {
                    let ctx = outer[x, y]
                    if ctx < det.threshold * 0.35 { continue }
                    let bright = inner.sample(Double(x) - ox, Double(y) - oy)   // Innenwand gegenüber der Sonne
                    let shadow = inner.sample(Double(x) + ox, Double(y) + oy)   // Schatten auf Sonnenseite
                    resp[y * w + x] = (bright - shadow) / (ctx + floorL)
                }
            }
            for y in (m + 1)..<(h - m - 1) {
                for x in (m + 1)..<(w - m - 1) {
                    let v = resp[y * w + x]
                    if v < 0.2 { continue }
                    var isMax = true
                    let nb = max(1, Int(r * 0.6))
                    loop: for dy in -nb...nb { for dx in -nb...nb where dx != 0 || dy != 0 {
                        let yy = y + dy, xx = x + dx
                        if yy < 0 || xx < 0 || yy >= h || xx >= w { continue }
                        if resp[yy * w + xx] > v { isMax = false; break loop }
                    } }
                    if !isMax { continue }
                    // Kontrast prüfen: Schattenseite dunkler als Umgebung
                    let ctx = outer[x, y]
                    let shadow = inner.sample(Double(x) + ox, Double(y) + oy)
                    if shadow > ctx * 0.97 { continue }
                    let rr = r * ff
                    let cx = Double(x) * ff + (ff - 1) / 2 + sun.0 * rr * 0.15, cy = Double(y) * ff + (ff - 1) / 2 + sun.1 * rr * 0.15
                    if let l = limb, hypot(cx - l.cx, cy - l.cy) > l.r - rr * 1.15 { continue }
                    // Umgebung überwiegend Mondfläche
                    var inside = 0
                    for k in 0..<12 {
                        let a = Double(k) / 12 * 2 * .pi
                        let px = Int(cx + cos(a) * rr * 1.4), py = Int(cy + sin(a) * rr * 1.4)
                        if px >= 0, py >= 0, px < full.width, py < full.height, det.mask[py * full.width + px] { inside += 1 }
                    }
                    if inside < 10 { continue }
                    let shadowFrac = Double(max(0, min(1, (ctx - shadow) / max(ctx, 1e-4))))
                    out.append(DetectedCrater(x: cx, y: cy, r: rr, strength: Double(v), shadowFraction: shadowFrac))
                }
            }
            r *= 1.15
        }
        return out
    }

    // MARK: Gesamtanalyse

    static func analyze(img: GrayImage, full: GrayImage, factor: Int, detection: MoonDetection, settings: AnalysisSettings,
                        step: (String, Double) -> Void, info: (String) -> Void, warn: (String) -> Void, ok: (String) -> Void,
                        check: () throws -> Void) throws -> AnalysisResult {
        let f = Double(factor)
        step("Mondrand wird vermessen", 0.2)
        let limb = fitLimb(img, det: detection)
        var kmPerPx: Double?
        if let l = limb {
            kmPerPx = moonRadiusKm / (l.r * f)
            ok(String(format: "Mondrand gefunden: Radius %.0f Pixel → %.2f km pro Pixel", l.r * f, kmPerPx!).replacingOccurrences(of: ".", with: ","))
        } else {
            warn("Kein Mondrand im Bild – Kratergrößen können nicht in Kilometern angegeben werden.")
        }
        try check()
        step("Krater werden erkannt", 0.45)
        let maxCount = settings.craterMode == .largest ? 12 : 120
        let craters = detectCraters(img, det: detection, limb: limb, maxCount: maxCount)
        info("\(craters.count) Krater erkannt (\(settings.craterMode.germanName)).")
        try check()
        step("Kraterdetails werden berechnet", 0.8)
        var objs: [FoundObject] = []
        for (i, c) in craters.enumerated() {
            let n = i + 1
            var facts: [InfoFact] = [InfoFact("Nummer", "\(n)")]
            var diaKm: Double?
            if let k = kmPerPx {
                let d = 2 * c.r * f * k
                diaKm = d
                facts.append(InfoFact("Geschätzter Durchmesser", String(format: "ca. %.0f km", d)))
            }
            facts.append(InfoFact("Durchmesser im Bild", String(format: "%.0f Pixel", 2 * c.r * f)))
            if let l = limb {
                let rho = min(0.999, hypot(c.x - l.cx, c.y - l.cy) / l.r)
                let ang = rad2deg(asin(rho))
                facts.append(InfoFact("Winkelabstand zur Scheibenmitte", String(format: "ca. %.0f°", ang)))
                if ang > 60 { facts.append(InfoFact("Perspektive", "randnah – stark verkürzt (oval)")) }
            }
            facts.append(InfoFact("Beleuchtung", c.shadowFraction > 0.35 ? "Kraterboden überwiegend im Schatten (flacher Sonnenstand)" : c.shadowFraction > 0.1 ? "teilweise beschattet" : "Kraterboden beleuchtet"))
            let cls = craterClass(diaKm)
            facts.insert(InfoFact("Kratertyp", cls.name), at: 1)
            let inf = ObjectInfo(title: "Krater \(n)", subtitle: cls.name, facts: facts,
                                 scientific: cls.scientific, latest: cls.latest, layman: cls.layman)
            objs.append(FoundObject(id: "crater-\(n)", label: "\(n)", type: .moonCrater, x: c.x * f, y: c.y * f,
                                    radius: c.r * f, number: n, drawCircle: false, info: inf,
                                    confidence: min(1, c.strength * 5), ra: nil, dec: nil))
        }
        var facts = [
            InfoFact("Mittlere Entfernung", "384.400 km (1,28 Lichtsekunden)"),
            InfoFact("Durchmesser", "3.474 km"),
            InfoFact("Alter", "ca. 4,5 Mrd. Jahre"),
            InfoFact("Erkannte Krater", "\(objs.count)"),
        ]
        if let k = kmPerPx {
            facts.append(InfoFact("Bildmaßstab", String(format: "%.2f km pro Pixel", k).replacingOccurrences(of: ".", with: ",")))
            facts.append(InfoFact("Bildbreite", String(format: "ca. %.0f km", k * Double(full.width))))
        }
        let summary = ObjectInfo(
            title: "Mond", subtitle: "Erdtrabant",
            facts: facts,
            scientific: "Der Mond entstand nach heutigem Verständnis vor rund 4,5 Mrd. Jahren aus den Trümmern einer Kollision der jungen Erde mit einem etwa marsgroßen Körper (Theia). Seine Krater sind Einschlagsspuren aus über vier Milliarden Jahren; die dunklen Maria sind erstarrte Basaltlava, die vor 3–3,8 Mrd. Jahren große Einschlagsbecken flutete. Die Krater sind hier nach Größe nummeriert (1 = größter). Eine Benennung nach IAU-Namen erfolgt offline nicht.",
            latest: "Chandrayaan-3 (2023) landete als erste Sonde nahe dem Südpol, Chang'e 6 brachte 2024 erstmals Gestein von der Rückseite zur Erde. Das Artemis-Programm der NASA plant die Rückkehr von Menschen in die Südpolregion, wo in dauerhaft beschatteten Kratern Wassereis vermutet wird.",
            layman: "Jeder Krater ist die Narbe eines Einschlags: Gesteinsbrocken aus dem All prallten mit vielfacher Gewehrkugelgeschwindigkeit auf den Mond. Weil der Mond keine Luft und kein Wetter hat, bleiben diese Spuren Milliarden Jahre erhalten. Besonders plastisch wirken Krater nahe der Licht-Schatten-Grenze, wo die Sonne flach einfällt.")
        ok("Analyse abgeschlossen – \(objs.count) Krater.")
        return AnalysisResult(kind: .moon, imageWidth: full.width, imageHeight: full.height, objects: objs, summary: summary,
                              wcs: nil, warnings: limb == nil ? ["Mondrand nicht im Bild"] : [])
    }

    static func craterClass(_ d: Double?) -> (name: String, scientific: String, latest: String, layman: String) {
        guard let d = d else {
            return ("Einschlagkrater",
                    "Ein Einschlagkrater. Ohne sichtbaren Mondrand lässt sich die tatsächliche Größe nicht bestimmen.",
                    "", "Ein Krater – die Spur eines Einschlags aus dem All.")
        }
        if d < 18 {
            return ("Einfacher Krater (schüsselförmig)",
                    "Einfache Krater unter etwa 15–20 km Durchmesser haben eine glatte Schüsselform mit einem Tiefe-Durchmesser-Verhältnis von etwa 1:5 und einem erhöhten Wall aus ausgeworfenem Material.",
                    "Hochauflösende Aufnahmen des Lunar Reconnaissance Orbiter zeigen, dass ständig neue kleine Krater entstehen – über 200 neue Einschläge wurden durch Vorher-Nachher-Vergleiche nachgewiesen.",
                    "Ein kleiner, schüsselförmiger Krater – entstanden durch den Einschlag eines Brockens, der vielleicht nur einige hundert Meter groß war.")
        } else if d < 160 {
            return ("Komplexer Krater",
                    "Komplexe Krater (ca. 20–150 km) besitzen terrassierte Innenwände, einen flachen Boden und häufig einen Zentralberg, der beim Einschlag durch elastisches Zurückfedern des Untergrunds entstand.",
                    "Zentralberge legen Material aus größerer Tiefe frei; Spektrometer von Raumsonden nutzen sie als natürliche „Bohrkerne“ in die Mondkruste.",
                    "Ein großer Krater mit Terrassenwänden. In der Mitte steht oft ein Berg – so wie ein Wassertropfen nach oben zurückspritzt, wenn etwas in eine Pfütze fällt.")
        } else {
            return ("Großkrater / Becken",
                    "Ab etwa 200 km Durchmesser spricht man von Becken mit mehreren konzentrischen Ringen. Viele wurden später von Basaltlava geflutet und bilden heute die dunklen Maria.",
                    "Schwerefeldmessungen der GRAIL-Mission (2012) zeigten unter vielen Becken Massenkonzentrationen (Mascons) und eine stark zerrüttete Kruste.",
                    "Ein riesiges Einschlagbecken – so groß, dass ganze Länder hineinpassen würden.")
        }
    }
}
