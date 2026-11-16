import SwiftUI
import AppKit
import UniformTypeIdentifiers
import SkyReaderCore

/// Thread-sicheres Abbruch-Flag für die Hintergrundanalyse
/// Übergabe der Datumsantwort vom Hauptthread an die wartende Analyse
final class AnswerBox: @unchecked Sendable {
    var answer: MoonDateAnswer = .unknown
    let semaphore = DispatchSemaphore(value: 0)
}

final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func cancel() { lock.lock(); value = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
}

@MainActor
final class AppState: ObservableObject {
    enum Phase: Equatable { case idle, loading, analyzing, finished, failed(String), cancelled }

    @Published var loaded: LoadedImage?
    @Published var displayImage: NSImage?
    @Published var phase: Phase = .idle
    @Published var log: [LogEntry] = []
    @Published var progress: Double = 0
    @Published var currentStep: String = ""
    /// Ergebnis der laufenden Analyse (noch nicht übernommen)
    @Published var pendingResult: AnalysisResult?
    /// Angezeigtes Ergebnis (nach „Fertig“)
    @Published var result: AnalysisResult?
    @Published var selectedObjectID: String?
    @Published var showAnalysisSheet = false
    @Published var showExport = false
    @Published var showSettings = false
    @Published var dropError: String?
    /// Offene Rückfrage nach dem Aufnahmedatum einer Mondaufnahme
    @Published var moonQuestion: MoonDateQuestion?
    @Published var mainTab: MainTab = .analysis
    enum MainTab: String { case analysis, journal }
    private var moonAnswerBox: AnswerBox?
    /// Zuletzt verwendetes Mond-Datum (für Tagebuch/Anzeige)
    @Published var lastMoonDate: Date?
    /// Entwurf eines neuen Tagebucheintrags (öffnet die Eingabemaske)
    @Published var journalDraft: JournalEntry?

    // Einstellungen
    @AppStorage("craterMode") var craterMode: AnalysisSettings.CraterMode = .largest
    @AppStorage("density") var density: DeepSkyCatalog.Density = .normal
    @AppStorage("analysisSize") var analysisSize: Int = 2000
    @AppStorage("showNebula") var showNebula = true
    @AppStorage("showGalaxy") var showGalaxy = true
    @AppStorage("showCluster") var showCluster = true
    @AppStorage("showDark") var showDark = true
    @AppStorage("showComet") var showComet = true
    @AppStorage("labelScale") var labelScale: Double = 1.0
    @AppStorage("showLabels") var showLabels = true
    @AppStorage("askMoonDate") var askMoonDate = true

    private var cancelFlag: CancelFlag?
    private var startedAt = Date()

    var analysisSettings: AnalysisSettings {
        var s = AnalysisSettings()
        s.craterMode = craterMode
        s.density = density
        s.maxAnalysisSize = analysisSize
        var c: Set<ObjectCategory> = [.moon]
        if showNebula { c.insert(.nebula) }
        if showGalaxy { c.insert(.galaxy) }
        if showCluster { c.insert(.cluster) }
        if showDark { c.insert(.darkNebula) }
        if showComet { c.insert(.comet) }
        s.categories = c
        return s
    }

    var isBusy: Bool { phase == .analyzing || phase == .loading }

    // MARK: Laden

    func openPanel() {
        let p = NSOpenPanel()
        p.allowedContentTypes = ImageLoader.allowedTypes
        p.allowsMultipleSelection = false
        p.message = "Astroaufnahme auswählen (JPEG oder TIFF)"
        if p.runModal() == .OK, let u = p.url { load(url: u) }
    }

