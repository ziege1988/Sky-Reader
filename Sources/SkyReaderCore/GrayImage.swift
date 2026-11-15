import Foundation

/// Einkanaliges Bild mit Float-Pixeln (0…1), zeilenweise, Ursprung oben links.
public struct GrayImage: Sendable {
    public let width: Int
    public let height: Int
    public var pixels: [Float]

    public init(width: Int, height: Int, pixels: [Float]) {
        precondition(pixels.count == width * height)
        self.width = width; self.height = height; self.pixels = pixels
    }

    public init(width: Int, height: Int, fill: Float = 0) {
        self.width = width; self.height = height
        pixels = [Float](repeating: fill, count: width * height)
    }

    @inline(__always) public subscript(x: Int, y: Int) -> Float {
        get { pixels[y * width + x] }
        set { pixels[y * width + x] = newValue }
    }

    /// Bilineare Abtastung
    public func sample(_ x: Double, _ y: Double) -> Float {
        let xc = min(max(x, 0), Double(width - 1)), yc = min(max(y, 0), Double(height - 1))
        let x0 = Int(xc), y0 = Int(yc)
        let x1 = min(x0 + 1, width - 1), y1 = min(y0 + 1, height - 1)
        let fx = Float(xc - Double(x0)), fy = Float(yc - Double(y0))
        let a = self[x0, y0] * (1 - fx) + self[x1, y0] * fx
        let b = self[x0, y1] * (1 - fx) + self[x1, y1] * fx
        return a * (1 - fy) + b * fy
    }

    /// Flächenmittelnde Verkleinerung um ganzzahligen Faktor
    public func downsampled(by f: Int) -> GrayImage {
        if f <= 1 { return self }
        let w = width / f, h = height / f
        var out = [Float](repeating: 0, count: w * h)
        let inv = 1 / Float(f * f)
        for y in 0..<h {
            for x in 0..<w {
                var s: Float = 0
                for dy in 0..<f {
                    let row = (y * f + dy) * width + x * f
                    for dx in 0..<f { s += pixels[row + dx] }
                }
                out[y * w + x] = s * inv
            }
        }
        return GrayImage(width: w, height: h, pixels: out)
    }

    /// Verkleinert auf maximale Kantenlänge (ganzzahliger Faktor). Liefert Bild und Faktor.
    public func limited(maxDimension: Int) -> (GrayImage, Int) {
        let m = max(width, height)
        if m <= maxDimension { return (self, 1) }
        let f = Int(ceil(Double(m) / Double(maxDimension)))
        return (downsampled(by: f), f)
    }

    /// Box-Weichzeichner (separabel), Radius r
    public func boxBlurred(radius r: Int) -> GrayImage {
        if r <= 0 { return self }
        var tmp = [Float](repeating: 0, count: pixels.count)
        var out = [Float](repeating: 0, count: pixels.count)
        for y in 0..<height {
            var acc: Float = 0
            let row = y * width
            for x in -r...r { acc += pixels[row + min(max(x, 0), width - 1)] }
            for x in 0..<width {
                tmp[row + x] = acc / Float(2 * r + 1)
                acc += pixels[row + min(x + r + 1, width - 1)] - pixels[row + max(x - r, 0)]
            }
        }
        for x in 0..<width {
            var acc: Float = 0
            for y in -r...r { acc += tmp[min(max(y, 0), height - 1) * width + x] }
            for y in 0..<height {
                out[y * width + x] = acc / Float(2 * r + 1)
                acc += tmp[min(y + r + 1, height - 1) * width + x] - tmp[max(y - r, 0) * width + x]
            }
        }
        return GrayImage(width: width, height: height, pixels: out)
    }

    /// Lädt ein PGM (P5, 8 oder 16 Bit) – für Tests und das CLI-Werkzeug.
    public static func loadPGM(_ url: URL) throws -> GrayImage {
        let d = try Data(contentsOf: url)
        var tokens: [String] = []
        var i = 0
        let bytes = [UInt8](d)
        while tokens.count < 4 && i < bytes.count {
            while i < bytes.count && (bytes[i] == 32 || bytes[i] == 10 || bytes[i] == 13 || bytes[i] == 9) { i += 1 }
            if i < bytes.count && bytes[i] == 35 { while i < bytes.count && bytes[i] != 10 { i += 1 }; continue }
            var t = ""
            while i < bytes.count && !(bytes[i] == 32 || bytes[i] == 10 || bytes[i] == 13 || bytes[i] == 9) { t.append(Character(UnicodeScalar(bytes[i]))); i += 1 }
            tokens.append(t)
        }
        i += 1
        guard tokens.count == 4, tokens[0] == "P5", let w = Int(tokens[1]), let h = Int(tokens[2]), let mx = Int(tokens[3]) else {
            throw NSError(domain: "PGM", code: 1, userInfo: [NSLocalizedDescriptionKey: "Kein gültiges PGM"])
        }
        var px = [Float](repeating: 0, count: w * h)
        if mx < 256 {
            for k in 0..<(w * h) { px[k] = Float(bytes[i + k]) / Float(mx) }
        } else {
            for k in 0..<(w * h) { px[k] = Float(UInt16(bytes[i + 2 * k]) << 8 | UInt16(bytes[i + 2 * k + 1])) / Float(mx) }
        }
        return GrayImage(width: w, height: h, pixels: px)
    }
}

/// Bildmetadaten (EXIF), sofern vorhanden
public struct ImageMetadata: Codable, Sendable {
    public var captureDate: Date?
    public var focalLengthMM: Double?
    public var focalLength35mm: Double?
    public var cameraModel: String?
    public var lensModel: String?
    public var exposureSeconds: Double?
    public var iso: Double?
    public var originalWidth: Int = 0
    public var originalHeight: Int = 0
    public var fileName: String = ""

    public init() {}

    /// Grobe Schätzung des Bildfelds (Diagonale, Grad) aus der 35-mm-äquivalenten Brennweite.
    public var estimatedFieldDiagonalDeg: Double? {
        guard let f = focalLength35mm, f > 1 else { return nil }
        return rad2deg(2 * atan(43.27 / (2 * f)))
    }
}
