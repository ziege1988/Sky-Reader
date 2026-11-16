import Foundation

/// Genäherte Mond-Ephemeride (Meeus, Astronomical Algorithms, Kap. 47 und 53; Genauigkeit ~0,3°).
/// Liefert optische Libration (Sub-Erde-Punkt), Sub-Sonnen-Punkt, Phase und Beleuchtung.
public struct MoonEphemeris: Sendable {
    public var date: Date
    /// Selenografische Breite/Länge des Sub-Erde-Punkts (optische Libration), Grad
    public var librationLat: Double
    public var librationLon: Double
    /// Selenografische Breite/Länge des Sub-Sonnen-Punkts, Grad
    public var subSolarLat: Double
    public var subSolarLon: Double
    /// Beleuchteter Anteil (0…1) und Mondalter in Tagen seit Neumond
    public var illuminatedFraction: Double
    public var ageDays: Double
    public var distanceKm: Double
    public var waxing: Bool

    /// Colongitude der Sonne (Lage des Morgenterminators), Grad
    public var colongitude: Double { var c = 90 - subSolarLon; c = c.truncatingRemainder(dividingBy: 360); return c < 0 ? c + 360 : c }

    public var phaseName: String {
        let a = ageDays
        switch a {
        case ..<1.5: return "Neumond"
        case ..<6.4: return "Zunehmende Sichel"
        case ..<8.4: return "Erstes Viertel"
        case ..<13.8: return "Zunehmender Mond (Dreiviertel)"
        case ..<15.8: return "Vollmond"
        case ..<21.1: return "Abnehmender Mond (Dreiviertel)"
        case ..<23.1: return "Letztes Viertel"
        case ..<28.0: return "Abnehmende Sichel"
        default: return "Neumond"
        }
    }

    public var subEarthVector: Vec3 { Vec3(ra: librationLon, dec: librationLat) }
    public var subSolarVector: Vec3 { Vec3(ra: subSolarLon, dec: subSolarLat) }

    public init(date: Date) {
        self.date = date
        let jd = julianDay(date)
        let T = (jd - 2451545.0) / 36525
        func n(_ x: Double) -> Double { var v = x.truncatingRemainder(dividingBy: 360); if v < 0 { v += 360 }; return v }
        let Lp = n(218.3164477 + 481267.88123421 * T)
        let D = n(297.8501921 + 445267.1114034 * T)
        let M = n(357.5291092 + 35999.0502909 * T)
        let Mp = n(134.9633964 + 477198.8675055 * T)
        let F = n(93.2720950 + 483202.0175233 * T)
        let Om = n(125.04452 - 1934.136261 * T)
        let r = deg2rad
        // Mondposition (geozentrisch, ekliptikal, Datum)
        let lam = Lp + 6.288774 * sin(r(Mp)) + 1.274027 * sin(r(2 * D - Mp)) + 0.658314 * sin(r(2 * D)) + 0.213618 * sin(r(2 * Mp))
            - 0.185116 * sin(r(M)) - 0.114332 * sin(r(2 * F)) + 0.058793 * sin(r(2 * D - 2 * Mp)) + 0.057066 * sin(r(2 * D - M - Mp))
            + 0.053322 * sin(r(2 * D + Mp)) + 0.045758 * sin(r(2 * D - M)) - 0.040923 * sin(r(M - Mp)) - 0.034720 * sin(r(D))
        let bet = 5.128122 * sin(r(F)) + 0.280602 * sin(r(Mp + F)) + 0.277693 * sin(r(Mp - F)) + 0.173237 * sin(r(2 * D - F))
            + 0.055413 * sin(r(2 * D - Mp + F)) + 0.046271 * sin(r(2 * D - Mp - F))
        let dist = 385000.56 - 20905.355 * cos(r(Mp)) - 3699.111 * cos(r(2 * D - Mp)) - 2955.968 * cos(r(2 * D)) - 569.925 * cos(r(2 * Mp))
        // Sonne (geozentrisch)
        let L0 = n(280.46646 + 36000.76983 * T)
        let C = (1.914602 - 0.004817 * T) * sin(r(M)) + 0.019993 * sin(r(2 * M)) + 0.000289 * sin(r(3 * M))
        let sunLon = n(L0 + C)
        let e = 0.016708634 - 0.000042037 * T
        let nu = M + C
        let Rsun = 1.000001018 * (1 - e * e) / (1 + e * cos(r(nu))) * 149_597_870.7
        // Optische Libration (Meeus 53.1)
        let I = 1.54242
        func selen(_ lambda: Double, _ beta: Double) -> (Double, Double) {
            let W = r(lambda - Om)
            let b = r(beta)
            let A = rad2deg(atan2(sin(W) * cos(b) * cos(r(I)) - sin(b) * sin(r(I)), cos(W) * cos(b)))
            var l = n(A - F); if l > 180 { l -= 360 }
            let lat = rad2deg(asin(-sin(W) * cos(b) * sin(r(I)) - sin(b) * cos(r(I))))
            return (lat, l)
        }
        let (bE, lE) = selen(lam, bet)
        librationLat = bE; librationLon = lE
        // Sub-Sonnen-Punkt (heliozentrische Richtung des Mondes)
        let lamH = sunLon + 180 + dist / Rsun * 57.296 * cos(r(bet)) * sin(r(sunLon - lam))
        let betH = dist / Rsun * bet
        let (bS, lS) = selen(lamH, betH)
        subSolarLat = bS; subSolarLon = lS
        // Phase
        let psi = acos(cos(r(bet)) * cos(r(lam - sunLon)))
        let i = atan2(Rsun * sin(psi), dist - Rsun * cos(psi))
        illuminatedFraction = (1 + cos(i)) / 2
        let elong = n(lam - sunLon)
        ageDays = elong / 360 * 29.530589
        waxing = elong < 180
        distanceKm = dist
    }
}

