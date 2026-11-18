import SwiftUI
import AppKit
import SkyReaderCore

struct ReleaseInfo: Identifiable, Equatable {
    var id: String { tag }
    var tag: String
    var version: String
    var notes: String
    var zipURL: URL
    var pageURL: URL
    var published: Date?
}

/// Sucht auf GitHub nach neuen Releases, lädt sie, ersetzt die App und startet sie neu.
@MainActor
final class Updater: ObservableObject {
    @AppStorage("autoUpdateCheck") var autoCheck = true
    @AppStorage("lastUpdateCheck") var lastCheck: Double = 0
    @Published var offer: ReleaseInfo?
    @Published var status: String = ""
    @Published var checking = false
    @Published var downloading = false
    @Published var downloadProgress: Double = 0

    private var observation: NSKeyValueObservation?

    var lastCheckText: String {
        guard lastCheck > 0 else { return "noch nie" }
        let f = DateFormatter(); f.locale = Locale(identifier: "de_DE"); f.dateStyle = .medium; f.timeStyle = .short
        return f.string(from: Date(timeIntervalSince1970: lastCheck))
    }

    func check(userInitiated: Bool) {
        guard !checking else { return }
        checking = true
        status = "Suche nach Updates …"
        Task {
            defer { checking = false }
            do {
                var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(AppInfo.repository)/releases/latest")!)
                req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                req.setValue("SkyReader/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
                req.timeoutInterval = 20
                let (data, resp) = try await URLSession.shared.data(for: req)
                lastCheck = Date().timeIntervalSince1970
                guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                    status = "Kein Release gefunden."
                    return
                }
                guard let rel = Updater.parse(data) else { status = "Release ohne passende Datei."; return }
                if Updater.compare(rel.version, AppInfo.version) > 0 {
                    status = "Version \(rel.version) ist verfügbar."
                    offer = rel
                } else {
                    status = "Sky Reader ist aktuell (Version \(AppInfo.version))."
                    if userInitiated { offer = nil }
                }
            } catch {
                status = "Update-Prüfung fehlgeschlagen: \(error.localizedDescription)"
            }
        }
    }

    static func parse(_ data: Data) -> ReleaseInfo? {
        guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = j["tag_name"] as? String,
              let assets = j["assets"] as? [[String: Any]],
              let page = (j["html_url"] as? String).flatMap(URL.init(string:)) else { return nil }
        guard let zip = assets.first(where: { (($0["name"] as? String) ?? "").hasSuffix(".zip") }),
              let zs = zip["browser_download_url"] as? String, let zu = URL(string: zs) else { return nil }
        let v = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let pub = (j["published_at"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
        return ReleaseInfo(tag: tag, version: v, notes: j["body"] as? String ?? "", zipURL: zu, pageURL: page, published: pub)
    }

    /// Semantischer Versionsvergleich (1.10.0 > 1.9.3)
    static func compare(_ a: String, _ b: String) -> Int {
        let pa = a.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x > y ? 1 : -1 }
        }
        return 0
    }

