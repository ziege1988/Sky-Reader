import SwiftUI
import SkyReaderCore

struct MainView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var updater: Updater

    var body: some View {
        ZStack {
            NebulaBackground()
            VStack(spacing: 0) {
                HeaderBar()
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        ImageArea()
                            .frame(width: geo.size.width * 2 / 3)
                        Rectangle().fill(Theme.divider).frame(width: 1)
                        ResultsPanel()
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $state.showAnalysisSheet) {
            AnalysisSheet().environmentObject(state)
        }
        .sheet(isPresented: $state.showExport) {
            ExportView().environmentObject(state)
        }
        .sheet(isPresented: $state.showSettings) {
            SettingsView(showsDone: true)
                .environmentObject(state)
                .environmentObject(updater)
                .frame(width: 600, height: 660)
        }
        .sheet(item: $updater.offer) { rel in
            UpdateSheet(release: rel).environmentObject(updater)
        }
    }
}

// MARK: - Kopfzeile

struct HeaderBar: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(spacing: 12) {
            Spacer().frame(width: 72) // Platz für die Fensterknöpfe
            if let l = state.loaded {
                Image(systemName: "photo")
                    .foregroundStyle(Theme.textSecondary)
                Text(l.url.lastPathComponent)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let r = state.result {
                    Text(r.kind.germanName)
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Capsule().fill(Theme.panelRaised))
                        .foregroundStyle(Theme.accent)
                }
            }
            Spacer()
            HStack(spacing: 10) {
                PleiadesMark().frame(width: 22, height: 22)
                Text("Sky Reader")
                    .font(Theme.titleFont)
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(.trailing, 20)
        }
        .frame(height: 52)
        .background(Color.black)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.divider).frame(height: 1) }
    }
}

/// Kleines Logo: das „Siebengestirn“ der Plejaden
struct PleiadesMark: View {
    var body: some View {
        Canvas { ctx, size in
            let pts: [(CGFloat, CGFloat, CGFloat)] = [(0.30, 0.30, 1.0), (0.55, 0.22, 0.8), (0.72, 0.38, 0.9), (0.48, 0.48, 1.0),
                                                      (0.25, 0.62, 0.7), (0.62, 0.70, 0.75), (0.82, 0.62, 0.6)]
            for (x, y, s) in pts {
                let r = size.width * 0.075 * s
                let c = CGPoint(x: x * size.width, y: y * size.height)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 2.2, y: c.y - r * 2.2, width: r * 4.4, height: r * 4.4)), with: .color(Theme.accent.opacity(0.18)))
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(Theme.glow))
            }
        }
    }
}

// MARK: - Bildbereich (Drag & Drop)

