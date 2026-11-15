import Foundation

// MARK: - Winkel & Sphäre

@inline(__always) public func deg2rad(_ d: Double) -> Double { d * .pi / 180 }
@inline(__always) public func rad2deg(_ r: Double) -> Double { r * 180 / .pi }

public struct Vec3: Equatable, Sendable {
    public var x: Double, y: Double, z: Double
    public init(_ x: Double, _ y: Double, _ z: Double) { self.x = x; self.y = y; self.z = z }

    /// Einheitsvektor aus RA/Dec (Grad)
    public init(ra: Double, dec: Double) {
        let a = deg2rad(ra), d = deg2rad(dec)
        x = cos(d) * cos(a); y = cos(d) * sin(a); z = sin(d)
    }

    public var ra: Double { var r = rad2deg(atan2(y, x)); if r < 0 { r += 360 }; return r }
    public var dec: Double { rad2deg(asin(max(-1, min(1, z / length)))) }
    public var length: Double { (x * x + y * y + z * z).squareRoot() }
    public var normalized: Vec3 { let l = length; return Vec3(x / l, y / l, z / l) }
    @inline(__always) public func dot(_ o: Vec3) -> Double { x * o.x + y * o.y + z * o.z }
    public static func + (a: Vec3, b: Vec3) -> Vec3 { Vec3(a.x + b.x, a.y + b.y, a.z + b.z) }
    public static func - (a: Vec3, b: Vec3) -> Vec3 { Vec3(a.x - b.x, a.y - b.y, a.z - b.z) }
    public static func * (a: Vec3, s: Double) -> Vec3 { Vec3(a.x * s, a.y * s, a.z * s) }
    public func cross(_ o: Vec3) -> Vec3 { Vec3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x) }
}

/// Winkelabstand in Grad
public func angularDistance(ra1: Double, dec1: Double, ra2: Double, dec2: Double) -> Double {
    let a = Vec3(ra: ra1, dec: dec1), b = Vec3(ra: ra2, dec: dec2)
    let c = a.cross(b).length, d = a.dot(b)
    return rad2deg(atan2(c, d))
}

/// Gnomonische (Tangential-)Projektion. Ergebnis in Grad. nil, wenn Punkt auf der Rückseite liegt.
public func tangentProject(ra: Double, dec: Double, ra0: Double, dec0: Double) -> (xi: Double, eta: Double)? {
    let a = deg2rad(ra), d = deg2rad(dec), a0 = deg2rad(ra0), d0 = deg2rad(dec0)
    let cosc = sin(d0) * sin(d) + cos(d0) * cos(d) * cos(a - a0)
    if cosc <= 0.05 { return nil }
    let xi = cos(d) * sin(a - a0) / cosc
    let eta = (cos(d0) * sin(d) - sin(d0) * cos(d) * cos(a - a0)) / cosc
    return (rad2deg(xi), rad2deg(eta))
}

/// Umkehrung der Tangentialprojektion (xi, eta in Grad)
public func tangentDeproject(xi: Double, eta: Double, ra0: Double, dec0: Double) -> (ra: Double, dec: Double) {
    let x = deg2rad(xi), y = deg2rad(eta), a0 = deg2rad(ra0), d0 = deg2rad(dec0)
    let rho = (x * x + y * y).squareRoot()
    if rho < 1e-15 { return (ra0, dec0) }
    let c = atan(rho)
    let dec = asin(cos(c) * sin(d0) + y * sin(c) * cos(d0) / rho)
    let ra = a0 + atan2(x * sin(c), rho * cos(d0) * cos(c) - y * sin(d0) * sin(c))
    var r = rad2deg(ra).truncatingRemainder(dividingBy: 360); if r < 0 { r += 360 }
    return (r, rad2deg(dec))
}

// MARK: - Lineare Algebra

