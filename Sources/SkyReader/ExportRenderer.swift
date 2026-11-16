import AppKit
import CoreText
import ImageIO
import UniformTypeIdentifiers
import SkyReaderCore

struct ExportOptions: Equatable {
    var showMarkers = true
    var showDescription = true
    var detailed = false
    var labelScale: Double = 1
}

enum ExportFormat: String, CaseIterable, Identifiable {
    case jpeg, tiff
    var id: String { rawValue }
    var title: String { self == .jpeg ? "JPEG" : "TIFF" }
    var ext: String { self == .jpeg ? "jpg" : "tif" }
    var utType: UTType { self == .jpeg ? .jpeg : .tiff }
}

/// Erzeugt das Exportbild: Aufnahme mit Markierungen, rechts die Beschreibung, unten in der Ecke klein der Softwarename.
enum ExportRenderer {
    struct Layout {
        var scale: CGFloat
        var imageRect: CGRect
        var size: CGSize
    }

    static func layout(image: CGImage, options: ExportOptions, scale: CGFloat) -> Layout {
        let w = CGFloat(image.width) * scale, h = CGFloat(image.height) * scale
        var total = CGSize(width: w, height: h)
        if options.showDescription {
            let panel = min(max(w * 0.34, h * 0.58), h * 1.0)
            total.width += panel.rounded()
        }
        return Layout(scale: scale, imageRect: CGRect(x: 0, y: 0, width: w, height: h), size: CGSize(width: total.width.rounded(), height: h.rounded()))
    }

    static func render(image: CGImage, result: AnalysisResult, hidden: Set<String>, options: ExportOptions,
                       scale: CGFloat, ghostHidden: Bool = false) -> CGImage? {
        let L = layout(image: image, options: options, scale: scale)
        let W = Int(L.size.width), H = Int(L.size.height)
        guard let cs = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        // Hintergrund
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        // Bild (CG-Koordinaten: Ursprung unten links)
        ctx.draw(image, in: CGRect(x: 0, y: CGFloat(H) - L.imageRect.height, width: L.imageRect.width, height: L.imageRect.height))
        // ab hier oben-links-Koordinaten
        ctx.translateBy(x: 0, y: CGFloat(H))
        ctx.scaleBy(x: 1, y: -1)
        let ref = max(L.imageRect.width, L.imageRect.height)
        let k = L.imageRect.width / CGFloat(result.imageWidth)
        let visible = result.objects.filter { !hidden.contains($0.id) }
        if options.showMarkers {
            let fs = max(9, ref / 95 * CGFloat(options.labelScale))
            let objs = ghostHidden ? result.objects : visible
            let items = OverlayLayout.layout(objects: objs, transform: { CGPoint(x: $0.x * k, y: $0.y * k) }, scale: k,
                                             fontSize: fs, bounds: L.imageRect.insetBy(dx: 2, dy: 2))
            ctx.saveGState()
            ctx.clip(to: L.imageRect)
            OverlayLayout.draw(items, in: ctx, lineWidth: max(1.2, ref / 900), fontSize: fs, showLabels: true,
                               hidden: hidden, ghostHidden: ghostHidden)
            ctx.restoreGState()
        }
        if options.showDescription {
            let panel = CGRect(x: L.imageRect.maxX, y: 0, width: L.size.width - L.imageRect.maxX, height: L.size.height)
            drawPanel(in: ctx, rect: panel, result: result, objects: visible, options: options)
        } else {
            drawSignature(in: ctx, corner: CGPoint(x: L.imageRect.maxX, y: L.imageRect.maxY), height: L.imageRect.height, onImage: true)
        }
        return ctx.makeImage()
    }

    // MARK: Beschreibungsspalte

