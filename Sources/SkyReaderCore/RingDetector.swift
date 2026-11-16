import Foundation

/// Ringwall-Detektor: findet Krater über ihre (meist hellen) kreisförmigen Wälle – ergänzt die
/// schattenbasierte Erkennung bei hohem Sonnenstand. Kreis-Hough mit Kantenrichtung über eine Bildpyramide.
public enum RingDetector {
    public static func detect(_ input: GrayImage, maxCount: Int = 80) -> [DetectedCrater] {
        let (img, f) = input.limited(maxDimension: 1700)
        var all: [DetectedCrater] = []
        var level = 1
        while Double(min(img.width, img.height)) / Double(level) > 80 && level <= 8 {
            let lv = img.downsampled(by: level)
            let rMin = level == 1 ? 5.0 : 6.0
            for c in detectLevel(lv, rMin: rMin, rMax: 22) {
                all.append(DetectedCrater(x: (c.x + 0.5) * Double(level) - 0.5, y: (c.y + 0.5) * Double(level) - 0.5,
                                          r: c.r * Double(level), strength: c.strength, shadowFraction: 0))
            }
            level *= 2
        }
        // Zusammenführen über Ebenen
        all.sort { $0.strength * pow($0.r, 0.2) > $1.strength * pow($1.r, 0.2) }
        var out: [DetectedCrater] = []
        for c in all {
            if out.contains(where: { o in
                let d = hypot(o.x - c.x, o.y - c.y), ratio = min(o.r, c.r) / max(o.r, c.r)
                return (d < 0.5 * max(o.r, c.r) && ratio > 0.6) || d < 0.25 * max(o.r, c.r)
            }) { continue }
            out.append(c)
            if out.count >= maxCount { break }
        }
        let ff = Double(f)
        return out.map { DetectedCrater(x: ($0.x + 0.5) * ff - 0.5, y: ($0.y + 0.5) * ff - 0.5, r: $0.r * ff,
                                        strength: $0.strength, shadowFraction: 0) }
    }

