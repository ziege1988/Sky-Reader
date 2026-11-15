import SwiftUI

/// Start-Popup: schwarz, flächig gefüllt mit der Plejaden-Aufnahme, darunter Name und Versionsnummer.
struct SplashView: View {
    @State private var shimmer = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black
            if let img = SplashView.image {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .scaleEffect(shimmer ? 1.06 : 1.0)
                    .animation(.easeOut(duration: 2.6), value: shimmer)
            }
            LinearGradient(colors: [.clear, .black.opacity(0.35), .black.opacity(0.92)], startPoint: .top, endPoint: .bottom)
            VStack(spacing: 6) {
                Text("Sky Reader")
                    .font(.system(size: 40, weight: .ultraLight).width(.expanded))
                    .foregroundStyle(Theme.textPrimary)
                    .shadow(color: Theme.accent.opacity(0.6), radius: 12)
                Text(AppInfo.versionLine)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(Theme.accent)
                ProgressView()
                    .controlSize(.small)
                    .tint(Theme.accent)
                    .padding(.top, 10)
            }
            .padding(.bottom, 34)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.accent.opacity(0.25), lineWidth: 1))
        .onAppear { shimmer = true }
    }

    static let image: NSImage? = {
        guard let u = Bundle.main.url(forResource: "splash", withExtension: "jpg", subdirectory: "Images")
                ?? Bundle.main.url(forResource: "splash", withExtension: "jpg") else { return nil }
        return NSImage(contentsOf: u)
    }()
}
