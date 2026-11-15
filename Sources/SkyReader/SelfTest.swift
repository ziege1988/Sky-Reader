import AppKit
import SkyReaderCore

/// Automatischer Oberflächentest (CI): Bild laden → analysieren → „Fertig“ → Fenster-Snapshot, Export und Report speichern.
@MainActor
enum SelfTest {
    static func run(image: URL, out: URL, state: AppState, window: NSWindow) {
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        print("SELFTEST: lade \(image.path)")
        state.load(url: image)
        poll(state: state, out: out, window: window, deadline: Date().addingTimeInterval(180))
    }

    private static func poll(state: AppState, out: URL, window: NSWindow, deadline: Date) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            MainActor.assumeIsolated {
                switch state.phase {
                case .finished, .failed, .cancelled:
                    if let sheet = window.attachedSheet?.contentView { snapshot(sheet, to: out.appendingPathComponent("analyse-popup.png")) }
                    try? state.reportText().write(to: out.appendingPathComponent("report.txt"), atomically: true, encoding: .utf8)
                    state.finish()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        MainActor.assumeIsolated {
                            if let v = window.contentView { snapshot(v, to: out.appendingPathComponent("hauptfenster.png")) }
                            exportSamples(state: state, out: out)
                            print("SELFTEST: fertig – \(state.phaseText), \(state.result?.objects.count ?? 0) Objekte")
                            NSApp.terminate(nil)
                        }
                    }
                default:
                    if Date() > deadline { print("SELFTEST: Zeitüberschreitung"); NSApp.terminate(nil); return }
                    poll(state: state, out: out, window: window, deadline: deadline)
                }
            }
        }
    }

    static func exportSamples(state: AppState, out: URL) {
        guard let l = state.loaded, let r = state.result else { return }
        let variants: [(String, ExportOptions)] = [
            ("export-beschreibung.jpg", ExportOptions(showMarkers: true, showDescription: true, detailed: false)),
            ("export-ausfuehrlich.jpg", ExportOptions(showMarkers: true, showDescription: true, detailed: true)),
            ("export-nur-bild.jpg", ExportOptions(showMarkers: true, showDescription: false, detailed: false)),
        ]
        for (name, o) in variants {
            if let img = ExportRenderer.render(image: l.cgImage, result: r, hidden: [], options: o, scale: 1) {
                try? ExportRenderer.write(img, to: out.appendingPathComponent(name), format: .jpeg, quality: 0.9)
            }
        }
        // Ein Objekt ausgeblendet (Rechtsklick-Simulation)
        if let first = r.objects.first,
           let img = ExportRenderer.render(image: l.cgImage, result: r, hidden: [first.id], options: ExportOptions(), scale: 1) {
            try? ExportRenderer.write(img, to: out.appendingPathComponent("export-ohne-\(first.label.replacingOccurrences(of: " ", with: "")).jpg"), format: .jpeg, quality: 0.9)
        }
    }

    static func snapshot(_ view: NSView, to url: URL) {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
