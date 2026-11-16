import SwiftUI
import AppKit
import SkyReaderCore

/// Export-Popup mit Live-Vorschau: Jede Änderung (Optionen, Rechtsklick auf Markierungen, Objektliste)
/// wird sofort im Bild und in der Beschreibung sichtbar. Entfernte Markierungen erscheinen rot gestrichelt
/// bzw. durchgestrichen, solange „Entfernte anzeigen“ aktiv ist.
struct ExportView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var options = ExportOptions()
    @State private var hidden: Set<String> = []
    @State private var history: [Set<String>] = []
    @State private var showRemoved = true
    @State private var format: ExportFormat = .jpeg
    @State private var quality: Double = 0.92
    @State private var preview: NSImage?
    @State private var previewScale: CGFloat = 1
    @State private var rendering = false
    @State private var generation = 0
    @State private var busy = false
    @State private var message: String?
    @State private var notice: String?
    @State private var zoom: CGFloat = 1
    @State private var baseZoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero
    /// Selbsttest: vorab entfernte Objekte
    @MainActor static var initialHidden: Set<String> = []

    /// Dialoggröße: fast so groß wie das Hauptfenster
    private var sheetSize: CGSize {
        let f = NSApp.mainWindow?.frame.size ?? NSApp.windows.first(where: { $0.isVisible && $0.frame.width > 900 })?.frame.size ?? CGSize(width: 1400, height: 900)
        return CGSize(width: max(1100, f.width * 0.95), height: max(700, f.height * 0.92))
    }

    var body: some View {
        HStack(spacing: 0) {
            previewPane
            Rectangle().fill(Theme.divider).frame(width: 1)
            sidebar
        }
        .frame(width: sheetSize.width, height: sheetSize.height)
        .background(Theme.background)
        .onAppear {
            options.labelScale = state.labelScale
            if !ExportView.initialHidden.isEmpty { hidden = ExportView.initialHidden; notice = "„\(state.result?.objects.first(where: { ExportView.initialHidden.contains($0.id) })?.info.title ?? "")“ entfernt – Markierung und Beschreibung sind nicht mehr im Export." }
            renderPreview()
        }
        .onChange(of: options) { _, _ in renderPreview() }
        .onChange(of: hidden) { _, _ in renderPreview() }
        .onChange(of: showRemoved) { _, _ in renderPreview() }
    }

    // MARK: Vorschau

    var previewPane: some View {
        GeometryReader { geo in
            let area = CGRect(origin: .zero, size: geo.size).insetBy(dx: 14, dy: 14)
            ZStack {
                Color.black
                if let p = preview {
                    let rect = displayRect(p.size, in: area)
                    Image(nsImage: p).resizable().interpolation(.high)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                    RightClickCatcher { pt in toggle(at: pt, displayRect: rect) }
                } else {
                    ProgressView()
                }
                VStack {
                    HStack(spacing: 8) {
                        Label("Live-Vorschau", systemImage: "eye").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.accent)
                        if rendering { ProgressView().controlSize(.mini) }
                        Spacer()
                        Button { setZoom(zoom / 1.4) } label: { Image(systemName: "minus.magnifyingglass") }.help("Verkleinern")
                        Text("\(Int(zoom * 100)) %").font(.system(size: 11, design: .monospaced)).frame(width: 46)
                        Button { setZoom(zoom * 1.4) } label: { Image(systemName: "plus.magnifyingglass") }.help("Vergrößern")
                        Button("Einpassen") { setZoom(1); offset = .zero; baseOffset = .zero }
                    }
                    .buttonStyle(.borderless)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Capsule().fill(Color.black.opacity(0.75)))
                    .padding(10)
                    Spacer()
                    if let n = notice {
                        HStack(spacing: 10) {
                            Image(systemName: "info.circle.fill").foregroundStyle(Theme.accent)
                            Text(n).font(.system(size: 12)).foregroundStyle(Theme.textPrimary)
                            if !history.isEmpty { Button("Rückgängig") { undo() }.buttonStyle(.borderless).foregroundStyle(Theme.accent) }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().fill(Theme.panelRaised))
                        .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.4)))
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    Text("Rechtsklick auf eine Markierung entfernt sie – erneuter Rechtsklick holt sie zurück. Zoomen mit Trackpad oder Lupe, verschieben durch Ziehen.")
                        .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(Color.black.opacity(0.75)))
                        .padding(10)
                }
            }
            .contentShape(Rectangle())
            .clipped()
            .gesture(MagnifyGesture()
                .onChanged { v in zoom = min(8, max(1, baseZoom * v.magnification)) }
                .onEnded { _ in baseZoom = zoom })
            .simultaneousGesture(DragGesture(minimumDistance: 3)
                .onChanged { v in
                    guard zoom > 1 else { return }
                    offset = CGSize(width: baseOffset.width + v.translation.width, height: baseOffset.height + v.translation.height)
                }
                .onEnded { _ in baseOffset = offset })
            .onTapGesture(count: 2) { withAnimation(.easeOut(duration: 0.2)) { setZoom(zoom > 1 ? 1 : 2.5) } }
        }
    }

    func setZoom(_ z: CGFloat) {
        withAnimation(.easeOut(duration: 0.15)) {
            zoom = min(8, max(1, z)); baseZoom = zoom
            if zoom == 1 { offset = .zero; baseOffset = .zero }
        }
    }

    func displayRect(_ s: CGSize, in r: CGRect) -> CGRect {
        let k = min(r.width / max(s.width, 1), r.height / max(s.height, 1)) * zoom
        let w = s.width * k, h = s.height * k
        return CGRect(x: r.midX - w / 2 + offset.width, y: r.midY - h / 2 + offset.height, width: w, height: h)
    }

    // MARK: Seitenleiste

    var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Exportieren").font(.system(size: 20, weight: .light).width(.expanded)).foregroundStyle(Theme.textPrimary)
            GroupBox {
                VStack(alignment: .leading, spacing: 9) {
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

            if let r = state.result {
                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle("Entfernte in der Vorschau rot anzeigen", isOn: $showRemoved)
                            .font(.system(size: 11.5))
                            .help("Aus: Die Vorschau zeigt exakt das spätere Exportbild.")
                        ScrollView {
                            VStack(alignment: .leading, spacing: 3) {
                                ForEach(r.objects) { o in
                                    let removed = hidden.contains(o.id)
                                    Toggle(isOn: Binding(get: { !removed }, set: { on in setHidden(o, !on) })) {
                                        HStack(spacing: 6) {
                                            Circle().fill(removed ? Color(nsColor: OverlayLayout.removedColor) : Theme.color(for: o.type)).frame(width: 7, height: 7)
                                            Text(o.info.title).font(.system(size: 11.5)).lineLimit(1)
                                                .strikethrough(removed, color: Color(nsColor: OverlayLayout.removedColor))
                                                .foregroundStyle(removed ? Theme.textSecondary : Theme.textPrimary)
                                        }
                                    }
                                    .toggleStyle(.checkbox)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(minHeight: 120, maxHeight: .infinity)
                        HStack {
                            Button("Alle") { record(); hidden.removeAll(); notice = "Alle Markierungen eingeblendet." }.controlSize(.small)
                            Button("Keine") { record(); hidden = Set(r.objects.map { $0.id }); notice = "Alle Markierungen entfernt – Bild und Beschreibung ohne Objekte." }.controlSize(.small)
                            Spacer()
                            Button("Rückgängig") { undo() }.controlSize(.small).disabled(history.isEmpty)
                        }
                    }
                    .padding(6)
                } label: { Text("Objekte im Export (\(r.objects.count - hidden.count) von \(r.objects.count))").foregroundStyle(Theme.textSecondary) }
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 9) {
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
        .padding(18)
        .frame(width: 340)
        .background(Theme.panel)
    }

    // MARK: Aktionen

    func record() { history.append(hidden); if history.count > 50 { history.removeFirst() } }

    func undo() {
        guard let last = history.popLast() else { return }
        hidden = last
        notice = "Letzte Änderung rückgängig gemacht."
    }

    func setHidden(_ o: FoundObject, _ hide: Bool) {
        guard hidden.contains(o.id) != hide else { return }
        record()
        if hide { hidden.insert(o.id) } else { hidden.remove(o.id) }
        withAnimation(.easeOut(duration: 0.2)) {
            notice = hide ? "„\(o.info.title)“ entfernt – Markierung und Beschreibung sind nicht mehr im Export."
                          : "„\(o.info.title)“ wieder im Export – Markierung und Beschreibung."
        }
    }

    /// Rendert die Vorschau im Hintergrund; nur das zuletzt angeforderte Ergebnis wird übernommen
    func renderPreview() {
        guard let l = state.loaded, let r = state.result else { return }
        let target: CGFloat = 2600
        let sc = min(1, target / CGFloat(max(l.cgImage.width, l.cgImage.height)))
        generation += 1
        let gen = generation, opts = options, hid = hidden, ghost = showRemoved, cg = l.cgImage
        rendering = true
        Task {
            let img = await Task.detached(priority: .userInitiated) {
                ExportRenderer.render(image: cg, result: r, hidden: hid, options: opts, scale: sc, ghostHidden: ghost)
            }.value
            guard gen == generation else { return }
            rendering = false
            previewScale = sc
            if let img { preview = NSImage(cgImage: img, size: NSSize(width: img.width, height: img.height)) }
        }
    }

    /// Rechtsklick in der Vorschau → nächstgelegene Markierung entfernen/zurückholen
    func toggle(at p: CGPoint, displayRect: CGRect) {
        guard let pv = preview, let r = state.result, options.showMarkers else { return }
        let k = displayRect.width / pv.size.width            // Vorschau-Pixel → Anzeige
        let comp = CGPoint(x: (p.x - displayRect.minX) / k, y: (p.y - displayRect.minY) / k)
        let imgK = previewScale * CGFloat(state.loaded?.cgImage.width ?? r.imageWidth) / CGFloat(r.imageWidth)
        var best: (FoundObject, CGFloat)?
        for o in r.objects {
            let c = CGPoint(x: CGFloat(o.x) * imgK, y: CGFloat(o.y) * imgK)
            let rr = max(CGFloat(o.radius) * imgK, 14 / k)
            let d = hypot(comp.x - c.x, comp.y - c.y)
            if d <= rr * 1.15, best == nil || d / rr < best!.1 { best = (o, d / rr) }
        }
        guard let b = best?.0 else { return }
        setHidden(b, !hidden.contains(b.id))
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
        Task {
            let err: String? = await Task.detached(priority: .userInitiated) { () -> String? in
                guard let img = ExportRenderer.render(image: cg, result: r, hidden: hid, options: opts, scale: 1) else {
                    return "Das Bild konnte nicht erzeugt werden (zu wenig Arbeitsspeicher?)."
                }
                do { try ExportRenderer.write(img, to: url, format: fmt, quality: q); return nil }
                catch { return error.localizedDescription }
            }.value
            busy = false
            if let err {
                let a = NSAlert(); a.messageText = "Export fehlgeschlagen"; a.informativeText = err; a.runModal()
            } else {
                message = "Gespeichert: \(url.lastPathComponent)"
                NSWorkspace.shared.activateFileViewerSelecting([url])
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
