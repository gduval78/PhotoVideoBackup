import Foundation

// An empty temporary directory that acts as a backup destination.
// FileCopyEngine writes into it; expect() checks for file presence here.
final class SimulatedSSD {

    let name:    String
    let rootURL: URL

    init(name: String) {
        self.name = name
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("pvb_ssd_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        self.rootURL = tmp
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: rootURL)
    }

    // Returns true if a file exists at the given path relative to this SSD root.
    // Example: ssd.contains("DJI Mini 3 Pro/2024-01-14/DJI_0001.MP4")
    func contains(_ relativePath: String) -> Bool {
        FileManager.default.fileExists(
            atPath: rootURL.appendingPathComponent(relativePath).path
        )
    }
}
