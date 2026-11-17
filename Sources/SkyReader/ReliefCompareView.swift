import SwiftUI
import AppKit
import SkyReaderCore

/// Vergleich: Foto ↔ aus dem LOLA-Höhenmodell berechnete Mondansicht (gleiche Lage, gleicher Sonnenstand).
/// Überblenden per Regler oder automatisches Blinken – Abweichungen fallen so sofort auf.
struct ReliefCompareView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var mix: Double = 0.5
    @State private var blink = false
    @State private var blinkOn = false
    @State private var sideBySide = false
    let timer = Timer.publish(every: 0.7, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Vergleich mit dem Mondrelief").font(.system(size: 20, weight: .light).width(.expanded))
                    if let r = state.result?.relief {
                        Text("Berechnet aus dem LOLA-Höhenmodell (NASA LRO) für \(Self.format(r.date)) · Übereinstimmung \(Int((r.score * 100).rounded())) %")
                            .font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer()
                Button("Fertig") { dismiss() }.buttonStyle(SkyButtonStyle(prominent: true)).keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 22).padding(.vertical, 14)

            GeometryReader { geo in
                ZStack {
                    Color.black
                    if let photo = state.displayImage, let relief = reliefNSImage {
                        if sideBySide {
                            HStack(spacing: 8) {
                                labeled(Image(nsImage: photo).resizable().aspectRatio(contentMode: .fit), "Foto")
                                labeled(Image(nsImage: relief).resizable().aspectRatio(photo.size, contentMode: .fit), "Mondrelief")
                            }
                        } else {
                            ZStack {
                                Image(nsImage: photo).resizable().aspectRatio(contentMode: .fit)
                                Image(nsImage: relief).resizable().aspectRatio(photo.size, contentMode: .fit)
                                    .opacity(blink ? (blinkOn ? 1 : 0) : mix)
                            }
                        }
                    } else {
                        Text("Für dieses Bild liegt keine Reliefansicht vor.").foregroundStyle(Theme.textSecondary)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .padding(.horizontal, 16)

            HStack(spacing: 16) {
                Picker("", selection: $sideBySide) {
                    Text("Überblenden").tag(false)
                    Text("Nebeneinander").tag(true)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 240)
                if !sideBySide {
                    Text("Foto").font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                    Slider(value: $mix, in: 0...1).frame(maxWidth: 260).disabled(blink)
                    Text("Relief").font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                    Toggle("Blinken", isOn: $blink).toggleStyle(.switch)
                }
                Spacer()
                Text("Die Reliefansicht zeigt nur Höhen und Schatten – helle und dunkle Gebiete (Maria) fehlen bewusst.")
                    .font(.system(size: 10.5)).foregroundStyle(Theme.textSecondary).lineLimit(2).frame(maxWidth: 330, alignment: .trailing)
            }
            .padding(16)
        }
        .frame(minWidth: 980, minHeight: 720)
        .background(Theme.background)
        .preferredColorScheme(.dark)
        .onReceive(timer) { _ in if blink { blinkOn.toggle() } }
    }

    func labeled<V: View>(_ v: V, _ t: String) -> some View {
        v.overlay(alignment: .topLeading) {
            Text(t).font(.system(size: 11, weight: .semibold)).padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(Color.black.opacity(0.7))).foregroundStyle(Theme.accent).padding(8)
        }
    }

    var reliefNSImage: NSImage? {
        guard let r = state.result?.relief, r.pixels.count == r.width * r.height,
              let provider = CGDataProvider(data: r.pixels as CFData),
              let cg = CGImage(width: r.width, height: r.height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: r.width,
                               space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                               provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: r.width, height: r.height))
    }

    static func format(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "de_DE"); f.dateStyle = .medium; f.timeStyle = .short
        return f.string(from: d)
    }
}
