import Foundation

/// Benannter Mondkrater (IAU/USGS Gazetteer of Planetary Nomenclature)
public struct NamedCrater: Codable, Sendable {
    public var name: String
    public var lat: Double
    public var lon: Double
    public var d: Double
    public var origin: String?
    /// 1 = offizieller Nebenkrater (z. B. „Atlas A“)
    public var sat: Int?
    public var isSatellite: Bool { sat == 1 }
}

/// Benannte Region (Mare, Lacus, Sinus, Mons/Montes, Vallis, Rima, …)
public struct MoonRegion: Codable, Sendable {
    public var name: String
    public var type: String
    public var lat: Double
    public var lon: Double
    public var d: Double
    public var origin: String?

    /// Deutsche Bezeichnung des Typs
    public var germanType: String {
        switch type {
        case "Mare": return "Mondmeer (Mare)"
        case "Oceanus": return "Ozean (Oceanus)"
        case "Lacus": return "Mondsee (Lacus)"
        case "Sinus": return "Bucht (Sinus)"
        case "Palus": return "Sumpf (Palus)"
        case "Mons", "Montes": return "Gebirge"
        case "Vallis": return "Tal (Vallis)"
        case "Rima": return "Rille (Rima)"
        case "Rupes": return "Steilstufe (Rupes)"
        case "Dorsum": return "Höhenrücken (Dorsum)"
        case "Catena": return "Kraterkette (Catena)"
        case "Promontorium": return "Kap (Promontorium)"
        default: return type
        }
    }
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

    /// Selenografische Lage eines Bildpunkts (nil, wenn außerhalb der Mondscheibe)
    public func unproject(x: Double, y: Double) -> (lat: Double, lon: Double)? {
        var vx = (x - cx) / radius
        let vy = -(y - cy) / radius
        let q = 1 - vx * vx - vy * vy
        guard q > 0 else { return nil }
        let vz = q.squareRoot()
        if mirrored { vx = -vx }
        // Körper = Rᵀ · Kamera
        let r = rotation
        let bx = r[0] * vx + r[3] * vy + r[6] * vz
        let by = r[1] * vx + r[4] * vy + r[7] * vz
        let bz = r[2] * vx + r[5] * vy + r[8] * vz
        return (rad2deg(asin(max(-1, min(1, bz)))), rad2deg(atan2(by, bx)))
    }
}

/// Robbins (2018) Lunar Crater Database: rund 1,3 Mio. vermessene Krater (auch ohne Eigennamen).
/// Ergänzt die IAU-Nomenklatur um genaue Durchmesser und bestätigt erkannte, unbenannte Krater.
public enum RobbinsCatalog {
    public struct Crater: Sendable { public var lat: Float; public var lon: Float; public var d: Float }
    nonisolated(unsafe) private static var cached: [Crater]??

    /// Nach Breite sortierte Liste (leer, wenn die Datei fehlt)
    public static func all() -> [Crater] {
        if let c = cached { return c ?? [] }
        guard let u = ResourceLocator.catalogURL("moon_robbins.bin"), let d = try? Data(contentsOf: u), d.count >= 12,
              d.prefix(4) == Data("SRMC".utf8) else { cached = .some(nil); return [] }
        let n = d.withUnsafeBytes { Int($0.loadUnaligned(fromByteOffset: 8, as: UInt32.self).littleEndian) }
        guard d.count >= 12 + n * 12 else { cached = .some(nil); return [] }
        var out = [Crater](); out.reserveCapacity(n)
        d.withUnsafeBytes { b in
            for i in 0..<n {
                let o = 12 + i * 12
                func f(_ k: Int) -> Float { Float(bitPattern: b.loadUnaligned(fromByteOffset: o + k, as: UInt32.self).littleEndian) }
                out.append(Crater(lat: f(0), lon: f(4), d: f(8)))
            }
        }
        cached = .some(out)
        return out
    }

