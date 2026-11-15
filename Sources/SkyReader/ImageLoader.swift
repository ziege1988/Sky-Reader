import Foundation
import AppKit
import ImageIO
import UniformTypeIdentifiers
import SkyReaderCore

struct LoadedImage {
    var url: URL
    var cgImage: CGImage
    var gray: GrayImage
    var metadata: ImageMetadata
}

enum ImageLoaderError: LocalizedError {
    case unsupported, unreadable
    var errorDescription: String? {
        switch self {
        case .unsupported: return "Dieses Dateiformat wird nicht unterstützt. Erlaubt sind JPEG (.jpg/.jpeg) und TIFF (.tif/.tiff)."
        case .unreadable: return "Das Bild konnte nicht gelesen werden."
        }
    }
}

enum ImageLoader {
    static let allowedTypes: [UTType] = [.jpeg, .tiff]
    static let allowedExtensions = ["jpg", "jpeg", "tif", "tiff"]

    static func isSupported(_ url: URL) -> Bool { allowedExtensions.contains(url.pathExtension.lowercased()) }

    static func load(_ url: URL) throws -> LoadedImage {
        guard isSupported(url) else { throw ImageLoaderError.unsupported }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { throw ImageLoaderError.unreadable }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] ?? [:]
        let w = props[kCGImagePropertyPixelWidth] as? Int ?? 0
        let h = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        // EXIF-Ausrichtung anwenden, maximale Kantenlänge 8000 px
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: min(max(w, h), 8000),
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { throw ImageLoaderError.unreadable }
        var meta = metadata(props)
        meta.fileName = url.lastPathComponent
        meta.originalWidth = cg.width
        meta.originalHeight = cg.height
        let gray = try grayImage(cg)
        return LoadedImage(url: url, cgImage: cg, gray: gray, metadata: meta)
    }

    /// Wandelt in Graustufen (16 Bit, damit TIFF-Dynamik erhalten bleibt)
    static func grayImage(_ cg: CGImage) throws -> GrayImage {
        let w = cg.width, h = cg.height
        var buf = [UInt16](repeating: 0, count: w * h)
        let ok: Bool = buf.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 16, bytesPerRow: w * 2,
                                      space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue | CGBitmapInfo.byteOrder16Little.rawValue) else { return false }
            ctx.interpolationQuality = .none
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { throw ImageLoaderError.unreadable }
        var px = [Float](repeating: 0, count: w * h)
        let inv: Float = 1 / 65535
        for i in 0..<(w * h) { px[i] = Float(UInt16(littleEndian: buf[i])) * inv }
        return GrayImage(width: w, height: h, pixels: px)
    }

    static func metadata(_ p: [CFString: Any]) -> ImageMetadata {
        var m = ImageMetadata()
        let exif = p[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let tiff = p[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        if let s = exif[kCGImagePropertyExifDateTimeOriginal] as? String ?? tiff[kCGImagePropertyTIFFDateTime] as? String {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            if let off = exif[kCGImagePropertyExifOffsetTimeOriginal] as? String {
                df.dateFormat = "yyyy:MM:dd HH:mm:ssXXXXX"
                m.captureDate = df.date(from: s + off)
            }
            if m.captureDate == nil {
                df.dateFormat = "yyyy:MM:dd HH:mm:ss"
                df.timeZone = .current   // Kamerazeit wird als lokale Zeit angenommen
                m.captureDate = df.date(from: s)
            }
        }
        m.focalLengthMM = exif[kCGImagePropertyExifFocalLength] as? Double
        if let f35 = exif[kCGImagePropertyExifFocalLenIn35mmFilm] as? Double, f35 > 0 { m.focalLength35mm = f35 }
        else if let f35 = exif[kCGImagePropertyExifFocalLenIn35mmFilm] as? Int, f35 > 0 { m.focalLength35mm = Double(f35) }
        m.exposureSeconds = exif[kCGImagePropertyExifExposureTime] as? Double
        if let iso = exif[kCGImagePropertyExifISOSpeedRatings] as? [Double] { m.iso = iso.first }
        m.cameraModel = tiff[kCGImagePropertyTIFFModel] as? String
        m.lensModel = exif[kCGImagePropertyExifLensModel] as? String
        return m
    }
}
