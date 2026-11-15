import SwiftUI
import AppKit
import SkyReaderCore

/// Export-Popup: Vorschau links (Rechtsklick auf eine Markierung blendet sie aus/ein), Einstellungen rechts.
struct ExportView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var options = ExportOptions()
    @State private var hidden: Set<String> = []
    @State private var format: ExportFormat = .jpeg
    @State private var quality: Double = 0.92
    @State private var preview: NSImage?
    @State private var previewScale: CGFloat = 1
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        HStack(spacing: 0) {
            // Vorschau
            GeometryReader { geo in
                ZStack {
                    Color.black
                    if let p = preview {
                        let fit = fitted(p.size, in: CGRect(origin: .zero, size: geo.size).insetBy(dx: 16, dy: 16))
                        Image(nsImage: p).resizable().interpolation(.high)
                            .frame(width: fit.width, height: fit.height)
                            .position(x: fit.midX, y: fit.midY)
                        RightClickCatcher { pt in toggle(at: pt, displayRect: fit) }
                    } else {
                        ProgressView()
                    }
                    VStack {
                        Spacer()
                        Text("Rechtsklick auf eine Markierung blendet sie aus – erneuter Rechtsklick blendet sie wieder ein.")
                            .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Capsule().fill(Color.black.opacity(0.75)))
                            .padding(10)
                    }
                }
            }
            Rectangle().fill(Theme.divider).frame(width: 1)
            // Einstellungen
            VStack(alignment: .leading, spacing: 16) {
                Text("Exportieren").font(.system(size: 20, weight: .light).width(.expanded)).foregroundStyle(Theme.textPrimary)
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Markierungen / Bezeichnungen anzeigen", isOn: $options.showMarkers)
                        Toggle("Beschreibung", isOn: $options.showDescription)
                        Toggle("Ausführliche Beschreibung", isOn: $options.detailed)
                            .disabled(!options.showDescription)
                            .padding(.leading, 18)
                        HStack {
                            Text("Beschriftungsgröße").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                            Slider(value: $options.labelScale, in: 0.6...1.8)
                        }
                    }
                    .padding(6)
                } label: { Text("Inhalt").foregroundStyle(Theme.textSecondary) }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Format", selection: $format) {
                            ForEach(ExportFormat.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        if format == .jpeg {
                            HStack {
                                Text("Qualität").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                                Slider(value: $quality, in: 0.6...1.0)
                                Text("\(Int(quality * 100)) %").font(.system(size: 11, design: .monospaced)).frame(width: 40)
                            }
                        } else {
                            Text("TIFF, verlustfrei (LZW)").font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                        }
                        if let l = state.loaded {
                            let L = ExportRenderer.layout(image: l.cgImage, options: options, scale: 1)
                            Text("Ausgabe: \(Int(L.size.width)) × \(Int(L.size.height)) Pixel").font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .padding(6)
                } label: { Text("Datei").foregroundStyle(Theme.textSecondary) }

                if let r = state.result {
                    GroupBox {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(r.objects) { o in
                                    Toggle(isOn: Binding(get: { !hidden.contains(o.id) }, set: { on in
                                        if on { hidden.remove(o.id) } else { hidden.insert(o.id) }
                                    })) {
                                        Text(o.info.title).font(.system(size: 11.5)).lineLimit(1)
                                    }
                                    .toggleStyle(.checkbox)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 180)
                        HStack {
                            Button("Alle") { hidden.removeAll() }.controlSize(.small)
                            Button("Keine") { hidden = Set(r.objects.map { $0.id }) }.controlSize(.small)
                        }
                    } label: { Text("Objekte (\(r.objects.count - hidden.count)/\(r.objects.count))").foregroundStyle(Theme.textSecondary) }
                }
                Spacer()
                if let m = message { Text(m).font(.system(size: 11)).foregroundStyle(Theme.success) }
                HStack {
                    Button("Abbrechen") { dismiss() }.buttonStyle(SkyButtonStyle()).keyboardShortcut(.cancelAction)
                    Spacer()
                    Button { save() } label: {
                        if busy { ProgressView().controlSize(.small) } else { Text("Exportieren …") }
                    }
                    .buttonStyle(SkyButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
                    .disabled(busy || state.result == nil)
                }
            }
            .padding(20)
            .frame(width: 330)
            .background(Theme.panel)
        }
        .frame(minWidth: 1100, idealWidth: 1280, minHeight: 680, idealHeight: 780)
        .background(Theme.background)
        .onAppear { options.labelScale = state.labelScale; renderPreview() }
        .onChange(of: options) { _, _ in renderPreview() }
        .onChange(of: hidden) { _, _ in renderPreview() }
    }

    func fitted(_ s: CGSize, in r: CGRect) -> CGRect {
        let k = min(r.width / max(s.width, 1), r.height / max(s.height, 1))
        return CGRect(x: r.midX - s.width * k / 2, y: r.midY - s.height * k / 2, width: s.width * k, height: s.height * k)
    }

    func renderPreview() {
        guard let l = state.loaded, let r = state.result else { return }
        let target: CGFloat = 1700
        let sc = min(1, target / CGFloat(max(l.cgImage.width, l.cgImage.height)))
        previewScale = sc
        if let img = ExportRenderer.render(image: l.cgImage, result: r, hidden: hidden, options: options, scale: sc, ghostHidden: true) {
            preview = NSImage(cgImage: img, size: NSSize(width: img.width, height: img.height))
        }
    }

    /// Rechtsklick in der Vorschau → nächstgelegene Markierung aus-/einblenden
    func toggle(at p: CGPoint, displayRect: CGRect) {
        guard let pv = preview, let r = state.result, options.showMarkers else { return }
        let k = displayRect.width / pv.size.width            // Vorschau-Pixel → Anzeige
        let comp = CGPoint(x: (p.x - displayRect.minX) / k, y: (p.y - displayRect.minY) / k)
        let imgK = previewScale * CGFloat(state.loaded?.cgImage.width ?? r.imageWidth) / CGFloat(r.imageWidth)
        var best: (String, CGFloat)?
        for o in r.objects {
            let c = CGPoint(x: CGFloat(o.x) * imgK, y: CGFloat(o.y) * imgK)
            let rr = max(CGFloat(o.radius) * imgK, 12 / k)
            let d = hypot(comp.x - c.x, comp.y - c.y)
            if d <= rr * 1.15, best == nil || d / rr < best!.1 { best = (o.id, d / rr) }
        }
        guard let b = best else { return }
        if hidden.contains(b.0) { hidden.remove(b.0) } else { hidden.insert(b.0) }
    }

    func save() {
        guard let l = state.loaded, let r = state.result else { return }
        let p = NSSavePanel()
        p.allowedContentTypes = [format.utType]
        p.nameFieldStringValue = l.url.deletingPathExtension().lastPathComponent + "-SkyReader." + format.ext
        p.message = "Analysiertes Bild exportieren"
        guard p.runModal() == .OK, let url = p.url else { return }
        busy = true
        let opts = options, hid = hidden, fmt = format, q = quality, cg = l.cgImage
        Task.detached(priority: .userInitiated) {
            let img = ExportRenderer.render(image: cg, result: r, hidden: hid, options: opts, scale: 1)
            var err: Error?
            if let img { do { try ExportRenderer.write(img, to: url, format: fmt, quality: q) } catch { err = error } }
            await MainActor.run {
                busy = false
                if let err { NSAlert(error: err).runModal() }
                else { message = "Gespeichert: \(url.lastPathComponent)"; NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }
        }
    }
}

/// Fängt Rechtsklicks ab (SwiftUI bietet unter macOS keine Position für Kontextklicks)
struct RightClickCatcher: NSViewRepresentable {
    var onRightClick: (CGPoint) -> Void

    final class CatcherView: NSView {
        var handler: ((CGPoint) -> Void)?
        override var isFlipped: Bool { true }
        override func rightMouseDown(with event: NSEvent) {
            handler?(convert(event.locationInWindow, from: nil))
        }
        override func hitTest(_ point: NSPoint) -> NSView? {
            // Nur Rechtsklicks abfangen, alles andere durchreichen
            if let e = NSApp.currentEvent, e.type == .rightMouseDown { return super.hitTest(point) }
            return nil
        }
    }

    func makeNSView(context: Context) -> CatcherView { let v = CatcherView(); v.handler = onRightClick; return v }
    func updateNSView(_ v: CatcherView, context: Context) { v.handler = onRightClick }
}