/// Löst A x = b (n×n, zeilenweise) per Gauß-Elimination mit Pivotisierung.
public func solveLinear(_ A: [Double], _ b: [Double], n: Int) -> [Double]? {
    var m = A, v = b
    for col in 0..<n {
        var piv = col
        var best = abs(m[col * n + col])
        for r in (col + 1)..<max(col + 1, n) where abs(m[r * n + col]) > best { best = abs(m[r * n + col]); piv = r }
        if best < 1e-14 { return nil }
        if piv != col {
            for k in 0..<n { m.swapAt(col * n + k, piv * n + k) }
            v.swapAt(col, piv)
        }
        let p = m[col * n + col]
        for r in 0..<n where r != col {
            let f = m[r * n + col] / p
            if f == 0 { continue }
            for k in col..<n { m[r * n + k] -= f * m[col * n + k] }
            v[r] -= f * v[col]
        }
    }
    return (0..<n).map { v[$0] / m[$0 * n + $0] }
}

/// Least-Squares-Fit: rows = Designmatrix (m×n), y = Messwerte. Normalengleichungen mit leichter Regularisierung.
public func leastSquares(rows: [[Double]], y: [Double], weights: [Double]? = nil) -> [Double]? {
    guard let n = rows.first?.count, rows.count >= n else { return nil }
    var ata = [Double](repeating: 0, count: n * n)
    var aty = [Double](repeating: 0, count: n)
    for (i, r) in rows.enumerated() {
        let w = weights?[i] ?? 1
        for a in 0..<n {
            aty[a] += w * r[a] * y[i]
            for b in a..<n { ata[a * n + b] += w * r[a] * r[b] }
        }
    }
    for a in 0..<n { for b in 0..<a { ata[a * n + b] = ata[b * n + a] } ; ata[a * n + a] += 1e-12 }
    return solveLinear(ata, aty, n: n)
}

// MARK: - Polynome 2D

/// Bivariates Polynom bis Ordnung 3 (Terme: 1, u, v, u², uv, v², u³, u²v, uv², v³)
public struct Poly2D: Codable, Sendable {
    public var order: Int
    public var cx: [Double]
    public var cy: [Double]

    public static func terms(_ u: Double, _ v: Double, order: Int) -> [Double] {
        var t: [Double] = [1, u, v]
        if order >= 2 { t += [u * u, u * v, v * v] }
        if order >= 3 { t += [u * u * u, u * u * v, u * v * v, v * v * v] }
        return t
    }

    public static func termCount(_ order: Int) -> Int { order >= 3 ? 10 : order == 2 ? 6 : 3 }

    public func apply(_ u: Double, _ v: Double) -> (Double, Double) {
        let t = Poly2D.terms(u, v, order: order)
        var x = 0.0, y = 0.0
        for i in 0..<t.count { x += cx[i] * t[i]; y += cy[i] * t[i] }
        return (x, y)
    }

    public static func fit(src: [(Double, Double)], dst: [(Double, Double)], order: Int, weights: [Double]? = nil) -> Poly2D? {
        let rows = src.map { terms($0.0, $0.1, order: order) }
        guard let a = leastSquares(rows: rows, y: dst.map { $0.0 }, weights: weights),
              let b = leastSquares(rows: rows, y: dst.map { $0.1 }, weights: weights) else { return nil }
        return Poly2D(order: order, cx: a, cy: b)
    }
}

// MARK: - Statistik

public func median(_ a: [Float]) -> Float {
    if a.isEmpty { return 0 }
    var s = a; s.sort()
    return s[s.count / 2]
}

public func median(_ a: [Double]) -> Double {
    if a.isEmpty { return 0 }
    let s = a.sorted()
    return s.count % 2 == 1 ? s[s.count / 2] : 0.5 * (s[s.count / 2 - 1] + s[s.count / 2])
}

extension Array {
    /// Alle k-Kombinationen von Indizes 0..<count
    static func combinations(_ n: Int, _ k: Int) -> [[Int]] {
        var out: [[Int]] = []
        var idx = Array<Int>(0..<k)
        if k > n { return [] }
        while true {
            out.append(idx)
            var i = k - 1
            while i >= 0 && idx[i] == n - k + i { i -= 1 }
            if i < 0 { break }
            idx[i] += 1
            for j in (i + 1)..<k { idx[j] = idx[j - 1] + 1 }
        }
        return out
    }
}
