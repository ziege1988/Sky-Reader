import AppKit
import SkyReaderCore

/// Automatischer Oberflächentest (CI): fotografiert alle Ansichten der App.
@MainActor
enum SelfTest {
    static func run(image: URL, moon: URL?, out: URL, state: AppState, journal: JournalStore, window: NSWindow) {
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        Task { @MainActor in
            // Einheitliche, gut lesbare Fenstergröße für die Screenshots
            window.setFrame(NSRect(x: 40, y: 40, width: 1500, height: 940), display: true)
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            snap(window, "01-start-leer", out)

            await analyze(image, state: state, window: window, out: out, prefix: "02")
            state.finish()
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            snap(window, "03-ergebnis", out)
            if let r = state.result, r.objects.count > 1 {
                state.selectedObjectID = r.objects[1].id
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                snap(window, "04-objektdetails", out)
            }
            try? state.reportText().write(to: out.appendingPathComponent("report.txt"), atomically: true, encoding: .utf8)
            if var e = journal.makeEntry(from: state) {
                e.notes = "Plejaden mit Staubwolken der Taurus-Region. Klare, mondlose Nacht."; e.location = "Garten"; e.equipment = "135 mm, APS-C"
                journal.save(e)
            }

            for (tab, name) in [(0, "analyse"), (1, "darstellung"), (2, "updates"), (3, "ueber")] {
                SettingsView.initialTab = tab
                state.showSettings = true
                try? await Task.sleep(nanoseconds: 1_300_000_000)
                snapSheet(window, "05-einstellungen-\(name)", out)
                state.showSettings = false
                try? await Task.sleep(nanoseconds: 900_000_000)
            }
            SettingsView.initialTab = 0

            await exportDialog(state: state, window: window, out: out, name: "06-export-dialog", hide: [])
            if let r = state.result, r.objects.count > 3 {
                await exportDialog(state: state, window: window, out: out, name: "06b-export-live-entfernt", hide: [r.objects[0].id, r.objects[3].id])
            }
            exportSamples(state: state, out: out, prefix: "07-export")

            if let moon {
                await analyze(moon, state: state, window: window, out: out, prefix: "08-mond")
                state.finish()
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                snap(window, "09-mond-ergebnis", out)
                if let r = state.result, r.objects.count > 2 {
                    state.selectedObjectID = r.objects[2].id
                    try? await Task.sleep(nanoseconds: 900_000_000)
                    snap(window, "09b-mond-krater-details", out)
                    await exportDialog(state: state, window: window, out: out, name: "09c-mond-export-live", hide: [r.objects[1].id])
                }
                try? state.reportText().write(to: out.appendingPathComponent("report-mond.txt"), atomically: true, encoding: .utf8)
                if var e = journal.makeEntry(from: state) {
                    e.notes = "Zunehmende Sichel, Nordostrand mit Mare Crisium. Ruhige Luft."; e.equipment = "Refraktor, Planetenkamera"
                    journal.save(e)
                    // Tagebuch: Kacheln und Eingabemaske
                    state.mainTab = .journal
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    snap(window, "11-tagebuch-kacheln", out)
                    state.journalDraft = e
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    snapSheet(window, "12-tagebuch-eintrag", out)
                    state.journalDraft = nil
                    state.mainTab = .analysis
                    try? await Task.sleep(nanoseconds: 800_000_000)
                }
                exportSamples(state: state, out: out, prefix: "10-mond-export")
            }
            print("SELFTEST: fertig – \(state.phaseText), \(state.result?.objects.count ?? 0) Objekte")
            NSApp.terminate(nil)
        }
    }

    static func exportDialog(state: AppState, window: NSWindow, out: URL, name: String, hide: Set<String>) async {
        ExportView.initialHidden = hide
        state.showExport = true
        try? await Task.sleep(nanoseconds: 3_500_000_000)
        snapSheet(window, name, out)
        state.showExport = false
        ExportView.initialHidden = []
        try? await Task.sleep(nanoseconds: 1_000_000_000)
    }