    public static var isAvailable: Bool { !all().isEmpty }

    /// Bester Katalogkrater nahe (lat, lon) mit passendem Durchmesser (km); Toleranz relativ zum Durchmesser
    public static func match(lat: Double, lon: Double, diameterKm: Double, sizeTolerance: Double = 0.5) -> Crater? {
        let list = all()
        guard !list.isEmpty else { return nil }
        let kmPerDeg = MoonAnalyzer.moonRadiusKm * .pi / 180
        let searchKm = max(3, diameterKm * 0.6)
        let dLat = searchKm / kmPerDeg
        // binäre Suche nach der Breite
        var lo = 0, hi = list.count
        while lo < hi { let m = (lo + hi) / 2; if Double(list[m].lat) < lat - dLat { lo = m + 1 } else { hi = m } }
        let p = Vec3(ra: lon, dec: lat)
        var best: (Crater, Double)?
        var i = lo
        while i < list.count, Double(list[i].lat) <= lat + dLat {
            let c = list[i]; i += 1
            let cd = Double(c.d)
            guard abs(cd - diameterKm) <= sizeTolerance * max(cd, diameterKm) else { continue }
            let distKm = acos(max(-1, min(1, Vec3(ra: Double(c.lon), dec: Double(c.lat)).dot(p)))) * MoonAnalyzer.moonRadiusKm
            guard distKm <= max(3, 0.5 * max(cd, diameterKm)) else { continue }
            let score = distKm / max(cd, 1) + abs(Foundation.log(cd / max(diameterKm, 0.1)))
            if best == nil || score < best!.1 { best = (c, score) }
        }
        return best?.0
    }
}

public enum MoonRegistration {
    nonisolated(unsafe) private static var cached: [NamedCrater]?

    nonisolated(unsafe) private static var cachedRegions: [MoonRegion]?

