import Foundation

public struct SolveResult: Sendable {
    public var wcs: WCS
    public var matchedStars: Int
    public var rmsPixels: Double
    public var stars: [DetectedStar]
}

/// Blindes Plate Solving mit Quad-Hashing gegen den mitgelieferten Sternkatalog.
public final class PlateSolver: @unchecked Sendable {
    public let catalog: StarCatalog
    private var indexes: [Double: QuadIndex] = [:]
    private let lock = NSLock()

    public init(catalog: StarCatalog) { self.catalog = catalog }

    /// Verfügbare Maßstabsstufen (Zellgröße in Grad), abhängig von der Katalogtiefe
    public var bands: [Double] {
        let cMin = max(0.35, (6.0 / catalog.meanDensity).squareRoot())
        var c = 24.0
        var out: [Double] = []
        while c >= cMin { out.append(c); c /= 1.45 }
        return out
    }

    func index(for c: Double, isCancelled: () -> Bool) -> QuadIndex {
        lock.lock(); defer { lock.unlock() }
        if let i = indexes[c] { return i }
        let i = QuadIndex(catalog: catalog, cellDeg: c, isCancelled: isCancelled)
        // Speicher begrenzen: nur wenige Stufen gleichzeitig halten
        if indexes.count > 4, let k = indexes.keys.min() { indexes[k] = nil }
        indexes[c] = i
        return i
    }

    struct Hypothesis {
        var tangentRA: Double, tangentDec: Double
        var ar: Double, ai: Double      // komplexer Faktor (Grad/Pixel)
        var br: Double, bi: Double      // Verschiebung
        var parity: Bool
        var centerRA: Double, centerDec: Double
        var scale: Double
    }

    public func solve(stars allStars: [DetectedStar], width: Int, height: Int,
                      fieldHintDeg: Double? = nil,
                      log: (String) -> Void = { _ in },
                      isCancelled: () -> Bool = { false }) -> SolveResult? {
        let stars = Array(allStars.prefix(300))
        guard stars.count >= 12 else { log("Zu wenige Sterne für Plate Solving (\(stars.count))."); return nil }
        let longSide = Double(max(width, height))
        let diag = Double(width * width + height * height).squareRoot()
        var bandList = bands
        if let hint = fieldHintDeg {
            // Feld kann durch Zuschnitt kleiner sein, aber nicht größer → nur passende Stufen zuerst
            bandList.sort { abs(log2($0 / (hint / 4))) < abs(log2($1 / (hint / 4))) }
        }
        var tried = Set<String>()
        for c in bandList {
            if isCancelled() { return nil }
            let idx = index(for: c, isCancelled: isCancelled)
            log(String(format: "Maßstabsstufe %.2f° – %d Quads im Index", c, idx.count))
            for g in [2, 3, 4, 5, 6, 8] {
                if isCancelled() { return nil }
                let cellPx = longSide / Double(g)
                let expectedScale = c / cellPx  // Grad/Pixel bei passender Zuordnung
                let fov = expectedScale * longSide
                if fov > 120 || fov < 0.2 { continue }
                if let hint = fieldHintDeg, fov > hint * 1.6 { continue }
                let key = "\(c)-\(g)"
                if tried.contains(key) { continue }
                tried.insert(key)
                let quads = imageQuads(stars, width: width, height: height, cellPx: cellPx)
                let hyps = matchQuads(quads, stars: stars, index: idx, expectedScale: expectedScale, width: width, height: height)
                for h in hyps.prefix(12) {
                    if isCancelled() { return nil }
                    if let res = verify(h, stars: stars, width: width, height: height, diag: diag) {
                        log(String(format: "Lösung gefunden: %d Sterne zugeordnet, Abweichung %.2f px", res.matchedStars, res.rmsPixels))
                        return res
                    }
                }
            }
        }
        return nil
    }

    // MARK: Bild-Quads

