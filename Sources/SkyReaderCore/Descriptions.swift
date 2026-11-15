import Foundation

public struct InfoFact: Codable, Hashable, Sendable {
    public var label: String
    public var value: String
    public init(_ label: String, _ value: String) { self.label = label; self.value = value }
}

/// Texte zu einem Objekt: Fakten, Wissenschaft, neueste Erkenntnisse, Laienbeschreibung
public struct ObjectInfo: Codable, Hashable, Sendable {
    public var title: String
    public var subtitle: String
    public var facts: [InfoFact]
    public var scientific: String
    public var latest: String
    public var layman: String
    public init(title: String, subtitle: String, facts: [InfoFact] = [], scientific: String = "", latest: String = "", layman: String = "") {
        self.title = title; self.subtitle = subtitle; self.facts = facts
        self.scientific = scientific; self.latest = latest; self.layman = layman
    }
}

/// Kuratierter Eintrag (Resources/Content/objects_de.json)
public struct CuratedEntry: Codable, Sendable {
    public var ids: [String]
    public var name: String
    public var distance: String?
    public var size: String?
    public var age: String?
    public var extra: [String: String]?
    public var scientific: String
    public var latest: String
    public var layman: String
}

public final class Descriptions: @unchecked Sendable {
    private var curated: [String: CuratedEntry] = [:]
    public static let shared = Descriptions()

    init() {
        if let u = ResourceLocator.catalogURL("objects_de.json"),
           let d = try? Data(contentsOf: u),
           let list = try? JSONDecoder().decode([CuratedEntry].self, from: d) {
            for e in list { for i in e.ids { curated[i] = e } }
        }
    }

    public var curatedCount: Int { Set(curated.values.map { $0.name }).count }

    public func curatedEntry(for o: DSO) -> CuratedEntry? {
        for i in o.allIDs { if let e = curated[i] { return e } }
        return nil
    }

    public func isHighlight(_ o: DSO) -> Bool { curatedEntry(for: o) != nil }

    public func curatedEntry(id: String) -> CuratedEntry? { curated[id] }

    // MARK: Deep-Sky

    public func info(for o: DSO) -> ObjectInfo {
        let cur = curatedEntry(for: o)
        let ids = ([o.displayID] + o.allIDs.filter { $0 != o.displayID && !$0.hasPrefix("C ") })
        var uniq: [String] = []
        for i in ids where !uniq.contains(i) { uniq.append(i) }
        let name = cur?.name ?? germanCommonName(o.common)
        let title = name.map { "\(o.displayID) – \($0)" } ?? o.displayID
        var facts: [InfoFact] = []
        facts.append(InfoFact("Objekttyp", o.type.germanName + (o.hubble.map { " (Typ \($0))" } ?? "")))
        if let d = cur?.distance { facts.append(InfoFact("Entfernung", d)) }
        else if let d = galaxyDistance(o) { facts.append(InfoFact("Entfernung", d + " (aus Rotverschiebung)")) }
        if let s = cur?.size { facts.append(InfoFact("Ausdehnung", s)) }
        if let maj = o.maj {
            let s = o.min.map { formatArcmin(maj) + " × " + formatArcmin($0) } ?? formatArcmin(maj)
            facts.append(InfoFact("Scheinbare Größe", s))
        }
        if let m = o.mag { facts.append(InfoFact("Helligkeit", String(format: "%.1f mag", m).replacingOccurrences(of: ".", with: ","))) }
        if let a = cur?.age { facts.append(InfoFact("Alter", a)) }
        for (k, v) in (cur?.extra ?? [:]).sorted(by: { $0.key < $1.key }) { facts.append(InfoFact(k, v)) }
        if let c = o.con, let cn = Constellations.german[c] { facts.append(InfoFact("Sternbild", cn)) }
        facts.append(InfoFact("Koordinaten (J2000)", formatRA(o.ra) + "  " + formatDec(o.dec)))
        if uniq.count > 1 { facts.append(InfoFact("Katalognummern", uniq.joined(separator: ", "))) }
        facts.append(InfoFact("Quelle", o.src == "OpenNGC" ? "OpenNGC" : "\(o.src)-Katalog"))
        if let cur = cur {
            return ObjectInfo(title: title, subtitle: o.type.germanName, facts: facts,
                              scientific: cur.scientific, latest: cur.latest, layman: cur.layman)
        }
        let (sci, lay) = generatedTexts(o)
        return ObjectInfo(title: title, subtitle: o.type.germanName, facts: facts, scientific: sci,
                          latest: "Für dieses Objekt liegen in Sky Reader keine gesonderten Forschungsnotizen vor. Die Angaben stammen aus dem \(o.src == "OpenNGC" ? "OpenNGC" : o.src)-Katalog.",
                          layman: lay)
    }

