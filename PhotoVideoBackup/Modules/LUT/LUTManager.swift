import Foundation
import CoreImage

// MARK: - LUTFile

struct LUTFile: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let url: URL

    init(url: URL) {
        self.id   = UUID()
        self.url  = url
        self.name = url.deletingPathExtension().lastPathComponent
    }

    func hash(into hasher: inout Hasher) { hasher.combine(url) }
    static func == (lhs: LUTFile, rhs: LUTFile) -> Bool { lhs.url == rhs.url }
}

// MARK: - ParsedLUT

struct ParsedLUT: Sendable {
    let name: String
    let size: Int
    let cubeData: Data

    func apply(to image: CIImage) -> CIImage? {
        guard let cs = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let filter = CIFilter(name: "CIColorCubeWithColorSpace")
        filter?.setValue(size,     forKey: "inputCubeDimension")
        filter?.setValue(cubeData, forKey: "inputCubeData")
        filter?.setValue(cs,       forKey: "inputColorSpace")
        filter?.setValue(image,    forKey: kCIInputImageKey)
        return filter?.outputImage
    }
}

// MARK: - LUTStore

@Observable
@MainActor
final class LUTStore {
    static let shared = LUTStore()

    private(set) var files: [LUTFile] = []

    private var lutDirectory: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LUTs", isDirectory: true)
    }

    private init() { refresh() }

    func refresh() {
        let fm = FileManager.default
        try? fm.createDirectory(at: lutDirectory, withIntermediateDirectories: true)
        let cubes = (try? fm.contentsOfDirectory(
            at: lutDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ))?.filter { $0.pathExtension.lowercased() == "cube" } ?? []
        files = cubes.map { LUTFile(url: $0) }.sorted { $0.name < $1.name }
    }

    func importLUT(from source: URL) throws {
        let dest = lutDirectory.appendingPathComponent(source.lastPathComponent)
        let fm = FileManager.default
        if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
        try fm.copyItem(at: source, to: dest)
        refresh()
    }

    func delete(_ lut: LUTFile) {
        try? FileManager.default.removeItem(at: lut.url)
        refresh()
    }

    /// Parse a .cube file on any thread — no actor isolation required.
    nonisolated static func parseCube(at url: URL) throws -> ParsedLUT {
        let text = try String(contentsOf: url, encoding: .utf8)
        return try parseCube(text: text, name: url.deletingPathExtension().lastPathComponent)
    }

    nonisolated static func parseCube(text: String, name: String) throws -> ParsedLUT {
        var size    = 0
        var entries = [Float]()

        for line in text.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty || t.hasPrefix("#")      { continue }
            if t.hasPrefix("LUT_3D_SIZE") {
                size = Int(t.components(separatedBy: .whitespaces).last ?? "") ?? 0
                continue
            }
            if t.hasPrefix("DOMAIN_") || t.hasPrefix("TITLE") { continue }
            let p = t.components(separatedBy: .whitespaces)
            guard p.count >= 3,
                  let r = Float(p[0]), let g = Float(p[1]), let b = Float(p[2])
            else { continue }
            entries.append(r); entries.append(g); entries.append(b); entries.append(1.0)
        }

        guard size > 0, entries.count == size * size * size * 4 else {
            throw LUTError.invalidFormat
        }
        let data = entries.withUnsafeBytes { Data($0) }
        return ParsedLUT(name: name, size: size, cubeData: data)
    }
}

// MARK: - LUTError

enum LUTError: LocalizedError {
    case invalidFormat
    var errorDescription: String? { "The .cube file format is invalid or unsupported." }
}