    public static func regions() -> [MoonRegion] {
        if let c = cachedRegions { return c }
        guard let u = ResourceLocator.catalogURL("moon_regions.json"), let d = try? Data(contentsOf: u),
              let list = try? JSONDecoder().decode([MoonRegion].self, from: d) else { return [] }
        cachedRegions = list
        return list
    }

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
                                ephemeris: MoonEphemeris? = nil,
                                log: (String) -> Void = { _ in }, isCancelled: () -> Bool = { false }) -> MoonPose? {
        // Mit bekanntem Datum: Sub-Erde-Punkt bis auf ~3° bekannt (Topozentrik, Zeitunsicherheit)
        let subEarth = ephemeris?.subEarthVector
        let libCos = cos(deg2rad(ephemeris != nil ? 3.0 : 11.0))
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
                                // Libration: Blickrichtung im Körpersystem nahe Länge/Breite 0 (±11°) bzw. am berechneten Punkt
                                if let se = subEarth {
                                    if rot[6] * se.x + rot[7] * se.y + rot[8] * se.z < libCos { continue }
                                } else if rot[6] < libCos { continue }
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

    /// Registrierung ohne sichtbaren Mondrand – nur mit bekanntem Datum möglich.
    /// Die Libration (aus der Ephemeride) legt die Projektion fest; die gemessene Sonnenrichtung im Bild
    /// bestimmt zusammen mit dem Sub-Sonnen-Punkt die Bilddrehung. Gesucht werden dann nur noch Maßstab und Lage.
    public static func registerWithoutLimb(craters dets: [DetectedCrater], ephemeris eph: MoonEphemeris, sunAngleDeg: Double,
                                           width: Int, height: Int, log: (String) -> Void = { _ in },
                                           isCancelled: () -> Bool = { false }) -> MoonPose? {
        let all = catalog()
        let e = eph.subEarthVector, sun = eph.subSolarVector
        // Kamera-Basis (Nord oben, Ost rechts bei Drehung 0)
        let north = Vec3(0, 0, 1)
        let y0 = (north - e * north.dot(e)).normalized
        let x0 = y0.cross(e)
        // nur sichtbare und beleuchtete Krater
        let cat = all.filter { c in
            let w = Vec3(ra: c.lon, dec: c.lat)
            return c.d >= 6 && w.dot(e) > 0.08 && w.dot(sun) > -0.04   // Wälle knapp hinter dem Terminator noch im Licht
        }
        let catVec = cat.map { Vec3(ra: $0.lon, dec: $0.lat) }
        let catD = cat.map { $0.d }
        guard cat.count > 50, dets.count >= 8 else { return nil }
        let grid = Grid(width: width, height: height, cell: 48)
        func pose(theta: Double, mirror: Bool, R: Double, cx: Double, cy: Double) -> MoonPose {
            let c = cos(theta), s = sin(theta)
            let X = mirror ? x0 * c + y0 * s : x0 * c - y0 * s
            let Y = mirror ? y0 * c - x0 * s : x0 * s + y0 * c
            return MoonPose(rotation: [X.x, X.y, X.z, Y.x, Y.y, Y.z, e.x, e.y, e.z], mirrored: mirror, cx: cx, cy: cy, radius: R,
                            matches: 0, candidates: dets.count)
        }
        // Scheibenkoordinaten (Einheit: Mondradius) bei bekannter Libration
        let hyp = cat.indices.filter { !cat[$0].isSatellite && cat[$0].d >= 12 }
        let hu = hyp.map { catVec[$0].dot(x0) }, hv = hyp.map { catVec[$0].dot(y0) }
        let hrho = hyp.map { catD[$0] / 2 / MoonAnalyzer.moonRadiusKm }
        // Sonnenrichtung tangential am Krater (Scheibenkoordinaten)
        let htu = hyp.map { j -> Double in let p = catVec[j]; return (sun - p * sun.dot(p)).dot(x0) }
        let htv = hyp.map { j -> Double in let p = catVec[j]; return (sun - p * sun.dot(p)).dot(y0) }
        let anchors = Array(dets.sorted { $0.strength * $0.r > $1.strength * $1.r }.prefix(14))
        let alpha = deg2rad(sunAngleDeg)
        var best: (Double, MoonPose)?
        var runnerUp = 0.0
        func angDiff(_ x: Double, _ y: Double) -> Double { abs(atan2(sin(x - y), cos(x - y))) }
        for (ai, a) in anchors.enumerated() {
            if isCancelled() { return nil }
            for (bi, b) in anchors.enumerated() where bi != ai {
                let vax = b.x - a.x, vay = -(b.y - a.y)
                let dab = hypot(vax, vay)
                guard dab > 2 * max(a.r, b.r) else { continue }
                let q = Foundation.log(a.r / b.r), tt = Foundation.log(dab / a.r)
                for j in 0..<hyp.count {
                    for l in 0..<hyp.count where l != j {
                        guard abs(Foundation.log(hrho[j] / hrho[l]) - q) < 0.45 else { continue }
                        let dcu = hu[l] - hu[j], dcv = hv[l] - hv[j]
                        let dc = hypot(dcu, dcv)
                        guard dc > 1e-6, abs(Foundation.log(dc / hrho[j]) - tt) < 0.4 else { continue }
                        for mirror in [false, true] {
                            let m: Double = mirror ? -1 : 1
                            let R = dab / dc
                            let th = atan2(vay, vax) - atan2(dcv, m * dcu)
                            // Sonnenstand muss zur gemessenen Schattenrichtung passen (Vorzeichen offen)
                            let pred = -(th + atan2(htv[j], m * htu[j]))
                            guard min(angDiff(pred, -alpha), angDiff(pred, -alpha + .pi)) < deg2rad(35) else { continue }
                            let mu = m * hu[j]
                            let dx = cos(th) * mu - sin(th) * hv[j], dy = sin(th) * mu + cos(th) * hv[j]
                            let ps = pose(theta: th, mirror: mirror, R: R, cx: a.x - R * dx, cy: a.y + R * dy)
                            let (sc, _) = score(ps, dets: dets, grid: grid, catVec: catVec, catD: catD, width: width, height: height,
                                                quickLimit: 14, quickNeed: 4)
                            if let bb = best {
                                let far = hypot(ps.cx - bb.1.cx, ps.cy - bb.1.cy) > 0.05 * bb.1.radius || abs(Foundation.log(ps.radius / bb.1.radius)) > 0.2
                                if sc > bb.0 { if far { runnerUp = max(runnerUp, bb.0) }; best = (sc, ps) }
                                else if far { runnerUp = max(runnerUp, sc) }
                            } else { best = (sc, ps) }
                        }
                    }
                }
            }
        }
        guard var b = best else { return nil }
        // Verfeinerung: Ähnlichkeitstransformation (Drehung, Maßstab, Lage) aus allen Zuordnungen
        for _ in 0..<4 {
            let (_, pairs) = score(b.1, dets: dets, grid: grid, catVec: catVec, catD: catD, width: width, height: height)
            guard pairs.count >= 3 else { break }
            let m: Double = b.1.mirrored ? -1 : 1
            var src: [(Double, Double)] = [], dst: [(Double, Double)] = []
            for (i, j) in pairs {
                let p = catVec[j]
                src.append((m * p.dot(x0), p.dot(y0))); dst.append((dets[i].x, -dets[i].y))
            }
            // komplexe Ähnlichkeit dst = A·src + B
            let n = Double(src.count)
            let sm = (src.map { $0.0 }.reduce(0, +) / n, src.map { $0.1 }.reduce(0, +) / n)
            let dm = (dst.map { $0.0 }.reduce(0, +) / n, dst.map { $0.1 }.reduce(0, +) / n)
            var nr = 0.0, ni = 0.0, dd = 0.0
            for k in 0..<src.count {
                let zx = src[k].0 - sm.0, zy = src[k].1 - sm.1, wx = dst[k].0 - dm.0, wy = dst[k].1 - dm.1
                nr += zx * wx + zy * wy; ni += zx * wy - zy * wx; dd += zx * zx + zy * zy
            }
            guard dd > 0 else { break }
            let ar = nr / dd, ai = ni / dd
            let R = hypot(ar, ai), th = atan2(ai, ar)
            let bx = dm.0 - (ar * sm.0 - ai * sm.1), by = dm.1 - (ar * sm.1 + ai * sm.0)
            let np = pose(theta: th, mirror: b.1.mirrored, R: R, cx: bx, cy: -by)
            let (s2, _) = score(np, dets: dets, grid: grid, catVec: catVec, catD: catD, width: width, height: height)
            if s2 >= b.0 { b = (s2, np) } else { break }
        }
        let (finalScore, pairs) = score(b.1, dets: dets, grid: grid, catVec: catVec, catD: catD, width: width, height: height)
        b.1.matches = pairs.count
        if ProcessInfo.processInfo.environment["SR_DEBUG"] != nil {
            let c0 = b.1.cameraVector(Vec3(1, 0, 0))
            print("DEBUG noLimb: R=\(b.1.radius) cx=\(b.1.cx) cy=\(b.1.cy) mirror=\(b.1.mirrored) north=\(b.1.northAngle) score=\(finalScore)")
            print("DEBUG pairs:", pairs.map { cat[$0.1].name }.joined(separator: ", "))
            _ = c0
        }
        log(String(format: "Kraterabgleich ohne Mondrand: %d Krater zugeordnet (nächstbeste andere Lage: %.0f)", pairs.count, runnerUp))
        let need = max(7.0, 0.25 * Double(min(dets.count, 40)))
        guard Double(pairs.count) >= need, finalScore >= runnerUp * 1.35 + 1 else { return nil }
        return b.1
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
