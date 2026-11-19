package gduvalsc.pvb.core

import com.sun.net.httpserver.HttpExchange
import com.sun.net.httpserver.HttpServer
import java.io.File
import java.net.InetSocketAddress
import java.net.URLDecoder
import java.util.concurrent.CopyOnWriteArrayList

/**
 * In-process WebDAV server for tests (JDK `HttpServer`): PROPFIND / MKCOL / PUT / GET / DELETE / MOVE /
 * OPTIONS over a real temp directory, with switches for the failures a real server produces (413 body
 * limit, 401, 412 ignored, 301 on folders, offline, a chunk that fails once, a failing MOVE).
 * Port of the iOS `FakeWebDAVServer`.
 */
class FakeWebDavServer : AutoCloseable {
    val root: File = java.nio.file.Files.createTempDirectory("pvb_fake_dav").toFile()
    val requests = CopyOnWriteArrayList<Pair<String, String>>()
    @Volatile var expectedAuthorization: String? = null
    @Volatile var putStatusOverride: Int? = null
    @Volatile var ignoreIfNoneMatch = false
    @Volatile var redirectCollections = false
    @Volatile var chunkingCapability = true
    @Volatile var failChunkOnce: String? = null
    @Volatile var moveStatusOverride: Int? = null
    /** A PUT of this chunk name always answers 500. */
    @Volatile var failChunkAlways: String? = null
    /** DELETE is accepted but does nothing (an unreachable server leaves its upload folder behind). */
    @Volatile var ignoreDelete = false
    /** Answers every request with a redirect to another host. */
    @Volatile var redirectToOtherHost = false
    /** The Authorization header received by the last request that reached a handler. */
    @Volatile var lastAuthorization: String? = null

    private val server: HttpServer = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
    val baseUrl: String get() = "http://127.0.0.1:${server.address.port}"

    init {
        server.createContext("/") { ex -> try { handle(ex) } catch (e: Throwable) { runCatching { respond(ex, 500) } } finally { ex.close() } }
        server.executor = java.util.concurrent.Executors.newCachedThreadPool()
        server.start()
    }

    override fun close() { server.stop(0); root.deleteRecursively() }

    fun count(method: String) = requests.count { it.first == method }
    fun file(path: String): File = path.split('/').filter { it.isNotEmpty() }.fold(root) { f, c -> File(f, c) }

    private fun respond(ex: HttpExchange, status: Int, body: ByteArray = ByteArray(0), headers: Map<String, String> = emptyMap()) {
        headers.forEach { (k, v) -> ex.responseHeaders.add(k, v) }
        if (body.isEmpty()) ex.sendResponseHeaders(status, -1) else { ex.sendResponseHeaders(status, body.size.toLong()); ex.responseBody.write(body) }
    }

    private fun handle(ex: HttpExchange) {
        val method = ex.requestMethod
        val rawPath = ex.requestURI.rawPath
        val path = URLDecoder.decode(rawPath.replace("+", "%2B"), "UTF-8")
        requests += method to path
        lastAuthorization = ex.requestHeaders.getFirst("Authorization")
        val bodyBytes = ex.requestBody.readBytes()
        if (redirectToOtherHost) return respond(ex, 301, headers = mapOf("Location" to "http://localhost:1/elsewhere"))
        expectedAuthorization?.let { if (ex.requestHeaders.getFirst("Authorization") != it) return respond(ex, 401) }
        if (path == "/ocs/v1.php/cloud/capabilities") {
            val b = if (chunkingCapability) """{"ocs":{"data":{"capabilities":{"dav":{"chunking":"1.0"}}}}}""" else """{"ocs":{"data":{"capabilities":{"dav":{}}}}}"""
            return respond(ex, 200, b.toByteArray())
        }
        val target = file(path)
        val exists = target.exists()
        val isDir = target.isDirectory
        val parentExists = target.parentFile?.exists() ?: true

        if (redirectCollections && exists && isDir && !path.endsWith("/") && method in setOf("PROPFIND", "MKCOL", "DELETE")) {
            return respond(ex, 301, headers = mapOf("Location" to "$baseUrl$rawPath/"))
        }
        when (method) {
            "OPTIONS" -> respond(ex, 200)
            "MKCOL" -> if (exists) respond(ex, 405) else if (!parentExists) respond(ex, 409) else { target.mkdir(); respond(ex, 201) }
            "PUT" -> {
                val fail = failChunkOnce
                if (fail != null && path.endsWith("/$fail")) { failChunkOnce = null; ex.close(); return }
                if (failChunkAlways?.let { path.endsWith("/$it") } == true) return respond(ex, 500)
                putStatusOverride?.let { return respond(ex, it) }
                if (ex.requestHeaders.getFirst("If-None-Match") == "*" && exists && !ignoreIfNoneMatch) return respond(ex, 412)
                if (!parentExists) return respond(ex, 409)
                target.writeBytes(bodyBytes)
                respond(ex, if (exists) 204 else 201)
            }
            "GET" -> if (!exists || isDir) respond(ex, 404) else respond(ex, 200, target.readBytes())
            "MOVE" -> {
                if (!path.endsWith("/.file")) return respond(ex, 405)
                moveStatusOverride?.let { return respond(ex, it) }
                val dir = target.parentFile
                val dest = ex.requestHeaders.getFirst("Destination")?.let { file(URLDecoder.decode(java.net.URI(it).rawPath.replace("+", "%2B"), "UTF-8")) } ?: return respond(ex, 400)
                if (ex.requestHeaders.getFirst("Overwrite") == "F" && dest.exists()) return respond(ex, 412)
                val assembled = java.io.ByteArrayOutputStream()
                dir.listFiles()!!.filter { it.name != ".file" }.sortedBy { it.name }.forEach { assembled.write(it.readBytes()) }
                if (assembled.size().toString() != ex.requestHeaders.getFirst("OC-Total-Length")) return respond(ex, 400)
                if (!dest.parentFile.exists()) return respond(ex, 409)
                dest.writeBytes(assembled.toByteArray()); dir.deleteRecursively()
                respond(ex, 201)
            }
            "DELETE" -> if (ignoreDelete) respond(ex, 204) else if (!exists) respond(ex, 404) else { target.deleteRecursively(); respond(ex, 204) }
            "PROPFIND" -> {
                if (!exists) return respond(ex, 404)
                val depth = ex.requestHeaders.getFirst("Depth") ?: "1"
                val items = ArrayList<Pair<String, File>>().apply { add(path to target) }
                if (isDir && depth != "0") target.listFiles()!!.sortedBy { it.name }.forEach { items += ((if (path.endsWith("/")) path else "$path/") + it.name) to it }
                respond(ex, 207, multistatus(items).toByteArray())
            }
            else -> respond(ex, 405)
        }
    }

    private fun multistatus(items: List<Pair<String, File>>): String {
        val sb = StringBuilder("""<?xml version="1.0"?><d:multistatus xmlns:d="DAV:">""")
        for ((path, f) in items) {
            val href = path.split('/').joinToString("/") { WebDavTarget.encode(it) } + if (f.isDirectory && !path.endsWith("/")) "/" else ""
            sb.append("<d:response><d:href>$href</d:href><d:propstat><d:prop>")
            sb.append(if (f.isDirectory) "<d:resourcetype><d:collection/></d:resourcetype>" else "<d:resourcetype/><d:getcontentlength>${f.length()}</d:getcontentlength>")
            sb.append("</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>")
        }
        return sb.append("</d:multistatus>").toString()
    }
}
