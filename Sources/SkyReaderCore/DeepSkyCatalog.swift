import Foundation

public enum SkyObjectType: String, Codable, Sendable, CaseIterable {
    case openCluster, globularCluster, clusterNebula, association, galaxy, galaxyGroup, planetaryNebula,
         emissionNebula, nebula, reflectionNebula, supernovaRemnant, darkNebula, nova, comet, moonCrater, moon

    /// Deutsche Bezeichnung
    public var germanName: String {
        switch self {
        case .openCluster: return "Offener Sternhaufen"
        case .globularCluster: return "Kugelsternhaufen"
        case .clusterNebula: return "Sternhaufen mit Nebel"
        case .association: return "Sternassoziation"
        case .galaxy: return "Galaxie"
        case .galaxyGroup: return "Galaxiengruppe"
        case .planetaryNebula: return "Planetarischer Nebel"
        case .emissionNebula: return "Emissionsnebel (H-II-Region)"
        case .nebula: return "Gasnebel"
        case .reflectionNebula: return "Reflexionsnebel"
        case .supernovaRemnant: return "Supernova-Überrest"
        case .darkNebula: return "Dunkelnebel"
        case .nova: return "Nova"
        case .comet: return "Komet"
        case .moonCrater: return "Mondkrater"
        case .moon: return "Mond"
        }
    }

    public var category: ObjectCategory {
        switch self {
        case .openCluster, .globularCluster, .association: return .cluster
        case .galaxy, .galaxyGroup: return .galaxy
        case .darkNebula: return .darkNebula
        case .comet: return .comet
        case .moonCrater, .moon: return .moon
        default: return .nebula
        }
    }
}

public enum ObjectCategory: String, Codable, Sendable, CaseIterable {
    case nebula, galaxy, cluster, darkNebula, comet, moon
    public var germanName: String {
        switch self {
        case .nebula: return "Nebel"
        case .galaxy: return "Galaxien"
        case .cluster: return "Sternhaufen"
        case .darkNebula: return "Dunkelnebel"
        case .comet: return "Kometen"
        case .moon: return "Mond"
        }
    }
}

public struct DSO: Codable, Sendable {
    public var id: String
    public var aliases: [String]?
    public var type: SkyObjectType
    public var ra: Double
    public var dec: Double
    public var maj: Double?
    public var min: Double?
    public var pa: Double?
    public var mag: Double?
    public var con: String?
    public var common: String?
    public var hubble: String?
    public var z: Double?
    public var opacity: Double?
    public var bright: Double?
    public var src: String

    /// Messier-Nummer, falls vorhanden
    public var messier: String? { aliases?.first { $0.hasPrefix("M ") } }

    /// Bevorzugte Bezeichnung (Messier vor NGC/IC)
    public var displayID: String { messier ?? id }

    public var allIDs: [String] {
        var a = [id]
        a += aliases ?? []
        return a
    }
}

public final class DeepSkyCatalog: @unchecked Sendable {
    public let objects: [DSO]
    private var byID: [String: Int] = [:]

    public init(url: URL) throws {
        objects = try JSONDecoder().decode([DSO].self, from: Data(contentsOf: url))
        for (i, o) in objects.enumerated() { for k in o.allIDs where byID[k] == nil { byID[k] = i } }
    }

    nonisolated(unsafe) private static var cached: DeepSkyCatalog?
    private static let lock = NSLock()
    public static func shared() throws -> DeepSkyCatalog {
        lock.lock(); defer { lock.unlock() }
        if let c = cached { return c }
        guard let u = ResourceLocator.catalogURL("dso.json") else {
            throw NSError(domain: "SkyReader", code: 12, userInfo: [NSLocalizedDescriptionKey: "Objektkatalog dso.json nicht gefunden"])
        }
        let c = try DeepSkyCatalog(url: u)
        cached = c
        return c
    }

    public func object(_ id: String) -> DSO? { byID[id].map { objects[$0] } }

