import Foundation

actor ReportBuilder {

    static let shared = ReportBuilder()

    private let reportsDir: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("PhotoVideoBackup/Reports", isDirectory: true)
    }()

    private init() {}

    // MARK: - Public API

    @discardableResult
    func generate(for session: BackupSession) async throws -> (json: URL, html: URL) {
        let report = try await buildReport(for: session)
        let jsonURL = try writeJSON(report: report)
        let htmlURL = try writeHTML(report: report)
        return (jsonURL, htmlURL)
    }

    func reportHTMLURL(for session: BackupSession) -> URL? {
        let fm  = FileManager.default
        let dir = reportsDir
        let name = "session_\(session.id)"
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return nil }
        return files.first { $0.lastPathComponent.hasPrefix(name) && $0.pathExtension == "html" }
    }

    // MARK: - Assembly

    private func buildReport(for session: BackupSession) async throws -> SessionReport {
        let files   = session.files
        let copied  = files.filter { $0.copyStatus == .copied }
        let skipped = files.filter { $0.copyStatus == .skipped }
        let failed  = files.filter { $0.copyStatus == .failed }
        let totalBytes = copied.reduce(Int64(0)) { $0 + $1.fileSize }
        let duration   = (session.completedAt ?? Date()).timeIntervalSince(session.startedAt)

        return SessionReport(
            sessionID: session.id,
            generatedAt: Date(),
            summary: SessionReport.Summary(
                totalScanned: files.count,
                copiedCount: copied.count,
                skippedCount: skipped.count,
                failedCount: failed.count,
                totalBytesCopied: totalBytes,
                durationSeconds: duration,
                incompleteMirror: session.incompleteMirror
            ),
            copiedFiles: copied.map {
                SessionReport.ReportEntry(
                    fileName: $0.fileName, sourcePath: $0.sourcePath,
                    destinationPaths: $0.destinationPaths, sha256: $0.sha256,
                    fileSizeBytes: $0.fileSize, captureDate: $0.captureDate,
                    sourceDevice: $0.sourceDevice
                )
            },
            skippedFiles: skipped.map {
                SessionReport.SkippedEntry(
                    fileName: $0.fileName, sourcePath: $0.sourcePath,
                    sha256: $0.sha256, reason: "Already present on SSD (size match)"
                )
            },
            failedFiles: failed.map {
                SessionReport.FailedEntry(
                    fileName: $0.fileName, sourcePath: $0.sourcePath,
                    error: $0.verificationPassed == false
                        ? "SHA-256 verification failed"
                        : "I/O error during copy"
                )
            },
            missingFiles: []
        )
    }

    // MARK: - JSON

    private func writeJSON(report: SessionReport) throws -> URL {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(report)
        let url  = reportURL(for: report, ext: "json")
        try FileManager.default.createDirectory(at: reportsDir, withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - HTML

    private func writeHTML(report: SessionReport) throws -> URL {
        let html = buildHTML(report: report)
        let url  = reportURL(for: report, ext: "html")
        try FileManager.default.createDirectory(at: reportsDir, withIntermediateDirectories: true)
        try html.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func buildHTML(report: SessionReport) -> String {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium; fmt.timeStyle = .medium

        func byteStr(_ b: Int64) -> String {
            ByteCountFormatter.string(fromByteCount: b, countStyle: .file)
        }
        func row(_ cells: [String]) -> String {
            "<tr>" + cells.map { "<td>\($0)</td>" }.joined() + "</tr>"
        }

        let s = report.summary
        var html = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>PhotoVideoBackup — \(report.sessionID)</title>
          <style>
            body { font-family: -apple-system, sans-serif; margin: 1em; color: #1c1c1e; }
            h1 { color: #007aff; font-size: 1.3em; }
            h2 { border-bottom: 1px solid #e5e5ea; padding-bottom: .3em; font-size: 1.1em; }
            table { border-collapse: collapse; width: 100%; font-size: .85em; margin-bottom: 1.5em; }
            th, td { border: 1px solid #d1d1d6; padding: .4em .6em; text-align: left; }
            th { background: #f2f2f7; }
            .ok { color: #34c759; } .fail { color: #ff3b30; } .skip { color: #ff9500; }
            .mono { font-family: monospace; font-size: .8em; word-break: break-all; }
          </style>
        </head>
        <body>
        <h1>PhotoVideoBackup — Session Report</h1>
        <p><strong>Session ID:</strong> \(report.sessionID)<br>
        <strong>Generated:</strong> \(fmt.string(from: report.generatedAt))</p>

        <h2>Summary</h2>
        <table>
          <tr><th>Files scanned</th><td>\(s.totalScanned)</td></tr>
          <tr><th>Copied</th><td class="ok">\(s.copiedCount)</td></tr>
          <tr><th>Skipped (already present)</th><td class="skip">\(s.skippedCount)</td></tr>
          <tr><th>Failed</th><td class="fail">\(s.failedCount)</td></tr>
          <tr><th>Total data copied</th><td>\(byteStr(s.totalBytesCopied))</td></tr>
          <tr><th>Duration</th><td>\(String(format: "%.1f s", s.durationSeconds))</td></tr>
          <tr><th>Incomplete mirror</th><td>\(s.incompleteMirror ? "⚠️ Yes" : "No")</td></tr>
        </table>
        """

        if !report.copiedFiles.isEmpty {
            html += "<h2>Copied (\(report.copiedFiles.count))</h2>"
            html += "<table><tr><th>File</th><th>Size</th><th>Date</th><th>SHA-256</th></tr>"
            let df = DateFormatter(); df.dateStyle = .short; df.timeStyle = .none
            for f in report.copiedFiles {
                let date = f.captureDate.map { df.string(from: $0) } ?? "—"
                html += row([f.fileName, byteStr(f.fileSizeBytes), date,
                             "<span class='mono'>\(f.sha256.prefix(16))…</span>"])
            }
            html += "</table>"
        }

        if !report.skippedFiles.isEmpty {
            html += "<h2>Skipped — already present (\(report.skippedFiles.count))</h2>"
            html += "<table><tr><th>File</th><th>Reason</th></tr>"
            for f in report.skippedFiles { html += row([f.fileName, f.reason]) }
            html += "</table>"
        }

        if !report.failedFiles.isEmpty {
            html += "<h2 class='fail'>Failed (\(report.failedFiles.count))</h2>"
            html += "<table><tr><th>File</th><th>Error</th></tr>"
            for f in report.failedFiles { html += row([f.fileName, f.error]) }
            html += "</table>"
        }

        html += "</body></html>"
        return html
    }

    private func reportURL(for report: SessionReport, ext: String) -> URL {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd_HHmmss"
        let dateStr  = fmt.string(from: report.generatedAt)
        let filename = "session_\(report.sessionID)_\(dateStr).\(ext)"
        return reportsDir.appendingPathComponent(filename)
    }
}