    func load(url: URL) {
        guard !isBusy else { return }
        guard ImageLoader.isSupported(url) else {
            dropError = ImageLoaderError.unsupported.errorDescription
            return
        }
        dropError = nil
        lastMoonDate = nil
        result = nil
        pendingResult = nil
        selectedObjectID = nil
        log = []
        progress = 0
        phase = .loading
        currentStep = "Bild wird geladen"
        startedAt = Date()
        showAnalysisSheet = true
        append(.step, "Bild wird geladen: \(url.lastPathComponent)", progress: 0.01)
        let flag = CancelFlag()
        cancelFlag = flag
        let settings = analysisSettings
        Task.detached(priority: .userInitiated) { [self] in
            do {
                let li = try ImageLoader.load(url)
                await MainActor.run {
                    self.loaded = li
                    self.displayImage = NSImage(cgImage: li.cgImage, size: NSSize(width: li.cgImage.width, height: li.cgImage.height))
                    self.phase = .analyzing
                }
                if flag.isCancelled { throw CancelledError() }
                let ask: ((MoonDateQuestion) -> MoonDateAnswer)? = settings.moonDate == nil && self.askMoonDateEnabled ? { q in
                    // Analyse pausiert, bis im Analysefenster geantwortet wurde
                    let box = AnswerBox()
                    DispatchQueue.main.async { MainActor.assumeIsolated { self.presentMoonQuestion(q, box: box) } }
                    while box.semaphore.wait(timeout: .now() + 0.25) == .timedOut {
                        if flag.isCancelled { return .unknown }
                    }
                    return box.answer
                } : nil
                let res = try SkyAnalyzer().analyze(image: li.gray, metadata: li.metadata, settings: settings, log: { entry in
                    Task { @MainActor in self.receive(entry) }
                }, isCancelled: { flag.isCancelled }, askMoonDate: ask)
                await MainActor.run {
                    guard !flag.isCancelled else { return }
                    self.pendingResult = res
                    self.progress = 1
                    self.currentStep = "Analyse abgeschlossen"
                    self.phase = .finished
                }
            } catch is CancelledError {
                await MainActor.run { self.phase = .cancelled; self.append(.warning, "Analyse abgebrochen.") }
            } catch {
                await MainActor.run {
                    self.append(.error, error.localizedDescription)
                    self.phase = .failed(error.localizedDescription)
                    self.currentStep = "Analyse fehlgeschlagen"
                }
            }
        }
    }

    nonisolated var askMoonDateEnabled: Bool { UserDefaults.standard.object(forKey: "askMoonDate") as? Bool ?? true }

    func presentMoonQuestion(_ q: MoonDateQuestion, box: AnswerBox) {
        moonAnswerBox = box
        moonQuestion = q
    }

    /// Antwort aus dem Datums-Popup
    func answerMoonQuestion(_ a: MoonDateAnswer) {
        if case .known(let d) = a { lastMoonDate = d }
        moonQuestion = nil
        if let b = moonAnswerBox { b.answer = a; b.semaphore.signal() }
        moonAnswerBox = nil
    }

    /// Erneute Analyse desselben Bilds (z. B. nach geänderten Einstellungen)
    func reanalyze() { if let u = loaded?.url { load(url: u) } }

    private func receive(_ e: LogEntry) {
        log.append(e)
        if e.level == .step { currentStep = e.message }
        if let p = e.progress { progress = max(progress, p) }
    }

    private func append(_ level: LogEntry.Level, _ msg: String, progress p: Double? = nil) {
        receive(LogEntry(time: Date(), level: level, message: msg, progress: p))
    }

    // MARK: Popup-Aktionen

    /// „Fertig“: Ergebnis übernehmen, Popup schließen
    func finish() {
        if let r = pendingResult {
            result = r
            selectedObjectID = r.objects.first?.id
        }
        showAnalysisSheet = false
    }

    /// „Abbrechen“: laufende Analyse stoppen bzw. Ergebnis verwerfen
    func cancel() {
        cancelFlag?.cancel()
        if moonQuestion != nil { answerMoonQuestion(.unknown) }
        if phase == .analyzing || phase == .loading { phase = .cancelled; append(.warning, "Abbruch angefordert.") }
        pendingResult = nil
        showAnalysisSheet = false
    }

    func reset() {
        guard !isBusy else { return }
        loaded = nil; displayImage = nil; result = nil; pendingResult = nil; selectedObjectID = nil
        log = []; phase = .idle; dropError = nil
    }

    // MARK: Report

