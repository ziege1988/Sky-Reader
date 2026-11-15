import SwiftUI
import SkyReaderCore

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var updater: Updater
    @Environment(\.dismiss) private var dismiss
    var showsDone = false
    @State private var tab = SettingsView.initialTab
    @MainActor static var initialTab = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Einstellungen").font(.system(size: 20, weight: .light).width(.expanded))
                Spacer()
                if showsDone {
                    Button("Fertig") { dismiss() }.buttonStyle(SkyButtonStyle(prominent: true)).keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 22).padding(.top, 18).padding(.bottom, 8)
            Picker("", selection: $tab) {
                Text("Analyse").tag(0)
                Text("Darstellung").tag(1)
                Text("Updates").tag(2)
                Text("Über").tag(3)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 22)
            Form {
                switch tab {
                case 0: analysis
                case 1: display
                case 2: updates
                default: about
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        .background(NebulaBackground())
        .preferredColorScheme(.dark)
    }

    // MARK: Analyse
    @ViewBuilder var analysis: some View {
        Section {
            Picker("Krater", selection: $state.craterMode) {
                ForEach(AnalysisSettings.CraterMode.allCases, id: \.self) { Text($0.germanName).tag($0) }
            }
            Text("Bei Mondaufnahmen werden die Krater nummeriert. „Nur die größten“ zeigt bis zu 12 deutliche Krater, „Alle“ bis zu 120.")
                .font(.caption).foregroundStyle(Theme.textSecondary)
        } header: { Text("Mond") }

        Section {
            Picker("Objektdichte", selection: $state.density) {
                ForEach(DeepSkyCatalog.Density.allCases, id: \.self) { Text($0.germanName).tag($0) }
            }
            Toggle("Nebel (Emissions-, Reflexions-, planetarische Nebel)", isOn: $state.showNebula)
            Toggle("Galaxien", isOn: $state.showGalaxy)
            Toggle("Sternhaufen", isOn: $state.showCluster)
            Toggle("Dunkelnebel", isOn: $state.showDark)
            Toggle("Kometen", isOn: $state.showComet)
            Text("Einzelne Sterne werden grundsätzlich nicht markiert.").font(.caption).foregroundStyle(Theme.textSecondary)
        } header: { Text("Himmelsobjekte") }

        Section {
            Picker("Analyseauflösung", selection: $state.analysisSize) {
                Text("Schnell (1.600 px)").tag(1600)
                Text("Standard (2.000 px)").tag(2000)
                Text("Genau (3.000 px)").tag(3000)
            }
            Text("Größere Werte finden mehr schwache Sterne und kleine Krater, benötigen aber mehr Zeit.").font(.caption).foregroundStyle(Theme.textSecondary)
            if state.loaded != nil {
                Button("Aktuelles Bild mit diesen Einstellungen neu analysieren") { dismiss(); state.reanalyze() }
                    .disabled(state.isBusy)
            }
        } header: { Text("Genauigkeit") }
    }

    // MARK: Darstellung
    @ViewBuilder var display: some View {
        Section {
            Toggle("Bezeichnungen im Bild anzeigen", isOn: $state.showLabels)
            HStack {
                Text("Schriftgröße")
                Slider(value: $state.labelScale, in: 0.7...1.8)
                Text("\(Int(state.labelScale * 100)) %").font(.system(size: 11, design: .monospaced)).frame(width: 44)
            }
        } header: { Text("Markierungen") }
        Section {
            HStack(spacing: 14) {
                ForEach([SkyObjectType.emissionNebula, .galaxy, .openCluster, .darkNebula, .comet, .moonCrater], id: \.self) { t in
                    HStack(spacing: 5) {
                        Circle().fill(Theme.color(for: t)).frame(width: 9, height: 9)
                        Text(t.category.germanName).font(.system(size: 11))
                    }
                }
            }
        } header: { Text("Farben") }
    }

    // MARK: Updates
    @ViewBuilder var updates: some View {
        Section {
            Toggle("Automatisch nach Updates suchen", isOn: $updater.autoCheck)
            LabeledContent("Installierte Version", value: AppInfo.versionLine)
            LabeledContent("Letzte Prüfung", value: updater.lastCheckText)
            HStack {
                Button(updater.checking ? "Suche …" : "Jetzt nach Updates suchen") { updater.check(userInitiated: true) }
                    .disabled(updater.checking)
                Spacer()
                Link("Alle Releases", destination: AppInfo.releasesURL)
            }
            if !updater.status.isEmpty { Text(updater.status).font(.caption).foregroundStyle(Theme.textSecondary) }
        } header: { Text("Software-Aktualisierung") } footer: {
            Text("Updates werden von GitHub geladen. Bei der Installation schließt sich Sky Reader, die neue Version wird eingespielt und automatisch gestartet.")
                .font(.caption).foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: Über
    @ViewBuilder var about: some View {
        Section {
            HStack(spacing: 14) {
                PleiadesMark().frame(width: 44, height: 44)
                VStack(alignment: .leading) {
                    Text("Sky Reader").font(.system(size: 18, weight: .light).width(.expanded))
                    Text(AppInfo.versionLine).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.textSecondary)
                }
            }
            Text("Analysiert Astroaufnahmen vollständig offline: Plate Solving gegen einen mitgelieferten Sternkatalog, Abgleich mit Deep-Sky-Katalogen, Kometenbahnen und Mondkrater-Erkennung.")
                .font(.caption).foregroundStyle(Theme.textSecondary)
            LabeledContent("Kataloge", value: state.catalogInfo)
        } header: { Text("Über Sky Reader") }
        Section {
            Group {
                Text("Sterne: Tycho-2 (Høg et al. 2000, CDS I/259) und HYG-Datenbank v4.1 (CC BY-SA 4.0)")
                Text("Deep-Sky: OpenNGC von Mattia Verga (CC BY-SA 4.0); LDN (Lynds 1962), Barnard, Sharpless, LBN, vdB, Cederblad über VizieR/CDS")
                Text("Kometen: Minor Planet Center (IAU)")
                Text("Mondkrater: Gazetteer of Planetary Nomenclature (IAU/USGS)")
            }
            .font(.caption).foregroundStyle(Theme.textSecondary)
        } header: { Text("Datenquellen") }
    }
}
