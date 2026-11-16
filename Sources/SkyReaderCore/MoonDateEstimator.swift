import Foundation

/// Schätzt das Aufnahmedatum einer Mondaufnahme allein aus dem Bild.
///
/// Zwei Messgrößen werden aus dem Bild gewonnen und mit der Ephemeride verglichen:
/// 1. **Libration** (Sub-Erde-Punkt) aus der Kraterlage – ändert sich im Rhythmus von ~27 Tagen.
/// 2. **Colongitude** (Lage des Terminators) aus der Licht-Schatten-Grenze – ändert sich um ~12° pro Tag.
/// Die Kombination wiederholt sich nur selten exakt; aus mehreren Jahren werden die passendsten Zeitpunkte gesucht.
/// Ein Datum im Dateinamen (auch ohne Jahr) schränkt die Suche zusätzlich ein.
public struct MoonDateEstimate: Sendable {
    public struct Candidate: Sendable, Hashable {
        public var date: Date
        /// Abweichung (Chi²-artig, kleiner = besser)
        public var cost: Double
        public var colongitude: Double
        public var librationLat: Double
        public var librationLon: Double
        public var phaseName: String
        public var illuminatedFraction: Double
    }

    public enum Quality: String, Sendable {
        /// Terminator und Libration gemessen, eindeutiges Ergebnis
        case good
        /// Mehrere Zeitpunkte passen ähnlich gut oder die Messung ist grob
        case uncertain
    }

    public var best: Candidate
    /// Weitere passende Zeitpunkte (mindestens einige Tage vom besten entfernt)
    public var alternatives: [Candidate]
    public var quality: Quality
    public var measuredLibrationLat: Double
    public var measuredLibrationLon: Double
    /// Gemessene Colongitude (nil, wenn kein Terminator im Bild ist)
    public var measuredColongitude: Double?
    /// Unsicherheit der Uhrzeit in Stunden (± 1σ)
    public var timeUncertaintyHours: Double
    /// Suche auf das Datum aus dem Dateinamen beschränkt
    public var usedFileNameDate: Bool
}

public enum MoonDateEstimator {
    /// Unsicherheit der aus der Kraterlage bestimmten Libration (Grad, 1σ)
    static let librationSigma = 1.3
    /// Fortschritt der Colongitude in Grad pro Stunde
    static let colongitudePerHour = 360.0 / (29.530589 * 24)

    // MARK: Sonnenstand aus dem Bild

    /// Sub-Sonnen-Länge aus der Beleuchtung: Für jede Sonnenrichtung wird vorhergesagt, welche Teile der sichtbaren
    /// Mondoberfläche beleuchtet sind, und mit dem Bild verglichen. Liefert Länge und halbe Breite des passenden Bereichs.
    public static func measureSubSolarLongitude(pose: MoonPose, image img: GrayImage, threshold: Float) -> (lon: Double, halfWidth: Double)? {
        var pts: [Vec3] = []
        var lit: [Bool] = []
        let litLevel = threshold * 0.4
        var lat = -86.0
        while lat <= 86 {
            var lon = -100.0
            while lon <= 100 {
                let v = Vec3(ra: lon, dec: lat)
                if let q = pose.project(lat: lat, lon: lon), q.z > 0.15 {
                    let x = Int(q.x), y = Int(q.y)
                    if x >= 3, y >= 3, x < img.width - 3, y < img.height - 3 {
                        // kleiner Mittelwert gegen Rauschen und Kraterschatten
                        var s: Float = 0
                        for dy in -1...1 { for dx in -1...1 { s += img[x + dx, y + dy] } }
                        pts.append(v)
                        lit.append(s / 9 > litLevel)
                    }
                }
                lon += 2
            }
            lat += 2
        }
        guard pts.count >= 150 else { return nil }
        let litCount = lit.filter { $0 }.count
        guard litCount >= 50 else { return nil }
        // Bewertung je Sonnenlänge (Sub-Sonnen-Breite ≤ 1,6° – vernachlässigbar)
        var score = [Double](repeating: 0, count: 360)
        for k in 0..<360 {
            let s = Vec3(ra: Double(k), dec: 0)
            var agree = 0.0, total = 0.0
            for i in 0..<pts.count {
                let d = pts[i].dot(s)
                // Punkte direkt am Terminator sind wegen Bergen/Schatten unsicher → geringeres Gewicht
                let w = abs(d) < 0.03 ? 0.3 : 1.0
                total += w
                if (d > 0) == lit[i] { agree += w }
            }
            score[k] = agree / total
        }
        guard let bestK = score.indices.max(by: { score[$0] < score[$1] }) else { return nil }
        let best = score[bestK]
        guard best > 0.8 else { return nil }
        // zusammenhängender Bereich nahezu gleich guter Lösungen um das Optimum
        let tol = 0.004
        var lo = 0, hi = 0
        while lo < 180, score[(bestK - lo - 1 + 360) % 360] >= best - tol { lo += 1 }
        while hi < 180, score[(bestK + hi + 1) % 360] >= best - tol { hi += 1 }
        let center = Double(bestK) + Double(hi - lo) / 2
        var c = center.truncatingRemainder(dividingBy: 360); if c < 0 { c += 360 }
        return (c, Double(hi + lo) / 2 + 1)
    }

    // MARK: Datumssuche

