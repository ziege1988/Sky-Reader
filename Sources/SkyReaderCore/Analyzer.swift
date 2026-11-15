import Foundation

/// Ein gefundenes Objekt mit Bildposition (Pixel des Originalbilds)
public struct FoundObject: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    /// Kurzbeschriftung im Bild (z. B. „M 42“)
    public var label: String
    public var type: SkyObjectType
    public var x: Double
    public var y: Double
    public var radius: Double
    /// Nummer (Mondkrater)
    public var number: Int?
    /// Kreis zeichnen? (Mondkrater: nein, nur Nummer)
    public var drawCircle: Bool
    public var info: ObjectInfo
    public var confidence: Double
    public var ra: Double?
    public var dec: Double?
}

public enum SceneKind: String, Codable, Sendable {
    case deepSky, moon, comet, unknown
    public var germanName: String {
        switch self {
        case .deepSky: return "Deep-Sky-Aufnahme"
        case .moon: return "Mondaufnahme"
        case .comet: return "Kometenaufnahme"
        case .unknown: return "Unbekannt"
        }
    }
}

public struct AnalysisResult: Codable, Sendable {
    public var kind: SceneKind
    public var imageWidth: Int
    public var imageHeight: Int
    public var objects: [FoundObject]
    /// Zusammenfassung des Bildfelds (Koordinaten, Maßstab, …)
    public var summary: ObjectInfo
    public var wcs: WCS?
    public var warnings: [String]
}

public struct AnalysisSettings: Codable, Sendable, Equatable {
    public enum CraterMode: String, Codable, Sendable, CaseIterable {
        case largest, all
        public var germanName: String { self == .largest ? "Nur die größten Krater" : "Alle sichtbaren Krater" }
    }
    public var craterMode: CraterMode = .largest
    public var density: DeepSkyCatalog.Density = .normal
    public var categories: Set<ObjectCategory> = Set(ObjectCategory.allCases)
    public var maxAnalysisSize: Int = 2000
    public init() {}
}

public struct LogEntry: Codable, Sendable, Identifiable, Hashable {
    public enum Level: String, Codable, Sendable { case step, info, success, warning, error }
    public var id = UUID()
    public var time: Date
    public var level: Level
    public var message: String
    public var progress: Double?
}

public struct AnalysisError: LocalizedError {
    public var message: String
    public init(_ m: String) { message = m }
    public var errorDescription: String? { message }
}

public struct CancelledError: LocalizedError {
    public init() {}
    public var errorDescription: String? { "Analyse abgebrochen" }
}

/// Komplette Bildanalyse: Szene erkennen → Plate Solving / Mondanalyse → Objekte & Texte
public final class SkyAnalyzer: @unchecked Sendable {
    public init() {}