    struct ImageQuad { var hash: QuadHash; var ids: [Int]; var mirrored: Bool }

    func imageQuads(_ stars: [DetectedStar], width: Int, height: Int, cellPx: Double, K: Int = 6, M: Int = 6) -> [ImageQuad] {
        let gx = max(1, Int(ceil(Double(width) / cellPx))), gy = max(1, Int(ceil(Double(height) / cellPx)))
        var cells = [[Int]](repeating: [], count: gx * gy)
        for (i, s) in stars.enumerated() {
            let cx = min(gx - 1, Int(s.x / cellPx)), cy = min(gy - 1, Int(s.y / cellPx))
            if cells[cy * gx + cx].count < K { cells[cy * gx + cx].append(i) }  // Sterne sind nach Fluss sortiert
        }
        let sel = cells.flatMap { $0 }
        let maxD = cellPx * 1.6
        var out: [ImageQuad] = []
        var seen = Set<[Int]>()
        let combos = Array<Int>.combinations(M, 3)
        for s in sel {
            var cand: [(Int, Double)] = []
            for j in sel where j != s {
                let dx = stars[j].x - stars[s].x, dy = stars[j].y - stars[s].y
                let d = (dx * dx + dy * dy).squareRoot()
                if d <= maxD { cand.append((j, d)) }
            }
            if cand.count < 3 { continue }
            cand.sort { $0.1 < $1.1 }
            let nb = cand.prefix(M).map { $0.0 }
            for cmb in combos where cmb.allSatisfy({ $0 < nb.count }) {
                let ids = [s, nb[cmb[0]], nb[cmb[1]], nb[cmb[2]]]
                let key = ids.sorted()
                if seen.contains(key) { continue }
                seen.insert(key)
                let pts = ids.map { (stars[$0].x, stars[$0].y) }
                if let q = QuadHash.compute(pts), q.size > 25 {
                    out.append(ImageQuad(hash: q, ids: [ids[q.order.0], ids[q.order.1], ids[q.order.2], ids[q.order.3]], mirrored: false))
                }
                let mp = pts.map { (-$0.0, $0.1) }
                if let q = QuadHash.compute(mp), q.size > 25 {
                    out.append(ImageQuad(hash: q, ids: [ids[q.order.0], ids[q.order.1], ids[q.order.2], ids[q.order.3]], mirrored: true))
                }
            }
        }
        return out
    }

    // MARK: Zuordnung & Abstimmung

    func matchQuads(_ quads: [ImageQuad], stars: [DetectedStar], index: QuadIndex, expectedScale: Double,
                    width: Int, height: Int) -> [Hypothesis] {
        var hits: [Int] = []
        var votes: [String: (Int, Hypothesis)] = [:]
        let tol: Float = 0.012
        for q in quads {
            index.lookup(q.hash.h, tol: tol, into: &hits)
            for hq in hits {
                let catIds = (0..<4).map { Int(index.stars[4 * hq + $0]) }
                guard let h = hypothesis(imageIds: q.ids, catIds: catIds, mirrored: q.mirrored, stars: stars,
                                         width: width, height: height) else { continue }
                // Maßstab muss zur Stufe passen (Faktor ~2,5)
                let r = h.scale / expectedScale
                if r < 0.4 || r > 2.5 { continue }
                let v = Vec3(ra: h.centerRA, dec: h.centerDec)
                let fov = h.scale * Double(max(width, height))
                let pb = max(fov / 15, 0.01) * .pi / 180
                let rot = atan2(h.ai, h.ar)
                let key = "\(Int((v.x / pb).rounded()))|\(Int((v.y / pb).rounded()))|\(Int((v.z / pb).rounded()))|\(Int((log(h.scale) / 0.08).rounded()))|\(Int((rot / 0.15).rounded()))|\(h.parity)"
                if let e = votes[key] { votes[key] = (e.0 + 1, e.1) } else { votes[key] = (1, h) }
            }
        }
        return votes.values.sorted { $0.0 > $1.0 }.map { $0.1 }
    }