/// Liest ein Datum aus dem Dateinamen (z. B. „Mond_13.05.jpeg“, „2024-10-23_Mond.tif“, „Mond_20241023.jpg“)
public enum FileNameDate {
    public struct Result: Sendable { public var date: Date; public var yearKnown: Bool; public var text: String }

    public static func parse(_ name: String, reference: Date = Date()) -> Result? {
        let base = (name as NSString).deletingPathExtension
        let cal = Calendar(identifier: .gregorian)
        func make(_ y: Int, _ m: Int, _ d: Int) -> Date? {
            guard (1...12).contains(m), (1...31).contains(d), (1990...2100).contains(y) else { return nil }
            var c = DateComponents(); c.year = y; c.month = m; c.day = d; c.hour = 22
            return cal.date(from: c)
        }
        let patterns: [(String, (NSTextCheckingResult, NSString) -> (Int, Int, Int, Bool)?)] = [
            (#"(?<!\d)(\d{4})[-_.](\d{1,2})[-_.](\d{1,2})(?!\d)"#, { m, s in (Int(s.substring(with: m.range(at: 1)))!, Int(s.substring(with: m.range(at: 2)))!, Int(s.substring(with: m.range(at: 3)))!, true) }),
            (#"(?<!\d)(\d{1,2})\.(\d{1,2})\.(\d{4})(?!\d)"#, { m, s in (Int(s.substring(with: m.range(at: 3)))!, Int(s.substring(with: m.range(at: 2)))!, Int(s.substring(with: m.range(at: 1)))!, true) }),
            (#"(?<!\d)(\d{1,2})\.(\d{1,2})\.(\d{2})(?!\d)"#, { m, s in (2000 + Int(s.substring(with: m.range(at: 3)))!, Int(s.substring(with: m.range(at: 2)))!, Int(s.substring(with: m.range(at: 1)))!, true) }),
            (#"(?<!\d)(20\d{2})(\d{2})(\d{2})(?!\d)"#, { m, s in (Int(s.substring(with: m.range(at: 1)))!, Int(s.substring(with: m.range(at: 2)))!, Int(s.substring(with: m.range(at: 3)))!, true) }),
            (#"(?<!\d)(\d{1,2})\.(\d{1,2})\.?(?!\d)"#, { m, s in (0, Int(s.substring(with: m.range(at: 2)))!, Int(s.substring(with: m.range(at: 1)))!, false) }),
        ]
        let ns = base as NSString
        for (pat, extract) in patterns {
            guard let re = try? NSRegularExpression(pattern: pat) else { continue }
            for m in re.matches(in: base, range: NSRange(location: 0, length: ns.length)) {
                guard var (y, mo, d, yk) = extract(m, ns) else { continue }
                if !yk {
                    // Jahr unbekannt: jüngstes vergangenes Vorkommen des Datums
                    y = cal.component(.year, from: reference)
                    if let dt = make(y, mo, d), dt > reference { y -= 1 }
                }
                if let dt = make(y, mo, d) { return Result(date: dt, yearKnown: yk, text: ns.substring(with: m.range)) }
            }
        }
        return nil
    }
}
