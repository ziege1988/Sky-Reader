import Foundation

public struct DetectedStar: Sendable {
    public var x: Double
    public var y: Double
    public var flux: Double
    public var peak: Float
    public var area: Int
    public var elongation: Double
}

/// Hintergrundmodell: Gitter aus Median/Streuung, bilinear interpoliert.
public struct BackgroundModel {
    public let cell: Int
    public let gw: Int, gh: Int
    public var level: [Float]
    public var sigma: [Float]

    public init(image: GrayImage, cell: Int = 48) {
        self.cell = cell
        gw = max(1, (image.width + cell - 1) / cell)
        gh = max(1, (image.height + cell - 1) / cell)
        level = [Float](repeating: 0, count: gw * gh)
        sigma = [Float](repeating: 0, count: gw * gh)
        var buf: [Float] = []
        buf.reserveCapacity(cell * cell)
        for gy in 0..<gh {
            for gx in 0..<gw {
                buf.removeAll(keepingCapacity: true)
                let x0 = gx * cell, y0 = gy * cell
                let x1 = min(x0 + cell, image.width), y1 = min(y0 + cell, image.height)
                var y = y0
                while y < y1 { var x = x0; while x < x1 { buf.append(image[x, y]); x += 2 }; y += 2 }
                buf.sort()
                // Sterne fallen in das obere Ende – Median und unteres Quantil sind robust
                let med = buf[buf.count / 2]
                let q16 = buf[max(0, Int(Double(buf.count) * 0.16))]
                level[gy * gw + gx] = med
                sigma[gy * gw + gx] = max(med - q16, 1e-4)
            }
        }
        // 3×3-Median-Glättung des Gitters
        level = BackgroundModel.medianFilter(level, gw, gh)
        sigma = BackgroundModel.medianFilter(sigma, gw, gh)
    }

    static func medianFilter(_ a: [Float], _ w: Int, _ h: Int) -> [Float] {
        var out = a
        var n: [Float] = []
        for y in 0..<h { for x in 0..<w {
            n.removeAll(keepingCapacity: true)
            for dy in -1...1 { for dx in -1...1 {
                let xx = x + dx, yy = y + dy
                if xx >= 0, yy >= 0, xx < w, yy < h { n.append(a[yy * w + xx]) }
            } }
            n.sort(); out[y * w + x] = n[n.count / 2]
        } }
        return out
    }

    @inline(__always) func interp(_ arr: [Float], _ x: Int, _ y: Int) -> Float {
        let fx = (Float(x) + 0.5) / Float(cell) - 0.5, fy = (Float(y) + 0.5) / Float(cell) - 0.5
        let x0 = max(0, min(gw - 1, Int(floor(fx)))), y0 = max(0, min(gh - 1, Int(floor(fy))))
        let x1 = min(gw - 1, x0 + 1), y1 = min(gh - 1, y0 + 1)
        let tx = max(0, min(1, fx - Float(x0))), ty = max(0, min(1, fy - Float(y0)))
        let a = arr[y0 * gw + x0] * (1 - tx) + arr[y0 * gw + x1] * tx
        let b = arr[y1 * gw + x0] * (1 - tx) + arr[y1 * gw + x1] * tx
        return a * (1 - ty) + b * ty
    }

    public func level(at x: Int, _ y: Int) -> Float { interp(level, x, y) }
    public func sigma(at x: Int, _ y: Int) -> Float { interp(sigma, x, y) }
}

public enum StarDetector {
    /// Findet punktförmige Sterne. Ausgedehnte Objekte (Nebel, Galaxien, Kometen) werden verworfen.
    public static func detect(_ img: GrayImage, maxStars: Int = 400, kSigma: Float = 5) -> [DetectedStar] {
        let w = img.width, h = img.height
        // leichte Glättung gegen Rauschen / Hotpixel
        let sm = img.boxBlurred(radius: 1)
        let bg = BackgroundModel(image: sm)
        var resid = [Float](repeating: 0, count: w * h)
        var thr = [Float](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                resid[i] = sm.pixels[i] - bg.level(at: x, y)
                thr[i] = kSigma * bg.sigma(at: x, y)
            }
        }
        var visited = [Bool](repeating: false, count: w * h)
        var stars: [DetectedStar] = []
        var stack: [Int] = []
        let border = 4
        for y in border..<(h - border) {
            for x in border..<(w - border) {
                let i = y * w + x
                let v = resid[i]
                if v <= thr[i] || visited[i] { continue }
                // lokales Maximum?
                var isMax = true
                for dy in -1...1 { for dx in -1...1 where dx != 0 || dy != 0 {
                    if resid[i + dy * w + dx] > v { isMax = false }
                } }
                if !isMax { continue }
                // Flood-Fill der zusammenhängenden Fläche oberhalb halber Schwelle
                let floorV = max(thr[i] * 0.5, v * 0.08)
                stack.removeAll(keepingCapacity: true)
                stack.append(i); visited[i] = true
                var sx = 0.0, sy = 0.0, sf = 0.0, sxx = 0.0, syy = 0.0, sxy = 0.0
                var area = 0
                var peak: Float = 0
                var touchesBorder = false
                var tooBig = false
                while let p = stack.popLast() {
                    let py = p / w, px = p % w
                    let f = Double(resid[p])
                    area += 1
                    peak = max(peak, img.pixels[p])
                    sx += f * Double(px); sy += f * Double(py); sf += f
                    sxx += f * Double(px * px); syy += f * Double(py * py); sxy += f * Double(px * py)
                    if area > 2500 { tooBig = true; break }
                    for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                        let nx = px + dx, ny = py + dy
                        if nx < 1 || ny < 1 || nx >= w - 1 || ny >= h - 1 { touchesBorder = true; continue }
                        let q = ny * w + nx
                        if !visited[q] && resid[q] > floorV { visited[q] = true; stack.append(q) }
                    }
                }
                if tooBig || touchesBorder || area < 3 || sf <= 0 { continue }
                let cx = sx / sf, cy = sy / sf
                let vxx = sxx / sf - cx * cx, vyy = syy / sf - cy * cy, vxy = sxy / sf - cx * cy
                let tr = vxx + vyy, det = vxx * vyy - vxy * vxy
                let disc = max(0, tr * tr / 4 - det).squareRoot()
                let l1 = tr / 2 + disc, l2 = max(tr / 2 - disc, 1e-6)
                let elong = (l1 / l2).squareRoot()
                if elong > 2.2 { continue }
                // Ausgedehnte, flache Flecken (Galaxien/Nebelknoten) verwerfen: Fläche vs. Spitzenhelligkeit
                let saturated = peak > 0.97
                if !saturated && area > 40 && Double(v) < 6 * Double(thr[i]) && area > 120 { continue }
                stars.append(DetectedStar(x: cx, y: cy, flux: sf, peak: peak, area: area, elongation: elong))
            }
        }
        stars.sort { $0.flux > $1.flux }
        // Doppelte (sehr nahe) Detektionen zusammenfassen
        var out: [DetectedStar] = []
        for s in stars {
            if out.count >= maxStars { break }
            if out.contains(where: { abs($0.x - s.x) < 3 && abs($0.y - s.y) < 3 }) { continue }
            out.append(s)
        }
        return out
    }
}
