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
    /// Kleine Halbachse und Lage der großen Achse (randnahe Krater erscheinen als Ellipsen)
    public var minorRadius: Double = 0
    public var angleDeg: Double = 0
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
        let sm = img.boxBlurred(radius: 2)
        // Himmel- und Mondhelligkeit
        var sample = stride(from: 0, to: sm.pixels.count, by: 5).map { sm.pixels[$0] }
        sample.sort()
        let sky = sample[Int(Double(sample.count - 1) * 0.02)]
        var litSum: Float = 0, litN: Float = 0
        for v in sample where v > det.threshold { litSum += v; litN += 1 }
        let lit = litN > 0 ? litSum / litN : det.threshold * 2
        let mThr = sky + 0.25 * (lit - sky), skyThr = sky + 0.1 * (lit - sky)
        var pts: [(Double, Double)] = []
        for y in stride(from: 6, to: h - 6, by: 2) {
            for x in stride(from: 6, to: w - 6, by: 2) {
                let v = sm[x, y]
                guard v > mThr else { continue }
                // Randpixel der Mondfläche?
                guard sm[x + 2, y] <= mThr || sm[x - 2, y] <= mThr || sm[x, y + 2] <= mThr || sm[x, y - 2] <= mThr else { continue }
                // Gradientenrichtung (nach außen = dunkler)
                let gx = Double(sm[x + 1, y] - sm[x - 1, y]), gy = Double(sm[x, y + 1] - sm[x, y - 1])
                let gl = hypot(gx, gy)
                guard gl > 1e-6 else { continue }
                let ux = gx / gl, uy = gy / gl   // zeigt zur helleren Seite (Mond)
                let inside = sm.sample(Double(x) + ux * 4, Double(y) + uy * 4)
                let outside = sm.sample(Double(x) - ux * 4, Double(y) - uy * 4)
                // scharfer Übergang zu echtem Himmel (Terminator ist weich und hat keinen schwarzen Himmel dahinter)
                if inside - outside > 0.45 * (lit - sky) && outside < skyThr { pts.append((Double(x), Double(y))) }
            }
        }
        guard pts.count >= 30 else { return nil }
        var rng = SystemRandomNumberGenerator()
        var best: LimbCircle?
        let minR = Double(min(w, h)) * 0.15, maxR = Double(max(w, h)) * 25
        let tol = 2.0
        for _ in 0..<2000 {
            let a = pts[Int.random(in: 0..<pts.count, using: &rng)]
            let b = pts[Int.random(in: 0..<pts.count, using: &rng)]
            let c = pts[Int.random(in: 0..<pts.count, using: &rng)]
            guard let circ = circleFrom(a, b, c), circ.r > minR, circ.r < maxR else { continue }
            var n = 0
            for p in pts where abs(hypot(p.0 - circ.cx, p.1 - circ.cy) - circ.r) < tol { n += 1 }
            if best == nil || n > best!.inliers { best = LimbCircle(cx: circ.cx, cy: circ.cy, r: circ.r, inliers: n) }
        }
        if ProcessInfo.processInfo.environment["SR_DEBUG"] != nil { print("limb pts \(pts.count) best \(String(describing: best))") }
        guard var b = best, b.inliers >= max(30, pts.count / 4) else { return nil }
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

    // MARK: Krater (Schatten-/Licht-Regionen)

    /// Momentensummen einer zusammenhängenden Region
    struct Region {
        var n = 0.0, sx = 0.0, sy = 0.0, sxx = 0.0, syy = 0.0, sxy = 0.0, sL = 0.0
        var sxz = 0.0, syz = 0.0, sz = 0.0
        mutating func add(_ x: Double, _ y: Double, _ l: Double) {
            n += 1; sx += x; sy += y; sxx += x * x; syy += y * y; sxy += x * y; sL += l
            let z = x * x + y * y; sxz += x * z; syz += y * z; sz += z
        }
        static func + (a: Region, b: Region) -> Region {
            var r = a
            r.n += b.n; r.sx += b.sx; r.sy += b.sy; r.sxx += b.sxx; r.syy += b.syy; r.sxy += b.sxy; r.sL += b.sL
            r.sxz += b.sxz; r.syz += b.syz; r.sz += b.sz
            return r
        }
        var cx: Double { sx / n }
        var cy: Double { sy / n }
        var meanL: Double { sL / n }
        /// Ellipse gleicher Momente: Halbachsen A ≥ B, Winkel der großen Achse
        var ellipse: (A: Double, B: Double, angle: Double) {
            let vxx = sxx / n - cx * cx, vyy = syy / n - cy * cy, vxy = sxy / n - cx * cy
            let tr = vxx + vyy, det = vxx * vyy - vxy * vxy
            let disc = max(0, tr * tr / 4 - det).squareRoot()
            let l1 = max(tr / 2 + disc, 0.25), l2 = max(tr / 2 - disc, 0.25)
            return (2 * l1.squareRoot(), 2 * l2.squareRoot(), 0.5 * atan2(2 * vxy, vxx - vyy))
        }
        var fill: Double { let e = ellipse; return n / (.pi * e.A * e.B) }
        /// Algebraischer Kreisfit (Kasa) an alle Pixel der Region
        var kasa: (cx: Double, cy: Double, r: Double)? {
            let A = [sxx, sxy, sx, sxy, syy, sy, sx, sy, n]
            guard let s = solveLinear(A, [sxz, syz, sz], n: 3) else { return nil }
            let cx = s[0] / 2, cy = s[1] / 2, r2 = s[2] + cx * cx + cy * cy
            return r2 > 0 ? (cx, cy, r2.squareRoot()) : nil
        }
    }

    /// Zusammenhangskomponenten einer Maske mit Momenten
    static func regions(_ mask: [Bool], _ w: Int, _ h: Int, L: [Float], minArea: Int) -> [Region] {
        var seen = [Bool](repeating: false, count: mask.count)
        var out: [Region] = []
        var stack: [Int] = []
        for s in 0..<mask.count where mask[s] && !seen[s] {
            var r = Region()
            stack.removeAll(keepingCapacity: true)
            stack.append(s); seen[s] = true
            while let p = stack.popLast() {
                let x = p % w, y = p / w
                r.add(Double(x), Double(y), Double(L[p]))
                if x > 0 { let q = p - 1; if mask[q] && !seen[q] { seen[q] = true; stack.append(q) } }
                if x < w - 1 { let q = p + 1; if mask[q] && !seen[q] { seen[q] = true; stack.append(q) } }
                if y > 0 { let q = p - w; if mask[q] && !seen[q] { seen[q] = true; stack.append(q) } }
                if y < h - 1 { let q = p + w; if mask[q] && !seen[q] { seen[q] = true; stack.append(q) } }
            }
            if Int(r.n) >= minArea { out.append(r) }
        }
        return out
    }

    static func gauss(_ img: GrayImage, sigma: Double) -> GrayImage {
        let r = max(1, Int((sigma * sigma + 1).squareRoot().rounded()))
        return img.boxBlurred(radius: r).boxBlurred(radius: r).boxBlurred(radius: r)
    }

    /// Ergebnis der Beleuchtungsanalyse (für Log und Tests)
    public struct CraterScan: Sendable {
        public var craters: [DetectedCrater]
        public var sunAngleDeg: Double
        public var sunFromLimb: Bool
    }

    /// Kratererkennung über Licht und Schatten:
    /// 1. Helligkeit relativ zur lokalen Umgebung (L), Schatten- und Lichtregionen auf mehreren Schwellen
    /// 2. Sonnenrichtung: Achse aus benachbarten Schatten/Licht-Paaren, Vorzeichen über den beleuchteten Mondrand
    /// 3. Krater = kompakter Schatten + beleuchtete Innenwand auf der sonnenabgewandten Seite (Ellipse, da randnah verkürzt)
    /// 4. Große, flache Krater: Schattensichel + gegenüberliegende Lichtsichel auf gemeinsamem Kreis
    public static func scanCraters(_ input: GrayImage, maxCount: Int) -> CraterScan {
        let (img, f) = input.limited(maxDimension: 1700)
        let w = img.width, h = img.height, n = w * h
        let ff = Double(f)
        // Normierung
        var sample = stride(from: 0, to: n, by: 7).map { img.pixels[$0] }
        sample.sort()
        let white = max(sample[Int(Double(sample.count - 1) * 0.998)], 1e-3)
        var I = img
        for k in 0..<n { I.pixels[k] = min(1.2, I.pixels[k] / white) }
        let sky = Double(sample[Int(Double(sample.count - 1) * 0.02)] / white)
        let otsuThr = otsu(I.pixels)
        var litSum = 0.0, litN = 0.0
        for v in I.pixels where v > otsuThr { litSum += Double(v); litN += 1 }
        let lit = litN > 0 ? litSum / litN : 0.5
        // Mondmaske (inkl. dunkler Maria), Löcher füllen
        let bl = I.boxBlurred(radius: max(4, min(w, h) / 60))
        let mThr = Float(sky + 0.12 * (lit - sky))
        var moon = bl.pixels.map { $0 > mThr }
        moon = fillHoles(moon, w, h)
        // Innenbereich (8 px Abstand zum Rand)
        var mf = GrayImage(width: w, height: h, pixels: moon.map { $0 ? 1 : 0 })
        mf = mf.boxBlurred(radius: 8)
        let interior = mf.pixels.map { $0 > 0.999 }
        // L = geglättetes Bild / großräumiger Hintergrund
        let Is = I.boxBlurred(radius: 1)
        var meanMoon = 0.0, cnt = 0.0
        for k in 0..<n where moon[k] { meanMoon += Double(I.pixels[k]); cnt += 1 }
        meanMoon /= max(cnt, 1)
        var filled = I
        for k in 0..<n where !moon[k] { filled.pixels[k] = Float(meanMoon) }
        let Bg = gauss(filled, sigma: Double(min(w, h)) / 14)
        var L = [Float](repeating: 1, count: n)
        for k in 0..<n { L[k] = Is.pixels[k] / (Bg.pixels[k] + 1e-3) }
        let minDim = Double(min(w, h))

        func masked(_ pred: (Float) -> Bool) -> [Bool] { (0..<n).map { interior[$0] && pred(L[$0]) } }
        // Schatten- und Lichtregionen
        var darks: [Region] = [], arcsSrc: [Region] = []
        for t in [0.45, 0.55, 0.65, 0.75, 0.85] as [Float] {
            for r in regions(masked { $0 < t }, w, h, L: L, minArea: 12) {
                let e = r.ellipse
                if r.fill > 0.55 && e.A < minDim / 4 && e.A / e.B < 4.5 { darks.append(r) }
                else if [0.55, 0.7, 0.85].contains(t) && r.n >= 25 { arcsSrc.append(r) }
            }
        }
        var brights: [Region] = []
        for t in [1.08, 1.18, 1.3, 1.45] as [Float] {
            for r in regions(masked { $0 > t }, w, h, L: L, minArea: 6) {
                let e = r.ellipse
                if e.A < minDim / 4 && e.A / e.B < 6 { brights.append(r) }
            }
        }
        // Sonnenachse aus nahen Paaren (Winkelverdopplung)
        var c2 = 0.0, s2 = 0.0
        for d in darks {
            let ed = d.ellipse
            guard ed.A < minDim / 12 else { continue }
            var best: (Double, Region)?
            for b in brights where b.ellipse.A < 2.5 * ed.A {
                let dist = hypot(b.cx - d.cx, b.cy - d.cy)
                if dist < 2.2 * ed.A, dist > 1, best == nil || dist < best!.0 { best = (dist, b) }
            }
            guard let b = best?.1 else { continue }
            let a = atan2(d.cy - b.cy, d.cx - b.cx)
            c2 += cos(2 * a); s2 += sin(2 * a)
        }
        let axis = 0.5 * atan2(s2, c2)
        // Vorzeichen: zum sichtbaren, beleuchteten Mondrand hin – sonst entlang des Helligkeitsanstiegs
        let skyThr = Float(sky + 0.06 * (lit - sky))
        var ex = 0.0, ey = 0.0, en = 0.0, mx = 0.0, my = 0.0, mn = 0.0
        let bl5 = I.boxBlurred(radius: 2)
        for y in stride(from: 3, to: h - 3, by: 2) {
            for x in stride(from: 3, to: w - 3, by: 2) {
                let k = y * w + x
                guard moon[k] else { continue }
                mx += Double(x); my += Double(y); mn += 1
                var nearSky = false
                for (dx, dy) in [(3, 0), (-3, 0), (0, 3), (0, -3)] {
                    let q = (y + dy) * w + x + dx
                    if !moon[q] && bl5.pixels[q] < skyThr { nearSky = true }
                }
                if nearSky { ex += Double(x); ey += Double(y); en += 1 }
            }
        }
        var refDir: Double
        var fromLimb = false
        if en > 25 && mn > 0 {
            refDir = atan2(ey / en - my / mn, ex / en - mx / mn); fromLimb = true
        } else {
            let g = gauss(I, sigma: minDim / 8)
            var gx = 0.0, gy = 0.0
            for y in stride(from: 1, to: h - 1, by: 3) { for x in stride(from: 1, to: w - 1, by: 3) where moon[y * w + x] {
                gx += Double(g[x + 1, y] - g[x - 1, y]); gy += Double(g[x, y + 1] - g[x, y - 1])
            } }
            refDir = atan2(gy, gx)
        }
        func angDiff(_ a: Double, _ b: Double) -> Double { abs(atan2(sin(a - b), cos(a - b))) }
        let sunA = angDiff(axis, refDir) <= angDiff(axis + .pi, refDir) ? axis : axis + .pi
        let sx = cos(sunA), sy = sin(sunA)

        // Kraterhypothesen
        struct Cand { var x, y, A, B, angle, score: Double }
        var cands: [Cand] = []
        for d in darks {
            let ed = d.ellipse
            var best: (Double, Region)?
            for b in brights {
                let vx = b.cx - d.cx, vy = b.cy - d.cy, dist = hypot(vx, vy)
                if dist < 0.3 * ed.A || dist > 2.5 * ed.A { continue }
                let cosang = -(vx * sx + vy * sy) / dist
                if cosang < 0.5 { continue }
                let sc = cosang * min(1, b.n / (0.15 * d.n + 1))
                if best == nil || sc > best!.0 { best = (sc, b) }
            }
            let shadow = max(0, 1 - d.meanL)
            var region = d
            var score: Double
            if let (sc, b) = best {
                score = shadow * sc * d.fill * min(1.5, (b.meanL - 1) * 4 + 0.5)
                region = d + b
            } else {
                score = shadow * 0.35 * d.fill
            }
            let e = region.ellipse
            if e.A / e.B > 3.2 { continue }
            cands.append(Cand(x: region.cx, y: region.cy, A: e.A, B: e.B, angle: e.angle, score: score))
        }
        // Große Krater aus Schattensicheln
        for d in arcsSrc {
            let ed = d.ellipse
            guard ed.A >= 6, ed.A <= minDim / 5, let fit = d.kasa else { continue }
            let R = fit.r
            if R < 1.2 * ed.B || R > 2.5 * ed.A || R > minDim / 4 { continue }
            let vx = fit.cx - d.cx, vy = fit.cy - d.cy, vn = hypot(vx, vy)
            if vn < 0.3 * R || (-(vx * sx + vy * sy)) / vn < 0.55 { continue }
            var hits = 0, tot = 0
            for k in 0..<24 {
                let a = Double(k) / 24 * 2 * .pi
                let ux = cos(a), uy = sin(a)
                if -(ux * sx + uy * sy) < 0.2 { continue }
                tot += 1
                for dr in stride(from: -0.2, through: 0.15, by: 0.07) {
                    let px = Int(fit.cx + ux * R * (1 + dr)), py = Int(fit.cy + uy * R * (1 + dr))
                    if px >= 0, py >= 0, px < w, py < h, L[py * w + px] > 1.08 { hits += 1; break }
                }
            }
            let cov = Double(hits) / Double(max(1, tot))
            let ix = Int(fit.cx), iy = Int(fit.cy)
            guard cov >= 0.45, ix >= 0, iy >= 0, ix < w, iy < h, moon[iy * w + ix] else { continue }
            cands.append(Cand(x: fit.cx, y: fit.cy, A: R, B: R, angle: 0, score: cov * (1 - d.meanL) * 1.2))
        }
        // Nicht-Maximum-Unterdrückung
        cands.sort { $0.score * pow($0.A, 0.5) > $1.score * pow($1.A, 0.5) }
        var keep: [Cand] = []
        for c in cands where c.score >= 0.05 {
            if keep.contains(where: { hypot($0.x - c.x, $0.y - c.y) < 0.7 * max($0.A, c.A) }) { continue }
            keep.append(c)
        }
        if maxCount <= 15 {
            keep = keep.filter { $0.score > 0.12 }
            keep.sort { a, b in
                a.score * (a.A * a.B).squareRoot() * min(1, 2 / (a.A / a.B)) > b.score * (b.A * b.B).squareRoot() * min(1, 2 / (b.A / b.B))
            }
        }
        keep = Array(keep.prefix(maxCount))
        let craters = keep.map { c in
            DetectedCrater(x: (c.x + 0.5) * ff - 0.5, y: (c.y + 0.5) * ff - 0.5, r: c.A * ff, strength: c.score,
                           shadowFraction: 0, minorRadius: c.B * ff, angleDeg: rad2deg(c.angle))
        }.sorted { $0.r > $1.r }
        var deg = rad2deg(sunA).truncatingRemainder(dividingBy: 360); if deg < 0 { deg += 360 }
        return CraterScan(craters: craters, sunAngleDeg: deg, sunFromLimb: fromLimb)
    }

    static func otsu(_ px: [Float]) -> Float {
        var hist = [Double](repeating: 0, count: 256)
        for v in stride(from: 0, to: px.count, by: 3) { hist[min(255, max(0, Int(px[v] / 1.2 * 255)))] += 1 }
        let total = hist.reduce(0, +)
        var sumAll = 0.0
        for k in 0..<256 { sumAll += Double(k) * hist[k] }
        var wB = 0.0, sumB = 0.0, best = 0.0, thr = 0
        for k in 0..<256 {
            wB += hist[k]; if wB == 0 { continue }
            let wF = total - wB; if wF == 0 { break }
            sumB += Double(k) * hist[k]
            let mB = sumB / wB, mF = (sumAll - sumB) / wF
            let b = wB * wF * (mB - mF) * (mB - mF)
            if b > best { best = b; thr = k }
        }
        return Float(thr) / 255 * 1.2
    }

    /// Löcher füllen: alles, was nicht vom Bildrand über Nicht-Mond erreichbar ist, gehört zum Mond
    static func fillHoles(_ m: [Bool], _ w: Int, _ h: Int) -> [Bool] {
        var outside = [Bool](repeating: false, count: m.count)
        var stack: [Int] = []
        for x in 0..<w { for y in [0, h - 1] { let k = y * w + x; if !m[k] && !outside[k] { outside[k] = true; stack.append(k) } } }
        for y in 0..<h { for x in [0, w - 1] { let k = y * w + x; if !m[k] && !outside[k] { outside[k] = true; stack.append(k) } } }
        while let p = stack.popLast() {
            let x = p % w, y = p / w
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let nx = x + dx, ny = y + dy
                guard nx >= 0, ny >= 0, nx < w, ny < h else { continue }
                let q = ny * w + nx
                if !m[q] && !outside[q] { outside[q] = true; stack.append(q) }
            }
        }
        return outside.map { !$0 }
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
        let scan = scanCraters(img, maxCount: maxCount)
        info(String(format: "Sonnenrichtung im Bild: %.0f° (%@)", scan.sunAngleDeg, scan.sunFromLimb ? "aus beleuchtetem Mondrand" : "aus Helligkeitsverlauf"))
        var craters = scan.craters
        // außerhalb des vermessenen Mondrands liegende Kandidaten verwerfen
        if let l = limb { craters = craters.filter { hypot($0.x - l.cx, $0.y - l.cy) < l.r - $0.minorRadius * 0.5 } }
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
            if c.minorRadius > 0 && c.r > 0 {
                let ratio = min(1, c.minorRadius / c.r)
                facts.append(InfoFact("Form im Bild", String(format: "Ellipse, Achsenverhältnis %.2f", ratio).replacingOccurrences(of: ".", with: ",")))
                if ratio < 0.9 { facts.append(InfoFact("Perspektive", String(format: "schräg gesehen (ca. %.0f° Blickwinkel) – Durchmesser entlang der langen Achse gemessen", rad2deg(acos(ratio))))) }
            }
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
