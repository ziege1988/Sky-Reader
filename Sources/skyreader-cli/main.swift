import Foundation
import SkyReaderCore

// Testwerkzeug: skyreader-cli bild.pgm [--all-craters] [--density few|normal|many] [--date 2024-10-20T19:00:00Z] [--json out.json]
var args = Array(CommandLine.arguments.dropFirst())
if args.first == "--ephem" {
    // Mond-Ephemeride für ISO-Zeitpunkte ausgeben (Entwicklung)
    for s in args.dropFirst() {
        guard let d = ISO8601DateFormatter().date(from: s) else { continue }
        let e = MoonEphemeris(date: d)
        let alt = e.altitudes(latitude: 50.1, longitude: 8.7)
        print(String(format: "%@  Libration %+.1f°/%+.1f°  Sub-Sonne %+.1f°/%+.1f°  Colong. %.1f°  beleuchtet %.0f%%  Alter %.1f d  %@  Höhe Frankfurt: Mond %.1f° Sonne %.1f°",
                     s, e.librationLat, e.librationLon, e.subSolarLat, e.subSolarLon, e.colongitude, e.illuminatedFraction * 100, e.ageDays, e.phaseName, alt.moon, alt.sun))
    }
    exit(0)
}
guard let path = args.first else { print("usage: skyreader-cli image.pgm [--all-craters] [--density x] [--date ISO] [--json out]"); exit(1) }
var settings = AnalysisSettings()
var meta = ImageMetadata()
var jsonOut: String?
var i = 1
while i < args.count {
    switch args[i] {
    case "--all-craters": settings.craterMode = .all
    case "--density": i += 1; settings.density = DeepSkyCatalog.Density(rawValue: args[i]) ?? .normal
    case "--date": i += 1; meta.captureDate = ISO8601DateFormatter().date(from: args[i]); settings.moonDate = meta.captureDate
    case "--json": i += 1; jsonOut = args[i]
    case "--ort":   // --ort 51.0,10.0 (Breite, Länge Ost)
        i += 1; let p = args[i].split(separator: ",").compactMap { Double($0) }
        if p.count == 2 { settings.observerLatitude = p[0]; settings.observerLongitude = p[1] }
    default: break
    }
    i += 1
}
let img = try GrayImage.loadPGM(URL(fileURLWithPath: path))
if let k = args.firstIndex(of: "--rings"), args.count > k + 1 {
    // Nur Ringwall-Detektor (Entwicklung)
    let t = Date()
    let rings = RingDetector.detect(img, maxCount: 120)
    print("Ringe: \(rings.count) in \(String(format: "%.1f", Date().timeIntervalSince(t))) s")
    let objs = rings.map { ["x": $0.x, "y": $0.y, "radius": $0.r, "strength": $0.strength] }
    try JSONSerialization.data(withJSONObject: ["objects": objs, "imageWidth": img.width]).write(to: URL(fileURLWithPath: args[k + 1]))
    exit(0)
}
meta.fileName = URL(fileURLWithPath: path).lastPathComponent
// --name „Mond_13.05.jpeg“, --ort 51,10: Dateinamen für die Datumserkennung vorgeben (Entwicklung)
if let k = args.firstIndex(of: "--name"), args.count > k + 1 { meta.fileName = args[k + 1] }
meta.originalWidth = img.width; meta.originalHeight = img.height
let t0 = Date()
do {
    let r = try SkyAnalyzer().analyze(image: img, metadata: meta, settings: settings, log: { e in
        print(String(format: "[%5.1fs] %@ %@", Date().timeIntervalSince(t0), e.level.rawValue.padding(toLength: 8, withPad: " ", startingAt: 0), e.message))
    }, isCancelled: { false })
    print("== \(r.kind.germanName): \(r.objects.count) Objekte")
    for o in r.objects { print(String(format: "  %-22@ %-26@ x=%6.0f y=%6.0f r=%5.0f", o.label, o.info.subtitle, o.x, o.y, o.radius)) }
    if let j = jsonOut {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(r).write(to: URL(fileURLWithPath: j))
    }
} catch {
    print("FEHLER: \(error.localizedDescription)")
    exit(2)
}