    /// Speichert einen Fehler-/Analysebericht als TXT
    func saveReport() {
        let p = NSSavePanel()
        p.allowedContentTypes = [.plainText]
        let base = loaded.map { $0.url.deletingPathExtension().lastPathComponent } ?? "SkyReader"
        p.nameFieldStringValue = "\(base)-Report.txt"
        p.message = "Analysebericht speichern"
        guard p.runModal() == .OK, let u = p.url else { return }
        do { try reportText().write(to: u, atomically: true, encoding: .utf8) }
        catch { NSAlert(error: error).runModal() }
    }

    func reportText() -> String {
        let iso = ISO8601DateFormatter()
        var s = "SKY READER – ANALYSEBERICHT\n"
        s += String(repeating: "=", count: 60) + "\n"
        s += "Erstellt:        \(iso.string(from: Date()))\n"
        s += "Programm:        Sky Reader \(AppInfo.versionLine)\n"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        s += "System:          macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)\n"
        s += "Status:          \(phaseText)\n"
        if let l = loaded {
            s += "\nBILD\n----\n"
            s += "Datei:           \(l.url.lastPathComponent)\n"
            s += "Größe:           \(l.cgImage.width) × \(l.cgImage.height) Pixel, \(l.cgImage.bitsPerComponent) Bit/Kanal\n"
            if let d = l.metadata.captureDate { s += "Aufnahme:        \(iso.string(from: d))\n" }
            if let c = l.metadata.cameraModel { s += "Kamera:          \(c)\n" }
            if let o = l.metadata.lensModel { s += "Objektiv:        \(o)\n" }
            if let f = l.metadata.focalLengthMM { s += "Brennweite:      \(f) mm\n" }
            if let f = l.metadata.focalLength35mm { s += "Brennweite KB:   \(f) mm\n" }
        }
        let st = analysisSettings
        s += "\nEINSTELLUNGEN\n-------------\n"
        s += "Krater:          \(st.craterMode.germanName)\nObjektdichte:    \(st.density.germanName)\nAnalysegröße:    \(st.maxAnalysisSize) px\n"
        s += "Objektarten:     \(st.categories.map { $0.germanName }.sorted().joined(separator: ", "))\n"
        s += "\nPROTOKOLL\n---------\n"
        let tf = DateFormatter(); tf.dateFormat = "HH:mm:ss.SSS"
        for e in log { s += "\(tf.string(from: e.time))  \(e.level.rawValue.uppercased().padding(toLength: 8, withPad: " ", startingAt: 0)) \(e.message)\n" }
        if let r = pendingResult ?? result {
            s += "\nERGEBNIS (\(r.kind.germanName))\n" + String(repeating: "-", count: 20) + "\n"
            for f in r.summary.facts { s += "\(f.label): \(f.value)\n" }
            for o in r.objects {
                s += String(format: "• %@ [%@]  x=%.0f y=%.0f r=%.0f\n", o.info.title, o.info.subtitle, o.x, o.y, o.radius)
            }
            if !r.warnings.isEmpty { s += "Warnungen: \(r.warnings.joined(separator: "; "))\n" }
        }
        s += "\nKataloge: \(catalogInfo)\n"
        return s
    }

    var catalogInfo: String {
        var parts: [String] = []
        if let c = try? StarCatalog.shared() { parts.append("\(c.count) Sterne") }
        if let d = try? DeepSkyCatalog.shared() { parts.append("\(d.objects.count) Deep-Sky-Objekte") }
        parts.append("\(CometAnalyzer.elements().count) Kometenbahnen")
        parts.append("\(Descriptions.shared.curatedCount) ausführlich beschriebene Objekte")
        if let u = ResourceLocator.catalogURL("VERSION.txt"), let v = try? String(contentsOf: u, encoding: .utf8) {
            parts.append("Stand \(v.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        return parts.joined(separator: ", ")
    }

    var phaseText: String {
        switch phase {
        case .idle: return "bereit"
        case .loading: return "lädt"
        case .analyzing: return "analysiert"
        case .finished: return "abgeschlossen"
        case .failed(let m): return "fehlgeschlagen – \(m)"
        case .cancelled: return "abgebrochen"
        }
    }

    var elapsed: TimeInterval { Date().timeIntervalSince(startedAt) }
}

