import SwiftUI
import AppKit
import SkyReaderCore

/// Beobachtungstagebuch: Aufnahmen als Kacheln, Klick öffnet den Eintrag zum Bearbeiten.
struct JournalView: View {
    @EnvironmentObject var journal: JournalStore
    @EnvironmentObject var state: AppState
    @State private var search = ""
    @State private var filter: Filter = .all
    @State private var editing: JournalEntry?

    enum Filter: String, CaseIterable, Identifiable {
        case all = "Alle", deepSky = "Himmel", moon = "Mond", comet = "Kometen"
        var id: String { rawValue }
    }

    var filtered: [JournalEntry] {
        journal.entries.filter { e in
            switch filter {
            case .all: break
            case .deepSky: if e.kind != .deepSky { return false }
            case .moon: if e.kind != .moon { return false }
            case .comet: if e.kind != .comet { return false }
            }
            guard !search.isEmpty else { return true }
            let hay = ([e.title, e.subtitle, e.notes, e.location, e.equipment] + e.objectNames).joined(separator: " ").lowercased()
            return hay.contains(search.lowercased())
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "book.pages").foregroundStyle(Theme.accent)
                Text("Beobachtungstagebuch").font(.system(size: 18, weight: .light).width(.expanded)).foregroundStyle(Theme.textPrimary)
                Text("\(journal.entries.count) Einträge").font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                Spacer()
                Picker("", selection: $filter) { ForEach(Filter.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 280)
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSecondary)
                    TextField("Suchen (Objekt, Ort, Notiz …)", text: $search).textFieldStyle(.plain).frame(width: 200)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 7).fill(Theme.panelRaised))
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            .background(Color.black.opacity(0.5))
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.divider).frame(height: 1) }

            if journal.entries.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "book.closed").font(.system(size: 44)).foregroundStyle(Theme.accent.opacity(0.7))
                    Text("Noch keine Einträge").font(.system(size: 18, weight: .light)).foregroundStyle(Theme.textPrimary)
                    Text("Analysiere eine Aufnahme und wähle „Ins Tagebuch“, um sie hier mit deinen Notizen abzulegen.")
                        .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 270, maximum: 380), spacing: 16)], spacing: 16) {
                        ForEach(filtered) { e in
                            JournalTile(entry: e, image: journal.thumbnail(e))
                                .onTapGesture { editing = e }
                                .contextMenu {
                                    Button("Bearbeiten") { editing = e }
                                    Button("Im Finder zeigen") { NSWorkspace.shared.activateFileViewerSelecting([journal.imageURL(e)]) }
                                    Divider()
                                    Button("Löschen", role: .destructive) { journal.delete(e) }
                                }
                        }
                    }
                    .padding(20)
                }
            }
        }
        .sheet(item: $editing) { e in
            JournalDetailView(entry: e, isNew: false)
                .environmentObject(journal).environmentObject(state)
        }
    }
}

struct JournalTile: View {
    let entry: JournalEntry
    let image: NSImage?
    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                Color.black
                if let img = image {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                }
                Label(kindLabel, systemImage: kindIcon)
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Color.black.opacity(0.7)))
                    .foregroundStyle(Theme.accent)
                    .padding(8)
            }
            .frame(height: 170)
            .clipped()
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                Text(dateLine).font(.system(size: 11)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                if !entry.objectNames.isEmpty {
                    Text(entry.objectNames.prefix(4).joined(separator: " · ")).font(.system(size: 10.5)).foregroundStyle(Theme.accent.opacity(0.9)).lineLimit(1)
                }
                Text(entry.notes.isEmpty ? "Keine Notizen" : entry.notes)
                    .font(.system(size: 11.5)).foregroundStyle(entry.notes.isEmpty ? Theme.textSecondary.opacity(0.6) : Theme.textPrimary.opacity(0.85))
                    .lineLimit(2, reservesSpace: true)
            }
            .padding(12)
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.panel))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(hover ? Theme.accent.opacity(0.7) : Theme.divider, lineWidth: 1))
        .scaleEffect(hover ? 1.015 : 1)
        .animation(.easeOut(duration: 0.15), value: hover)
        .onHover { hover = $0 }
        .contentShape(Rectangle())
    }

    var kindLabel: String { entry.kind == .moon ? "Mond" : entry.kind == .comet ? "Komet" : "Himmel" }
    var kindIcon: String { entry.kind == .moon ? "moon.fill" : entry.kind == .comet ? "sparkle" : "sparkles" }

    var dateLine: String {
        let f = DateFormatter(); f.locale = Locale(identifier: "de_DE"); f.dateStyle = .medium; f.timeStyle = .short
        var parts: [String] = []
        if let d = entry.observationDate { parts.append(f.string(from: d)) } else { parts.append("Datum unbekannt") }
        if !entry.location.isEmpty { parts.append(entry.location) }
        return parts.joined(separator: " · ")
    }
}

