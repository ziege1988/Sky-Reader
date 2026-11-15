import Foundation

/// Geometrischer Hash einer Vierergruppe von Sternen (invariant gegen Verschiebung, Drehung, Skalierung).
public struct QuadHash {
    public var h: (Float, Float, Float, Float)
    /// Reihenfolge der Eingabepunkte: A, B, C, D
    public var order: (Int, Int, Int, Int)
    /// Größter Abstand AB (Einheit der Eingabe)
    public var size: Double

    public static func compute(_ p: [(Double, Double)]) -> QuadHash? {
        // größtes Paar
        var best = -1.0, ia = 0, ib = 1
        for i in 0..<4 { for j in (i + 1)..<4 {
            let dx = p[i].0 - p[j].0, dy = p[i].1 - p[j].1
            let d = dx * dx + dy * dy
            if d > best { best = d; ia = i; ib = j }
        } }
        if best <= 0 { return nil }
        let others = (0..<4).filter { $0 != ia && $0 != ib }
        func frame(_ a: Int, _ b: Int) -> [(Double, Double)] {
            // z' = (z - A) / (B - A) * (1 + i)
            let ax = p[a].0, ay = p[a].1
            let bx = p[b].0 - ax, by = p[b].1 - ay
            let den = bx * bx + by * by
            return others.map { k in
                let zx = p[k].0 - ax, zy = p[k].1 - ay
                // (z / (B-A))
                let qx = (zx * bx + zy * by) / den, qy = (zy * bx - zx * by) / den
                // * (1 + i)
                return (qx - qy, qx + qy)
            }
        }
        var a = ia, b = ib
        var c = frame(a, b)
        if c[0].0 + c[1].0 > 1 { swap(&a, &b); c = frame(a, b) }
        var ic = others[0], id = others[1]
        var cc = c[0], dd = c[1]
        if cc.0 > dd.0 { swap(&cc, &dd); swap(&ic, &id) }
        return QuadHash(h: (Float(cc.0), Float(cc.1), Float(dd.0), Float(dd.1)), order: (a, b, ic, id), size: best.squareRoot())
    }
}

/// Quad-Index für eine Maßstabsstufe (Zellgröße in Grad).
public final class QuadIndex: @unchecked Sendable {
    public let cellDeg: Double
    public private(set) var hashes: [Float] = []   // 4 je Quad
    public private(set) var stars: [Int32] = []    // 4 je Quad (A,B,C,D)
    public var count: Int { stars.count / 4 }

    // Buckets über (h0, h1)
    static let lo: Float = -0.7, binSize: Float = 0.025
    static let bins = 96
    private var bucketStart: [Int32] = []
    private var bucketItems: [Int32] = []