    /// Lädt das Release, entpackt es und ersetzt die laufende App. Danach Neustart.
    func install(_ rel: ReleaseInfo) {
        guard !downloading else { return }
        let appURL = Bundle.main.bundleURL
        let parent = appURL.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parent.path) else {
            status = "Keine Schreibrechte für \(parent.path). Bitte das Update manuell installieren."
            NSWorkspace.shared.open(rel.pageURL)
            return
        }
        downloading = true
        downloadProgress = 0
        status = "Update wird geladen …"
        Task {
            do {
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("SkyReaderUpdate-\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
                let zipPath = tmp.appendingPathComponent("update.zip")
                let (loc, resp) = try await URLSession.shared.download(from: rel.zipURL, delegate: nil)
                guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                try FileManager.default.moveItem(at: loc, to: zipPath)
                downloadProgress = 0.7
                status = "Update wird entpackt …"
                let unzip = Process()
                unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                unzip.arguments = ["-x", "-k", zipPath.path, tmp.path]
                try unzip.run(); unzip.waitUntilExit()
                guard unzip.terminationStatus == 0 else { throw NSError(domain: "SkyReader", code: 50, userInfo: [NSLocalizedDescriptionKey: "Entpacken fehlgeschlagen"]) }
                let items = try FileManager.default.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil)
                guard let newApp = items.first(where: { $0.pathExtension == "app" }) else {
                    throw NSError(domain: "SkyReader", code: 51, userInfo: [NSLocalizedDescriptionKey: "Im Update wurde keine App gefunden"])
                }
                downloadProgress = 0.9
                status = "Installation startet – Sky Reader wird neu gestartet …"
                try launchInstaller(newApp: newApp, target: appURL, workDir: tmp)
                Updater.log("Installer gestartet, App wird beendet (PID \(ProcessInfo.processInfo.processIdentifier))")
                try await Task.sleep(nanoseconds: 400_000_000)
                // Update-Fenster schließen, damit nichts das Beenden blockiert
                offer = nil
                NSApp.windows.forEach { w in w.sheets.forEach { w.endSheet($0) } }
                try await Task.sleep(nanoseconds: 300_000_000)
                // Sicherheitsnetz: falls das reguläre Beenden hängt, Prozess nach 4 s hart beenden
                DispatchQueue.global().asyncAfter(deadline: .now() + 4) {
                    Updater.log("Reguläres Beenden hat nicht gegriffen – Prozess wird beendet")
                    exit(0)
                }
                NSApp.terminate(nil)
            } catch {
                downloading = false
                status = "Update fehlgeschlagen: \(error.localizedDescription)"
            }
        }
    }

    /// Protokoll unter ~/Library/Logs/Sky Reader/update.log (zur Fehlersuche)
    nonisolated static func log(_ msg: String) {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Sky Reader")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("update.log")
        let line = "\(ISO8601DateFormatter().string(from: Date())) [App \(AppInfo.version)] \(msg)\n"
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
        else { try? line.write(to: url, atomically: true, encoding: .utf8) }
    }

    /// Externes Skript: wartet auf das Beenden (beendet notfalls hart), ersetzt die App, entfernt die Quarantäne,
    /// meldet die neue Version bei macOS an und startet sie neu. Alles wird protokolliert.
    private func launchInstaller(newApp: URL, target: URL, workDir: URL) throws {
        let script = """
        #!/bin/sh
        PID="$1"; NEW="$2"; DEST="$3"; WORK="$4"
        LOGDIR="$HOME/Library/Logs/Sky Reader"; mkdir -p "$LOGDIR"; LOG="$LOGDIR/update.log"
        log() { echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [Installer] $*" >> "$LOG"; }
        log "wartet auf Ende von PID $PID"
        i=0
        while kill -0 "$PID" 2>/dev/null && [ $i -lt 100 ]; do sleep 0.2; i=$((i+1)); done
        if kill -0 "$PID" 2>/dev/null; then
          log "App reagiert nicht – wird beendet (TERM)"; kill -TERM "$PID" 2>/dev/null; sleep 3
          if kill -0 "$PID" 2>/dev/null; then log "App beendet (KILL)"; kill -KILL "$PID" 2>/dev/null; sleep 1; fi
        fi
        log "alte App beendet, ersetze $DEST"
        BACKUP="$DEST.old-update"
        rm -rf "$BACKUP"
        if mv "$DEST" "$BACKUP" && /usr/bin/ditto "$NEW" "$DEST"; then
          rm -rf "$BACKUP"; log "neue Version installiert"
        else
          log "FEHLER beim Ersetzen – alte Version wiederhergestellt"; rm -rf "$DEST"; mv "$BACKUP" "$DEST"
        fi
        /usr/bin/xattr -dr com.apple.quarantine "$DEST" 2>/dev/null
        /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST" 2>/dev/null
        sleep 1
        if /usr/bin/open -n "$DEST"; then log "neue Version gestartet"; else log "FEHLER: Start fehlgeschlagen"; fi
        rm -rf "$WORK"
        """
        let sh = workDir.appendingPathComponent("install.sh")
        try script.write(to: sh, atomically: true, encoding: .utf8)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = [sh.path, "\(ProcessInfo.processInfo.processIdentifier)", newApp.path, target.path, workDir.path]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice; p.standardInput = FileHandle.nullDevice
        try p.run()
    }
}

struct UpdateSheet: View {
    @EnvironmentObject var updater: Updater
    @Environment(\.dismiss) private var dismiss
    let release: ReleaseInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle.fill").font(.system(size: 30)).foregroundStyle(Theme.accent)
                VStack(alignment: .leading) {
                    Text("Update verfügbar").font(.system(size: 18, weight: .semibold))
                    Text("Version \(release.version) – installiert ist \(AppInfo.version)").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                }
            }
            if !release.notes.isEmpty {
                ScrollView {
                    Text(release.notes).font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                }
                .frame(maxHeight: 200)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.panel))
            }
            if updater.downloading {
                ProgressView(value: updater.downloadProgress).tint(Theme.accent)
            }
            Text(updater.status).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
            HStack {
                Button("Release-Seite") { NSWorkspace.shared.open(release.pageURL) }.buttonStyle(SkyButtonStyle())
                Spacer()
                Button("Später") { updater.offer = nil; dismiss() }.buttonStyle(SkyButtonStyle()).disabled(updater.downloading)
                Button("Jetzt installieren") { updater.install(release) }
                    .buttonStyle(SkyButtonStyle(prominent: true)).disabled(updater.downloading)
                    .keyboardShortcut(.defaultAction)
            }
            Text("Sky Reader schließt sich, das Update wird installiert und die neue Version startet automatisch.")
                .font(.system(size: 10.5)).foregroundStyle(Theme.textSecondary)
        }
        .padding(22)
        .frame(width: 480)
        .background(NebulaBackground())
    }
}
