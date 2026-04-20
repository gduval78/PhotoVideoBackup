import Foundation
import ImageIO

// MARK: - MediaScanner

/// Recursively scans a source folder and returns a sorted [MediaFile].
/// Supports Insta360 X5, DJI Mini 3 Pro, and generic devices.
actor MediaScanner {

    // MARK: - Public API

    func scan(root: URL, deviceType: DeviceType) async throws -> [MediaFile] {
        print("[MediaScanner] scan root=\(root.path) deviceType=\(deviceType.rawValue)")
        let files: [MediaFile]
        switch deviceType {
        case .insta360X5:  files = try await scanInsta360(root: root)
        case .djiMini3Pro: files = try await scanDJI(root: root)
        case .dji360:      files = try await scanDJI360(root: root)
        case .generic:     files = try await scanGeneric(root: root)
        }
        print("[MediaScanner] found \(files.count) file(s)")
        return files.sorted { $0.sortDate < $1.sortDate }
    }

    // MARK: - Insta360 X5

    private func scanInsta360(root: URL) async throws -> [MediaFile] {
        let dcim = root.appendingPathComponent("DCIM")
        let fm   = FileManager.default
        var result: [MediaFile] = []

        guard let enumerator = fm.enumerator(
            at: dcim,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var insvByBase: [String: URL] = [:]
        var mp4ByBase:  [String: URL] = [:]
        var lrvByBase:  [String: URL] = [:]
        var inspFiles:  [URL]         = []

        for case let url as URL in enumerator {
            let ext  = url.pathExtension.lowercased()
            let base = url.deletingPathExtension().lastPathComponent
            switch ext {
            case "insv": insvByBase[base] = url
            case "mp4":  mp4ByBase[base]  = url
            case "lrv":  lrvByBase[base]  = url
            case "insp": inspFiles.append(url)
            default: break
            }
        }

        for (base, url) in insvByBase {
            if let mf = try? mediaFile(at: url, device: .insta360X5, lrv: lrvByBase[base]) {
                result.append(mf)
            }
        }
        for (base, url) in mp4ByBase where insvByBase[base] == nil {
            if let mf = try? mediaFile(at: url, device: .insta360X5, lrv: lrvByBase[base]) {
                result.append(mf)
            }
        }
        for url in inspFiles {
            if let mf = try? mediaFile(at: url, device: .insta360X5) { result.append(mf) }
        }
        return result
    }

    // MARK: - DJI Mini 3 Pro

    private func scanDJI(root: URL) async throws -> [MediaFile] {
        let dcim = root.appendingPathComponent("DCIM")
        let fm   = FileManager.default
        var result: [MediaFile] = []

        guard let djiDirs = try? fm.contentsOfDirectory(
            at: dcim,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let mediaExts = Set(["mp4", "jpg", "jpeg", "dng"])

        for dir in djiDirs where dir.lastPathComponent.hasPrefix("DJI_") {
            guard let files = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            var mediaByBase: [String: URL] = [:]
            var srtByBase:   [String: URL] = [:]

            for url in files {
                let ext  = url.pathExtension.lowercased()
                let base = url.deletingPathExtension().lastPathComponent
                if mediaExts.contains(ext) { mediaByBase[base] = url }
                if ext == "srt"            { srtByBase[base]   = url }
            }

            for (base, url) in mediaByBase {
                if let mf = try? mediaFile(at: url, device: .djiMini3Pro, srt: srtByBase[base]) {
                    result.append(mf)
                }
            }
        }
        return result
    }

    // MARK: - DJI 360 / Action cameras (100DJIMED, 100MEDIA…)

    private func scanDJI360(root: URL) async throws -> [MediaFile] {
        let dcim = root.appendingPathComponent("DCIM")
        let fm   = FileManager.default
        var result: [MediaFile] = []

        guard let dirs = try? fm.contentsOfDirectory(
            at: dcim,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let mediaExts  = Set(["mp4", "mov", "jpg", "jpeg", "dng", "mp3", "osv"])
        let dirPattern = #"^\d{3}"#

        for dir in dirs {
            let name = dir.lastPathComponent
            guard name.range(of: dirPattern, options: .regularExpression) != nil else { continue }

            guard let files = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            var mediaByBase: [String: URL] = [:]
            var srtByBase:   [String: URL] = [:]

            for url in files {
                let ext  = url.pathExtension.lowercased()
                let base = url.deletingPathExtension().lastPathComponent
                if mediaExts.contains(ext) { mediaByBase[base] = url }
                if ext == "srt"            { srtByBase[base]   = url }
            }

            for (base, url) in mediaByBase {
                if let mf = try? mediaFile(at: url, device: .dji360, srt: srtByBase[base]) {
                    result.append(mf)
                }
            }
        }
        return result
    }

    // MARK: - Generic

    private func scanGeneric(root: URL) async throws -> [MediaFile] {
        let fm   = FileManager.default
        let exts = Set(["mp4", "mov", "avi", "jpg", "jpeg", "heic", "png",
                        "dng", "raw", "cr2", "cr3", "arw", "nef", "rw2",
                        "insv", "insp", "braw", "mp3"])
        var result: [MediaFile] = []

        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        for case let url as URL in enumerator {
            guard exts.contains(url.pathExtension.lowercased()) else { continue }
            if let mf = try? mediaFile(at: url, device: .generic) { result.append(mf) }
        }
        return result
    }

    // MARK: - MediaFile factory

    private func mediaFile(
        at url: URL,
        device: DeviceType,
        lrv: URL? = nil,
        srt: URL? = nil
    ) throws -> MediaFile {
        let res   = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let size  = Int64(res.fileSize ?? 0)
        let mdate = res.contentModificationDate ?? Date()
        return MediaFile(
            path: url,
            size: size,
            modificationDate: mdate,
            captureDate: exifCaptureDate(at: url),
            deviceType: device,
            companionLRV: lrv,
            companionSRT: srt
        )
    }

    // MARK: - EXIF date (ImageIO — available on iOS)

    private func exifCaptureDate(at url: URL) -> Date? {
        guard let src   = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        guard let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any] else { return nil }

        let exifDict = props[kCGImagePropertyExifDictionary as String] as? [String: Any]
        let tiffDict = props[kCGImagePropertyTIFFDictionary as String] as? [String: Any]
        let rawDate  = exifDict?[kCGImagePropertyExifDateTimeOriginal as String] as? String
                    ?? tiffDict?[kCGImagePropertyTIFFDateTime as String] as? String

        guard let raw = rawDate else { return nil }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy:MM:dd HH:mm:ss"
        fmt.locale     = Locale(identifier: "en_US_POSIX")
        return fmt.date(from: raw)
    }
}