    func galaxyDistance(_ o: DSO) -> String? {
        guard o.type.category == .galaxy, let z = o.z, z > 0.0025 else { return nil }
        let mpc = z * 299_792.458 / 70
        let mly = mpc * 3.2616
        return mly >= 1000 ? String(format: "ca. %.1f Mrd. Lichtjahre", mly / 1000) : String(format: "ca. %.0f Mio. Lichtjahre", mly)
    }

    func germanCommonName(_ s: String?) -> String? {
        guard let s = s, let first = s.split(separator: ",").first else { return nil }
        let n = String(first).trimmingCharacters(in: .whitespaces)
        return CommonNames.german[n] ?? n
    }

    func generatedTexts(_ o: DSO) -> (String, String) {
        let size = o.maj.map { " Am Himmel erstreckt es sich über etwa \(formatArcmin($0))." } ?? ""
        switch o.type {
        case .galaxy:
            let d = galaxyDistance(o).map { " Aus ihrer Rotverschiebung ergibt sich eine Entfernung von \($0)." } ?? ""
            let hub = o.hubble.map { " Ihre morphologische Klassifikation lautet \($0)." } ?? ""
            return ("Eine eigenständige Galaxie weit außerhalb der Milchstraße, bestehend aus Milliarden Sternen, Gas, Staub und Dunkler Materie.\(hub)\(d)\(size)",
                    "Dieser kleine Lichtfleck ist eine ganze Galaxie – eine eigene „Sterneninsel“ mit Milliarden Sonnen. Ihr Licht war Millionen Jahre unterwegs, bevor es deine Kamera erreicht hat.")
        case .galaxyGroup:
            return ("Eine Gruppe gravitativ gebundener Galaxien.\(size)", "Hier stehen mehrere Galaxien so nah beieinander, dass sie sich gegenseitig mit ihrer Schwerkraft beeinflussen.")
        case .openCluster:
            return ("Ein offener Sternhaufen: eine Gruppe gemeinsam aus einer Gaswolke entstandener, relativ junger Sterne in der Scheibe der Milchstraße, die nur schwach gravitativ gebunden sind.\(size)",
                    "Diese Sterne sind „Geschwister“ – sie sind gemeinsam aus derselben Gaswolke entstanden und ziehen noch als lockere Gruppe durch die Milchstraße.")
        case .globularCluster:
            return ("Ein Kugelsternhaufen: eine dichte, kugelförmige Ansammlung von Hunderttausenden sehr alter Sterne im Halo der Milchstraße, oft über 10 Milliarden Jahre alt.\(size)",
                    "Ein Kugelsternhaufen ist wie eine riesige Sternenkugel – Hunderttausende uralte Sonnen, dicht gedrängt, fast so alt wie das Universum selbst.")
        case .clusterNebula, .emissionNebula, .nebula:
            return ("Eine Wolke aus Wasserstoffgas, die von der ultravioletten Strahlung junger, heißer Sterne ionisiert wird und dadurch – vor allem im roten H-alpha-Licht – selbst leuchtet. Solche Regionen sind Geburtsstätten neuer Sterne.\(size)",
                    "Hier leuchtet eine riesige Gaswolke rötlich, weil heiße junge Sterne sie wie eine Neonröhre zum Glühen bringen. In solchen Wolken entstehen neue Sterne.")
        case .reflectionNebula:
            return ("Ein Reflexionsnebel: Staubwolke, die das Licht benachbarter Sterne streut. Da blaues Licht stärker gestreut wird, erscheinen solche Nebel meist bläulich.\(size)",
                    "Dieser bläuliche Schimmer ist Staub, der das Licht naher Sterne zurückwirft – ähnlich wie Nebel im Scheinwerferlicht.")
        case .planetaryNebula:
            return ("Ein planetarischer Nebel: die abgestoßene Gashülle eines sterbenden sonnenähnlichen Sterns, die vom heißen Kern (einem werdenden Weißen Zwerg) zum Leuchten angeregt wird. Lebensdauer: nur einige zehntausend Jahre.\(size)",
                    "So wird unsere Sonne in etwa 5 Milliarden Jahren enden: Ein sterbender Stern bläst seine Hülle als leuchtende Gasblase ab.")
        case .supernovaRemnant:
            return ("Die expandierende Trümmerwolke einer Sternexplosion (Supernova). Stoßwellen heizen das umgebende Gas auf und bringen es zum Leuchten.\(size)",
                    "Hier ist einst ein Stern explodiert. Was du siehst, sind die Trümmer, die noch immer mit hoher Geschwindigkeit ins All hinausrasen.")
        case .darkNebula:
            let op = o.opacity.map { " Lynds-Opazitätsklasse \(Int($0)) (1 = durchscheinend, 6 = sehr dicht)." } ?? ""
            return ("Ein Dunkelnebel: eine kalte, dichte Wolke aus Gas und Staub, die das Licht dahinterliegender Sterne und Nebel verschluckt. In ihrem Inneren können neue Sterne entstehen.\(op)\(size)",
                    "Das dunkle Gebiet ist kein „Loch“ im All, sondern eine Staubwolke, die wie Rauch das Licht der Sterne dahinter verdeckt.")
        case .association:
            return ("Eine Sternassoziation: eine lose Gruppe junger Sterne gemeinsamen Ursprungs, die nicht gravitativ gebunden ist.\(size)", "Eine lockere Gruppe junger Sterne, die gemeinsam entstanden sind und langsam auseinanderdriften.")
        default:
            return ("\(o.type.germanName).\(size)", "")
        }
    }
}