    /// Sucht die Zeitpunkte, deren Libration und Colongitude am besten zu den Messwerten passen.
    /// - Parameters:
    ///   - fileNameDate: Datum aus dem Dateinamen; mit Jahr → nur diese Nacht, ohne Jahr → dieser Tag in allen Jahren.
    ///   - range: Suchzeitraum ohne Dateinamen-Datum
    public static func search(librationLat: Double, librationLon: Double, colongitude: Double?, colongitudeSigma: Double,
                              fileNameDate: FileNameDate.Result? = nil,
                              range: ClosedRange<Date> = Date(timeIntervalSince1970: 946_684_800)...Date(),
                              isCancelled: () -> Bool = { false }) -> MoonDateEstimate? {
        let sl = librationSigma
        let sc = max(2.5, colongitudeSigma)
        func cost(_ e: MoonEphemeris) -> Double {
            var c = pow((e.librationLat - librationLat) / sl, 2)
            var dl = e.librationLon - librationLon
            dl = (dl + 540).truncatingRemainder(dividingBy: 360) - 180
            c += pow(dl / sl, 2)
            if let col = colongitude {
                var d = e.colongitude - col
                d = (d + 540).truncatingRemainder(dividingBy: 360) - 180
                c += pow(d / sc, 2)
            }
            return c
        }
        // Suchfenster
        var windows: [ClosedRange<Date>] = []
        let cal = Calendar(identifier: .gregorian)
        if let f = fileNameDate {
            let ymd = cal.dateComponents([.year, .month, .day], from: f.date)
            let years: [Int]
            if f.yearKnown { years = [ymd.year ?? 2024] } else {
                let y1 = cal.component(.year, from: range.upperBound)
                years = Array(2000...max(2000, y1))
            }
            for y in years {
                var comps = DateComponents()
                comps.year = y; comps.month = ymd.month; comps.day = ymd.day
                guard let day = cal.date(from: comps) else { continue }
                // Abend des genannten Tages bis zum folgenden Morgen (Nachtaufnahmen), etwas Reserve
                let a = day.addingTimeInterval(-6 * 3600), b = day.addingTimeInterval(33 * 3600)
                if a <= range.upperBound.addingTimeInterval(86400) { windows.append(a...b) }
            }
        } else {
            windows = [range]
        }
        guard !windows.isEmpty else { return nil }
        // Grobsuche
        let coarse: TimeInterval = fileNameDate != nil ? 1800 : 6 * 3600
        var samples: [(Date, Double)] = []
        for w in windows {
            var t = w.lowerBound
            while t <= w.upperBound {
                samples.append((t, cost(MoonEphemeris(date: t))))
                t = t.addingTimeInterval(coarse)
            }
            if isCancelled() { return nil }
        }
        samples.sort { $0.1 < $1.1 }
        // beste, deutlich voneinander getrennte Kandidaten (≥ 4 Tage)
        var seeds: [Date] = []
        for (t, _) in samples {
            if seeds.contains(where: { abs($0.timeIntervalSince(t)) < 4 * 86400 }) { continue }
            seeds.append(t)
            if seeds.count >= 8 { break }
        }
        // Verfeinerung
        func refine(_ t0: Date) -> (Date, Double) {
            var bestT = t0, bestC = cost(MoonEphemeris(date: t0))
            for (span, step) in [(coarse, 900.0), (1800.0, 120.0)] {
                let center = bestT
                var t = center.addingTimeInterval(-span)
                while t <= center.addingTimeInterval(span) {
                    let c = cost(MoonEphemeris(date: t))
                    if c < bestC { bestC = c; bestT = t }
                    t = t.addingTimeInterval(step)
                }
            }
            return (bestT, bestC)
        }
        var cands: [MoonDateEstimate.Candidate] = seeds.map { s in
            let (t, c) = refine(s)
            let e = MoonEphemeris(date: t)
            return .init(date: t, cost: c, colongitude: e.colongitude, librationLat: e.librationLat, librationLon: e.librationLon,
                         phaseName: e.phaseName, illuminatedFraction: e.illuminatedFraction)
        }
        cands.sort { $0.cost < $1.cost }
        guard let best = cands.first else { return nil }
        let alts = Array(cands.dropFirst().filter { $0.cost < best.cost + 9 }.prefix(3))
        // eindeutig: Terminator gemessen, gutes Gesamtmaß und nächster Kandidat deutlich schlechter
        let separated = cands.count < 2 || cands[1].cost - best.cost > 4
        let good = colongitude != nil && colongitudeSigma <= 8 && best.cost < 9 && separated
        let hours = colongitude != nil ? sc / colongitudePerHour : 48
        return MoonDateEstimate(best: best, alternatives: alts, quality: good ? .good : .uncertain,
                                measuredLibrationLat: librationLat, measuredLibrationLon: librationLon,
                                measuredColongitude: colongitude, timeUncertaintyHours: hours,
                                usedFileNameDate: fileNameDate != nil)
    }

    /// Vollständige Schätzung aus einer bestimmten Mondlage und dem Bild.
    public static func estimate(pose: MoonPose, image: GrayImage, threshold: Float, fileNameDate: FileNameDate.Result?,
                                isCancelled: () -> Bool = { false }) -> MoonDateEstimate? {
        let se = pose.subEarth
        let sun = measureSubSolarLongitude(pose: pose, image: image, threshold: threshold)
        var colong: Double?
        var sigma = 180.0
        if let s = sun, s.halfWidth < 60 {
            var c = 90 - s.lon; c = c.truncatingRemainder(dividingBy: 360); if c < 0 { c += 360 }
            colong = c
            // Breite des passenden Bereichs plus Unschärfe durch Libration/Gelände
            sigma = max(3, s.halfWidth * 0.6 + 2)
        }
        // Ohne Terminator und ohne Dateinamen-Datum ist keine sinnvolle Schätzung möglich
        if colong == nil && fileNameDate == nil { return nil }
        return search(librationLat: se.lat, librationLon: se.lon, colongitude: colong, colongitudeSigma: sigma,
                      fileNameDate: fileNameDate, isCancelled: isCancelled)
    }
}
