import Foundation

/// Mondrelief aus dem LOLA-Höhenmodell (NASA LRO, gemeinfrei): berechnet, wie der Mond bei gegebener Lage und
/// gegebenem Sonnenstand aussehen muss (Beleuchtung nach Hangneigung + Schlagschatten), und vergleicht das mit dem Foto.
/// Genutzt für die Aufnahmezeit (Schattenlängen hängen empfindlich vom Sonnenstand ab), als Qualitätsmaß der Zuordnung
/// und als Vergleichsbild.
public final class MoonRelief: @unchecked Sendable {
    public let width: Int, height: Int
    let ppd: Double, lonMin: Double, latMax: Double, metersPerUnit: Double
    private let data: Data
    static let rMoon = 1_737_400.0

    nonisolated(unsafe) private static var cached: MoonRelief??

    /// Geladenes Höhenmodell (nil, wenn die Datei fehlt)
    public static func shared() -> MoonRelief? {
        if let c = cached { return c }
        var r: MoonRelief?
        if let ju = ResourceLocator.catalogURL("moon_dem_nearside.json"), let bu = ResourceLocator.catalogURL("moon_dem_nearside.bin"),
           let jd = try? Data(contentsOf: ju), let j = try? JSONSerialization.jsonObject(with: jd) as? [String: Any],
           let w = j["width"] as? Int, let h = j["height"] as? Int,
           let d = try? Data(contentsOf: bu, options: .alwaysMapped), d.count >= w * h * 2 {
            r = MoonRelief(width: w, height: h, ppd: (j["ppd"] as? Double) ?? 32, lonMin: (j["lonMin"] as? Double) ?? -120,
                           latMax: (j["latMax"] as? Double) ?? 90, metersPerUnit: (j["metersPerUnit"] as? Double) ?? 0.5, data: d)
        }
        cached = .some(r)
        return r
    }

    init(width: Int, height: Int, ppd: Double, lonMin: Double, latMax: Double, metersPerUnit: Double, data: Data) {
        self.width = width; self.height = height; self.ppd = ppd; self.lonMin = lonMin; self.latMax = latMax
        self.metersPerUnit = metersPerUnit; self.data = data
    }

