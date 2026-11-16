import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers
import SkyReaderCore

/// Ein Eintrag im Beobachtungstagebuch
struct JournalEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var created = Date()
    var title: String
    var subtitle: String
    var observationDate: Date?
    var location: String = ""
    var equipment: String = ""
    var conditions: String = ""
    var notes: String = ""
    var kind: SceneKind
    var objectNames: [String]
    var originalPath: String
    var result: AnalysisResult?

    static func == (a: JournalEntry, b: JournalEntry) -> Bool { a.id == b.id && a.title == b.title && a.notes == b.notes && a.location == b.location && a.equipment == b.equipment && a.conditions == b.conditions && a.observationDate == b.observationDate }
    func hash(into h: inout Hasher) { h.combine(id) }

    /// Überschrift: größter Nebel im Bild bzw. „Mond – größter Krater“
    static func autoTitle(result r: AnalysisResult, fileName: String) -> (String, String) {
        switch r.kind {
        case .moon:
            let craters = r.objects.filter { $0.type == .moonCrater }
            // größter Krater: offizieller Durchmesser (Fakt) oder Bildradius
            func diameter(_ o: FoundObject) -> Double {
                if let f = o.info.facts.first(where: { $0.label == "Durchmesser" }) {
                    return Double(f.value.filter { $0.isNumber }) ?? o.radius
                }
                return o.radius / 1000
            }
            if let big = craters.max(by: { diameter($0) < diameter($1) }) {
                let name = big.number == nil ? big.label : "Krater \(big.label)"
                let region = r.objects.first(where: { $0.type == .moon && ($0.label.hasPrefix("Mare") || $0.label.hasPrefix("Oceanus")) })?.label
                return ("Mond – \(name)", region.map { "Mondaufnahme · \($0)" } ?? "Mondaufnahme")
            }
            return ("Mond", "Mondaufnahme")
        case .comet:
            if let c = r.objects.first(where: { $0.type == .comet }) { return (c.info.title, "Kometenaufnahme") }
            return ("Komet", "Kometenaufnahme")
        default:
            let nebulaTypes: Set<SkyObjectType> = [.emissionNebula, .nebula, .reflectionNebula, .darkNebula, .supernovaRemnant, .planetaryNebula, .clusterNebula]
            if let neb = r.objects.filter({ nebulaTypes.contains($0.type) }).max(by: { $0.radius < $1.radius }) {
                return (neb.info.title, "Größter Nebel im Bild")
            }
            if let any = r.objects.max(by: { $0.radius < $1.radius }) { return (any.info.title, "Größtes Objekt im Bild") }
            return ((fileName as NSString).deletingPathExtension, r.kind.germanName)
        }
    }
}

/// Speichert das Tagebuch unter ~/Library/Application Support/Sky Reader/Tagebuch/<id>/
@MainActor
final class JournalStore: ObservableObject {
    @Published private(set) var entries: [JournalEntry] = []

    let root: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let u = base.appendingPathComponent("Sky Reader/Tagebuch", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }()

    init() { load() }

    func folder(_ e: JournalEntry) -> URL { root.appendingPathComponent(e.id.uuidString, isDirectory: true) }
    func imageURL(_ e: JournalEntry) -> URL { folder(e).appendingPathComponent("bild.jpg") }
    func thumbURL(_ e: JournalEntry) -> URL { folder(e).appendingPathComponent("vorschau.jpg") }

    func load() {
        let dirs = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        entries = dirs.compactMap { d in
            guard let data = try? Data(contentsOf: d.appendingPathComponent("eintrag.json")) else { return nil }
            return try? dec.decode(JournalEntry.self, from: data)
        }.sorted { ($0.observationDate ?? $0.created) > ($1.observationDate ?? $1.created) }
    }

    func save(_ e: JournalEntry) {
        try? FileManager.default.createDirectory(at: folder(e), withIntermediateDirectories: true)
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(e) { try? data.write(to: folder(e).appendingPathComponent("eintrag.json"), options: .atomic) }
        if let i = entries.firstIndex(where: { $0.id == e.id }) { entries[i] = e } else { entries.insert(e, at: 0) }
        entries.sort { ($0.observationDate ?? $0.created) > ($1.observationDate ?? $1.created) }
    }

    func delete(_ e: JournalEntry) {
        try? FileManager.default.removeItem(at: folder(e))
        entries.removeAll { $0.id == e.id }
    }

    /// Neuer Eintrag aus der aktuellen Analyse: Bild (max. 4000 px) und Vorschau mit Markierungen werden abgelegt
    func makeEntry(from state: AppState) -> JournalEntry? {
        guard let l = state.loaded, let r = state.result else { return nil }
        let (t, sub) = JournalEntry.autoTitle(result: r, fileName: l.url.lastPathComponent)
        let names = r.objects.filter { $0.type != .moon || $0.label.hasPrefix("Mare") }.prefix(12).map { $0.info.title }
        var e = JournalEntry(title: t, subtitle: sub, observationDate: state.lastMoonDate ?? l.metadata.captureDate, kind: r.kind,
                             objectNames: Array(names), originalPath: l.url.path, result: r)
        try? FileManager.default.createDirectory(at: folder(e), withIntermediateDirectories: true)
        writeJPEG(l.cgImage, to: imageURL(e), maxSize: 4000)
        if let thumb = ExportRenderer.render(image: l.cgImage, result: r, hidden: [], options: ExportOptions(showMarkers: true, showDescription: false),
                                             scale: min(1, 900 / CGFloat(max(l.cgImage.width, l.cgImage.height)))) {
            writeJPEG(thumb, to: thumbURL(e), maxSize: 900)
        }
        e.created = Date()
        return e
    }

    private func writeJPEG(_ img: CGImage, to url: URL, maxSize: Int) {
        var cg = img
        let m = max(img.width, img.height)
        if m > maxSize {
            let k = CGFloat(maxSize) / CGFloat(m)
            let w = Int(CGFloat(img.width) * k), h = Int(CGFloat(img.height) * k)
            if let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                   bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) {
                ctx.interpolationQuality = .high
                ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
                if let s = ctx.makeImage() { cg = s }
            }
        }
        guard let d = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(d, cg, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        CGImageDestinationFinalize(d)
    }

    func thumbnail(_ e: JournalEntry) -> NSImage? { NSImage(contentsOf: thumbURL(e)) ?? NSImage(contentsOf: imageURL(e)) }
}
