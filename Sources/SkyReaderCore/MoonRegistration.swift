import Foundation

/// Benannter Mondkrater (IAU/USGS Gazetteer of Planetary Nomenclature)
public struct NamedCrater: Codable, Sendable {
    public var name: String
    public var lat: Double
    public var lon: Double
    public var d: Double
    public var origin: String?
}

/// Lage des Mondes im Bild: Rotation Mond-Körpersystem → Kamera, Spiegelung, Scheibe
public struct MoonPose: Sendable {
    /// 3×3 zeilenweise, Körper (x zur Erde, y Ost, z Nord) → Kamera (x rechts, y oben, z zum Beobachter)
    public var rotation: [Double]
    public var mirrored: Bool
    public var cx: Double, cy: Double, radius: Double
    public var matches: Int
    public var candidates: Int

    /// Sub-Erde-Punkt (optische Libration), Grad
    public var subEarth: (lat: Double, lon: Double) {
        // Kamera-z im Körpersystem = 3. Zeile der Rotation
        let x = rotation[6], y = rotation[7], z = rotation[8]
        return (rad2deg(asin(max(-1, min(1, z)))), rad2deg(atan2(y, x)))
    }

    /// Positionswinkel des Mond-Nordpols im Bild (Grad, von „oben“ im Uhrzeigersinn)
    public var northAngle: Double {
        let n = cameraVector(Vec3(0, 0, 1))
        var a = rad2deg(atan2(n.x, n.y)); if a < 0 { a += 360 }
        return a
    }

    func cameraVector(_ b: Vec3) -> Vec3 {
        let r = rotation
        var v = Vec3(r[0] * b.x + r[1] * b.y + r[2] * b.z, r[3] * b.x + r[4] * b.y + r[5] * b.z, r[6] * b.x + r[7] * b.y + r[8] * b.z)
        if mirrored { v.x = -v.x }
        return v
    }

    /// Bildposition eines Kraters (nil, wenn auf der Rückseite) und Sichtbarkeit (z = cos des Winkels zur Blickrichtung)
    public func project(lat: Double, lon: Double) -> (x: Double, y: Double, z: Double)? {
        let v = cameraVector(Vec3(ra: lon, dec: lat))
        guard v.z > 0 else { return nil }
        return (cx + radius * v.x, cy - radius * v.y, v.z)
    }

    public var kmPerPixel: Double { MoonAnalyzer.moonRadiusKm / radius }
}

public enum MoonRegistration {
    nonisolated(unsafe) private static var cached: [NamedCrater]?

    public static func catalog() -> [NamedCrater] {
        if let c = cached { return c }
        guard let u = ResourceLocator.catalogURL("moon_craters.json"), let d = try? Data(contentsOf: u),
              let list = try? JSONDecoder().decode([NamedCrater].self, from: d) else { return [] }
        cached = list
        return list
    }