/// Eintrag anlegen/bearbeiten
struct JournalDetailView: View {
    @EnvironmentObject var journal: JournalStore
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State var entry: JournalEntry
    let isNew: Bool
    @State private var hasDate = true
    @State private var date = Date()
    @State private var confirmDelete = false
    @MainActor static var autoSaveForSelfTest = false

    init(entry: JournalEntry, isNew: Bool) {
        _entry = State(initialValue: entry)
        self.isNew = isNew
        _hasDate = State(initialValue: entry.observationDate != nil)
        _date = State(initialValue: entry.observationDate ?? Date())
    }

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                Color.black
                if let img = NSImage(contentsOf: journal.thumbURL(entry)) ?? NSImage(contentsOf: journal.imageURL(entry)) {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fit).padding(14)
                }
            }
            .frame(minWidth: 520)
            Rectangle().fill(Theme.divider).frame(width: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(isNew ? "Ins Tagebuch übernehmen" : "Tagebucheintrag").font(.system(size: 20, weight: .light).width(.expanded))
                    field("Überschrift") { TextField("Überschrift", text: $entry.title).textFieldStyle(.roundedBorder) }
                    Text(entry.subtitle).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                    field("Beobachtungszeitpunkt") {
                        HStack {
                            Toggle("bekannt", isOn: $hasDate)
                            if hasDate { DatePicker("", selection: $date).labelsHidden() }
                        }
                    }
                    field("Ort") { TextField("z. B. Sternwarte, Garten, Alpen …", text: $entry.location).textFieldStyle(.roundedBorder) }
                    field("Ausrüstung") { TextField("Teleskop, Kamera, Filter …", text: $entry.equipment).textFieldStyle(.roundedBorder) }
                    field("Bedingungen") { TextField("Seeing, Transparenz, Mond, Temperatur …", text: $entry.conditions).textFieldStyle(.roundedBorder) }
                    field("Beschreibung / Notizen") {
                        TextEditor(text: $entry.notes)
                            .font(.system(size: 12.5))
                            .frame(minHeight: 140)
                            .scrollContentBackground(.hidden)
                            .padding(6)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.panelRaised))
                    }
                    if !entry.objectNames.isEmpty {
                        field("Objekte im Bild") {
                            Text(entry.objectNames.joined(separator: " · ")).font(.system(size: 11.5)).foregroundStyle(Theme.accent)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    HStack {
                        if !isNew {
                            Button("Löschen", role: .destructive) { confirmDelete = true }.buttonStyle(SkyButtonStyle())
                            Button("Analyse öffnen") {
                                if FileManager.default.fileExists(atPath: entry.originalPath) { state.load(url: URL(fileURLWithPath: entry.originalPath)) }
                                else { state.load(url: journal.imageURL(entry)) }
                                state.mainTab = .analysis
                                dismiss()
                            }.buttonStyle(SkyButtonStyle())
                        }
                        Spacer()
                        Button(isNew ? "Verwerfen" : "Abbrechen") {
                            if isNew { journal.delete(entry) }
                            dismiss()
                        }.buttonStyle(SkyButtonStyle()).keyboardShortcut(.cancelAction)
                        Button("Speichern") { commit(); dismiss() }
                            .buttonStyle(SkyButtonStyle(prominent: true)).keyboardShortcut(.defaultAction)
                    }
                }
                .padding(20)
            }
            .frame(width: 380)
            .background(Theme.panel)
        }
        .frame(width: 1040, height: 680)
        .background(Theme.background)
        .preferredColorScheme(.dark)
        .confirmationDialog("Eintrag löschen?", isPresented: $confirmDelete) {
            Button("Löschen", role: .destructive) { journal.delete(entry); dismiss() }
        } message: { Text("Bild und Notizen dieses Eintrags werden entfernt. Die Originaldatei bleibt erhalten.") }
        .onAppear { if JournalDetailView.autoSaveForSelfTest { entry.notes = entry.notes.isEmpty ? "Beispielnotiz: klare Nacht, gutes Seeing." : entry.notes } }
    }

    func commit() {
        entry.observationDate = hasDate ? date : nil
        journal.save(entry)
    }

    @ViewBuilder func field<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Theme.accent).textCase(.uppercase)
            content()
        }
    }
}
