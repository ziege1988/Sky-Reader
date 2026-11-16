import SwiftUI
import SkyReaderCore

/// Farbwelt angelehnt an die Plejaden: tiefes Schwarz, staubiges Blaugrau, eisiges Sternblau.
enum Theme {
    static let background = Color(red: 0.016, green: 0.024, blue: 0.047)      // #04060C
    static let panel = Color(red: 0.039, green: 0.063, blue: 0.118)           // #0A1020
    static let panelRaised = Color(red: 0.067, green: 0.102, blue: 0.180)     // #111A2E
    static let divider = Color(red: 0.110, green: 0.153, blue: 0.251)         // #1C2740
    static let accent = Color(red: 0.561, green: 0.765, blue: 0.941)          // #8FC3F0 Plejadenblau
    static let accentDeep = Color(red: 0.361, green: 0.561, blue: 0.839)      // #5C8FD6
    static let glow = Color(red: 0.812, green: 0.902, blue: 1.0)              // #CFE6FF
    static let dust = Color(red: 0.431, green: 0.498, blue: 0.525)            // #6E7F86 Staubnebel
    static let textPrimary = Color(red: 0.910, green: 0.945, blue: 1.0)       // #E8F1FF
    static let textSecondary = Color(red: 0.549, green: 0.627, blue: 0.741)   // #8CA0BD
    static let success = Color(red: 0.498, green: 0.878, blue: 0.788)
    static let warning = Color(red: 0.961, green: 0.784, blue: 0.459)
    static let error = Color(red: 0.961, green: 0.502, blue: 0.502)

    static func color(for type: SkyObjectType) -> Color {
        switch type.category {
        case .nebula: return accent
        case .galaxy: return Color(red: 0.910, green: 0.788, blue: 0.561)
        case .cluster: return glow
        case .darkNebula: return Color(red: 0.62, green: 0.66, blue: 0.74)
        case .comet: return Color(red: 0.498, green: 0.878, blue: 0.788)
        case .moon: return accent   // Mondkrater: Fadenkreuz im Plejadenblau
        }
    }

    static func nsColor(for type: SkyObjectType) -> NSColor { NSColor(color(for: type)) }

    static let titleFont = Font.system(size: 22, weight: .light, design: .default).width(.expanded)
}

/// Hintergrund mit sanftem Plejaden-Schimmer
struct NebulaBackground: View {
    var body: some View {
        ZStack {
            Theme.background
            RadialGradient(colors: [Theme.accentDeep.opacity(0.18), .clear], center: .topTrailing, startRadius: 10, endRadius: 700)
            RadialGradient(colors: [Theme.dust.opacity(0.10), .clear], center: .bottomLeading, startRadius: 10, endRadius: 600)
        }
        .ignoresSafeArea()
    }
}

struct PanelCard<Content: View>: View {
    var highlighted = false
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(highlighted ? Theme.panelRaised : Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(highlighted ? Theme.accent.opacity(0.55) : Theme.divider, lineWidth: 1))
    }
}

struct SkyButtonStyle: ButtonStyle {
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 14).padding(.vertical, 7)
            .foregroundStyle(prominent ? Theme.background : Theme.textPrimary)
            .background(RoundedRectangle(cornerRadius: 7).fill(prominent ? Theme.accent : Theme.panelRaised))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(prominent ? Color.clear : Theme.divider, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Rectangle())
    }
}

enum AppInfo {
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0" }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0" }
    static var versionLine: String { "Version \(version) (Build \(build))" }
    static let repository = "ziege1988/Sky-Reader"
    static var releasesURL: URL { URL(string: "https://github.com/\(repository)/releases")! }
}
