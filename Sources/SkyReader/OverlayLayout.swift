import AppKit
import SkyReaderCore

/// Platzierung einer Markierung samt kollisionsfreier Beschriftung (in Zielkoordinaten)
struct OverlayItem {
    var object: FoundObject
    var center: CGPoint
    var radius: CGFloat
    var labelRect: CGRect
    var anchor: CGPoint
    var color: NSColor
}

enum OverlayLayout {
    static func font(size: CGFloat, number: Bool = false) -> NSFont {
        number ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: .semibold) : NSFont.systemFont(ofSize: size, weight: .medium)
    }

    static func textSize(_ s: String, font: NSFont) -> CGSize {
        let r = (s as NSString).size(withAttributes: [.font: font])
        return CGSize(width: ceil(r.width), height: ceil(r.height))
    }

    /// - Parameters:
    ///   - transform: Bildpixel → Zielkoordinaten
    ///   - scale: Pixel → Zielmaß (für Radien)
    ///   - bounds: sichtbarer Bereich in Zielkoordinaten
    static func layout(objects: [FoundObject], transform: (CGPoint) -> CGPoint, scale: CGFloat, fontSize: CGFloat,
                       bounds: CGRect, selected: String? = nil) -> [OverlayItem] {
        var placed: [CGRect] = []
        var items: [OverlayItem] = []
        // Große und ausgewählte Objekte zuerst beschriften
        let order = objects.sorted { a, b in
            if a.id == selected { return true }
            if b.id == selected { return false }
            return a.radius > b.radius
        }
        for o in order {
            let c = transform(CGPoint(x: o.x, y: o.y))
            let r = max(CGFloat(o.radius) * scale, o.drawCircle ? 6 : 0)
            let isNum = o.number != nil && !o.drawCircle
            let f = font(size: fontSize, number: isNum)
            let ts = textSize(o.label, font: f)
            let pad: CGFloat = isNum ? 3 : 4
            let size = CGSize(width: ts.width + 2 * pad, height: ts.height + (isNum ? 0 : 2))
            var best: (CGRect, CGPoint, CGFloat)?
            if isNum {
                // Fadenkreuz in der Mitte, Nummer kollisionsfrei daneben
                let arm = crosshairArm(fontSize)
                for (k, a) in ([-45, 45, -135, 135, 0, 180, -90, 90] as [CGFloat]).enumerated() {
                    let rad = a * .pi / 180
                    let anchor = CGPoint(x: c.x + cos(rad) * (arm + 2), y: c.y + sin(rad) * (arm + 2))
                    var origin = anchor
                    if cos(rad) < -0.3 { origin.x -= size.width } else if abs(cos(rad)) <= 0.3 { origin.x -= size.width / 2 }
                    if sin(rad) < -0.3 { origin.y -= size.height } else if abs(sin(rad)) <= 0.3 { origin.y -= size.height / 2 }
                    let rect = CGRect(origin: origin, size: size)
                    var penalty = CGFloat(k) * 0.5
                    for p in placed { let i = p.intersection(rect); if !i.isNull { penalty += i.width * i.height } }
                    if !bounds.contains(rect) { penalty += size.width * size.height }
                    if best == nil || penalty < best!.2 { best = (rect, anchor, penalty) }
                    if penalty < 1 { break }
                }
            } else {
                var angles: [CGFloat] = [-45, -135, 45, 135, 0, 180, -90, 90, -20, -160, 20, 160]
                if r > min(bounds.width, bounds.height) * 0.3 {
                    // Sehr große Kreise: Ankerpunkte entlang des ganzen Umfangs, die im Bild liegen (nahe der Bildmitte zuerst)
                    let mid = CGPoint(x: bounds.midX, y: bounds.midY)
                    angles = stride(from: 0, to: 360, by: 7.5).map { CGFloat($0) }.filter { a in
                        let p = CGPoint(x: c.x + cos(a * .pi / 180) * r, y: c.y + sin(a * .pi / 180) * r)
                        return bounds.insetBy(dx: size.width, dy: size.height).contains(p)
                    }.sorted { a, b in
                        let pa = CGPoint(x: c.x + cos(a * .pi / 180) * r, y: c.y + sin(a * .pi / 180) * r)
                        let pb = CGPoint(x: c.x + cos(b * .pi / 180) * r, y: c.y + sin(b * .pi / 180) * r)
                        return hypot(pa.x - mid.x, pa.y - mid.y) > hypot(pb.x - mid.x, pb.y - mid.y)
                    }
                    if angles.isEmpty { angles = [-45, -135, 45, 135] }
                }
                for (k, a) in angles.enumerated() {
                    let rad = a * .pi / 180
                    let anchor = CGPoint(x: c.x + cos(rad) * r, y: c.y + sin(rad) * r)
                    let gap: CGFloat = 3 + CGFloat(k / 8) * 10
                    var origin = CGPoint(x: anchor.x + cos(rad) * gap, y: anchor.y + sin(rad) * gap)
                    // Große Kreise: Beschriftung innen an den Bogen legen
                    if r > min(bounds.width, bounds.height) * 0.3 { origin = CGPoint(x: anchor.x - cos(rad) * (gap + size.width * 0.6), y: anchor.y - sin(rad) * (gap + size.height)) }
                    // Rechteck so ausrichten, dass es vom Kreis weg zeigt
                    if cos(rad) < -0.3 { origin.x -= size.width } else if abs(cos(rad)) <= 0.3 { origin.x -= size.width / 2 }
                    if sin(rad) < -0.3 { origin.y -= size.height } else if abs(sin(rad)) <= 0.3 { origin.y -= size.height / 2 }
                    let rect = CGRect(origin: origin, size: size)
                    var penalty: CGFloat = CGFloat(k) * 0.5
                    for p in placed { let i = p.intersection(rect); if !i.isNull { penalty += i.width * i.height } }
                    if !bounds.contains(rect) {
                        let i = bounds.intersection(rect)
                        penalty += (size.width * size.height - (i.isNull ? 0 : i.width * i.height)) * 2
                    }
                    if best == nil || penalty < best!.2 { best = (rect, anchor, penalty) }
                    if penalty < 1 { break }
                }
            }
            guard let b = best else { continue }
            placed.append(b.0)
            if isNum { let arm = crosshairArm(fontSize); placed.append(CGRect(x: c.x - arm, y: c.y - arm, width: 2 * arm, height: 2 * arm)) }
            items.append(OverlayItem(object: o, center: c, radius: r, labelRect: b.0, anchor: b.1, color: Theme.nsColor(for: o.type)))
        }
        return items
    }

    static func crosshairArm(_ fontSize: CGFloat) -> CGFloat { max(5, fontSize * 0.6) }

    /// Farbe für Markierungen, die im Export entfernt werden
    static let removedColor = NSColor(calibratedRed: 1.0, green: 0.42, blue: 0.42, alpha: 1)

    /// Zeichnet die Markierungen in einen CoreGraphics-Kontext (Ursprung oben links; Kontext muss geflippt sein)
    static func draw(_ items: [OverlayItem], in ctx: CGContext, lineWidth: CGFloat, fontSize: CGFloat, showLabels: Bool,
                     selected: String? = nil, hidden: Set<String> = [], ghostHidden: Bool = false) {
        for it in items {
            let isHidden = hidden.contains(it.object.id)
            if isHidden && !ghostHidden { continue }
            // Entfernte Markierungen (nur Vorschau): rot gestrichelt, Bezeichnung durchgestrichen
            let alpha: CGFloat = isHidden ? 0.9 : 1
            let col = isHidden ? removedColor.withAlphaComponent(0.9) : it.color
            let sel = it.object.id == selected
            ctx.saveGState()
            if it.object.drawCircle {
                ctx.setStrokeColor(col.cgColor)
                ctx.setLineWidth(lineWidth * (sel ? 1.8 : 1))
                if isHidden { ctx.setLineDash(phase: 0, lengths: [lineWidth * 4, lineWidth * 3]) }
                ctx.setShadow(offset: .zero, blur: lineWidth * 3, color: NSColor.black.withAlphaComponent(0.8 * alpha).cgColor)
                ctx.strokeEllipse(in: CGRect(x: it.center.x - it.radius, y: it.center.y - it.radius, width: 2 * it.radius, height: 2 * it.radius))
                ctx.setLineDash(phase: 0, lengths: [])
                if showLabels {
                    // Verbindungslinie bei abgesetzter Beschriftung
                    let lc = CGPoint(x: it.labelRect.midX, y: it.labelRect.midY)
                    let d = hypot(lc.x - it.anchor.x, lc.y - it.anchor.y)
                    if d > max(it.labelRect.width, it.labelRect.height) * 0.9 {
                        ctx.setLineWidth(lineWidth * 0.6)
                        ctx.move(to: it.anchor)
                        let nx = min(max(it.anchor.x, it.labelRect.minX), it.labelRect.maxX)
                        let ny = min(max(it.anchor.y, it.labelRect.minY), it.labelRect.maxY)
                        ctx.addLine(to: CGPoint(x: nx, y: ny))
                        ctx.strokePath()
                    }
                }
            }
            let isNum = it.object.number != nil && !it.object.drawCircle
            if isNum {
                // Kleines Fadenkreuz in der Kratermitte (keine Kreise um Krater)
                let arm = crosshairArm(fontSize) * (sel ? 1.25 : 1), gap = arm * 0.35
                let c = it.center
                ctx.setShadow(offset: .zero, blur: lineWidth * 2.5, color: NSColor.black.withAlphaComponent(0.9).cgColor)
                ctx.setStrokeColor((sel ? NSColor(Theme.glow) : col).cgColor)
                ctx.setLineWidth(max(1, lineWidth * (sel ? 1.3 : 0.9)))
                if isHidden { ctx.setLineDash(phase: 0, lengths: [lineWidth * 2, lineWidth * 1.5]) }
                for (dx, dy) in [(1.0, 0.0), (-1.0, 0.0), (0.0, 1.0), (0.0, -1.0)] {
                    ctx.move(to: CGPoint(x: c.x + dx * gap, y: c.y + dy * gap))
                    ctx.addLine(to: CGPoint(x: c.x + dx * arm, y: c.y + dy * arm))
                }
                ctx.strokePath()
                ctx.setLineDash(phase: 0, lengths: [])
            }
            ctx.restoreGState()
            guard showLabels || !it.object.drawCircle else { continue }
            let f = font(size: fontSize * (sel ? 1.12 : 1), number: isNum)
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.95)
            shadow.shadowBlurRadius = fontSize * 0.3
            var attrs: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: (sel && isNum) ? NSColor(Theme.glow) : col, .shadow: shadow]
            if isHidden { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue; attrs[.strikethroughColor] = removedColor }
            let s = NSAttributedString(string: it.object.label, attributes: attrs)
            let ts = s.size()
            let origin = CGPoint(x: it.labelRect.midX - ts.width / 2, y: it.labelRect.midY - ts.height / 2)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
            s.draw(at: origin)
            NSGraphicsContext.restoreGraphicsState()
        }
    }
}