    public init(catalog: StarCatalog, cellDeg c: Double, perCell K: Int = 4, neighbors M: Int = 4, isCancelled: () -> Bool = { false }) {
        cellDeg = c
        // 1) Pro Himmelszelle die K hellsten Sterne
        let nRows = Int(ceil(180 / c))
        var rowCols = [Int](repeating: 1, count: nRows), rowOff = [Int](repeating: 0, count: nRows + 1)
        for r in 0..<nRows {
            let mid = -90 + (Double(r) + 0.5) * c
            rowCols[r] = max(1, Int(360 * cos(deg2rad(mid)) / c))
            rowOff[r + 1] = rowOff[r] + rowCols[r]
        }
        let nCells = rowOff[nRows]
        var slot = [Int32](repeating: -1, count: nCells * K)
        for i in 0..<catalog.count {
            let r = min(nRows - 1, max(0, Int((Double(catalog.dec[i]) + 90) / c)))
            let col = min(rowCols[r] - 1, Int(Double(catalog.ra[i]) / 360 * Double(rowCols[r])))
            let base = (rowOff[r] + col) * K
            let m = catalog.mag[i]
            // Einfügen (sortiert nach Helligkeit)
            var pos = -1
            for k in 0..<K {
                let s = slot[base + k]
                if s < 0 || catalog.mag[Int(s)] > m { pos = k; break }
            }
            if pos < 0 { continue }
            var k = K - 1
            while k > pos { slot[base + k] = slot[base + k - 1]; k -= 1 }
            slot[base + pos] = Int32(i)
        }
        let sel = slot.filter { $0 >= 0 }.map { Int($0) }
        if isCancelled() { return }
        // 2) Räumlicher Hash auf Einheitsvektoren
        let g = deg2rad(c * 1.6)
        func key(_ i: Int) -> (Int, Int, Int) {
            (Int(floor(Double(catalog.x[i]) / g)), Int(floor(Double(catalog.y[i]) / g)), Int(floor(Double(catalog.z[i]) / g)))
        }
        var grid: [Int64: [Int]] = [:]
        @inline(__always) func pack(_ a: Int, _ b: Int, _ c: Int) -> Int64 {
            (Int64(a + 4096) << 26) | (Int64(b + 4096) << 13) | Int64(c + 4096)
        }
        for i in sel { let k = key(i); grid[pack(k.0, k.1, k.2), default: []].append(i) }
        let maxDist = deg2rad(c * 1.6)
        let cosMax = cos(maxDist)
        // 3) Quads aus Stern + 3 seiner M nächsten Nachbarn
        var seen = Set<SIMD4<Int32>>()
        var hs: [Float] = [], st: [Int32] = []
        let combos = Array<Int>.combinations(M, 3)
        for s in sel {
            let k = key(s)
            var cand: [(Int, Float)] = []
            for dx in -1...1 { for dy in -1...1 { for dz in -1...1 {
                guard let l = grid[pack(k.0 + dx, k.1 + dy, k.2 + dz)] else { continue }
                for j in l where j != s {
                    let d = catalog.x[s] * catalog.x[j] + catalog.y[s] * catalog.y[j] + catalog.z[s] * catalog.z[j]
                    if Double(d) >= cosMax { cand.append((j, d)) }
                }
            } } }
            if cand.count < 3 { continue }
            cand.sort { $0.1 > $1.1 }
            let nb = cand.prefix(M).map { $0.0 }
            let ra0 = Double(catalog.ra[s]), dec0 = Double(catalog.dec[s])
            for cmb in combos where cmb.allSatisfy({ $0 < nb.count }) {
                let ids = [s, nb[cmb[0]], nb[cmb[1]], nb[cmb[2]]]
                let sorted = ids.sorted()
                let sk = SIMD4<Int32>(Int32(sorted[0]), Int32(sorted[1]), Int32(sorted[2]), Int32(sorted[3]))
                if seen.contains(sk) { continue }
                seen.insert(sk)
                var pts: [(Double, Double)] = []
                for i in ids {
                    guard let t = tangentProject(ra: Double(catalog.ra[i]), dec: Double(catalog.dec[i]), ra0: ra0, dec0: dec0) else { break }
                    pts.append((t.xi, t.eta))
                }
                guard pts.count == 4, let q = QuadHash.compute(pts) else { continue }
                hs += [q.h.0, q.h.1, q.h.2, q.h.3]
                st += [Int32(ids[q.order.0]), Int32(ids[q.order.1]), Int32(ids[q.order.2]), Int32(ids[q.order.3])]
            }
        }
        hashes = hs; stars = st
        buildBuckets()
    }

    @inline(__always) static func bin(_ v: Float) -> Int { max(0, min(bins - 1, Int((v - lo) / binSize))) }

    private func buildBuckets() {
        let nb = QuadIndex.bins * QuadIndex.bins
        var counts = [Int32](repeating: 0, count: nb + 1)
        for q in 0..<count {
            let b = QuadIndex.bin(hashes[4 * q]) * QuadIndex.bins + QuadIndex.bin(hashes[4 * q + 1])
            counts[b + 1] += 1
        }
        for i in 0..<nb { counts[i + 1] += counts[i] }
        bucketStart = counts
        var fill = counts
        bucketItems = [Int32](repeating: 0, count: count)
        for q in 0..<count {
            let b = QuadIndex.bin(hashes[4 * q]) * QuadIndex.bins + QuadIndex.bin(hashes[4 * q + 1])
            bucketItems[Int(fill[b])] = Int32(q); fill[b] += 1
        }
    }

    /// Alle Quads, deren Hash innerhalb ±tol liegt
    public func lookup(_ h: (Float, Float, Float, Float), tol: Float, into out: inout [Int]) {
        out.removeAll(keepingCapacity: true)
        let b0 = QuadIndex.bin(h.0 - tol), b1 = QuadIndex.bin(h.0 + tol)
        let c0 = QuadIndex.bin(h.1 - tol), c1 = QuadIndex.bin(h.1 + tol)
        for b in b0...b1 { for c in c0...c1 {
            let k = b * QuadIndex.bins + c
            for t in Int(bucketStart[k])..<Int(bucketStart[k + 1]) {
                let q = Int(bucketItems[t])
                if abs(hashes[4 * q] - h.0) <= tol && abs(hashes[4 * q + 1] - h.1) <= tol &&
                    abs(hashes[4 * q + 2] - h.2) <= tol && abs(hashes[4 * q + 3] - h.3) <= tol {
                    out.append(q)
                }
            }
        } }
    }
}
