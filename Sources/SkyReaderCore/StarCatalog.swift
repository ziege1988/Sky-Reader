import Foundation

/// Sucht die mitgelieferten Katalogdateien.
public enum ResourceLocator {
    nonisolated(unsafe) public static var overrideDirectory: URL?

    public static func catalogURL(_ name: String) -> URL? {
        var dirs: [URL] = []
        if let o = overrideDirectory { dirs.append(o) }
        if let env = ProcessInfo.processInfo.environment["SKYREADER_CATALOGS"] { dirs.append(URL(fileURLWithPath: env)) }
        if let r = Bundle.main.resourceURL { dirs.append(r.appendingPathComponent("Catalogs")) }
        let exe = URL(fileURLWithPath: CommandLine.arguments.first ?? ".").deletingLastPathComponent()
        dirs.append(exe.appendingPathComponent("../Resources/Catalogs"))
        dirs.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/Catalogs"))
        for d in dirs {
            let u = d.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: u.path) { return u.standardizedFileURL }
        }
        return nil
    }
}

/// Sternkatalog (Tycho-2/HYG) aus stars.bin, nach Deklination sortiert.
public final class StarCatalog: @unchecked Sendable {
    public let count: Int
    public let ra: [Float]
    public let dec: [Float]
    public let mag: [Float]
    public let x: [Float], y: [Float], z: [Float]

    public init(url: URL) throws {
        let d = try Data(contentsOf: url)
        guard d.count >= 12, String(data: d.prefix(4), encoding: .ascii) == "SRST" else {
            throw NSError(domain: "SkyReader", code: 10, userInfo: [NSLocalizedDescriptionKey: "Ungültiger Sternkatalog"])
        }
        let n = d.withUnsafeBytes { Int($0.loadUnaligned(fromByteOffset: 8, as: UInt32.self).littleEndian) }
        var r = [Float](repeating: 0, count: n), de = r, m = r, xx = r, yy = r, zz = r
        d.withUnsafeBytes { buf in
            var off = 12
            for i in 0..<n {
                let a = Float(bitPattern: buf.loadUnaligned(fromByteOffset: off, as: UInt32.self).littleEndian)
                let b = Float(bitPattern: buf.loadUnaligned(fromByteOffset: off + 4, as: UInt32.self).littleEndian)
                let c = Int16(littleEndian: buf.loadUnaligned(fromByteOffset: off + 8, as: Int16.self))
                r[i] = a; de[i] = b; m[i] = Float(c) / 1000
                let ar = Double(a) * .pi / 180, dr = Double(b) * .pi / 180
                xx[i] = Float(cos(dr) * cos(ar)); yy[i] = Float(cos(dr) * sin(ar)); zz[i] = Float(sin(dr))
                off += 10
            }
        }
        count = n; ra = r; dec = de; mag = m; x = xx; y = yy; z = zz
    }

    nonisolated(unsafe) private static var cached: StarCatalog?
    private static let lock = NSLock()
    public static func shared() throws -> StarCatalog {
        lock.lock(); defer { lock.unlock() }
        if let c = cached { return c }
        guard let u = ResourceLocator.catalogURL("stars.bin") else {
            throw NSError(domain: "SkyReader", code: 11, userInfo: [NSLocalizedDescriptionKey: "Sternkatalog stars.bin nicht gefunden"])
        }
        let c = try StarCatalog(url: u)
        cached = c
        return c
    }

    /// Mittlere Sterndichte pro Quadratgrad bis zur Grenzgröße
    public var meanDensity: Double { Double(count) / 41253 }

    /// Indizes aller Sterne innerhalb des Radius (Grad) um RA/Dec, optional bis Grenzgröße
    public func cone(ra ra0: Double, dec dec0: Double, radius: Double, maxMag: Float = 99) -> [Int] {
        let lo = Float(dec0 - radius), hi = Float(dec0 + radius)
        var a = 0, b = count
        while a < b { let m = (a + b) / 2; if dec[m] < lo { a = m + 1 } else { b = m } }
        let c = Vec3(ra: ra0, dec: dec0)
        let cx = Float(c.x), cy = Float(c.y), cz = Float(c.z)
        let cosR = Float(cos(deg2rad(radius)))
        var out: [Int] = []
        var i = a
        while i < count && dec[i] <= hi {
            if mag[i] <= maxMag && x[i] * cx + y[i] * cy + z[i] * cz >= cosR { out.append(i) }
            i += 1
        }
        return out
    }
}
