import SwiftUI
import SkyReaderCore

/// Popup während der Analyse: zeigt die Prozessabläufe live. „Fertig“ übernimmt das Ergebnis.
struct AnalysisSheet: View {
    @EnvironmentObject var state: AppState

    var done: Bool { state.phase == .finished }
    var failed: Bool { if case .failed = state.phase { return true }; return false }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                ScanAnimation(active: state.isBusy, success: done, failed: failed)
                    .frame(width: 58, height: 58)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                }
                Spacer()
                if let l = state.loaded {
                    Text(l.url.lastPathComponent).font(.system(size: 11)).foregroundStyle(Theme.textSecondary).lineLimit(1).frame(maxWidth: 180, alignment: .trailing)
                }
            }
            .padding(20)

            ProgressView(value: state.progress)
                .progressViewStyle(.linear)
                .tint(failed ? Theme.error : done ? Theme.success : Theme.accent)
                .padding(.horizontal, 20)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(state.log) { e in
                            LogLine(entry: e).id(e.id)
                        }
                    }
                    .padding(14)
                }
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.55)))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.divider))
                .padding(20)
                .onChange(of: state.log.count) { _, _ in
                    if let last = state.log.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }

            if done, let r = state.pendingResult {
                Text(resultLine(r))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.success)
                    .padding(.bottom, 8)
            }

            HStack(spacing: 10) {
                Button { state.saveReport() } label: { Label("Report", systemImage: "doc.text") }
                    .buttonStyle(SkyButtonStyle())
                    .help("Protokoll als TXT-Datei speichern (für Fehlermeldungen)")
                Spacer()
                Button("Abbrechen") { state.cancel() }
                    .buttonStyle(SkyButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button("Fertig") { state.finish() }
                    .buttonStyle(SkyButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
                    .disabled(!(done || failed))
            }
            .padding(.horizontal, 20).padding(.bottom, 18)
        }
        .frame(width: 620, height: 520)
        .background(NebulaBackground())
        .interactiveDismissDisabled()
    }

    var title: String {
        switch state.phase {
        case .finished: return "Analyse abgeschlossen"
        case .failed: return "Analyse fehlgeschlagen"
        case .cancelled: return "Abgebrochen"
        default: return "Bild wird analysiert …"
        }
    }

    var subtitle: String {
        if state.isBusy { return state.currentStep }
        let t = String(format: "%.1f s", state.log.last.map { $0.time.timeIntervalSince(state.log.first?.time ?? $0.time) } ?? 0)
            .replacingOccurrences(of: ".", with: ",")
        switch state.phase {
        case .finished: return "Rechenzeit \(t)"
        case .failed: return "Details im Protokoll – „Report“ speichert es als Textdatei"
        default: return state.currentStep
        }
    }

    func resultLine(_ r: AnalysisResult) -> String {
        let n = r.objects.count
        switch r.kind {
        case .moon: return "\(n) Krater erkannt – „Fertig“ zeigt sie im Bild."
        default: return "\(n) Objekte gefunden – „Fertig“ zeigt sie im Bild."
        }
    }
}

struct LogLine: View {
    let entry: LogEntry
    static let tf: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f }()

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(LogLine.tf.string(from: entry.time))
                .font(.system(size: 10.5, design: .monospaced)).foregroundStyle(Theme.textSecondary.opacity(0.7))
            Image(systemName: icon).font(.system(size: 10)).foregroundStyle(color).frame(width: 12)
            Text(entry.message)
                .font(.system(size: 11.5, weight: entry.level == .step ? .semibold : .regular, design: entry.level == .step ? .default : .monospaced))
                .foregroundStyle(entry.level == .step ? Theme.textPrimary : color)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(.top, entry.level == .step ? 5 : 0)
    }

    var icon: String {
        switch entry.level {
        case .step: return "arrow.right.circle.fill"
        case .info: return "circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    var color: Color {
        switch entry.level {
        case .step: return Theme.accent
        case .info: return Theme.textSecondary
        case .success: return Theme.success
        case .warning: return Theme.warning
        case .error: return Theme.error
        }
    }
}

/// Animierter „Sternfeld-Scan“
struct ScanAnimation: View {
    let active: Bool
    let success: Bool
    let failed: Bool

    var body: some View {
        TimelineView(.animation(paused: !active)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let R = min(size.width, size.height) / 2 - 2
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - R, y: c.y - R, width: 2 * R, height: 2 * R)), with: .color(Theme.divider), lineWidth: 1.5)
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - R * 0.55, y: c.y - R * 0.55, width: R * 1.1, height: R * 1.1)), with: .color(Theme.divider.opacity(0.7)), lineWidth: 1)
                let stars: [(Double, Double)] = [(0.2, 0.7), (1.3, 0.45), (2.4, 0.8), (3.1, 0.3), (4.0, 0.65), (4.9, 0.5), (5.6, 0.85)]
                let sweep = active ? (t * 1.6).truncatingRemainder(dividingBy: 2 * .pi) : 0
                for (a, r) in stars {
                    let p = CGPoint(x: c.x + cos(a) * R * r, y: c.y + sin(a) * R * r)
                    var diff = (sweep - a).truncatingRemainder(dividingBy: 2 * .pi); if diff < 0 { diff += 2 * .pi }
                    let glow = active ? max(0.25, 1 - diff / 2.5) : 1
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - 2, y: p.y - 2, width: 4, height: 4)), with: .color(Theme.glow.opacity(glow)))
                }
                if active {
                    var wedge = Path()
                    wedge.move(to: c)
                    wedge.addArc(center: c, radius: R, startAngle: .radians(sweep - 0.6), endAngle: .radians(sweep), clockwise: false)
                    wedge.closeSubpath()
                    ctx.fill(wedge, with: .linearGradient(Gradient(colors: [Theme.accent.opacity(0), Theme.accent.opacity(0.45)]),
                                                         startPoint: CGPoint(x: c.x + cos(sweep - 0.6) * R, y: c.y + sin(sweep - 0.6) * R),
                                                         endPoint: CGPoint(x: c.x + cos(sweep) * R, y: c.y + sin(sweep) * R)))
                } else {
                    let sym = failed ? "xmark" : success ? "checkmark" : "pause"
                    let txt = ctx.resolve(Image(systemName: sym))
                    ctx.draw(txt, at: c)
                }
            }
        }
        .foregroundStyle(failed ? Theme.error : Theme.success)
    }
}
