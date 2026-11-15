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
                let rect = CGRect(x: c.x - size.width / 2, y: c.y - size.height / 2, width: size.width, height: size.height)
                best = (rect, c, 0)
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
            items.append(OverlayItem(object: o, center: c, radius: r, labelRect: b.0, anchor: b.1, color: Theme.nsColor(for: o.type)))
        }
        return items
    }

    /// Zeichnet die Markierungen in einen CoreGraphics-Kontext (Ursprung oben links; Kontext muss geflippt sein)
    static func draw(_ items: [OverlayItem], in ctx: CGContext, lineWidth: CGFloat, fontSize: CGFloat, showLabels: Bool,
                     selected: String? = nil, hidden: Set<String> = [], ghostHidden: Bool = false) {
        for it in items {
            let isHidden = hidden.contains(it.object.id)
            if isHidden && !ghostHidden { continue }
            let alpha: CGFloat = isHidden ? 0.28 : 1
            let col = it.color.withAlphaComponent(alpha)
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
            ctx.restoreGState()
            guard showLabels || !it.object.drawCircle else { continue }
            let isNum = it.object.number != nil && !it.object.drawCircle
            let f = font(size: fontSize * (sel ? 1.12 : 1), number: isNum)
            if isNum {
                ctx.saveGState()
                ctx.setFillColor(NSColor.black.withAlphaComponent(0.55 * alpha).cgColor)
                let bg = CGPath(roundedRect: it.labelRect, cornerWidth: it.labelRect.height / 2, cornerHeight: it.labelRect.height / 2, transform: nil)
                ctx.addPath(bg); ctx.fillPath()
                ctx.setStrokeColor(col.withAlphaComponent(sel ? 1 : 0.7 * alpha).cgColor)
                ctx.setLineWidth(max(1, lineWidth * (sel ? 1.2 : 0.6)))
                ctx.addPath(bg); ctx.strokePath()
                ctx.restoreGState()
            }
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.9 * alpha)
            shadow.shadowBlurRadius = fontSize * 0.25
            let attrs: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: col, .shadow: shadow]
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
