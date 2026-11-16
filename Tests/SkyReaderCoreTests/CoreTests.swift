import XCTest
import SkyReaderCore

final class CoreTests: XCTestCase {
    func testTangentRoundTrip() {
        for (ra, dec) in [(10.0, 20.0), (359.5, -45.0), (180.0, 89.5)] {
            let t = tangentProject(ra: ra + 0.7, dec: dec + 0.4, ra0: ra, dec0: dec)!
            let b = tangentDeproject(xi: t.xi, eta: t.eta, ra0: ra, dec0: dec)
            XCTAssertEqual(angularDistance(ra1: b.ra, dec1: b.dec, ra2: ra + 0.7, dec2: dec + 0.4), 0, accuracy: 1e-9)
        }
    }

    func testQuadHashInvariance() {
        let p: [(Double, Double)] = [(0, 0), (10, 2), (4, 7), (6, -3)]
        let a = QuadHash.compute(p)!
        // gedreht, skaliert, verschoben und permutiert
        let ang = 0.83, s = 3.7
        let q = [p[2], p[0], p[3], p[1]].map { (s * ($0.0 * cos(ang) - $0.1 * sin(ang)) + 50, s * ($0.0 * sin(ang) + $0.1 * cos(ang)) - 20) }
        let b = QuadHash.compute(q)!
        XCTAssertEqual(a.h.0, b.h.0, accuracy: 1e-5); XCTAssertEqual(a.h.1, b.h.1, accuracy: 1e-5)
        XCTAssertEqual(a.h.2, b.h.2, accuracy: 1e-5); XCTAssertEqual(a.h.3, b.h.3, accuracy: 1e-5)
    }

    func testCometEphemerisTsuchinshanATLAS() {
        // Näherungs-Bahnelemente von C/2023 A3: Perihel 2024-09-27.74, q = 0.39144 AE
        let line = "    CK23A030  2024 09 27.7426  0.391445  1.000117  308.4920   21.5596  139.1110  20241025   4.5  4.0  C/2023 A3 (Tsuchinshan-ATLAS)                            MPEC 2024-UQ0"
        let el = CometElements(mpcLine: line)
        XCTAssertNotNil(el)
        // 23. Oktober 2024, 18 UT: Komet stand in der Schlange/Schlangenträger nahe RA ~ 15h–17h, Dec ~ 0…+8°
        let e = el!.ephemeris(jd: julianDay(year: 2024, month: 10, day: 23.75))
        XCTAssertGreaterThan(e.ra, 200); XCTAssertLessThan(e.ra, 270)
        XCTAssertGreaterThan(e.dec, -10); XCTAssertLessThan(e.dec, 15)
        XCTAssertLessThan(e.delta, 0.8)
    }

    func testWCSFitIdentity() {
        // Synthetisches Feld: 1"/px um RA 83.8, Dec -5.4
        var px: [(Double, Double)] = [], sky: [(Double, Double)] = []
        for i in 0..<30 {
            let x = Double(i % 6) * 300 + 50, y = Double(i / 6) * 250 + 40
            let s = tangentDeproject(xi: (x - 900) / 3600, eta: -(y - 650) / 3600, ra0: 83.8, dec0: -5.4)
            px.append((x, y)); sky.append(s)
        }
        let w = WCS.fit(pixels: px, sky: sky, ra0: 83.8, dec0: -5.4, width: 1800, height: 1300, order: 1)!
        XCTAssertEqual(w.pixelScaleArcsec, 1, accuracy: 0.01)
        let p = w.skyToPixel(sky[7].0, sky[7].1)!
        XCTAssertEqual(p.x, px[7].0, accuracy: 0.05); XCTAssertEqual(p.y, px[7].1, accuracy: 0.05)
    }

    func testMoonRegistrationSynthetic() throws {
        ResourceLocator.overrideDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Resources/Catalogs").standardizedFileURL
        let cat = MoonRegistration.catalog()
        try XCTSkipIf(cat.isEmpty, "Kraterkatalog nicht gefunden")
        // Bekannte Lage: Libration −4°/+6°, Bild um 40° gedreht, Rand unten links wie in den Testbildern
        let lat0 = deg2rad(-4.0), lon0 = deg2rad(6.0), th = deg2rad(40.0)
        let w = 1600, h = 1100, cx = 1800.0, cy = -1600.0, R = 2700.0
        var rng = SystemRandomNumberGenerator()
        var dets: [DetectedCrater] = []
        var truth = 0
        for c in cat where c.d >= 15 {
            let la = deg2rad(c.lat), lo = deg2rad(c.lon)
            let cosc = sin(lat0) * sin(la) + cos(lat0) * cos(la) * cos(lo - lon0)
            guard cosc > 0.15 else { continue }
            let X = cos(la) * sin(lo - lon0), Y = cos(lat0) * sin(la) - sin(lat0) * cos(la) * cos(lo - lon0)
            let dx = X * cos(th) - Y * sin(th), dy = X * sin(th) + Y * cos(th)
            let px = cx + R * dx + Double.random(in: -4...4, using: &rng), py = cy - R * dy + Double.random(in: -4...4, using: &rng)
            guard px > 0, py > 0, px < Double(w), py < Double(h) else { continue }
            dets.append(DetectedCrater(x: px, y: py, r: c.d / 2 / 1737.4 * R * Double.random(in: 0.7...1.05, using: &rng), strength: 1, shadowFraction: 0))
            truth += 1
        }
        for _ in 0..<(truth * 3 / 10) {
            dets.append(DetectedCrater(x: Double.random(in: 0..<Double(w), using: &rng), y: Double.random(in: 0..<Double(h), using: &rng),
                                       r: Double.random(in: 10...60, using: &rng), strength: 1, shadowFraction: 0))
        }
        XCTAssertGreaterThan(truth, 15)
        let pose = MoonRegistration.register(craters: dets, limb: LimbCircle(cx: cx, cy: cy, r: R, inliers: 100), width: w, height: h)
        XCTAssertNotNil(pose)
        if let p = pose {
            XCTAssertEqual(p.subEarth.lat, -4, accuracy: 1.0)
            XCTAssertEqual(p.subEarth.lon, 6, accuracy: 1.0)
            XCTAssertFalse(p.mirrored)
            XCTAssertGreaterThan(p.matches, truth / 2)
        }
    }
}