    func hypothesis(imageIds: [Int], catIds: [Int], mirrored: Bool, stars: [DetectedStar], width: Int, height: Int) -> Hypothesis? {
        let ra0 = Double(catalog.ra[catIds[0]]), dec0 = Double(catalog.dec[catIds[0]])
        var w: [(Double, Double)] = []
        for c in catIds {
            guard let t = tangentProject(ra: Double(catalog.ra[c]), dec: Double(catalog.dec[c]), ra0: ra0, dec0: dec0) else { return nil }
            w.append((t.xi, t.eta))
        }
        let z: [(Double, Double)] = imageIds.map { mirrored ? (-stars[$0].x, stars[$0].y) : (stars[$0].x, stars[$0].y) }
        // komplexe Ähnlichkeitstransformation w = a z + b (Least Squares)
        let zm = (z.map { $0.0 }.reduce(0, +) / 4, z.map { $0.1 }.reduce(0, +) / 4)
        let wm = (w.map { $0.0 }.reduce(0, +) / 4, w.map { $0.1 }.reduce(0, +) / 4)
        var nr = 0.0, ni = 0.0, dd = 0.0
        for k in 0..<4 {
            let zx = z[k].0 - zm.0, zy = z[k].1 - zm.1
            let wx = w[k].0 - wm.0, wy = w[k].1 - wm.1
            // conj(z) * w
            nr += zx * wx + zy * wy; ni += zx * wy - zy * wx
            dd += zx * zx + zy * zy
        }
        if dd <= 0 { return nil }
        let ar = nr / dd, ai = ni / dd
        let br = wm.0 - (ar * zm.0 - ai * zm.1), bi = wm.1 - (ar * zm.1 + ai * zm.0)
        // Residuum prüfen
        var res = 0.0, size = 0.0
        for k in 0..<4 {
            let px = ar * z[k].0 - ai * z[k].1 + br, py = ar * z[k].1 + ai * z[k].0 + bi
            res = max(res, hypot(px - w[k].0, py - w[k].1))
            size = max(size, hypot(w[k].0 - wm.0, w[k].1 - wm.1))
        }
        if res > 0.03 * size { return nil }
        // Bildmitte
        let cxz = mirrored ? -Double(width) / 2 : Double(width) / 2, cyz = Double(height) / 2
        let xi = ar * cxz - ai * cyz + br, eta = ar * cyz + ai * cxz + bi
        let c = tangentDeproject(xi: xi, eta: eta, ra0: ra0, dec0: dec0)
        return Hypothesis(tangentRA: ra0, tangentDec: dec0, ar: ar, ai: ai, br: br, bi: bi, parity: mirrored,
                          centerRA: c.ra, centerDec: c.dec, scale: hypot(ar, ai))
    }

    // MARK: Verifikation & Verfeinerung

