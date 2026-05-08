import Foundation

// A minimal file to place on a simulated peripheral.
// Content is fixed bytes — no real media metadata, but real size and date.
struct TestFile {
    let name:        String
    let sizeInBytes: Int
    let date:        Date

    func write(to folder: URL) throws {
        let url  = folder.appendingPathComponent(name)
        let data = Data(repeating: 0xAB, count: sizeInBytes)
        try data.write(to: url)
        try FileManager.default.setAttributes(
            [.modificationDate: date],
            ofItemAtPath: url.path
        )
    }
}

// Fixed reference date shared across all scenarios.
// Ensures expected destination paths are fully deterministic.
extension Date {
    static let scenarioDefault: Date = {
        var c = DateComponents()
        c.year = 2024; c.month = 1; c.day = 14
        c.hour = 10; c.minute = 0; c.second = 0
        c.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: c)!
    }()
}