    /// Bestimmt die Lage des Mondes aus erkannten Kratern und dem vermessenen Mondrand.
    /// Wie beim Plate Solving: Winkelabstände zwischen Kraterpaaren sind unabhängig von Drehung und Libration
    /// und werden mit Katalogpaaren passender Größe verglichen; jede Hypothese wird an allen Kratern geprüft.
    public static func register(craters dets: [DetectedCrater], limb: LimbCircle, width: Int, height: Int,
                                log: (String) -> Void = { _ in }, isCancelled: () -> Bool = { false }) -> MoonPose? {
        let cat = catalog().filter { $0.d >= 8 && abs($0.lon) < 105 }
        guard cat.count > 50, dets.count >= 6 else { return nil }
        let catVec = cat.map { Vec3(ra: $0.lon, dec: $0.lat) }
        let catD = cat.map { $0.d }
        // Randpunkt nächst zur Bildmitte bleibt fest, wenn der Radius variiert wird
        let mx = Double(width) / 2, my = Double(height) / 2
        let nx0 = mx - limb.cx, ny0 = my - limb.cy, nl = max(hypot(nx0, ny0), 1e-9)
        let ex = limb.cx + nx0 / nl * limb.r, ey = limb.cy + ny0 / nl * limb.r

        var best: (score: Double, pose: MoonPose)?
        var runnerUp = 0.0
        let grid = Grid(width: width, height: height, cell: 48)
        for scale in [0.86, 0.9, 0.93, 0.96, 1.0, 1.04] {
            if isCancelled() { return nil }
            let R = limb.r * scale
            let cx = ex - nx0 / nl * R, cy = ey - ny0 / nl * R
            // nur Krater mit plausibler Perspektive (kurze Achse zeigt zur Scheibenmitte)
            let usable = dets.filter { c in
                let rx = c.x - cx, ry = c.y - cy, rr = hypot(rx, ry)
                guard rr < R * 0.985 else { return false }
                if c.minorRadius <= 0 || c.minorRadius / c.r > 0.85 { return true }
                let a = deg2rad(c.angleDeg)
                return abs(-sin(a) * rx / rr + cos(a) * ry / rr) > 0.8
            }
            guard usable.count >= 6 else { continue }
            let kmpx = MoonAnalyzer.moonRadiusKm / R
            for mirror in [false, true] {
                let V: [Vec3] = usable.map { c in
                    var x = (c.x - cx) / R; let y = -(c.y - cy) / R
                    let z = max(0, 1 - x * x - y * y).squareRoot()
                    if mirror { x = -x }
                    return Vec3(x, y, z)
                }
                let dkm = usable.map { 2 * $0.r * kmpx }
                let order = usable.indices.sorted { usable[$0].r > usable[$1].r }
                let use = Array(order.prefix(14))
                var cand: [Int: [Int]] = [:]
                for i in use { cand[i] = cat.indices.filter { catD[$0] > dkm[i] * 0.4 && catD[$0] < dkm[i] * 2.6 } }
                for ai in 0..<use.count {
                    for bi in (ai + 1)..<use.count {
                        if isCancelled() { return nil }
                        let a = use[ai], b = use[bi]
                        let sep = acos(max(-1, min(1, V[a].dot(V[b]))))
                        if sep < deg2rad(1.5) { continue }
                        let tol = max(deg2rad(0.6), sep * 0.06)
                        let cosLo = cos(sep + tol), cosHi = cos(max(0, sep - tol))
                        for j in cand[a] ?? [] {
                            let wj = catVec[j]
                            for l in cand[b] ?? [] where l != j {
                                let cs = wj.dot(catVec[l])
                                if cs < cosLo || cs > cosHi { continue }
                                guard let rot = triad(V[a], V[b], wj, catVec[l]) else { continue }
                                // Libration: Blickrichtung im Körpersystem nahe Länge/Breite 0 (±11°)
                                if rot[6] < cos(deg2rad(11)) { continue }
                                let pose = MoonPose(rotation: rot, mirrored: mirror, cx: cx, cy: cy, radius: R, matches: 0, candidates: usable.count)
                                let (s, _) = score(pose, dets: usable, grid: grid, catVec: catVec, catD: catD,
                                                   width: width, height: height, quickLimit: 14, quickNeed: 3)
                                if let bb = best {
                                    if s > bb.score {
                                        if angleBetween(pose, bb.pose) > 10 { runnerUp = max(runnerUp, bb.score) }
                                        best = (s, pose)
                                    } else if angleBetween(pose, bb.pose) > 10 { runnerUp = max(runnerUp, s) }
                                } else { best = (s, pose) }
                            }
                        }
                    }
                }
            }
        }
        guard var b = best else { return nil }
        b.score = score(b.pose, dets: dets, cat: cat, width: width, height: height).0
        // Verfeinerung: Rotation aus allen Zuordnungen (Horn), Radius fein nachjustieren
        for _ in 0..<3 {
            var improved = false
            for ds in [-0.02, -0.01, 0.0, 0.01, 0.02] {
                var p = b.pose
                let R = p.radius * (1 + ds)
                p.cx = ex - nx0 / nl * R; p.cy = ey - ny0 / nl * R; p.radius = R
                let (_, pairs) = score(p, dets: dets, cat: cat, width: width, height: height)
                if pairs.count >= 3, let rot = fitRotation(pairs: pairs, pose: p, dets: dets, cat: cat) { p.rotation = rot }
                let (s2, _) = score(p, dets: dets, cat: cat, width: width, height: height)
                if s2 > b.score + 1e-6 { b = (s2, p); improved = true }
            }
            if !improved { break }
        }
        let (finalScore, pairs) = score(b.pose, dets: dets, cat: cat, width: width, height: height)
        b.pose.matches = pairs.count
        b.pose.candidates = dets.count
        let need = max(6.0, 0.25 * Double(min(dets.count, 30)))
        log(String(format: "Kraterabgleich: %d Krater dem Katalog zugeordnet (nächstbeste andere Lage: %.0f)", pairs.count, runnerUp))
        guard Double(pairs.count) >= need, finalScore >= runnerUp * 1.3 + 1 else { return nil }
        return b.pose
    }

