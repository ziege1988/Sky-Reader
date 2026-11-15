import Foundation

/// Astrometrische Lösung: Pixel ↔ Himmelskoordinaten (Tangentialprojektion + Polynom für Verzeichnung).
public struct WCS: Codable, Sendable {
    public var ra0: Double
    public var dec0: Double
    /// Pixelmitte und Normierung (halbe Diagonale) für numerische Stabilität
    public var cx: Double
    public var cy: Double
    public var norm: Double
    /// Pixel (normiert) → Tangentialebene (Grad)
    public var forward: Poly2D
    /// Tangentialebene (Grad / xiNorm) → Pixel (normiert)
    public var inverse: Poly2D
    public var xiNorm: Double
    public var imageWidth: Int
    public var imageHeight: Int

    public func pixelToSky(_ x: Double, _ y: Double) -> (ra: Double, dec: Double) {
        let (xi, eta) = forward.apply((x - cx) / norm, (y - cy) / norm)
        return tangentDeproject(xi: xi, eta: eta, ra0: ra0, dec0: dec0)
    }

    public func skyToPixel(_ ra: Double, _ dec: Double) -> (x: Double, y: Double)? {
        guard let t = tangentProject(ra: ra, dec: dec, ra0: ra0, dec0: dec0) else { return nil }
        let (u, v) = inverse.apply(t.xi / xiNorm, t.eta / xiNorm)
        return (u * norm + cx, v * norm + cy)
    }

    /// Bildmaßstab in Bogensekunden pro Pixel (in Bildmitte)
    public var pixelScaleArcsec: Double {
        let a = pixelToSky(cx, cy), b = pixelToSky(cx + 10, cy), c = pixelToSky(cx, cy + 10)
        let dx = angularDistance(ra1: a.ra, dec1: a.dec, ra2: b.ra, dec2: b.dec)
        let dy = angularDistance(ra1: a.ra, dec1: a.dec, ra2: c.ra, dec2: c.dec)
        return (dx + dy) / 2 / 10 * 3600
    }

    public var center: (ra: Double, dec: Double) { pixelToSky(Double(imageWidth) / 2, Double(imageHeight) / 2) }

    /// Bildfeld (Breite × Höhe, Grad)
    public var fieldSize: (w: Double, h: Double) {
        let w = Double(imageWidth), h = Double(imageHeight)
        let l = pixelToSky(0, h / 2), r = pixelToSky(w, h / 2), t = pixelToSky(w / 2, 0), b = pixelToSky(w / 2, h)
        return (angularDistance(ra1: l.ra, dec1: l.dec, ra2: r.ra, dec2: r.dec),
                angularDistance(ra1: t.ra, dec1: t.dec, ra2: b.ra, dec2: b.dec))
    }

    /// Positionswinkel von Bild-„oben“ gegen Nord (Grad, Ost über Nord) und Spiegelung
    public var orientation: (rotation: Double, mirrored: Bool) {
        let c = pixelToSky(cx, cy)
        let up = pixelToSky(cx, cy - 20), right = pixelToSky(cx + 20, cy)
        guard let tu = tangentProject(ra: up.ra, dec: up.dec, ra0: c.ra, dec0: c.dec),
              let tr = tangentProject(ra: right.ra, dec: right.dec, ra0: c.ra, dec0: c.dec) else { return (0, false) }
        var rot = rad2deg(atan2(tu.xi, tu.eta)); if rot < 0 { rot += 360 }
        // Normales Himmelsbild: Nord oben → Ost links. Kreuzprodukt bestimmt die Parität.
        let cross = tu.xi * tr.eta - tu.eta * tr.xi
        return (rot, cross < 0)
    }

    /// Radius in Pixeln für eine Winkelausdehnung (Bogenminuten)
    public func pixels(forArcmin a: Double) -> Double { a * 60 / pixelScaleArcsec }

    /// Anpassung aus Stern-Paaren (Pixel ↔ RA/Dec)
    public static func fit(pixels: [(Double, Double)], sky: [(Double, Double)], ra0: Double, dec0: Double,
                           width: Int, height: Int, order: Int) -> WCS? {
        let cx = Double(width) / 2, cy = Double(height) / 2
        let norm = (Double(width * width + height * height)).squareRoot() / 2
        var src: [(Double, Double)] = [], dst: [(Double, Double)] = []
        for (p, s) in zip(pixels, sky) {
            guard let t = tangentProject(ra: s.0, dec: s.1, ra0: ra0, dec0: dec0) else { continue }
            src.append(((p.0 - cx) / norm, (p.1 - cy) / norm)); dst.append((t.xi, t.eta))
        }
        let need = Poly2D.termCount(order)
        guard src.count >= need + 2 || (order == 1 && src.count >= 3) else { return nil }
        guard let fwd = Poly2D.fit(src: src, dst: dst, order: order) else { return nil }
        let xiNorm = max(dst.map { max(abs($0.0), abs($0.1)) }.max() ?? 1, 1e-6)
        guard let inv = Poly2D.fit(src: dst.map { ($0.0 / xiNorm, $0.1 / xiNorm) }, dst: src, order: order) else { return nil }
        return WCS(ra0: ra0, dec0: dec0, cx: cx, cy: cy, norm: norm, forward: fwd, inverse: inv, xiNorm: xiNorm,
                   imageWidth: width, imageHeight: height)
    }

    /// Skaliert die Lösung auf eine andere Bildgröße (z. B. Analyse auf verkleinertem Bild)
    public func scaled(by f: Double, width: Int, height: Int) -> WCS {
        var w = self
        w.cx = cx * f; w.cy = cy * f; w.norm = norm * f
        w.imageWidth = width; w.imageHeight = height
        return w
    }
}