    public func analyze(image full: GrayImage, metadata: ImageMetadata, settings: AnalysisSettings,
                        log: @escaping (LogEntry) -> Void,
                        isCancelled: @escaping () -> Bool) throws -> AnalysisResult {
        func step(_ m: String, _ p: Double) { log(LogEntry(time: Date(), level: .step, message: m, progress: p)) }
        func info(_ m: String) { log(LogEntry(time: Date(), level: .info, message: m)) }
        func warn(_ m: String) { log(LogEntry(time: Date(), level: .warning, message: m)) }
        func ok(_ m: String) { log(LogEntry(time: Date(), level: .success, message: m)) }
        func check() throws { if isCancelled() { throw CancelledError() } }

        step("Bild wird vorbereitet", 0.02)
        info("Datei: \(metadata.fileName), \(full.width) × \(full.height) Pixel")
        if let d = metadata.captureDate { info("Aufnahmezeitpunkt (EXIF): \(ISO8601DateFormatter().string(from: d))") }
        else { info("Kein Aufnahmezeitpunkt in den Metadaten – Kometen werden über ihre Bahn gesucht.") }
        if let f = metadata.focalLength35mm { info(String(format: "Brennweite (KB-äquivalent): %.0f mm", f)) }
        let (img, factor) = full.limited(maxDimension: settings.maxAnalysisSize)
        if factor > 1 { info("Für die Analyse auf \(img.width) × \(img.height) Pixel verkleinert (Faktor \(factor)).") }
        try check()

        step("Szene wird klassifiziert", 0.06)
        let moon = MoonAnalyzer.detectMoon(img)
        if let m = moon {
            ok(String(format: "Mondoberfläche erkannt (%.0f %% der Bildfläche hell).", m.brightFraction * 100))
            return try MoonAnalyzer.analyze(img: img, full: full, factor: factor, detection: m, settings: settings,
                                            step: step, info: info, warn: warn, ok: ok, check: check)
        }
        info("Kein Mond erkannt – Analyse als Himmelsaufnahme.")
        try check()

        step("Sterne werden erkannt", 0.12)
        let stars = StarDetector.detect(img)
        info("\(stars.count) punktförmige Sterne gefunden (Sterne selbst werden nicht beschriftet).")
        try check()

        step("Sternkatalog wird geladen", 0.2)
        let catalog = try StarCatalog.shared()
        info("\(catalog.count) Katalogsterne verfügbar.")
        try check()

        step("Plate Solving: Sternmuster werden mit dem Katalog verglichen", 0.25)
        let solver = PlateSolver(catalog: catalog)
        let fieldHint = metadata.estimatedFieldDiagonalDeg
        if let fh = fieldHint { info(String(format: "Bildfeld laut Brennweite höchstens ca. %.1f° (Diagonale).", fh)) }
        let solved = solver.solve(stars: stars, width: img.width, height: img.height, fieldHintDeg: fieldHint,
                                  log: { info($0) }, isCancelled: isCancelled)
        try check()

        // Kometensuche (auch ohne Lösung möglich)
        step("Suche nach Kometen", 0.7)
        let cometCandidate = CometAnalyzer.detect(img, stars: stars)
        if let c = cometCandidate { info(String(format: "Diffuses Objekt mit Schweif bei (%.0f, %.0f) gefunden.", c.x * Double(factor), c.y * Double(factor))) }

        guard let sol = solved else {
            if let c = cometCandidate, c.score > 0.5 {
                warn("Das Sternfeld konnte nicht bestimmt werden – der Komet kann daher nicht identifiziert werden.")
                let obj = CometAnalyzer.unidentifiedObject(c, factor: Double(factor))
                return AnalysisResult(kind: .comet, imageWidth: full.width, imageHeight: full.height, objects: [obj],
                                      summary: ObjectInfo(title: "Kometenaufnahme", subtitle: "Sternfeld nicht bestimmt"),
                                      wcs: nil, warnings: ["Plate Solving fehlgeschlagen"])
            }
            throw AnalysisError("Das Sternfeld konnte nicht bestimmt werden. Mögliche Ursachen: zu wenige oder strichförmige Sterne, sehr kleines Bildfeld (< ca. 0,7°) oder ein stark bearbeitetes Bild. Bitte den Fehlerbericht über „Report“ speichern.")
        }
        let wcsFull = sol.wcs.scaled(by: Double(factor), width: full.width, height: full.height)
        let c = wcsFull.center, fs = wcsFull.fieldSize, o = wcsFull.orientation
        ok(String(format: "Bildmitte: RA %@, Dec %@", formatRA(c.ra), formatDec(c.dec)))
        info(String(format: "Bildfeld %.2f° × %.2f°, %.2f″/Pixel, Drehung %.1f°%@", fs.w, fs.h, wcsFull.pixelScaleArcsec, o.rotation, o.mirrored ? ", gespiegelt" : ""))
        try check()

        step("Objekte im Bildfeld werden gesucht", 0.8)
        let dso = try DeepSkyCatalog.shared()
        let desc = Descriptions.shared
        let inField = dso.objects(in: wcsFull, density: settings.density, categories: settings.categories, isHighlight: desc.isHighlight)
        var objects: [FoundObject] = []
        for (d, x, y, r) in inField {
            let inf = desc.info(for: d)
            objects.append(FoundObject(id: d.id, label: d.displayID, type: d.type, x: x, y: y, radius: r, number: nil,
                                       drawCircle: true, info: inf, confidence: 1, ra: d.ra, dec: d.dec))
            info("Gefunden: \(inf.title)")
        }
        try check()

        var kind: SceneKind = .deepSky
        if settings.categories.contains(.comet) {
            step("Kometenbahnen werden berechnet", 0.88)
            if let cobj = CometAnalyzer.identify(candidate: cometCandidate, wcs: sol.wcs, factor: Double(factor),
                                                 date: metadata.captureDate, dsos: objects, log: info, isCancelled: isCancelled) {
                objects.insert(cobj, at: 0)
                kind = .comet
                ok("Komet: \(cobj.info.title)")
            } else if let cc = cometCandidate, cc.score > 0.7,
                      !objects.contains(where: { hypot($0.x - cc.x * Double(factor), $0.y - cc.y * Double(factor)) < $0.radius }) {
                objects.insert(CometAnalyzer.unidentifiedObject(cc, factor: Double(factor), wcs: wcsFull), at: 0)
                kind = .comet
                warn("Komet erkannt, aber keiner bekannten Bahn zuordenbar.")
            }
        }
        try check()

        step("Ergebnis wird zusammengestellt", 0.96)
        var facts = [
            InfoFact("Bildmitte RA", formatRA(c.ra)), InfoFact("Bildmitte Dec", formatDec(c.dec)),
            InfoFact("Bildfeld", formatDegrees(fs.w) + " × " + formatDegrees(fs.h)),
            InfoFact("Bildmaßstab", String(format: "%.2f″ pro Pixel", wcsFull.pixelScaleArcsec).replacingOccurrences(of: ".", with: ",")),
            InfoFact("Drehung", formatDegrees(o.rotation, digits: 1) + (o.mirrored ? " (gespiegelt)" : "")),
            InfoFact("Zugeordnete Sterne", "\(sol.matchedStars)"),
        ]
        if let con = Constellations.nearest(ra: c.ra, dec: c.dec, dsos: dso) { facts.insert(InfoFact("Sternbild", con), at: 2) }
        let summary = ObjectInfo(title: kind == .comet ? "Kometenaufnahme" : "Himmelsausschnitt", subtitle: "Astrometrische Lösung",
                                 facts: facts,
                                 scientific: "Die Position des Bildes am Himmel wurde durch Vergleich von \(sol.matchedStars) Sternen mit dem Sternkatalog bestimmt (mittlere Abweichung \(String(format: "%.1f", sol.rmsPixels * Double(factor))) Pixel).",
                                 latest: "", layman: objects.isEmpty ? "In diesem Ausschnitt befinden sich keine katalogisierten Nebel, Galaxien oder Sternhaufen oberhalb der gewählten Anzeigeschwelle." : "Im Bild wurden \(objects.count) Objekte gefunden. Wähle rechts ein Objekt, um mehr darüber zu erfahren.")
        ok("Analyse abgeschlossen – \(objects.count) Objekte.")
        return AnalysisResult(kind: kind, imageWidth: full.width, imageHeight: full.height, objects: objects,
                              summary: summary, wcs: wcsFull, warnings: [])
    }
}

extension Constellations {
    /// Sternbild aus dem nächstgelegenen Katalogobjekt (ausreichend genau für die Bildmitte)
    static func nearest(ra: Double, dec: Double, dsos: DeepSkyCatalog) -> String? {
        var best: (Double, String)?
        for o in dsos.objects where abs(o.dec - dec) < 3 {
            guard let c = o.con, c.count == 3 || c == "Se1" || c == "Se2" else { continue }
            let d = angularDistance(ra1: ra, dec1: dec, ra2: o.ra, dec2: o.dec)
            if best == nil || d < best!.0 { best = (d, c) }
        }
        return best.flatMap { german[$0.1] }
    }
}