    /// Wiederverwendbarer Rasterpuffer für die schnelle Bewertung
    final class Grid {
        let cs: Double, gw: Int, gh: Int
        var start: [Int32], items: [Int32], px: [Double], py: [Double], pr: [Double], pj: [Int32]
        init(width: Int, height: Int, cell: Double) {
            cs = cell
            gw = Int(Double(width + 80) / cell) + 2; gh = Int(Double(height + 80) / cell) + 2
            start = [Int32](repeating: 0, count: gw * gh + 1); items = []; px = []; py = []; pr = []; pj = []
        }
        @inline(__always) func cellIndex(_ x: Double, _ y: Double) -> Int {
            let gx = min(gw - 1, max(0, Int((x + 40) / cs))), gy = min(gh - 1, max(0, Int((y + 40) / cs)))
            return gy * gw + gx
        }
        func fill(_ pose: MoonPose, catVec: [Vec3], catD: [Double], width: Int, height: Int) {
            px.removeAll(keepingCapacity: true); py.removeAll(keepingCapacity: true)
            pr.removeAll(keepingCapacity: true); pj.removeAll(keepingCapacity: true)
            let r = pose.rotation, R = pose.radius, kmpx = pose.kmPerPixel
            let w = Double(width), h = Double(height)
            for j in 0..<catVec.count {
                let b = catVec[j]
                let z = r[6] * b.x + r[7] * b.y + r[8] * b.z
                if z <= 0.05 { continue }
                var x = r[0] * b.x + r[1] * b.y + r[2] * b.z
                let y = r[3] * b.x + r[4] * b.y + r[5] * b.z
                if pose.mirrored { x = -x }
                let ix = pose.cx + R * x, iy = pose.cy - R * y
                if ix < -40 || iy < -40 || ix > w + 40 || iy > h + 40 { continue }
                px.append(ix); py.append(iy); pr.append(catD[j] / 2 / kmpx); pj.append(Int32(j))
            }
            for k in 0..<start.count { start[k] = 0 }
            for k in 0..<px.count { start[cellIndex(px[k], py[k]) + 1] += 1 }
            for k in 0..<(start.count - 1) { start[k + 1] += start[k] }
            var fillPos = start
            items = [Int32](repeating: 0, count: px.count)
            for k in 0..<px.count { let c = cellIndex(px[k], py[k]); items[Int(fillPos[c])] = Int32(k); fillPos[c] += 1 }
        }
        /// Bester passender Katalogkrater zu einer Erkennung (Index in px/py), oder -1
        func match(_ d: DetectedCrater, used: Set<Int32>) -> (Int, Double) {
            let tol = max(0.4 * d.r, 6)
            let c0 = cellIndex(d.x, d.y), gx = c0 % gw, gy = c0 / gw
            let span = Int(ceil(tol / cs))
            var best = -1, bd = tol
            for yy in max(0, gy - span)...min(gh - 1, gy + span) {
                for xx in max(0, gx - span)...min(gw - 1, gx + span) {
                    let c = yy * gw + xx
                    for t in Int(start[c])..<Int(start[c + 1]) {
                        let k = Int(items[t])
                        let dist = hypot(px[k] - d.x, py[k] - d.y)
                        guard dist < bd else { continue }
                        let ratio = d.r / pr[k]
                        guard ratio > 0.35 && ratio < 2.6, !used.contains(pj[k]) else { continue }
                        best = k; bd = dist
                    }
                }
            }
            return (best, bd / tol)
        }
    }

    /// Anzahl erkannter Krater, die nach Position und Größe zu einem projizierten Katalogkrater passen
    static func score(_ p: MoonPose, dets: [DetectedCrater], cat: [NamedCrater], width: Int, height: Int) -> (Double, [(Int, Int)]) {
        let g = Grid(width: width, height: height, cell: 48)
        let catVec = cat.map { Vec3(ra: $0.lon, dec: $0.lat) }
        return score(p, dets: dets, grid: g, catVec: catVec, catD: cat.map { $0.d }, width: width, height: height)
    }