    static func drawPanel(in ctx: CGContext, rect: CGRect, result: AnalysisResult, objects: [FoundObject], options: ExportOptions) {
        // Hintergrund mit leichtem Plejaden-Verlauf
        let colors = [NSColor(Theme.panel).cgColor, NSColor(Theme.background).cgColor] as CFArray
        if let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1]) {
            ctx.saveGState(); ctx.clip(to: rect)
            ctx.drawLinearGradient(g, start: CGPoint(x: rect.minX, y: rect.minY), end: CGPoint(x: rect.maxX, y: rect.maxY), options: [])
            ctx.restoreGState()
        }
        ctx.setFillColor(NSColor(Theme.accent).withAlphaComponent(0.6).cgColor)
        ctx.fill(CGRect(x: rect.minX, y: rect.minY, width: max(1, rect.height / 900), height: rect.height))

        let pad = rect.height * 0.045
        let footerH = rect.height * 0.05
        let textRect = CGRect(x: rect.minX + pad, y: rect.minY + pad, width: rect.width - 2 * pad, height: rect.height - 2 * pad - footerH)
        var base = rect.height / 44
        let minBase = rect.height / 110
        var content = buildText(result: result, objects: objects, options: options, base: base)
        while base > minBase && measure(content, width: textRect.width) > textRect.height {
            base *= 0.93
            content = buildText(result: result, objects: objects, options: options, base: base)
        }
        drawText(content, in: textRect, ctx: ctx)
        drawSignature(in: ctx, corner: CGPoint(x: rect.maxX, y: rect.maxY), height: rect.height, onImage: false)
    }

    static func buildText(result: AnalysisResult, objects: [FoundObject], options: ExportOptions, base: CGFloat) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let primary = NSColor(Theme.textPrimary), secondary = NSColor(Theme.textSecondary), accent = NSColor(Theme.accent)
        func para(_ spacing: CGFloat, after: CGFloat = 0) -> NSParagraphStyle {
            let p = NSMutableParagraphStyle(); p.lineSpacing = spacing; p.paragraphSpacing = after; p.lineBreakMode = .byWordWrapping
            return p
        }
        func add(_ s: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor, after: CGFloat = 0, kern: CGFloat = 0) {
            out.append(NSAttributedString(string: s + "\n", attributes: [
                .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color,
                .paragraphStyle: para(size * 0.22, after: after), .kern: kern]))
        }
        add(result.kind == .moon ? "MONDANALYSE" : "BILDANALYSE", size: base * 0.75, weight: .semibold, color: accent, after: base * 0.3, kern: base * 0.12)
        let headline: String
        if objects.count == 1 { headline = objects[0].info.title }
        else if result.kind == .moon { headline = "Mondoberfläche" }
        else { headline = result.summary.title }
        add(headline, size: base * 1.75, weight: .light, color: primary, after: base * 0.4)
        // Kurzfakten zum Bild
        let keys = result.kind == .moon ? ["Bildmaßstab", "Bildbreite", "Erkannte Krater"] : ["Sternbild", "Bildfeld", "Bildmitte RA", "Bildmitte Dec"]
        let line = result.summary.facts.filter { keys.contains($0.label) }.map { "\($0.label): \($0.value)" }.joined(separator: "   ·   ")
        if !line.isEmpty { add(line, size: base * 0.72, color: secondary, after: base * 0.9) }
        if result.kind == .moon && options.detailed {
            add(result.summary.scientific, size: base * 0.8, color: primary.withAlphaComponent(0.85), after: base * 0.8)
        }
        var shownTexts = Set<String>()
        for o in objects {
            let dot = NSAttributedString(string: "● ", attributes: [.font: NSFont.systemFont(ofSize: base * 0.8), .foregroundColor: Theme.nsColor(for: o.type)])
            out.append(dot)
            add(o.info.title, size: base * 1.08, weight: .semibold, color: primary, after: base * 0.12)
            let factKeys = ["Objekttyp", "Kratertyp", "Entfernung", "Ausdehnung", "Geschätzter Durchmesser", "Helligkeit", "Alter", "Abstand zur Erde", "Perihel"]
            let fl = o.info.facts.filter { factKeys.contains($0.label) }.prefix(options.detailed ? 6 : 3).map { "\($0.label): \($0.value)" }.joined(separator: "  ·  ")
            if !fl.isEmpty { add(fl, size: base * 0.72, color: secondary, after: base * 0.3) }
            // gleiche Laientexte (z. B. je Kratertyp) nur einmal zeigen
            if !o.info.layman.isEmpty && shownTexts.insert(o.info.layman).inserted { add(o.info.layman, size: base * 0.82, color: primary.withAlphaComponent(0.88), after: base * (options.detailed ? 0.3 : 0.75)) }
            if options.detailed {
                if !o.info.scientific.isEmpty && shownTexts.insert(o.info.scientific).inserted { add(o.info.scientific, size: base * 0.76, color: primary.withAlphaComponent(0.75), after: base * 0.3) }
                if !o.info.latest.isEmpty {
                    out.append(NSAttributedString(string: "Neueste Erkenntnisse: ", attributes: [.font: NSFont.systemFont(ofSize: base * 0.76, weight: .semibold), .foregroundColor: accent]))
                    add(o.info.latest, size: base * 0.76, color: primary.withAlphaComponent(0.75), after: base * 0.75)
                }
            }
        }
        if objects.isEmpty {
            add("Keine Markierungen ausgewählt.", size: base * 0.85, color: secondary)
        }
        return out
    }

    static func measure(_ s: NSAttributedString, width: CGFloat) -> CGFloat {
        let fs = CTFramesetterCreateWithAttributedString(s as CFAttributedString)
        let size = CTFramesetterSuggestFrameSizeWithConstraints(fs, CFRange(location: 0, length: 0), nil,
                                                                CGSize(width: width, height: .greatestFiniteMagnitude), nil)
        return size.height
    }

    static func drawText(_ s: NSAttributedString, in rect: CGRect, ctx: CGContext) {
        // Kontext ist oben-links; CoreText erwartet unten-links → lokal zurückdrehen
        ctx.saveGState()
        ctx.translateBy(x: 0, y: rect.minY + rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        let fs = CTFramesetterCreateWithAttributedString(s as CFAttributedString)
        let path = CGPath(rect: rect, transform: nil)
        let frame = CTFramesetterCreateFrame(fs, CFRange(location: 0, length: 0), path, nil)
        ctx.textMatrix = .identity
        CTFrameDraw(frame, ctx)
        ctx.restoreGState()
    }

    static func drawSignature(in ctx: CGContext, corner: CGPoint, height: CGFloat, onImage: Bool) {
        let size = max(8, height / 75)
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.8); shadow.shadowBlurRadius = size * 0.3
        let s = NSAttributedString(string: "Sky Reader", attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: .light), .foregroundColor: NSColor(Theme.accent).withAlphaComponent(onImage ? 0.85 : 0.75),
            .kern: size * 0.15, .shadow: shadow])
        let ts = s.size()
        let m = size * 1.2
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        s.draw(at: CGPoint(x: corner.x - ts.width - m, y: corner.y - ts.height - m * 0.8))
        NSGraphicsContext.restoreGraphicsState()
    }

    // MARK: Schreiben

    static func write(_ img: CGImage, to url: URL, format: ExportFormat, quality: Double) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, format.utType.identifier as CFString, 1, nil) else {
            throw NSError(domain: "SkyReader", code: 40, userInfo: [NSLocalizedDescriptionKey: "Datei konnte nicht angelegt werden."])
        }
        var props: [CFString: Any] = [:]
        if format == .jpeg { props[kCGImageDestinationLossyCompressionQuality] = quality }
        else { props[kCGImagePropertyTIFFDictionary] = [kCGImagePropertyTIFFCompression: 5] }  // LZW
        props[kCGImagePropertyTIFFDictionary] = (props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:])
            .merging([kCGImagePropertyTIFFSoftware: "Sky Reader \(AppInfo.version)"]) { a, _ in a }
        CGImageDestinationAddImage(dest, img, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw NSError(domain: "SkyReader", code: 41, userInfo: [NSLocalizedDescriptionKey: "Bild konnte nicht gespeichert werden."])
        }
    }
}
