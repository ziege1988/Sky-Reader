import SwiftUI
import AppKit
import SkyReaderCore

@main
struct SkyReaderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Fenster werden im AppDelegate verwaltet (Splash → Hauptfenster mit gemerkter Position).
        Settings {
            SettingsView()
                .environmentObject(appDelegate.state)
                .environmentObject(appDelegate.updater)
                .frame(width: 560, height: 620)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Bild öffnen …") { appDelegate.state.openPanel() }.keyboardShortcut("o")
            }
            CommandGroup(after: .appInfo) {
                Button("Nach Updates suchen …") { appDelegate.updater.check(userInitiated: true) }
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let state = AppState()
    let updater = Updater()
    private var splashWindow: NSWindow?
    private var mainWindow: NSWindow?
    private var pendingOpen: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        ResourceLocator.overrideDirectory = Bundle.main.resourceURL?.appendingPathComponent("Catalogs")
        showSplash()
        // Kataloge schon während des Splash im Hintergrund laden
        Task.detached(priority: .userInitiated) {
            _ = try? StarCatalog.shared()
            _ = try? DeepSkyCatalog.shared()
            _ = Descriptions.shared
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { MainActor.assumeIsolated { self.showMain() } }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func application(_ application: NSApplication, open urls: [URL]) {
        if mainWindow == nil { pendingOpen += urls } else if let u = urls.first { state.load(url: u) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { mainWindow?.makeKeyAndOrderFront(nil) }
        return true
    }

    /// Bildschirm, auf dem das Hauptfenster zuletzt war (aus der gespeicherten Fensterposition)
    private func preferredScreen() -> NSScreen {
        if let s = UserDefaults.standard.string(forKey: "NSWindow Frame SkyReaderMain") {
            let parts = s.split(separator: " ").compactMap { Double($0) }
            if parts.count >= 4 {
                let center = NSPoint(x: parts[0] + parts[2] / 2, y: parts[1] + parts[3] / 2)
                if let scr = NSScreen.screens.first(where: { $0.frame.contains(center) }) { return scr }
            }
        }
        return NSScreen.main ?? NSScreen.screens[0]
    }

    private func showSplash() {
        let screen = preferredScreen()
        let size = NSSize(width: 620, height: 400)
        let frame = NSRect(x: screen.visibleFrame.midX - size.width / 2, y: screen.visibleFrame.midY - size.height / 2,
                           width: size.width, height: size.height)
        let w = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = true
        w.level = .floating
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: SplashView())
        w.alphaValue = 0
        w.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in ctx.duration = 0.35; w.animator().alphaValue = 1 }
        splashWindow = w
        NSApp.activate()
    }

    private func showMain() {
        let screen = preferredScreen()
        let vf = screen.visibleFrame
        // Standard: 2/3 der Bildschirmfläche, zentriert
        let size = NSSize(width: (vf.width * 2 / 3).rounded(), height: (vf.height * 2 / 3).rounded())
        let frame = NSRect(x: vf.midX - size.width / 2, y: vf.midY - size.height / 2, width: size.width, height: size.height)
        let w = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.title = "Sky Reader"
        w.backgroundColor = NSColor(Theme.background)
        w.minSize = NSSize(width: 980, height: 620)
        w.isReleasedWhenClosed = false
        w.delegate = self
        let root = MainView()
            .environmentObject(state)
            .environmentObject(updater)
        w.contentView = NSHostingView(rootView: root)
        // Gemerkte Position und Bildschirm wiederherstellen
        w.setFrameAutosaveName("SkyReaderMain")
        if !w.setFrameUsingName("SkyReaderMain") { w.setFrame(frame, display: false) }
        mainWindow = w
        w.alphaValue = 0
        w.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.45
            w.animator().alphaValue = 1
            splashWindow?.animator().alphaValue = 0
        }, completionHandler: {
            Task { @MainActor in
                self.splashWindow?.orderOut(nil)
                self.splashWindow = nil
            }
        })
        if let u = pendingOpen.first { state.load(url: u) }
        pendingOpen = []
        if updater.autoCheck {
            let up = updater
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { MainActor.assumeIsolated { up.check(userInitiated: false) } }
        }
    }

    func windowDidMove(_ notification: Notification) { mainWindow?.saveFrame(usingName: "SkyReaderMain") }
    func windowDidResize(_ notification: Notification) { mainWindow?.saveFrame(usingName: "SkyReaderMain") }
}