// MARK: - Formatierung

public func formatArcmin(_ a: Double) -> String {
    if a >= 60 { return String(format: "%.1f°", a / 60).replacingOccurrences(of: ".", with: ",") }
    if a >= 1 { return String(format: "%.1f′", a).replacingOccurrences(of: ".", with: ",") }
    return String(format: "%.0f″", a * 60)
}

public func formatRA(_ ra: Double) -> String {
    let h = ra / 15
    let hh = Int(h), mm = Int((h - Double(hh)) * 60), ss = ((h - Double(hh)) * 60 - Double(mm)) * 60
    return String(format: "%02dh %02dm %04.1fs", hh, mm, ss).replacingOccurrences(of: ".", with: ",")
}

public func formatDec(_ dec: Double) -> String {
    let s = dec < 0 ? "−" : "+"
    let a = abs(dec)
    let d = Int(a), m = Int((a - Double(d)) * 60), sec = ((a - Double(d)) * 60 - Double(m)) * 60
    return String(format: "%@%02d° %02d′ %02.0f″", s, d, m, sec)
}

public func formatDegrees(_ v: Double, digits: Int = 2) -> String {
    String(format: "%.\(digits)f°", v).replacingOccurrences(of: ".", with: ",")
}

public enum CommonNames {
    public static let german: [String: String] = [
        "Great Orion Nebula": "Orionnebel", "Orion Nebula": "Orionnebel", "Pleiades": "Plejaden",
        "Andromeda Galaxy": "Andromedagalaxie", "Triangulum Galaxy": "Dreiecksgalaxie", "Crab Nebula": "Krebsnebel",
        "Ring Nebula": "Ringnebel", "Dumbbell Nebula": "Hantelnebel", "Lagoon Nebula": "Lagunennebel",
        "Trifid Nebula": "Trifidnebel", "Eagle Nebula": "Adlernebel", "Omega Nebula": "Omeganebel",
        "Whirlpool Galaxy": "Whirlpool-Galaxie", "Sombrero Galaxy": "Sombrerogalaxie", "Pinwheel Galaxy": "Feuerradgalaxie",
        "Bode's Galaxy": "Bodes Galaxie", "Cigar Galaxy": "Zigarrengalaxie", "Owl Nebula": "Eulennebel",
        "Beehive Cluster": "Praesepe (Krippe)", "Praesepe": "Praesepe (Krippe)", "Horsehead Nebula": "Pferdekopfnebel",
        "Flame Nebula": "Flammennebel", "North America Nebula": "Nordamerikanebel", "Pelican Nebula": "Pelikannebel",
        "Veil Nebula": "Cirrusnebel (Schleiernebel)", "Helix Nebula": "Helixnebel", "Rosette Nebula": "Rosettennebel",
        "Heart Nebula": "Herznebel", "Soul Nebula": "Seelennebel", "California Nebula": "Kaliforniennebel",
        "Witch Head Nebula": "Hexenkopfnebel", "Bubble Nebula": "Blasennebel", "Crescent Nebula": "Sichelnebel",
        "Cone Nebula": "Konusnebel", "Christmas Tree Cluster": "Weihnachtsbaumhaufen", "Iris Nebula": "Irisnebel",
        "Pacman Nebula": "Pacman-Nebel", "Cave Nebula": "Höhlennebel", "Elephant's Trunk Nebula": "Elefantenrüsselnebel",
        "Double Cluster": "Doppelsternhaufen h & χ Persei", "Wild Duck Cluster": "Wildentenhaufen",
        "Black Eye Galaxy": "Galaxie mit dem schwarzen Auge", "Sunflower Galaxy": "Sonnenblumengalaxie",
        "Needle Galaxy": "Nadelgalaxie", "Sculptor Galaxy": "Sculptor-Galaxie", "Silver Coin Galaxy": "Silbermünzgalaxie",
        "Eskimo Nebula": "Eskimonebel", "Cat's Eye Nebula": "Katzenaugennebel", "Running Man Nebula": "Running-Man-Nebel",
        "De Mairan's Nebula": "De-Mairans-Nebel", "Merope Nebula": "Merope-Nebel", "Hercules Globular Cluster": "Herkules-Kugelsternhaufen",
        "Butterfly Cluster": "Schmetterlingshaufen", "Ptolemy Cluster": "Ptolemäus-Haufen", "Little Dumbbell": "Kleiner Hantelnebel",
        "Fireworks Galaxy": "Feuerwerksgalaxie", "Leo Triplet": "Leo-Triplett", "Hyades": "Hyaden",
        "Seagull Nebula": "Möwennebel", "Thor's Helmet": "Thors Helm", "Flaming Star Nebula": "Flammender-Stern-Nebel",
        "Monkey Head Nebula": "Affenkopfnebel", "Jellyfish Nebula": "Quallennebel", "Wizard Nebula": "Zauberernebel",
        "Fish Head Nebula": "Fischkopfnebel", "Cocoon Nebula": "Kokonnebel", "Tadpoles Nebula": "Kaulquappennebel",
        "Little Ghost Nebula": "Kleiner Geisternebel", "Blue Snowball": "Blauer Schneeball",
    ]
}