    func verify(_ h: Hypothesis, stars: [DetectedStar], width: Int, height: Int, diag: Double) -> SolveResult? {
        // Anfangs-WCS aus Hypothese: an Hilfspunkten auswerten und linear anpassen
        var px: [(Double, Double)] = [], sky: [(Double, Double)] = []
        for gx in stride(from: 0.0, through: 1.0, by: 0.25) { for gy in stride(from: 0.0, through: 1.0, by: 0.25) {
            let x = gx * Double(width), y = gy * Double(height)
            let zx = h.parity ? -x : x
            let xi = h.ar * zx - h.ai * y + h.br, eta = h.ar * y + h.ai * zx + h.bi
            px.append((x, y)); sky.append(tangentDeproject(xi: xi, eta: eta, ra0: h.tangentRA, dec0: h.tangentDec))
        } }
        guard var wcs = WCS.fit(pixels: px, sky: sky, ra0: h.centerRA, dec0: h.centerDec, width: width, height: height, order: 1) else { return nil }
        let nImg = min(stars.count, 150)
        let img = Array(stars.prefix(nImg))
        let radius = h.scale * diag / 2 * 1.08
        if radius > 80 { return nil }
        let cone = catalog.cone(ra: h.centerRA, dec: h.centerDec, radius: radius)
        let byMag = cone.sorted { catalog.mag[$0] < catalog.mag[$1] }
        let area = Double(width * height)
        var tol = max(3.0, 0.004 * diag)
        var bestMatches = 0, rms = 0.0
        var lastPairs: [(Int, Int)] = []
        for iter in 0..<7 {
            // Katalogsterne projizieren (die hellsten ~2.5× Bildsterne im Feld)
            var proj: [(Int, Double, Double)] = []
            for i in byMag {
                guard let p = wcs.skyToPixel(Double(catalog.ra[i]), Double(catalog.dec[i])) else { continue }
                if p.x < 0 || p.y < 0 || p.x >= Double(width) || p.y >= Double(height) { continue }
                proj.append((i, p.x, p.y))
                if proj.count >= nImg * 5 / 2 { break }
            }
            if proj.count < 8 { return nil }
            // Rasterhash für Nachbarsuche
            let cs = max(tol, 4)
            var grid: [Int: [Int]] = [:]
            let gw = Int(Double(width) / cs) + 2
            for (k, p) in proj.enumerated() { grid[Int(p.2 / cs) * gw + Int(p.1 / cs), default: []].append(k) }
            var pairs: [(Int, Int)] = []
            var used = Set<Int>()
            var se = 0.0
            for (si, s) in img.enumerated() {
                let gx = Int(s.x / cs), gy = Int(s.y / cs)
                var best = -1, bd = tol
                for dy in -1...1 { for dx in -1...1 {
                    for k in grid[(gy + dy) * gw + gx + dx] ?? [] {
                        let d = hypot(proj[k].1 - s.x, proj[k].2 - s.y)
                        if d < bd { bd = d; best = k }
                    }
                } }
                if best >= 0 && !used.contains(best) { used.insert(best); pairs.append((si, proj[best].0)); se += bd * bd }
            }
            let lambda = Double(proj.count) / area
            let expected = Double(nImg) * lambda * .pi * tol * tol
            let n = pairs.count
            if iter == 0 && (n < 8 || Double(n) < expected * 3 + 5) { return nil }
            rms = n > 0 ? (se / Double(n)).squareRoot() : 99
            bestMatches = n
            lastPairs = pairs
            let order = n >= 70 ? 3 : n >= 30 ? 2 : 1
            let center = wcs.center
            guard let nw = WCS.fit(pixels: pairs.map { (img[$0.0].x, img[$0.0].y) },
                                   sky: pairs.map { (Double(catalog.ra[$0.1]), Double(catalog.dec[$0.1])) },
                                   ra0: center.ra, dec0: center.dec, width: width, height: height, order: order) else { return nil }
            wcs = nw
            if iter >= 2 { tol = max(2.0, min(tol, 3 * rms + 1.5)) }
        }
        // Endgültige Prüfung: genügend Sterne, Zufall ausgeschlossen
        let lambda = Double(min(cone.count, nImg * 5 / 2)) / area
        let expected = Double(nImg) * lambda * .pi * tol * tol
        guard bestMatches >= 10, Double(bestMatches) > expected * 4 + 8, Double(bestMatches) >= 0.15 * Double(nImg) else { return nil }
        // Restfehler mit finaler Lösung
        var se = 0.0
        for (si, ci) in lastPairs {
            if let p = wcs.skyToPixel(Double(catalog.ra[ci]), Double(catalog.dec[ci])) { se += pow(hypot(p.x - img[si].x, p.y - img[si].y), 2) }
        }
        return SolveResult(wcs: wcs, matchedStars: bestMatches, rmsPixels: (se / Double(max(1, lastPairs.count))).squareRoot(), stars: stars)
    }
}
