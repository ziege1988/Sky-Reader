import SwiftUI
import SkyReaderCore

struct ResultsPanel: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if let r = state.result {
                    ResultList(result: r)
                } else {
                    EmptyResults()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            BottomBar()
        }
        .background(Theme.background.opacity(0.6))
    }
}

struct EmptyResults: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Ergebnisse")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .textCase(.uppercase)
            switch state.phase {
            case .failed(let m):
                PanelCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Analyse fehlgeschlagen", systemImage: "exclamationmark.triangle").foregroundStyle(Theme.warning)
                        Text(m).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                        Button("Bericht speichern …") { state.saveReport() }.buttonStyle(SkyButtonStyle())
                    }
                }
            case .analyzing, .loading:
                PanelCard {
                    HStack { ProgressView().controlSize(.small); Text(state.currentStep).font(.system(size: 12)).foregroundStyle(Theme.textSecondary) }
                }
            default:
                VStack(alignment: .leading, spacing: 12) {
                    InfoRow(icon: "square.and.arrow.down", text: "Ziehe ein JPEG- oder TIFF-Bild in die linke Fläche.")
                    InfoRow(icon: "scope", text: "Sky Reader bestimmt die Himmelsposition anhand der Sterne und sucht alle bekannten Objekte im Bildfeld.")
                    InfoRow(icon: "moon.stars", text: "Mondaufnahmen werden erkannt – Krater werden nummeriert und beschrieben.")
                    InfoRow(icon: "sparkles", text: "Kometen werden über ihre Bahn identifiziert, auch ohne Aufnahmedatum.")
                    InfoRow(icon: "wifi.slash", text: "Alles läuft offline auf deinem Mac.")
                }
            }
            Spacer()
        }
        .padding(20)
    }
}

struct InfoRow: View {
    let icon: String, text: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(Theme.accent).frame(width: 20)
            Text(text).font(.system(size: 12.5)).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct ResultList: View {
    @EnvironmentObject var state: AppState
    let result: AnalysisResult

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    SummaryCard(info: result.summary, kind: result.kind, count: result.objects.count)
                    if result.objects.isEmpty {
                        Text("Keine Objekte gefunden.").font(.system(size: 12)).foregroundStyle(Theme.textSecondary).padding(.top, 8)
                    }
                    ForEach(result.objects) { o in
                        ObjectCard(object: o, expanded: state.selectedObjectID == o.id)
                            .id(o.id)
                            .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { state.selectedObjectID = state.selectedObjectID == o.id ? nil : o.id } }
                    }
                }
                .padding(16)
            }
            .onChange(of: state.selectedObjectID) { _, id in
                if let id { withAnimation { proxy.scrollTo(id, anchor: .top) } }
            }
        }
    }
}

struct SummaryCard: View {
    let info: ObjectInfo
    let kind: SceneKind
    let count: Int
    var body: some View {
        PanelCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(info.title).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
                    Spacer()
                    Text("\(count) \(kind == .moon ? "Krater" : "Objekte")")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.accent)
                }
                FactGrid(facts: info.facts)
                if !info.layman.isEmpty { Text(info.layman).font(.system(size: 12)).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true) }
                if kind == .moon {
                    TextSection(title: "Wissenschaft", text: info.scientific)
                    TextSection(title: "Neueste Erkenntnisse", text: info.latest)
                }
            }
        }
    }
}

struct ObjectCard: View {
    let object: FoundObject
    let expanded: Bool

    var body: some View {
        PanelCard(highlighted: expanded) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Circle().fill(Theme.color(for: object.type)).frame(width: 9, height: 9)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(object.info.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                        Text(object.info.subtitle).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.system(size: 10)).foregroundStyle(Theme.textSecondary)
                }
                if expanded {
                    FactGrid(facts: object.info.facts)
                    TextSection(title: "Was du hier siehst", text: object.info.layman)
                    TextSection(title: "Wissenschaftliche Einordnung", text: object.info.scientific)
                    TextSection(title: "Neueste Erkenntnisse", text: object.info.latest)
                } else if !object.info.layman.isEmpty {
                    Text(object.info.layman).font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary).lineLimit(2)
                }
            }
        }
        .contentShape(Rectangle())
    }
}

struct FactGrid: View {
    let facts: [InfoFact]
    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            ForEach(facts, id: \.self) { f in
                GridRow {
                    Text(f.label).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                    Text(f.value).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.textPrimary)
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

struct TextSection: View {
    let title: String
    let text: String
    var body: some View {
        if !text.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Theme.accent).textCase(.uppercase)
                Text(text).font(.system(size: 12)).foregroundStyle(Theme.textPrimary.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
            .padding(.top, 4)
        }
    }
}

struct BottomBar: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var journal: JournalStore
    var body: some View {
        ViewThatFits(in: .horizontal) {
            bar(compact: false)
            bar(compact: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.6))
        .overlay(alignment: .top) { Rectangle().fill(Theme.divider).frame(height: 1) }
    }

    func bar(compact: Bool) -> some View {
        HStack(spacing: 8) {
            Button { state.openPanel() } label: { label("Öffnen", "folder", compact) }
                .buttonStyle(SkyButtonStyle()).disabled(state.isBusy).help("Bild öffnen (⌘O)")
            if state.loaded != nil {
                Button { state.reanalyze() } label: { label("Neu analysieren", "arrow.clockwise", compact) }
                    .buttonStyle(SkyButtonStyle()).disabled(state.isBusy)
                    .help("Mit den aktuellen Einstellungen erneut analysieren")
            }
            Spacer(minLength: 8)
            Button {
                if let e = journal.makeEntry(from: state) { state.journalDraft = e }
            } label: { label("Ins Tagebuch", "book.pages", compact) }
                .buttonStyle(SkyButtonStyle())
                .disabled(state.result == nil)
                .help("Aufnahme mit Analyse und Notizen im Beobachtungstagebuch ablegen")
            Button { state.showExport = true } label: { label("Exportieren", "square.and.arrow.up", compact && state.loaded != nil) }
                .buttonStyle(SkyButtonStyle(prominent: true))
                .disabled(state.result == nil)
                .help("Bild mit Markierungen und Beschreibung exportieren")
            Button { state.showSettings = true } label: { Image(systemName: "gearshape.fill").font(.system(size: 14)) }
                .buttonStyle(SkyButtonStyle())
                .help("Einstellungen")
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder func label(_ t: String, _ icon: String, _ compact: Bool) -> some View {
        if compact { Image(systemName: icon) }
        else { Label(t, systemImage: icon).labelStyle(.titleAndIcon).lineLimit(1).fixedSize() }
    }
}