struct ImageArea: View {
    @EnvironmentObject var state: AppState
    @State private var targeted = false
    @State private var zoom: CGFloat = 1
    @State private var baseZoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            let area = CGRect(origin: .zero, size: geo.size).insetBy(dx: 20, dy: 20)
            ZStack {
                if let img = state.displayImage {
                    let fit = fittedRect(imageSize: img.size, in: area)
                    let rect = zoomed(fit, in: area)
                    Image(nsImage: img)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                    if let r = state.result {
                        OverlayCanvas(result: r, imageRect: rect, bounds: CGRect(origin: .zero, size: geo.size))
                    }
                    if state.result == nil && !state.isBusy {
                        HintBadge(text: dropHint)
                    }
                } else {
                    DropPlaceholder(targeted: targeted)
                        .padding(28)
                }
                if targeted && state.displayImage != nil {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                        .padding(12)
                        .overlay(Text("Neues Bild loslassen").font(.title3).foregroundStyle(Theme.accent))
                        .background(Color.black.opacity(0.4))
                }
                if let e = state.dropError {
                    VStack { Spacer(); ErrorBanner(text: e).padding(24) }
                }
            }
            .contentShape(Rectangle())
            .clipped()
            .gesture(
                MagnifyGesture()
                    .onChanged { v in zoom = min(8, max(1, baseZoom * v.magnification)) }
                    .onEnded { _ in baseZoom = zoom; if zoom <= 1.01 { resetZoom() } }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { v in
                        guard zoom > 1 else { return }
                        offset = CGSize(width: baseOffset.width + v.translation.width, height: baseOffset.height + v.translation.height)
                    }
                    .onEnded { _ in baseOffset = offset }
            )
            .onTapGesture(count: 2) { withAnimation(.easeOut(duration: 0.2)) { resetZoom() } }
            .onTapGesture(coordinateSpace: .local) { p in select(at: p, area: area) }
            .dropDestination(for: URL.self) { urls, _ in
                guard let u = urls.first else { return false }
                resetZoom()
                state.load(url: u)
                return true
            } isTargeted: { targeted = $0 }
        }
        .background(Color.black.opacity(0.35))
    }

    var dropHint: String { "Analyse abgebrochen – Bild erneut ablegen oder „Neu analysieren“ wählen." }

    func resetZoom() { zoom = 1; baseZoom = 1; offset = .zero; baseOffset = .zero }

    func fittedRect(imageSize s: CGSize, in r: CGRect) -> CGRect {
        guard s.width > 0, s.height > 0 else { return r }
        let k = min(r.width / s.width, r.height / s.height)
        let w = s.width * k, h = s.height * k
        return CGRect(x: r.midX - w / 2, y: r.midY - h / 2, width: w, height: h)
    }

    func zoomed(_ fit: CGRect, in area: CGRect) -> CGRect {
        let w = fit.width * zoom, h = fit.height * zoom
        return CGRect(x: area.midX - w / 2 + offset.width, y: area.midY - h / 2 + offset.height, width: w, height: h)
    }

    func select(at p: CGPoint, area: CGRect) {
        guard let r = state.result, let img = state.displayImage else { return }
        let rect = zoomed(fittedRect(imageSize: img.size, in: area), in: area)
        let k = rect.width / CGFloat(r.imageWidth)
        var best: (String, CGFloat)?
        for o in r.objects {
            let c = CGPoint(x: rect.minX + CGFloat(o.x) * k, y: rect.minY + CGFloat(o.y) * k)
            let rr = max(CGFloat(o.radius) * k, 14)
            let d = hypot(p.x - c.x, p.y - c.y)
            if d <= rr * 1.1, best == nil || d / rr < best!.1 { best = (o.id, d / rr) }
        }
        if let b = best { state.selectedObjectID = b.0 }
    }
}

struct OverlayCanvas: View {
    @EnvironmentObject var state: AppState
    let result: AnalysisResult
    let imageRect: CGRect
    let bounds: CGRect

    var body: some View {
        Canvas { ctx, _ in
            let k = imageRect.width / CGFloat(result.imageWidth)
            let fs = CGFloat(12 * state.labelScale)
            let items = OverlayLayout.layout(objects: result.objects,
                                             transform: { CGPoint(x: imageRect.minX + $0.x * k, y: imageRect.minY + $0.y * k) },
                                             scale: k, fontSize: fs, bounds: bounds.insetBy(dx: 4, dy: 4),
                                             selected: state.selectedObjectID)
            ctx.withCGContext { cg in
                OverlayLayout.draw(items, in: cg, lineWidth: 1.5, fontSize: fs, showLabels: state.showLabels, selected: state.selectedObjectID)
            }
        }
        .allowsHitTesting(false)
    }
}

struct DropPlaceholder: View {
    @EnvironmentObject var state: AppState
    let targeted: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18)
                .fill(targeted ? Theme.accent.opacity(0.08) : Theme.panel.opacity(0.55))
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(targeted ? Theme.accent : Theme.divider, style: StrokeStyle(lineWidth: targeted ? 2 : 1.5, dash: [10, 8]))
            VStack(spacing: 16) {
                PleiadesMark().frame(width: 74, height: 74).opacity(targeted ? 1 : 0.8)
                Text(targeted ? "Loslassen zum Analysieren" : "Astroaufnahme hierher ziehen")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(Theme.textPrimary)
                Text("JPEG oder TIFF · Nebel, Galaxien, Sternhaufen, Dunkelnebel, Kometen und Mond")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                Button("Datei auswählen …") { state.openPanel() }
                    .buttonStyle(SkyButtonStyle(prominent: true))
                    .padding(.top, 6)
            }
            .padding(30)
        }
    }
}

struct HintBadge: View {
    let text: String
    var body: some View {
        VStack {
            Spacer()
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(Color.black.opacity(0.7)))
                .padding(18)
        }
    }
}

struct ErrorBanner: View {
    let text: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning)
            Text(text).font(.system(size: 12)).foregroundStyle(Theme.textPrimary)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.panelRaised))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.warning.opacity(0.5)))
    }
}