public enum Constellations {
    public static let german: [String: String] = [
        "And": "Andromeda", "Ant": "Luftpumpe", "Aps": "Paradiesvogel", "Aqr": "Wassermann", "Aql": "Adler", "Ara": "Altar",
        "Ari": "Widder", "Aur": "Fuhrmann", "Boo": "Bärenhüter", "Cae": "Grabstichel", "Cam": "Giraffe", "Cnc": "Krebs",
        "CVn": "Jagdhunde", "CMa": "Großer Hund", "CMi": "Kleiner Hund", "Cap": "Steinbock", "Car": "Kiel des Schiffs",
        "Cas": "Kassiopeia", "Cen": "Zentaur", "Cep": "Kepheus", "Cet": "Walfisch", "Cha": "Chamäleon", "Cir": "Zirkel",
        "Col": "Taube", "Com": "Haar der Berenike", "CrA": "Südliche Krone", "CrB": "Nördliche Krone", "Crv": "Rabe",
        "Crt": "Becher", "Cru": "Kreuz des Südens", "Cyg": "Schwan", "Del": "Delfin", "Dor": "Schwertfisch", "Dra": "Drache",
        "Equ": "Füllen", "Eri": "Eridanus", "For": "Chemischer Ofen", "Gem": "Zwillinge", "Gru": "Kranich", "Her": "Herkules",
        "Hor": "Pendeluhr", "Hya": "Wasserschlange", "Hyi": "Kleine Wasserschlange", "Ind": "Inder", "Lac": "Eidechse",
        "Leo": "Löwe", "LMi": "Kleiner Löwe", "Lep": "Hase", "Lib": "Waage", "Lup": "Wolf", "Lyn": "Luchs", "Lyr": "Leier",
        "Men": "Tafelberg", "Mic": "Mikroskop", "Mon": "Einhorn", "Mus": "Fliege", "Nor": "Winkelmaß", "Oct": "Oktant",
        "Oph": "Schlangenträger", "Ori": "Orion", "Pav": "Pfau", "Peg": "Pegasus", "Per": "Perseus", "Phe": "Phönix",
        "Pic": "Maler", "Psc": "Fische", "PsA": "Südlicher Fisch", "Pup": "Achterdeck des Schiffs", "Pyx": "Schiffskompass",
        "Ret": "Netz", "Sge": "Pfeil", "Sgr": "Schütze", "Sco": "Skorpion", "Scl": "Bildhauer", "Sct": "Schild",
        "Se1": "Schlange (Kopf)", "Se2": "Schlange (Schwanz)", "Ser": "Schlange", "Sex": "Sextant", "Tau": "Stier",
        "Tel": "Teleskop", "Tri": "Dreieck", "TrA": "Südliches Dreieck", "Tuc": "Tukan", "UMa": "Großer Bär",
        "UMi": "Kleiner Bär", "Vel": "Segel des Schiffs", "Vir": "Jungfrau", "Vol": "Fliegender Fisch", "Vul": "Fuchs",
    ]
}