    static func score(_ p: MoonPose, dets: [DetectedCrater], grid g: Grid, catVec: [Vec3], catD: [Double],
                      width: Int, height: Int, quickLimit: Int = Int.max, quickNeed: Int = 0) -> (Double, [(Int, Int)]) {
        g.fill(p, catVec: catVec, catD: catD, width: width, height: height)
        var used = Set<Int32>()
        var pairs: [(Int, Int)] = []
        var s = 0.0
        let order = dets.indices.sorted(by: { dets[$0].r > dets[$1].r })
        for (n, i) in order.enumerated() {
            if n == quickLimit && pairs.count < quickNeed { return (s, pairs) }   // Vorprüfung gescheitert
            let (k, rel) = g.match(dets[i], used: used)
            if k >= 0 { used.insert(g.pj[k]); pairs.append((i, Int(g.pj[k]))); s += 1 - 0.3 * rel }
        }
        return (s, pairs)
    }

    /// Rotation mit R·b ≈ a aus zwei Vektorpaaren (TRIAD)
    static func triad(_ a1: Vec3, _ a2: Vec3, _ b1: Vec3, _ b2: Vec3) -> [Double]? {
        func frame(_ u: Vec3, _ v: Vec3) -> (Vec3, Vec3, Vec3)? {
            let t1 = u.normalized
            let c = u.cross(v); let l = c.length
            guard l > 1e-9 else { return nil }
            let t2 = c * (1 / l)
            return (t1, t2, t1.cross(t2))
        }
        guard let (p1, p2, p3) = frame(a1, a2), let (q1, q2, q3) = frame(b1, b2) else { return nil }
        // R = [p1 p2 p3] · [q1 q2 q3]^T
        let P = [p1, p2, p3], Q = [q1, q2, q3]
        var r = [Double](repeating: 0, count: 9)
        for i in 0..<3 { for j in 0..<3 {
            var s = 0.0
            for k in 0..<3 {
                let pi = [P[k].x, P[k].y, P[k].z][i], qj = [Q[k].x, Q[k].y, Q[k].z][j]
                s += pi * qj
            }
            r[i * 3 + j] = s
        } }
        return r
    }

    /// Optimale Rotation (Horn, Quaternion über Potenziteration) für alle zugeordneten Paare
    static func fitRotation(pairs: [(Int, Int)], pose: MoonPose, dets: [DetectedCrater], cat: [NamedCrater]) -> [Double]? {
        var S = [[Double]](repeating: [0, 0, 0], count: 3)
        for (i, j) in pairs {
            let d = dets[i]
            var x = (d.x - pose.cx) / pose.radius; let y = -(d.y - pose.cy) / pose.radius
            let z = max(0, 1 - x * x - y * y).squareRoot()
            if pose.mirrored { x = -x }
            let a = [x, y, z]
            let bv = Vec3(ra: cat[j].lon, dec: cat[j].lat)
            let b = [bv.x, bv.y, bv.z]
            for r in 0..<3 { for c in 0..<3 { S[r][c] += b[r] * a[c] } }
        }
        let (Sxx, Sxy, Sxz, Syx, Syy, Syz, Szx, Szy, Szz) = (S[0][0], S[0][1], S[0][2], S[1][0], S[1][1], S[1][2], S[2][0], S[2][1], S[2][2])
        let N: [[Double]] = [
            [Sxx + Syy + Szz, Syz - Szy, Szx - Sxz, Sxy - Syx],
            [Syz - Szy, Sxx - Syy - Szz, Sxy + Syx, Szx + Sxz],
            [Szx - Sxz, Sxy + Syx, -Sxx + Syy - Szz, Syz + Szy],
            [Sxy - Syx, Szx + Sxz, Syz + Szy, -Sxx - Syy + Szz]]
        // größter Eigenvektor per Potenziteration auf N + c·I
        let c = N.flatMap { $0 }.map(abs).reduce(0, +) + 1
        var q = [1.0, 0, 0, 0]
        for _ in 0..<200 {
            var nq = [0.0, 0, 0, 0]
            for r in 0..<4 { for k in 0..<4 { nq[r] += (N[r][k] + (r == k ? c : 0)) * q[k] } }
            let l = (nq.map { $0 * $0 }.reduce(0, +)).squareRoot()
            guard l > 0 else { return nil }
            q = nq.map { $0 / l }
        }
        let (w, x, y, z) = (q[0], q[1], q[2], q[3])
        return [w * w + x * x - y * y - z * z, 2 * (x * y - w * z), 2 * (x * z + w * y),
                2 * (x * y + w * z), w * w - x * x + y * y - z * z, 2 * (y * z - w * x),
                2 * (x * z - w * y), 2 * (y * z + w * x), w * w - x * x - y * y + z * z]
    }

