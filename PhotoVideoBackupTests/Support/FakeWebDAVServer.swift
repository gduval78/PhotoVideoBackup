import Foundation

/// In-process WebDAV server for tests: a `URLProtocol` that serves PROPFIND / MKCOL / PUT / GET / DELETE /
/// OPTIONS over a real temp directory, with switches for the failures a real server produces
/// (413 body limit, 401, 412 ignored, offline). No network, no live server.
final class FakeWebDAVServer: URLProtocol {

    // MARK: Shared state (tests run serially inside one class)

    nonisolated(unsafe) static var root: URL = FileManager.default.temporaryDirectory
    nonisolated(unsafe) static var requests: [(method: String, path: String)] = []
    nonisolated(unsafe) static var expectedAuthorization: String?
    nonisolated(unsafe) static var putStatusOverride: Int?
    nonisolated(unsafe) static var ignoreIfNoneMatch = false
    nonisolated(unsafe) static var offline = false
    private static let lock = NSLock()

    /// Fresh empty tree; returns a session that routes every request to this server.
    static func start() -> URLSession {
        lock.lock(); defer { lock.unlock() }
        root = FileManager.default.temporaryDirectory.appendingPathComponent("pvb_fake_dav_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        requests = []; expectedAuthorization = nil; putStatusOverride = nil
        ignoreIfNoneMatch = false; offline = false
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FakeWebDAVServer.self]
        return URLSession(configuration: config)
    }

    static func stop() { try? FileManager.default.removeItem(at: root) }

    static func count(of method: String) -> Int { requests.filter { $0.method == method }.count }

    static func fileURL(_ path: String) -> URL {
        path.split(separator: "/").reduce(root) { $0.appendingPathComponent(String($1)) }
    }

    // MARK: URLProtocol

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let url = request.url else { return }
        if Self.offline {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)); return
        }
        let method = request.httpMethod ?? "GET"
        let path = url.path
        Self.requests.append((method, path))

        if let expected = Self.expectedAuthorization, request.value(forHTTPHeaderField: "Authorization") != expected {
            return respond(401)
        }
        let target = Self.fileURL(path)
        let fm = FileManager.default
        var isDir: ObjCBool = false
        let exists = fm.fileExists(atPath: target.path, isDirectory: &isDir)
        let parentExists = fm.fileExists(atPath: target.deletingLastPathComponent().path)

        switch method {
        case "OPTIONS":
            respond(200)
        case "MKCOL":
            if exists { respond(405) }
            else if !parentExists { respond(409) }
            else { try? fm.createDirectory(at: target, withIntermediateDirectories: false); respond(201) }
        case "PUT":
            if let forced = Self.putStatusOverride { return respond(forced) }
            if request.value(forHTTPHeaderField: "If-None-Match") == "*", exists, !Self.ignoreIfNoneMatch { return respond(412) }
            guard parentExists else { return respond(409) }
            try? body().write(to: target)
            respond(exists ? 204 : 201)
        case "GET":
            guard exists, !isDir.boolValue, let data = try? Data(contentsOf: target) else { return respond(404) }
            respond(200, body: data)
        case "DELETE":
            guard exists else { return respond(404) }
            try? fm.removeItem(at: target); respond(204)
        case "PROPFIND":
            guard exists else { return respond(404) }
            let depth = request.value(forHTTPHeaderField: "Depth") ?? "1"
            var items = [(path, target, isDir.boolValue)]
            if isDir.boolValue, depth != "0",
               let names = try? fm.contentsOfDirectory(atPath: target.path).sorted() {
                for n in names {
                    var d: ObjCBool = false
                    let child = target.appendingPathComponent(n)
                    fm.fileExists(atPath: child.path, isDirectory: &d)
                    items.append(((path.hasSuffix("/") ? path : path + "/") + n, child, d.boolValue))
                }
            }
            respond(207, body: Self.multistatus(items))
        default:
            respond(405)
        }
    }

    // MARK: Helpers

    private func body() -> Data {
        if let b = request.httpBody { return b }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            if n <= 0 { break }
            data.append(buffer, count: n)
        }
        return data
    }

    private func respond(_ status: Int, body: Data = Data()) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !body.isEmpty { client?.urlProtocol(self, didLoad: body) }
        client?.urlProtocolDidFinishLoading(self)
    }

    private static func multistatus(_ items: [(String, URL, Bool)]) -> Data {
        var xml = #"<?xml version="1.0"?><d:multistatus xmlns:d="DAV:">"#
        for (path, url, isDir) in items {
            let href = path.split(separator: "/", omittingEmptySubsequences: false)
                .map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
                .joined(separator: "/") + (isDir && !path.hasSuffix("/") ? "/" : "")
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            xml += "<d:response><d:href>\(href)</d:href><d:propstat><d:prop>"
            xml += isDir ? "<d:resourcetype><d:collection/></d:resourcetype>"
                         : "<d:resourcetype/><d:getcontentlength>\(size)</d:getcontentlength>"
            xml += "</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>"
        }
        return Data((xml + "</d:multistatus>").utf8)
    }
}