    public enum Density: String, Codable, Sendable, CaseIterable {
        case few, normal, many
        public var germanName: String { self == .few ? "Nur markante Objekte" : self == .normal ? "Ausgewogen" : "Alle erkennbaren" }
        var factor: Double { self == .few ? 2.2 : self == .normal ? 1 : 0.45 }
        var maxCount: Int { self == .few ? 12 : self == .normal ? 30 : 80 }
    }

    /// Objekte im Bildfeld, nach Bedeutung sortiert und gefiltert
    public func objects(in wcs: WCS, density: Density, categories: Set<ObjectCategory>, isHighlight: (DSO) -> Bool) -> [(DSO, Double, Double, Double)] {
        let c = wcs.center
        let fs = wcs.fieldSize
        let fov = max(fs.w, fs.h)
        let radius = (fs.w * fs.w + fs.h * fs.h).squareRoot() / 2 * 1.1
        let fieldArcmin = fov * 60
        let f = density.factor
        let magLimit = min(15, max(8.5, 11.8 - 2.5 * log10(fov / 5))) - (f - 1) * 1.2
        var out: [(DSO, Double, Double, Double, Double)] = []  // obj, x, y, r, score
        let w = Double(wcs.imageWidth), h = Double(wcs.imageHeight)
        for o in objects {
            if !categories.contains(o.type.category) { continue }
            if abs(o.dec - c.dec) > radius + 6 { continue }
            if angularDistance(ra1: c.ra, dec1: c.dec, ra2: o.ra, dec2: o.dec) > radius + (o.maj ?? 0) / 120 { continue }
            guard let p = wcs.skyToPixel(o.ra, o.dec) else { continue }
            let rPix = max(wcs.pixels(forArcmin: (o.maj ?? 1) / 2), 0)
            // Mittelpunkt muss im Bild liegen (großzügig bei sehr großen Objekten)
            let margin = min(rPix * 0.3, max(w, h) * 0.05)
            if p.x < -margin || p.y < -margin || p.x > w + margin || p.y > h + margin { continue }
            let size = o.maj ?? 0
            let rel = size / fieldArcmin
            var score = 0.0
            let hl = isHighlight(o)
            if hl { score += 100 }
            if o.messier != nil { score += 80 }
            if o.common != nil { score += 25 }
            score += min(40, rel * 400)
            if let m = o.mag { score += max(0, 14 - m) * 3 }
            var keep = hl || o.messier != nil
            if !keep {
                switch o.type.category {
                case .galaxy:
                    keep = (o.mag ?? 99) <= magLimit && rel >= 0.004 * f
                case .cluster:
                    keep = rel >= 0.01 * f && (o.mag ?? 9) <= magLimit + 1
                case .darkNebula:
                    if o.src == "LDN" { keep = (o.opacity ?? 0) >= (density == .many ? 4 : 5) && rel >= 0.03 * f }
                    else { keep = rel >= 0.012 * f }
                default:
                    if o.src == "LBN" { keep = (o.bright ?? 6) <= (density == .many ? 4 : 3) && rel >= 0.02 * f }
                    else if o.src == "Sharpless" { keep = rel >= 0.02 * f }
                    else if o.type == .planetaryNebula { keep = (o.mag ?? 99) <= magLimit + 1 || rel >= 0.004 * f }
                    else { keep = rel >= 0.008 * f || (o.mag ?? 99) <= magLimit }
                }
            }
            if !keep { continue }
            // Riesige Objekte nur, wenn sie nicht das gesamte Bild um ein Vielfaches überdecken
            if rel > 4 && !hl { continue }
            out.append((o, p.x, p.y, max(rPix, 10), score))
        }
        out.sort { $0.4 > $1.4 }
        // Doppelte Einträge (gleiche Position, ähnliche Größe) entfernen
        var res: [(DSO, Double, Double, Double)] = []
        for e in out {
            if res.count >= density.maxCount { break }
            let dup = res.contains { r in
                let d = hypot(r.1 - e.1, r.2 - e.2)
                let ratio = e.3 / r.3
                return d < 0.35 * max(r.3, e.3) + 3 && ratio > 0.5 && ratio < 2 && r.0.type.category == e.0.type.category
            }
            if dup { continue }
            res.append((e.0, e.1, e.2, e.3))
        }
        return res
    }
}