    /// Winkelunterschied zweier Lagen (Grad)
    static func angleBetween(_ a: MoonPose, _ b: MoonPose) -> Double {
        if a.mirrored != b.mirrored { return 180 }
        var tr = 0.0
        for i in 0..<3 { for k in 0..<3 { tr += a.rotation[i * 3 + k] * b.rotation[i * 3 + k] } }
        return rad2deg(acos(max(-1, min(1, (tr - 1) / 2))))
    }

    // MARK: Namensgeber auf Deutsch

    public static func germanOrigin(_ s: String?) -> String? {
        guard var t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        if t.hasSuffix(".") { t.removeLast() }
        let words: [(String, String)] = [
            ("astronomer", "Astronom"), ("mathematician", "Mathematiker"), ("physicist", "Physiker"), ("philosopher", "Philosoph"),
            ("geologist", "Geologe"), ("chemist", "Chemiker"), ("engineer", "Ingenieur"), ("explorer", "Entdecker"),
            ("geographer", "Geograf"), ("selenographer", "Selenograf"), ("astronaut", "Astronaut"), ("cosmonaut", "Kosmonaut"),
            ("physician", "Arzt"), ("naturalist", "Naturforscher"), ("scientist", "Wissenschaftler"), ("meteorologist", "Meteorologe"),
            ("instrument maker", "Instrumentenbauer"), ("optician", "Optiker"), ("writer", "Schriftsteller"), ("historian", "Historiker"),
            ("geodesist", "Geodät"), ("geophysicist", "Geophysiker"), ("astrophysicist", "Astrophysiker"), ("biologist", "Biologe"),
            ("botanist", "Botaniker"), ("inventor", "Erfinder"), ("rocket", "Raketen-"), ("pioneer", "Pionier"),
            ("German", "deutscher"), ("French", "französischer"), ("English", "englischer"), ("British", "britischer"),
            ("Italian", "italienischer"), ("Greek", "griechischer"), ("Russian", "russischer"), ("Soviet", "sowjetischer"),
            ("American", "amerikanischer"), ("Dutch", "niederländischer"), ("Danish", "dänischer"), ("Swedish", "schwedischer"),
            ("Austrian", "österreichischer"), ("Swiss", "Schweizer"), ("Polish", "polnischer"), ("Czech", "tschechischer"),
            ("Belgian", "belgischer"), ("Spanish", "spanischer"), ("Portuguese", "portugiesischer"), ("Scottish", "schottischer"),
            ("Irish", "irischer"), ("Norwegian", "norwegischer"), ("Finnish", "finnischer"), ("Hungarian", "ungarischer"),
            ("Arab", "arabischer"), ("Persian", "persischer"), ("Chinese", "chinesischer"), ("Japanese", "japanischer"),
            ("Roman", "römischer"), ("Egyptian", "ägyptischer"), ("Indian", "indischer"), ("Canadian", "kanadischer"),
            ("Flemish", "flämischer"), ("Croatian", "kroatischer"), ("Ukrainian", "ukrainischer"), ("Estonian", "estnischer"),
            ("Mexican", "mexikanischer"), ("Australian", "australischer"), ("Turkish", "türkischer"), ("Armenian", "armenischer"),
            ("Byzantine", "byzantinischer"), ("unkn", "?"), ("Unkn", "?"), (" and ", " und "), ("Named to honor", "Benannt zu Ehren von"), ("Named for", "Benannt nach"),
            ("Named from", "Benannt nach"), ("Hero of", "Held aus"), ("mythology", "Mythologie"), ("century", "Jh."),
            ("B.C.", "v. Chr."), ("A.D.", "n. Chr."), ("c. ", "um "), ("Greek mythology", "griechische Mythologie"),
        ]
        for (en, de) in words { t = t.replacingOccurrences(of: en, with: de) }
        return t
    }
}
