import Foundation
import UIKit

/// Lightweight append-only diagnostic logger.
/// Writes are serialized on a background queue — callers never block.
/// The file lives in Documents/ so it survives app updates and can be shared via Files app.
enum DiagnosticLog {

    private static let queue    = DispatchQueue(label: "pvb.diagnostic-log", qos: .utility)
    private static let maxLines = 1000
    /// Guards `[UI_READY]` so it is written only once per launch. Only touched on `queue`.
    private static var uiReadyLogged = false
    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static var logURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("pvb_diagnostic.log")
    }

    /// Appends one timestamped line. Safe to call from any thread or actor context.
    static func write(_ message: String) {
        queue.async {
            append("[\(formatter.string(from: Date()))] \(message)\n")
        }
    }

    /// Call once at launch — trims to `maxLines`, then writes device + OS + version + environment.
    static func pruneAndMarkLaunch(appVersion: String) {
        queue.async {
            let url = logURL
            if let content = try? String(contentsOf: url, encoding: .utf8) {
                let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
                if lines.count > maxLines {
                    let trimmed = lines.suffix(maxLines).joined(separator: "\n") + "\n"
                    try? trimmed.write(to: url, atomically: true, encoding: .utf8)
                }
            }
            let device = UIDevice.current
            let model  = Self.deviceModel()
            append("[\(formatter.string(from: Date()))] [LAUNCH] v\(appVersion) | \(model) | iOS \(device.systemVersion) | \(envSnapshot())\n")
        }
    }

    /// Writes `[UI_READY]` exactly once, the first time the UI renders.
    /// Distinguishes a clean launch (this line present) from an early crash
    /// (log stops at `[LAUNCH]` with no `[UI_READY]` after it).
    static func markUIReady() {
        queue.async {
            guard !uiReadyLogged else { return }
            uiReadyLogged = true
            append("[\(formatter.string(from: Date()))] [UI_READY] \(envSnapshot())\n")
        }
    }

    /// Registers process-lifetime observers for lifecycle, memory, thermal,
    /// power-state and data-protection events. Call once in `App.init()`.
    /// Observers are never removed (they live for the whole process).
    static func installObservers() {
        let nc   = NotificationCenter.default
        let main = OperationQueue.main
        nc.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: main) { _ in
            write("[MEMORY_WARNING] iOS signaled low memory — \(envSnapshot())")
        }
        nc.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: main) { _ in
            write("[LIFECYCLE] background — \(memoryTag)")
        }
        nc.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: main) { _ in
            write("[LIFECYCLE] foreground — \(memoryTag)")
        }
        nc.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: main) { _ in
            write("[LIFECYCLE] terminate")
        }
        nc.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: main) { _ in
            write("[THERMAL] changed — \(envSnapshot())")
        }
        nc.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: main) { _ in
            write("[POWER] lowPowerMode=\(ProcessInfo.processInfo.isLowPowerModeEnabled ? "on" : "off")")
        }
        nc.addObserver(forName: UIApplication.protectedDataWillBecomeUnavailableNotification, object: nil, queue: main) { _ in
            write("[DATA_PROTECTION] unavailable (device locked)")
        }
        nc.addObserver(forName: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil, queue: main) { _ in
            write("[DATA_PROTECTION] available (device unlocked)")
        }
    }

    // MARK: - System metrics (cheap, side-effect-free — safe to call from any context)

    /// Compact one-liner: used/total RAM, free disk, thermal state, low-power, language.
    static func envSnapshot() -> String {
        let pi = ProcessInfo.processInfo
        let ram = Int(pi.physicalMemory / (1024 * 1024))
        let thermal: String
        switch pi.thermalState {
        case .nominal:  thermal = "nominal"
        case .fair:     thermal = "fair"
        case .serious:  thermal = "serious"
        case .critical: thermal = "critical"
        @unknown default: thermal = "?"
        }
        // Phone language (system) + any in-app override (LanguageManager persists to "appLanguage";
        // empty/nil = follows the system). Report both so support can reply in the user's language.
        let sysLang     = Locale.preferredLanguages.first ?? "?"
        let appOverride = UserDefaults.standard.string(forKey: "appLanguage")
        let appLang     = (appOverride?.isEmpty ?? true) ? "auto" : appOverride!
        return "mem=\(memoryFootprintMB())/\(ram)MB disk=\(freeDiskMB())MB thermal=\(thermal) lowpower=\(pi.isLowPowerModeEnabled ? "on" : "off") lang=\(sysLang) applang=\(appLang)"
    }

    /// Very compact memory tag for high-frequency lines (e.g. `[PROGRESS]`).
    static var memoryTag: String {
        "mem=\(memoryFootprintMB())/\(Int(ProcessInfo.processInfo.physicalMemory / (1024 * 1024)))MB"
    }

    /// Current app memory footprint in MB (`phys_footprint` — what iOS jetsam watches). -1 on failure.
    static func memoryFootprintMB() -> Int {
        var info  = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.stride / MemoryLayout<natural_t>.stride)
        let kerr = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), intPtr, &count)
            }
        }
        guard kerr == KERN_SUCCESS else { return -1 }
        return Int(info.phys_footprint) / (1024 * 1024)
    }

    /// Free disk space available for important usage, in MB. -1 on failure.
    static func freeDiskMB() -> Int {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        if let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let capacity = values.volumeAvailableCapacityForImportantUsage {
            return Int(capacity / (1024 * 1024))
        }
        return -1
    }

    // MARK: - Internal

    private static func append(_ line: String) {
        guard let data = line.data(using: .utf8) else { return }
        let url = logURL
        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(data)
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Returns a compact device model string (e.g. "iPhone16,2").
    private static func deviceModel() -> String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { buf in
            buf.compactMap { $0 == 0 ? nil : Character(UnicodeScalar($0)) }
               .map(String.init)
               .joined()
        }
    }
}
