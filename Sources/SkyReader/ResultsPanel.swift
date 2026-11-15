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
                    Text(info.title).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.textPrimary)
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
    var body: some View {
        HStack(spacing: 8) {
            Button { state.openPanel() } label: { Label("Öffnen", systemImage: "folder") }
                .buttonStyle(SkyButtonStyle()).disabled(state.isBusy)
            if state.loaded != nil {
                Button { state.reanalyze() } label: { Label("Neu analysieren", systemImage: "arrow.clockwise") }
                    .buttonStyle(SkyButtonStyle()).disabled(state.isBusy)
                    .help("Mit den aktuellen Einstellungen erneut analysieren")
            }
            Spacer()
            Button { state.showExport = true } label: { Label("Exportieren", systemImage: "square.and.arrow.up") }
                .buttonStyle(SkyButtonStyle(prominent: true))
                .disabled(state.result == nil)
            Button { state.showSettings = true } label: { Image(systemName: "gearshape.fill").font(.system(size: 15)) }
                .buttonStyle(SkyButtonStyle())
                .help("Einstellungen")
        }
        .labelStyle(.titleAndIcon)
        .padding(12)
        .background(Color.black.opacity(0.6))
        .overlay(alignment: .top) { Rectangle().fill(Theme.divider).frame(height: 1) }
    }
}