    /// Bild laden, auf Ende warten, Analyse-Popup fotografieren
    static func analyze(_ url: URL, state: AppState, window: NSWindow, out: URL, prefix: String) async {
        print("SELFTEST: lade \(url.lastPathComponent)")
        state.load(url: url)
        let deadline = Date().addingTimeInterval(180)
        while state.isBusy && Date() < deadline {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if state.moonQuestion != nil {
                // Datums-Popup fotografieren und mit dem bekannten Aufnahmedatum der Testaufnahme beantworten
                try? await Task.sleep(nanoseconds: 900_000_000)
                snapSheet(window, "\(prefix)-datum-popup", out)
                state.answerMoonQuestion(.known(ISO8601DateFormatter().date(from: "2024-05-13T20:30:00Z")!))
            }
        }
        try? await Task.sleep(nanoseconds: 800_000_000)
        snapSheet(window, "\(prefix)-analyse-popup", out)
    }

    static func exportSamples(state: AppState, out: URL, prefix: String) {
        guard let l = state.loaded, let r = state.result else { return }
        let variants: [(String, ExportOptions)] = [
            ("beschreibung", ExportOptions(showMarkers: true, showDescription: true, detailed: false)),
            ("ausfuehrlich", ExportOptions(showMarkers: true, showDescription: true, detailed: true)),
            ("nur-bild", ExportOptions(showMarkers: true, showDescription: false, detailed: false)),
        ]
        for (name, o) in variants {
            if let img = ExportRenderer.render(image: l.cgImage, result: r, hidden: [], options: o, scale: 1) {
                try? ExportRenderer.write(img, to: out.appendingPathComponent("\(prefix)-\(name).jpg"), format: .jpeg, quality: 0.9)
            }
        }
    }

    static func snap(_ window: NSWindow, _ name: String, _ out: URL) {
        if let v = window.contentView { snapshot(v, to: out.appendingPathComponent(name + ".png")) }
    }

    /// Sheet zusammen mit dem abgedunkelten Hauptfenster (so wie es auf dem Bildschirm erscheint)
    static func snapSheet(_ window: NSWindow, _ name: String, _ out: URL) {
        guard let main = window.contentView, let sheetWin = window.attachedSheet, let sheet = sheetWin.contentView,
              let mainRep = rep(main), let sheetRep = rep(sheet) else { snap(window, name, out); return }
        let W = mainRep.pixelsWide, H = mainRep.pixelsHigh
        let scale = CGFloat(W) / main.bounds.width
        guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let mi = mainRep.cgImage, let si = sheetRep.cgImage else { return }
        ctx.draw(mi, in: CGRect(x: 0, y: 0, width: W, height: H))
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.45).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        let sw = CGFloat(si.width), sh = CGFloat(si.height)
        let fit = min(1, CGFloat(W) * 0.96 / sw, CGFloat(H) * 0.96 / sh)
        let w = sw * fit, h = sh * fit
        let r = CGRect(x: (CGFloat(W) - w) / 2, y: CGFloat(H) - h - 28 * scale, width: w, height: h)
        ctx.setShadow(offset: CGSize(width: 0, height: -8 * scale), blur: 30 * scale, color: NSColor.black.withAlphaComponent(0.8).cgColor)
        let path = CGPath(roundedRect: r, cornerWidth: 12 * scale, cornerHeight: 12 * scale, transform: nil)
        ctx.addPath(path); ctx.setFillColor(NSColor.black.cgColor); ctx.fillPath()
        ctx.setShadow(offset: .zero, blur: 0)
        ctx.saveGState(); ctx.addPath(path); ctx.clip(); ctx.draw(si, in: r); ctx.restoreGState()
        if let img = ctx.makeImage() {
            try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?.write(to: out.appendingPathComponent(name + ".png"))
        }
    }

    static func rep(_ view: NSView) -> NSBitmapImageRep? {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }

    static func snapshot(_ view: NSView, to url: URL) {
        try? rep(view)?.representation(using: .png, properties: [:])?.write(to: url)
    }
}