    static func detectLevel(_ raw: GrayImage, rMin: Double, rMax: Double) -> [DetectedCrater] {
        let w = raw.width, h = raw.height, n = w * h
        guard w > 2 * Int(rMax) + 8, h > 2 * Int(rMax) + 8 else { return [] }
        // lokale Kontrastnormierung (Maria und Hochland gleich behandeln)
        let sm = raw.boxBlurred(radius: 1).boxBlurred(radius: 1)
        let bg = sm.boxBlurred(radius: 12).boxBlurred(radius: 12)
        var mean: Float = 0
        for v in sm.pixels { mean += v }
        mean /= Float(n)
        var I = sm
        for k in 0..<n { I.pixels[k] = sm.pixels[k] / (bg.pixels[k] + 0.15 * mean) }
        // Gradienten
        var gx = [Float](repeating: 0, count: n), gy = gx, mag = gx
        for y in 1..<(h - 1) {
            for x in 1..<(w - 1) {
                let i = y * w + x
                let a = I.pixels[i - w - 1], b = I.pixels[i - w], c = I.pixels[i - w + 1]
                let d = I.pixels[i - 1], e = I.pixels[i + 1]
                let g = I.pixels[i + w - 1], hh = I.pixels[i + w], k = I.pixels[i + w + 1]
                let sx = (c + 2 * e + k) - (a + 2 * d + g), sy = (g + 2 * hh + k) - (a + 2 * b + c)
                gx[i] = sx; gy[i] = sy; mag[i] = (sx * sx + sy * sy).squareRoot()
            }
        }
        // nur Mondfläche (nicht schwarzer Himmel / Nachtseite)
        let darkThr = mean * 0.25
        var sample: [Float] = []
        for k in stride(from: 0, to: n, by: 3) where sm.pixels[k] > darkThr { sample.append(mag[k]) }
        guard sample.count > 100 else { return [] }
        sample.sort()
        let edgeThr = sample[Int(Double(sample.count - 1) * 0.82)]
        // Kanten mit Nicht-Maximum-Unterdrückung entlang der Gradientenrichtung
        var edges: [Int] = []
        for y in 2..<(h - 2) {
            for x in 2..<(w - 2) {
                let i = y * w + x
                let m = mag[i]
                guard m >= edgeThr, sm.pixels[i] > darkThr else { continue }
                let ux = gx[i] / m, uy = gy[i] / m
                let dx = Int((ux).rounded()), dy = Int((uy).rounded())
                if mag[i + dy * w + dx] > m || mag[i - dy * w - dx] > m { continue }
                edges.append(i)
            }
        }
        // Mittelpunkt-Akkumulator: Abstimmung entlang ±Gradient
        var acc = [Float](repeating: 0, count: n)
        for i in edges {
            let x = Double(i % w), y = Double(i / w)
            let m = Double(mag[i])
            let ux = Double(gx[i]) / m, uy = Double(gy[i]) / m
            for sgn in [-1.0, 1.0] {
                var t = rMin
                while t <= rMax {
                    let cx = Int((x + sgn * ux * t).rounded()), cy = Int((y + sgn * uy * t).rounded())
                    if cx >= 0, cy >= 0, cx < w, cy < h { acc[cy * w + cx] += 1 }
                    t += 1
                }
            }
        }
        let accImg = GrayImage(width: w, height: h, pixels: acc).boxBlurred(radius: 1)
        // Spitzen
        var peaks: [(Int, Int, Float)] = []
        let m0 = Int(rMax) + 2
        for y in m0..<(h - m0) {
            for x in m0..<(w - m0) {
                let v = accImg[x, y]
                guard v >= 2.5 else { continue }
                var isMax = true
                loop: for dy in -3...3 { for dx in -3...3 where dx != 0 || dy != 0 {
                    if accImg[x + dx, y + dy] > v { isMax = false; break loop }
                } }
                if isMax { peaks.append((x, y, v)) }
            }
        }
        peaks.sort { $0.2 > $1.2 }
        // Radius je Spitze: radial ausgerichtete Kanten im Abstand r
        var out: [DetectedCrater] = []
        let nBins = Int(rMax) + 3
        for (px, py, _) in peaks.prefix(600) {
            var bins = [Double](repeating: 0, count: nBins)
            var sectors = [[Bool]](repeating: [Bool](repeating: false, count: 24), count: nBins)
            let R = Int(rMax) + 2
            for yy in max(1, py - R)...min(h - 2, py + R) {
                for xx in max(1, px - R)...min(w - 2, px + R) {
                    let i = yy * w + xx
                    let m = mag[i]
                    guard m >= edgeThr * 0.8 else { continue }
                    let dx = Double(xx - px), dy = Double(yy - py)
                    let d = (dx * dx + dy * dy).squareRoot()
                    guard d >= rMin - 1, d < Double(nBins - 1) else { continue }
                    let radial = abs(Double(gx[i]) * dx + Double(gy[i]) * dy) / (Double(m) * d)
                    guard radial > 0.85 else { continue }
                    let b = Int(d.rounded())
                    bins[b] += 1
                    var a = atan2(dy, dx); if a < 0 { a += 2 * .pi }
                    sectors[b][min(23, Int(a / (2 * .pi) * 24))] = true
                }
            }
            var best = (0.0, 0, 0)
            for b in Int(rMin)...(nBins - 2) {
                let s = (bins[b - 1] * 0.5 + bins[b] + bins[b + 1] * 0.5) / (2 * .pi * Double(b))
                var cov = 0
                for k in 0..<24 where sectors[b][k] || sectors[b - 1][k] || sectors[b + 1][k] { cov += 1 }
                let score = min(1.2, s) * Double(cov) / 24
                if score > best.0 { best = (score, b, cov) }
            }
            guard best.2 >= 13, best.0 >= 0.3 else { continue }
            out.append(DetectedCrater(x: Double(px), y: Double(py), r: Double(best.1), strength: best.0, shadowFraction: 0))
        }
        return out
    }

    /// Vereinigt Ring- und Schatten-Erkennungen; bei Überschneidung zählt der Ring (genauere Mitte und Größe)
    public static func merge(rings: [DetectedCrater], shadows: [DetectedCrater]) -> [DetectedCrater] {
        var out = rings
        for s in shadows {
            if let k = out.firstIndex(where: { o in
                let d = hypot(o.x - s.x, o.y - s.y), ratio = min(o.r, s.r) / max(o.r, s.r)
                return d < 0.6 * max(o.r, s.r) && ratio > 0.45
            }) {
                out[k].strength = max(out[k].strength, s.strength)
                if out[k].minorRadius == 0 { out[k].minorRadius = s.minorRadius; out[k].angleDeg = s.angleDeg }
            } else {
                out.append(s)
            }
        }
        return out
    }
}
