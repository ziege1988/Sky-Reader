import SwiftUI
import SkyReaderCore

/// Rückfrage im Analysefenster: Aufnahmedatum der Mondaufnahme (ermöglicht Libration, Sonnenstand und
/// die Kraterbenennung auch ohne sichtbaren Mondrand).
struct MoonDatePanel: View {
    @EnvironmentObject var state: AppState
    let question: MoonDateQuestion
    @State private var date = Date()
    @State private var timeKnown = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "moon.stars.fill").font(.system(size: 24)).foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mondaufnahme erkannt – wann wurde sie aufgenommen?")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                    Text("Mit Datum und Uhrzeit berechnet Sky Reader Libration und Sonnenstand. So lassen sich die Krater auch ohne sichtbaren Mondrand sicher benennen.")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 14) {
                DatePicker("Datum", selection: $date, displayedComponents: .date)
                    .datePickerStyle(.field)
                Toggle("Uhrzeit bekannt", isOn: $timeKnown)
                if timeKnown {
                    DatePicker("Uhrzeit", selection: $date, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.field)
                        .labelsHidden()
                }
            }
            .font(.system(size: 12))
            if let est = question.estimate {
                VStack(alignment: .leading, spacing: 6) {
                    Label(estimateLine(est), systemImage: "function")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(est.quality == .good ? Theme.success : Theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(estimateDetail(est))
                        .font(.system(size: 10.5)).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !est.alternatives.isEmpty {
                        HStack(spacing: 6) {
                            Text("Ebenfalls möglich:").font(.system(size: 10.5)).foregroundStyle(Theme.textSecondary)
                            ForEach(est.alternatives, id: \.self) { a in
                                Button(Self.format(a.date)) { date = a.date; timeKnown = true }
                                    .buttonStyle(.link).font(.system(size: 10.5))
                            }
                            Button("Berechnet") { date = est.best.date; timeKnown = true }
                                .buttonStyle(.link).font(.system(size: 10.5))
                        }
                    }
                }
            } else if let note = question.estimateNote {
                Label(note, systemImage: "function")
                    .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let f = question.fromFileName {
                Label("Datum im Dateinamen: „\(f.text)“\(f.yearKnown ? "" : (question.estimate != nil ? " – Jahr aus dem Bild berechnet" : " – das Jahr bitte prüfen"))", systemImage: "doc.text.magnifyingglass")
                    .font(.system(size: 11)).foregroundStyle(question.estimate == nil ? Theme.success : Theme.textSecondary)
            }
            if let e = question.exifDate {
                Label("Kamera-Zeitstempel (oft unzuverlässig): \(Self.format(e))", systemImage: "camera")
                    .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
            }
            if !timeKnown {
                Text("Ohne Uhrzeit wird 22:00 Uhr angenommen – die Benennung bleibt meist möglich, ist aber etwas unsicherer.")
                    .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
            }
            HStack {
                Button("Datum unbekannt") { state.answerMoonQuestion(.unknown) }
                    .buttonStyle(SkyButtonStyle())
                Spacer()
                Button("Übernehmen") { state.answerMoonQuestion(.known(resolvedDate)) }
                    .buttonStyle(SkyButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.panelRaised))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.accent.opacity(0.5)))
        .onAppear {
            if let est = question.estimate { date = est.best.date; timeKnown = true }
            else if let f = question.fromFileName { date = f.date } else if let e = question.exifDate { date = e }
        }
    }

    func estimateLine(_ e: MoonDateEstimate) -> String {
        let h = Int(e.timeUncertaintyHours.rounded())
        let unc = e.measuredColongitude != nil && h <= 24 ? " (Uhrzeit ± \(max(1, h)) h)" : ""
        return "Aus dem Bild berechnet: \(Self.format(e.best.date))\(unc)" + (e.quality == .good ? "" : " – unsicher, bitte prüfen")
    }

    func estimateDetail(_ e: MoonDateEstimate) -> String {
        var s = String(format: "Libration %+.1f°/%+.1f°", e.measuredLibrationLat, e.measuredLibrationLon)
            .replacingOccurrences(of: ".", with: ",") + " aus der Kraterlage"
        if let c = e.measuredColongitude {
            s += String(format: ", Terminator bei Colongitude %.0f°", c)
        } else {
            s += ", kein Terminator im Bild"
        }
        s += " → \(e.best.phaseName), \(Int((e.best.illuminatedFraction * 100).rounded())) % beleuchtet."
        if e.usedFileNameDate { s += " Der Tag aus dem Dateinamen wurde berücksichtigt." }
        s += " Passt das nicht, Datum einfach korrigieren."
        return s
    }

    var resolvedDate: Date {
        guard !timeKnown else { return date }
        var c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        c.hour = 22; c.minute = 0
        return Calendar.current.date(from: c) ?? date
    }

    static func format(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "de_DE"); f.dateStyle = .medium; f.timeStyle = .short
        return f.string(from: d)
    }
}