    /// Höhe in Metern (bilinear); nil außerhalb des abgedeckten Bereichs
    @inline(__always) func elevation(_ buf: UnsafeRawBufferPointer, lat: Double, lon: Double) -> Double? {
        let x = (lon - lonMin) * ppd - 0.5, y = (latMax - lat) * ppd - 0.5
        guard x >= 0, y >= 0, x < Double(width - 1), y < Double(height - 1) else { return nil }
        let x0 = Int(x), y0 = Int(y), fx = x - Double(x0), fy = y - Double(y0)
        @inline(__always) func v(_ xx: Int, _ yy: Int) -> Double {
            Double(Int16(littleEndian: buf.loadUnaligned(fromByteOffset: (yy * width + xx) * 2, as: Int16.self)))
        }
        let a = v(x0, y0), b = v(x0 + 1, y0), c = v(x0, y0 + 1), d = v(x0 + 1, y0 + 1)
        return ((a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy) * metersPerUnit
    }

    /// Gerenderte Ansicht im Raster eines Bilds (Lage in dessen Koordinaten). Liefert Helligkeit 0…1 und Gültigkeitsmaske.
    public func render(pose: MoonPose, sun: Vec3, width W: Int, height H: Int, pixelScale: Double, shadows: Bool = true) -> (pixels: [Float], mask: [Bool]) {
        var out = [Float](repeating: 0, count: W * H)
        var mask = [Bool](repeating: false, count: W * H)
        let R = pose.rotation
        let stepDeg = 1.0 / ppd
        let stepM = stepDeg * .pi / 180 * MoonRelief.rMoon
        let lock = NSLock()
        data.withUnsafeBytes { buf in
            DispatchQueue.concurrentPerform(iterations: H) { yi in
                var rowP = [Float](repeating: 0, count: W)
                var rowM = [Bool](repeating: false, count: W)
                for xi in 0..<W {
                    let X = (Double(xi) + 0.5) * pixelScale - 0.5, Y = (Double(yi) + 0.5) * pixelScale - 0.5
                    var vx = (X - pose.cx) / pose.radius
                    let vy = -(Y - pose.cy) / pose.radius
                    let q = 1 - vx * vx - vy * vy
                    guard q > 0.02 else { continue }
                    let vz = q.squareRoot()
                    if pose.mirrored { vx = -vx }
                    let bx = R[0] * vx + R[3] * vy + R[6] * vz
                    let by = R[1] * vx + R[4] * vy + R[7] * vz
                    let bz = R[2] * vx + R[5] * vy + R[8] * vz
                    let lat = rad2deg(asin(max(-1, min(1, bz)))), lon = rad2deg(atan2(by, bx))
                    let cl = max(cos(deg2rad(lat)), 0.05)
                    guard let z0 = elevation(buf, lat: lat, lon: lon),
                          let ze1 = elevation(buf, lat: lat, lon: lon + stepDeg / cl), let ze0 = elevation(buf, lat: lat, lon: lon - stepDeg / cl),
                          let zn1 = elevation(buf, lat: lat + stepDeg, lon: lon), let zn0 = elevation(buf, lat: lat - stepDeg, lon: lon) else { continue }
                    let gx = (ze1 - ze0) / (2 * stepM), gy = (zn1 - zn0) / (2 * stepM)
                    // lokale Basis
                    let la = deg2rad(lat), lo = deg2rad(lon)
                    let up = Vec3(cos(la) * cos(lo), cos(la) * sin(lo), sin(la))
                    let east = Vec3(-sin(lo), cos(lo), 0)
                    let north = Vec3(-sin(la) * cos(lo), -sin(la) * sin(lo), cos(la))
                    let n = (up - east * gx - north * gy).normalized
                    var shade = max(0, n.dot(sun))
                    if shadows && shade > 0 {
                        // Schlagschatten: in Sonnenrichtung über das Gelände laufen
                        let se = up.dot(sun), sE = east.dot(sun), sN = north.dot(sun)
                        let hor = (sE * sE + sN * sN).squareRoot() + 1e-9
                        let tanEl = se / hor
                        for k in 1..<60 {
                            let d = Double(k) * stepM * (1 + Double(k) / 15)
                            let dlat = rad2deg(d * sN / hor / MoonRelief.rMoon)
                            let dlon = rad2deg(d * sE / hor / MoonRelief.rMoon / cl)
                            guard let z = elevation(buf, lat: lat + dlat, lon: lon + dlon) else { break }
                            if z - d * d / (2 * MoonRelief.rMoon) >= z0 + d * tanEl { shade = 0; break }
                        }
                    }
                    rowP[xi] = Float(shade); rowM[xi] = true
                }
                lock.lock()
                for xi in 0..<W { out[yi * W + xi] = rowP[xi]; mask[yi * W + xi] = rowM[xi] }
                lock.unlock()
            }
        }
        return (out, mask)
    }

    // MARK: Vergleich mit dem Foto

    /// Helligkeiten 0…1 als 8-Bit-Graustufen (leicht aufgehellt wie ein Foto)
    public static func to8Bit(_ p: [Float]) -> Data {
        var s = p.filter { $0 > 0 }; s.sort()
        let white = s.isEmpty ? 1 : max(s[Int(Double(s.count - 1) * 0.995)], 1e-6)
        return Data(p.map { UInt8(max(0, min(255, ($0 / white).squareRoot() * 255))) })
    }

    /// Vorbereitetes Foto für die Vergleiche (verkleinert, Hochpass)
    public struct Target: Sendable {
        public let width: Int, height: Int
        public let pixelScale: Double         // Analysebildpixel pro Zielpixel
        let highpass: [Float]
        let valid: [Bool]
        public let photo: [Float]
    }

    public static func target(from img: GrayImage, maxDimension: Int = 640) -> Target {
        let (small, f) = img.limited(maxDimension: maxDimension)
        var p = small.pixels
        var sorted = stride(from: 0, to: p.count, by: 5).map { p[$0] }; sorted.sort()
        let white = max(sorted[Int(Double(sorted.count - 1) * 0.995)], 1e-6)
        for i in 0..<p.count { p[i] = min(1.5, p[i] / white) }
        let norm = GrayImage(width: small.width, height: small.height, pixels: p)
        let hp = highpass(norm)
        return Target(width: small.width, height: small.height, pixelScale: Double(f), highpass: hp, valid: p.map { $0 > 0.03 }, photo: p)
    }

    static func highpass(_ g: GrayImage) -> [Float] {
        let b = g.boxBlurred(radius: 3).boxBlurred(radius: 3)
        return (0..<g.pixels.count).map { g.pixels[$0] - b.pixels[$0] }
    }

    /// Normierte Kreuzkorrelation der Hochpass-Bilder (−1…1)
    public func similarity(pose: MoonPose, sun: Vec3, target t: Target) -> (score: Double, render: [Float]) {
        let (r, m) = render(pose: pose, sun: sun, width: t.width, height: t.height, pixelScale: t.pixelScale)
        let hr = MoonRelief.highpass(GrayImage(width: t.width, height: t.height, pixels: r))
        var sx = 0.0, sy = 0.0, n = 0.0
        for i in 0..<r.count where m[i] && t.valid[i] { sx += Double(hr[i]); sy += Double(t.highpass[i]); n += 1 }
        guard n > 500 else { return (0, r) }
        let mx = sx / n, my = sy / n
        var cxy = 0.0, cxx = 0.0, cyy = 0.0
        for i in 0..<r.count where m[i] && t.valid[i] {
            let a = Double(hr[i]) - mx, b = Double(t.highpass[i]) - my
            cxy += a * b; cxx += a * a; cyy += b * b
        }
        return (cxy / max((cxx * cyy).squareRoot(), 1e-12), r)
    }

    /// Ergebnis der Zeitbestimmung über den Schattenwurf
    public struct TimeFit: Sendable {
        public var date: Date
        /// ± Stunden (Bereich, in dem die Übereinstimmung höchstens leicht unter dem Bestwert liegt)
        public var uncertaintyHours: Double
        public var score: Double
        public var render: [Float]
    }

    /// Sucht im Fenster ±windowHours um `near` den Zeitpunkt, dessen Sonnenstand die Schatten im Foto am besten erklärt.
    public func fitTime(pose: MoonPose, near: Date, windowHours: Double = 12, target t: Target, isCancelled: () -> Bool = { false }) -> TimeFit? {
        func eval(_ h: Double) -> (Double, [Float]) {
            similarity(pose: pose, sun: MoonEphemeris(date: near.addingTimeInterval(h * 3600)).subSolarVector, target: t)
        }
        var curve: [(Double, Double)] = []
        var bestH = 0.0, bestS = -2.0, bestR: [Float] = []
        var h = -windowHours
        while h <= windowHours + 1e-9 {
            if isCancelled() { return nil }
            let (s, r) = eval(h)
            curve.append((h, s))
            if s > bestS { bestS = s; bestH = h; bestR = r }
            h += 1
        }
        // fein: ±1 h in 15-Minuten-Schritten
        for dh in stride(from: -0.75, through: 0.75, by: 0.25) where dh != 0 {
            let hh = bestH + dh
            guard abs(hh) <= windowHours else { continue }
            let (s, r) = eval(hh)
            curve.append((hh, s))
            if s > bestS { bestS = s; bestH = hh; bestR = r }
        }
        guard bestS > 0.15 else { return nil }
        // Unsicherheit: Spanne, in der die Übereinstimmung höchstens 0,005 unter dem Bestwert liegt
        let close = curve.filter { $0.1 >= bestS - 0.005 }.map { $0.0 }
        let unc = max(0.5, max(bestH - (close.min() ?? bestH), (close.max() ?? bestH) - bestH))
        return TimeFit(date: near.addingTimeInterval(bestH * 3600), uncertaintyHours: unc, score: bestS, render: bestR)
    }
}
