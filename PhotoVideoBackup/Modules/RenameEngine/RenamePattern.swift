import Foundation
import AVFoundation
import ImageIO

// MARK: - RenamePattern

struct RenamePattern: Equatable {
    var raw: String
    var indexWidth: Int = 3

    static let tokens: [(label: String, token: String)] = [
        ("YYYY", "{YYYY}"),
        ("MM",   "{MM}"),
        ("DD",   "{DD}"),
        ("hh",   "{hh}"),
        ("mm",   "{mm}"),
        ("ss",   "{ss}"),
        ("#",    "{index}"),
        ("name", "{original}"),
    ]

    func filename(original: String, captureDate: Date?, index: Int) -> String {
        let nsStr = original as NSString
        let ext   = nsStr.pathExtension
        let stem  = nsStr.deletingPathExtension

        var result = raw

        if let date = captureDate {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = .current
            let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
            result = result.replacingOccurrences(of: "{YYYY}", with: String(format: "%04d", c.year  ?? 0))
            result = result.replacingOccurrences(of: "{MM}",   with: String(format: "%02d", c.month  ?? 0))
            result = result.replacingOccurrences(of: "{DD}",   with: String(format: "%02d", c.day    ?? 0))
            result = result.replacingOccurrences(of: "{hh}",   with: String(format: "%02d", c.hour   ?? 0))
            result = result.replacingOccurrences(of: "{mm}",   with: String(format: "%02d", c.minute ?? 0))
            result = result.replacingOccurrences(of: "{ss}",   with: String(format: "%02d", c.second ?? 0))
        } else {
            for (_, token) in Self.tokens where token.contains("Y") || token.contains("M") ||
                                               token.contains("D") || token.contains("h") ||
                                               token.contains("m") || token.contains("s") {
                result = result.replacingOccurrences(of: token, with: "????")
            }
        }

        result = result.replacingOccurrences(of: "{index}",
                                             with: String(format: "%0\(indexWidth)d", index + 1))
        result = result.replacingOccurrences(of: "{original}", with: stem)

        return result + (ext.isEmpty ? "" : "." + ext)
    }

    // MARK: - Capture date extraction (EXIF → video container → nil)

    static func captureDate(at url: URL) -> Date? {
        if let d = exifDate(at: url) { return d }
        return videoContainerDate(at: url)
    }

    private static func exifDate(at url: URL) -> Date? {
        guard let src   = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any]
        else { return nil }
        let exif = props[kCGImagePropertyExifDictionary as String] as? [String: Any]
        let tiff = props[kCGImagePropertyTIFFDictionary as String] as? [String: Any]
        guard let raw = exif?[kCGImagePropertyExifDateTimeOriginal as String] as? String
                     ?? tiff?[kCGImagePropertyTIFFDateTime as String] as? String
        else { return nil }
        let fmt = DateFormatter()
        fmt.locale     = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return fmt.date(from: raw)
    }

    private static let videoExts: Set<String> = ["mp4", "mov", "avi", "m4v", "insv", "braw"]

    private static func videoContainerDate(at url: URL) -> Date? {
        guard videoExts.contains(url.pathExtension.lowercased()) else { return nil }
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])
        let items = AVMetadataItem.metadataItems(from: asset.commonMetadata,
                                                  withKey: AVMetadataKey.commonKeyCreationDate,
                                                  keySpace: .common)
        guard let item = items.first else { return nil }
        if let d = item.dateValue { return d }
        if let str = item.stringValue {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime]
            if let d = iso.date(from: str) { return d }
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = iso.date(from: str) { return d }
            let fmt = DateFormatter()
            fmt.locale = Locale(identifier: "en_US_POSIX")
            fmt.dateFormat = "yyyy:MM:dd HH:mm:ss"
            return fmt.date(from: str)
        }
        return nil
    }
}
