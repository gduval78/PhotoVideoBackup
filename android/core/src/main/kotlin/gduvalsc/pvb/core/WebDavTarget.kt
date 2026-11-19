package gduvalsc.pvb.core

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.Headers
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import okio.BufferedSink
import okio.source
import java.io.File
import java.io.FileNotFoundException
import java.io.InputStream
import java.io.OutputStream
import java.io.RandomAccessFile
import java.net.URI
import java.net.UnknownHostException
import java.security.MessageDigest
import java.security.cert.CertificateException
import java.security.cert.X509Certificate
import java.util.concurrent.TimeUnit
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLException
import javax.net.ssl.TrustManager
import javax.net.ssl.TrustManagerFactory
import javax.net.ssl.X509TrustManager

/** Why a WebDAV request failed, as something the user can act on. */
class WebDavException(val kind: Kind, val status: Int = 0, message: String? = null) : java.io.IOException(message ?: kind.name) {
    enum class Kind {
        /** 401 / 403 — wrong credentials (with two-factor authentication an app password is needed). */
        UNAUTHORIZED,
        /** 412 on a `PUT` with `If-None-Match: *` — the name is taken by another file; never overwritten. */
        ALREADY_EXISTS,
        /** 413 (or a body refused by a proxy) — a size limit at the server or a proxy. */
        TOO_LARGE,
        /** 429 / 503 — the server asks us to slow down. */
        RATE_LIMITED,
        UNTRUSTED_CERTIFICATE,
        /** A certificate was trusted earlier and the server now presents another one. */
        CERTIFICATE_CHANGED,
        /** 301 / 302 / 307 / 308 that was not followed: the address answers from somewhere else. */
        REDIRECTED,
        HTTP,
        INVALID_RESPONSE,
    }

    companion object {
        /** Maps an HTTP status to an error, or null when it is a success for a write. */
        fun forWrite(status: Int): WebDavException? = when (status) {
            in 200..299 -> null
            401, 403 -> WebDavException(Kind.UNAUTHORIZED, status)
            412 -> WebDavException(Kind.ALREADY_EXISTS, status)
            413 -> WebDavException(Kind.TOO_LARGE, status)
            429, 503 -> WebDavException(Kind.RATE_LIMITED, status)
            301, 302, 307, 308 -> WebDavException(Kind.REDIRECTED, status)
            else -> WebDavException(Kind.HTTP, status, "HTTP $status")
        }
    }
}

/**
 * Trust decisions for a server's TLS certificate. A user can trust one certificate of a server they run
 * themselves (self-signed Nextcloud, Synology…): its SHA-256 is stored with the backup, and from then on
 * **only that exact certificate** is accepted — never "trust everything".
 */
object WebDavTrust {
    fun fingerprint(der: ByteArray): String = MessageDigest.getInstance("SHA-256").digest(der).toHex()

    /** "AB:CD:EF…" for display. */
    fun displayFingerprint(hex: String): String = hex.uppercase().chunked(2).joinToString(":")

    /** With a pin the presented certificate must be exactly that one; without, the system decides (null). */
    fun accepts(pin: String?, presented: String?): Boolean? {
        if (pin.isNullOrEmpty()) return null
        return presented?.lowercase() == pin.lowercase()
    }

    /** The system's trust manager. */
    private fun systemTrustManager(): X509TrustManager {
        val f = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm())
        f.init(null as java.security.KeyStore?)
        return f.trustManagers.filterIsInstance<X509TrustManager>().first()
    }

    /** Applies the pin (when there is one) to the server's certificate chain; remembers a mismatch. */
    class PinningTrustManager(private val pin: String?) : X509TrustManager {
        @Volatile var mismatch = false
        private val system by lazy { systemTrustManager() }

        override fun checkClientTrusted(chain: Array<X509Certificate>, authType: String) = system.checkClientTrusted(chain, authType)

        override fun checkServerTrusted(chain: Array<X509Certificate>, authType: String) {
            val verdict = accepts(pin, chain.firstOrNull()?.let { fingerprint(it.encoded) })
            when (verdict) {
                null -> system.checkServerTrusted(chain, authType)
                true -> {}
                false -> { mismatch = true; throw CertificateException("The server certificate is not the trusted one") }
            }
        }

        override fun getAcceptedIssuers(): Array<X509Certificate> = system.acceptedIssuers
    }

    /**
     * Reads the certificate a server presents, **without sending anything**: the handshake is made and the
     * connection closed. Used by *Test connection* after an untrusted-certificate error. Null if unreachable.
     */
    fun presentedFingerprint(host: String, port: Int = 443, timeoutMs: Int = 15_000): String? {
        var seen: String? = null
        val tm = object : X509TrustManager {
            override fun checkClientTrusted(chain: Array<X509Certificate>, authType: String) {}
            override fun checkServerTrusted(chain: Array<X509Certificate>, authType: String) { seen = chain.firstOrNull()?.let { fingerprint(it.encoded) } }
            override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()
        }
        return runCatching {
            val ctx = SSLContext.getInstance("TLS").apply { init(null, arrayOf<TrustManager>(tm), null) }
            (ctx.socketFactory.createSocket() as javax.net.ssl.SSLSocket).use { s ->
                s.soTimeout = timeoutMs
                s.connect(java.net.InetSocketAddress(host, port), timeoutMs)
                s.startHandshake()
            }
            seen
        }.getOrNull() ?: seen
    }

    /** True for the failures that mean "the certificate is not acceptable". */
    fun isCertificateError(e: Throwable): Boolean {
        var t: Throwable? = e
        while (t != null) {
            if (t is CertificateException || t is javax.net.ssl.SSLPeerUnverifiedException || t is javax.net.ssl.SSLHandshakeException) return true
            t = t.cause
        }
        return false
    }
}

/**
 * Backup target on a WebDAV server (Nextcloud, ownCloud, Synology/QNAP WebDAV, Hetzner Storage Box,
 * pCloud's WebDAV…) over HTTP(S), through OkHttp. The port of the iOS `WebDAVTarget`.
 *
 * Path model: [serverUrl] is the WebDAV root the user typed (`https://cloud.example.com/remote.php/dav/files/me/`),
 * [basePath] a folder under it. Every path component is percent-encoded **individually**.
 *
 * Rules shared with the SMB target: a different file is **never overwritten** (`PUT` with
 * `If-None-Match: *`; a 412 surfaces as [WebDavException.Kind.ALREADY_EXISTS], and a delete only removes
 * what this run wrote), verification re-downloads the file and hashes it, an unreachable server is
 * "offline" and never an empty one. The engine streams into [openOutput]; the bytes are spooled to a temp
 * file and sent when the stream is closed (HTTP needs the length, and a chunked upload needs the file).
 */
class WebDavTarget(
    serverUrl: String,
    basePath: String,
    private val user: String,
    private val password: String,
    private val label: String,
    private val tempDir: File = File(System.getProperty("java.io.tmpdir")),
    chunking: Boolean? = null,
    pinnedCertificate: String? = null,
    private val chunkThreshold: Long = DEFAULT_CHUNK_THRESHOLD,
    private val chunkSize: Int = DEFAULT_CHUNK_SIZE,
    client: OkHttpClient? = null,
) : BrowsableTarget {

    private val root: String = serverUrl.trim().trimEnd('/')
    private val base: String = basePath.trim('/', ' ')
    private val trust = WebDavTrust.PinningTrustManager(pinnedCertificate)
    private val http: OkHttpClient = client ?: buildClient(trust, pinnedCertificate)

    @Volatile private var chunking: Boolean? = chunking
    private val createdFolders = HashSet<String>()
    private val writtenByUs = HashSet<String>()
    private val lock = Any()

    override val isRemote: Boolean = true
    override val displayName: String = label

    /** "webdav://host[:port]/<server path>/<basePath>" — stable prefix stored in the index. */
    override val rootIdentifier: String
        get() {
            val u = URI(root)
            var s = "webdav://" + (u.host ?: "")
            if (u.port != -1) s += ":${u.port}"
            val serverPath = (u.rawPath ?: "").trim('/')
            if (serverPath.isNotEmpty()) s += "/$serverPath"
            if (base.isNotEmpty()) s += "/$base"
            return s
        }

    override fun absolutePath(rel: String): String = "$rootIdentifier/$rel"

    // MARK: Paths

    /** Full URL for an engine-relative path (`rel` may contain `/`). */
    fun url(rel: String, folder: Boolean = false): String {
        val sb = StringBuilder(root)
        for (c in "$base/$rel".split('/')) if (c.isNotEmpty()) sb.append('/').append(encode(c))
        if (folder) sb.append('/')
        return sb.toString()
    }

    private fun urlOfComponents(comps: List<String>): String {
        val sb = StringBuilder(root)
        for (c in comps) sb.append('/').append(encode(c))
        return sb.append('/').toString()   // a collection is addressed with a trailing slash (Apache-based servers answer 301 otherwise)
    }

    // MARK: HTTP

    private fun request(method: String, url: String, headers: Map<String, String> = emptyMap(), body: RequestBody? = null): Request {
        val b = Request.Builder().url(url).method(method, body ?: if (method in setOf("PUT", "POST", "PROPFIND", "PROPPATCH")) ByteArray(0).toRequestBody(null) else null)
            .header("Authorization", okhttp3.Credentials.basic(user, password, Charsets.UTF_8))
        for ((k, v) in headers) b.header(k, v)
        return b.build()
    }

    /**
     * Sends [req]. A redirect on the same server (pCloud and Apache answer 301 for a folder asked without
     * its trailing slash) is followed **with the original method, headers and body**; a redirect to another
     * host is not followed and is returned as is.
     */
    private fun send(req: Request, call: OkHttpClient = http): Response {
        var current = req
        repeat(5) {
            val response = try { call.newCall(current).execute() } catch (e: Exception) { throw mapped(e) }
            val code = response.code
            if (code in setOf(301, 302, 307, 308)) {
                val location = response.header("Location")?.let { runCatching { current.url.resolve(it) }.getOrNull() }
                if (location != null && location.host == current.url.host && location.scheme == current.url.scheme) {
                    response.close()
                    current = current.newBuilder().url(location).build()
                    return@repeat
                }
            }
            return response
        }
        throw WebDavException(WebDavException.Kind.REDIRECTED, 301)
    }

    /** Reads a failure as the reason the user can act on (untrusted / changed certificate). */
    fun mapped(e: Exception): Exception = when {
        e is WebDavException -> e
        trust.mismatch -> WebDavException(WebDavException.Kind.CERTIFICATE_CHANGED)
        e is SSLException && WebDavTrust.isCertificateError(e) -> WebDavException(WebDavException.Kind.UNTRUSTED_CERTIFICATE)
        WebDavTrust.isCertificateError(e) -> WebDavException(WebDavException.Kind.UNTRUSTED_CERTIFICATE)
        else -> e
    }

    private inline fun <T> Response.useStatus(block: (Int) -> T): T = use { block(it.code) }

    private fun check(response: Response) {
        val err = WebDavException.forWrite(response.code)
        if (err != null) { response.close(); throw err }
    }

    // MARK: Existence / size

    private fun propfind(url: String, depth: Int): Pair<Int, List<WebDavEntry>> {
        val body = PROPFIND_BODY.toRequestBody("application/xml".toMediaTypeOrNull())
        send(request("PROPFIND", url, mapOf("Depth" to "$depth"), body)).use { r ->
            val bytes = if (r.code == 207) r.body?.bytes() ?: ByteArray(0) else ByteArray(0)
            return r.code to (if (r.code == 207) WebDavMultiStatus.parse(bytes) else emptyList())
        }
    }

    override suspend fun existingSize(rel: String): Long? = runCatching {
        val (code, entries) = propfind(url(rel), 0)
        entries.firstOrNull()?.takeIf { code == 207 && !it.isCollection }?.size
    }.getOrNull()

    // MARK: Reading

    override suspend fun openInput(rel: String): InputStream {
        val r = send(request("GET", url(rel)))
        if (r.code == 404) { r.close(); throw FileNotFoundException(rel) }
        check(r)
        val stream = r.body?.byteStream() ?: run { r.close(); throw WebDavException(WebDavException.Kind.INVALID_RESPONSE) }
        return object : InputStream() {
            override fun read(): Int = stream.read()
            override fun read(b: ByteArray, off: Int, len: Int): Int = stream.read(b, off, len)
            override fun close() { try { stream.close() } finally { r.close() } }
        }
    }

    override suspend fun readSmallFile(rel: String): ByteArray? = runCatching {
        send(request("GET", url(rel))).use { if (it.code == 200) it.body?.bytes() else null }
    }.getOrNull()

    override suspend fun writeSmallFile(data: ByteArray, rel: String) {
        ensureParentFolders(rel)
        // Replace allowed: the sidecar is rebuildable (no If-None-Match).
        send(request("PUT", url(rel), body = data.toRequestBody(null))).use { check(it) }
    }

    // MARK: Writing

    /** Spools the bytes to a temp file and uploads them when closed. [abort] drops them. */
    override suspend fun openOutput(rel: String): OutputStream {
        ensureParentFolders(rel)
        val spool = File.createTempFile("pvb-up-", ".part", tempDir)
        return object : OutputStream(), AbortableOutput {
            private val out = spool.outputStream().buffered(256 * 1024)
            private var done = false
            override fun write(b: Int) = out.write(b)
            override fun write(b: ByteArray, off: Int, len: Int) = out.write(b, off, len)
            override fun flush() = out.flush()
            override fun abort() { if (done) return; done = true; runCatching { out.close() }; spool.delete() }
            override fun close() {
                if (done) return
                done = true
                try { out.close(); upload(spool, rel) } finally { spool.delete() }
            }
        }
    }

    private fun upload(file: File, rel: String) {
        val size = file.length()
        if (size > chunkThreshold && supportsChunking() && uploadsRoot() != null) {
            chunkedUpload(file, size, rel, uploadsRoot()!!)
        } else {
            val req = request("PUT", url(rel), mapOf("If-None-Match" to "*"), FileBody(file, 0, size))
            send(req).use { check(it) }
        }
        synchronized(lock) { writtenByUs += rel }
    }

    /** A byte range of a file as a request body (repeatable, so a redirect can resend it). */
    private class FileBody(val file: File, val offset: Long, val length: Long) : RequestBody() {
        override fun contentType() = null
        override fun contentLength() = length
        override fun writeTo(sink: BufferedSink) {
            RandomAccessFile(file, "r").use { raf ->
                raf.seek(offset)
                val buf = ByteArray(64 * 1024)
                var left = length
                while (left > 0) {
                    val n = raf.read(buf, 0, minOf(buf.size.toLong(), left).toInt())
                    if (n < 0) throw java.io.EOFException()
                    sink.write(buf, 0, n); left -= n
                }
            }
        }
    }

    // MARK: Chunked upload (Nextcloud / ownCloud)

    /** `…/remote.php/dav/uploads/<user>` for a server URL of the form `…/remote.php/dav/files/<user>/…`. */
    private fun uploadsRoot(): String? {
        val marker = "/remote.php/dav/files/"
        val i = root.indexOf(marker)
        if (i < 0) return null
        val who = root.substring(i + marker.length).substringBefore('/')
        return if (who.isEmpty()) null else root.substring(0, i) + "/remote.php/dav/uploads/" + who
    }

    /** Whether the server advertises Nextcloud chunking (`dav.chunking` in its capabilities); remembered. */
    fun supportsChunking(): Boolean {
        chunking?.let { return it }
        val found = detectChunking()
        chunking = found
        return found
    }

    private fun detectChunking(): Boolean = runCatching {
        val i = root.indexOf("/remote.php/")
        if (i < 0) return false
        val url = root.substring(0, i) + "/ocs/v1.php/cloud/capabilities?format=json"
        send(request("GET", url, mapOf("OCS-APIRequest" to "true", "Accept" to "application/json"))).use { r ->
            if (r.code != 200) return false
            val dav = Json.parseToJsonElement(r.body!!.string()).jsonObject["ocs"]?.jsonObject?.get("data")?.jsonObject
                ?.get("capabilities")?.jsonObject?.get("dav")?.jsonObject
            dav?.get("chunking")?.jsonPrimitive?.contentOrNull == "1.0"
        }
    }.getOrDefault(false)

    private fun chunkedUpload(file: File, size: Long, rel: String, uploads: String) {
        val folder = "$uploads/${uploadId(file, rel, size)}"
        try {
            send(request("MKCOL", folder)).use { r ->
                if (r.code !in 200..299 && r.code != 405) throw WebDavException.forWrite(r.code) ?: WebDavException(WebDavException.Kind.HTTP, r.code)
            }
            // Chunks already on the server (resume).
            val present = HashMap<String, Long>()
            runCatching { propfind("$folder/", 1) }.getOrNull()?.takeIf { it.first == 207 }?.second?.forEach {
                if (!it.isCollection) present[it.name] = it.size ?: 0
            }
            var offset = 0L
            var number = 1
            while (offset < size) {
                val length = minOf(chunkSize.toLong(), size - offset)
                val name = "%06d".format(number)
                if (present[name] != length) {
                    val req = request("PUT", "$folder/$name", mapOf("OC-Total-Length" to "$size"), FileBody(file, offset, length))
                    send(req).use { check(it) }
                }
                offset += length; number++
            }
            // The name is checked right before the MOVE: MOVE does not honour If-None-Match everywhere.
            if (runBlockingSize(rel) != null) throw WebDavException(WebDavException.Kind.ALREADY_EXISTS, 412)
            val move = request("MOVE", "$folder/.file", mapOf("Destination" to url(rel), "OC-Total-Length" to "$size", "Overwrite" to "F"))
            send(move).use { check(it) }
        } catch (e: Throwable) {
            runCatching { send(request("DELETE", folder)).close() }   // no orphan chunks using quota
            throw e
        }
    }

    private fun runBlockingSize(rel: String): Long? = runCatching {
        val (code, entries) = propfind(url(rel), 0)
        entries.firstOrNull()?.takeIf { code == 207 && !it.isCollection }?.size
    }.getOrNull()

    /** Deterministic per destination + file (name, size, start of the content), so an interrupted upload is found again. */
    private fun uploadId(file: File, rel: String, size: Long): String {
        val md = MessageDigest.getInstance("SHA-256")
        val head = ByteArray(minOf(1L shl 20, size).toInt())
        file.inputStream().use { var o = 0; while (o < head.size) { val n = it.read(head, o, head.size - o); if (n < 0) break; o += n } }
        val key = MessageDigest.getInstance("SHA-256").digest(head).toHex()
        return "pvb-" + md.digest("$rel|$size|$key".toByteArray()).toHex().take(24)
    }

    // MARK: Delete

    /** Best effort, and only what this target wrote: a failed copy must never remove another file that holds the name. */
    override suspend fun delete(rel: String) {
        val ours = synchronized(lock) { writtenByUs.remove(rel) }
        if (ours) runCatching { deleteAny(rel) }
    }

    /** Removes a file or folder whoever wrote it (LUT cleanup, tests, the connection test). 404 is fine. */
    fun deleteAny(rel: String) {
        send(request("DELETE", url(rel))).use { r -> if (r.code != 404) check(r) }
    }

    override suspend fun setModified(rel: String, modifiedMs: Long) {}

    // MARK: Folders

    /** `MKCOL` one level at a time, top-down; an existing folder (405) is fine. Remembered per run. */
    private fun ensureParentFolders(rel: String) {
        val comps = base.split('/').filter { it.isNotEmpty() } + rel.split('/').filter { it.isNotEmpty() }.dropLast(1)
        val prefix = ArrayList<String>()
        for (c in comps) {
            prefix += c
            val key = prefix.joinToString("/")
            if (synchronized(lock) { key in createdFolders }) continue
            send(request("MKCOL", urlOfComponents(prefix))).use { r ->
                if (r.code !in 200..299 && r.code != 405) throw WebDavException.forWrite(r.code) ?: WebDavException(WebDavException.Kind.HTTP, r.code)
            }
            synchronized(lock) { createdFolders += key }
        }
    }

    // MARK: Reachability / connection test

    /** True when the server answers at all (any HTTP status): a wrong password is not "offline" — use [testConnection]. */
    override suspend fun isReachable(): Boolean = runCatching { send(request("OPTIONS", url("", true))).use { true } }.getOrDefault(false)

    /** Throws the reason a backup would fail; returns whether the server supports chunked uploads. */
    fun testConnection(): Boolean {
        val (code, _) = propfind("$root/", 0)
        WebDavException.forWrite(if (code == 207) 200 else code)?.let { throw it }
        // Write + read back + delete a small object under the base folder.
        val probe = ".pvb-test-" + java.util.UUID.randomUUID()
        kotlinx.coroutines.runBlocking {
            writeSmallFile("ok".toByteArray(), probe)
            val back = readSmallFile(probe)
            runCatching { deleteAny(probe) }
            if (back?.toString(Charsets.UTF_8) != "ok") throw WebDavException(WebDavException.Kind.INVALID_RESPONSE)
        }
        return supportsChunking()
    }

    // MARK: Browsing

    override suspend fun list(rel: String): List<TargetEntry> {
        val (code, entries) = propfind(url(rel, true), 1)
        if (code != 207) throw WebDavException.forWrite(code) ?: WebDavException(WebDavException.Kind.HTTP, code)
        val self = entries.firstOrNull()?.path
        return entries.mapNotNull { e ->
            if (e.path == self || e.name.isEmpty() || e.name.startsWith(".")) null
            else TargetEntry(e.name, e.isCollection, e.size ?: 0, e.modifiedMs ?: 0)
        }
    }

    companion object {
        const val DEFAULT_CHUNK_THRESHOLD = 100L * 1024 * 1024
        const val DEFAULT_CHUNK_SIZE = 10 * 1024 * 1024
        private const val PROPFIND_BODY = """<?xml version="1.0" encoding="utf-8"?><d:propfind xmlns:d="DAV:"><d:prop><d:resourcetype/><d:getcontentlength/><d:getlastmodified/></d:prop></d:propfind>"""

        /** Unreserved characters only: spaces, accents, `#`, `%`, `+`, `?` in names are all encoded. */
        fun encode(component: String): String {
            val sb = StringBuilder()
            for (b in component.toByteArray(Charsets.UTF_8)) {
                val c = b.toInt() and 0xFF
                if (c in 'A'.code..'Z'.code || c in 'a'.code..'z'.code || c in '0'.code..'9'.code || c == '-'.code || c == '.'.code || c == '_'.code || c == '~'.code) sb.append(c.toChar())
                else sb.append('%').append("0123456789ABCDEF"[c ushr 4]).append("0123456789ABCDEF"[c and 15])
            }
            return sb.toString()
        }

        fun buildClient(trust: WebDavTrust.PinningTrustManager, pin: String?): OkHttpClient {
            val ctx = SSLContext.getInstance("TLS").apply { init(null, arrayOf<TrustManager>(trust), null) }
            val b = OkHttpClient.Builder()
                .followRedirects(false).followSslRedirects(false)     // redirects are followed by hand, keeping method, headers and body
                .connectTimeout(30, TimeUnit.SECONDS).readTimeout(120, TimeUnit.SECONDS).writeTimeout(120, TimeUnit.SECONDS)
                .sslSocketFactory(ctx.socketFactory, trust)
            // An exact pinned certificate is the trust anchor: a self-signed server is usually addressed by a name it does not carry.
            if (!pin.isNullOrEmpty()) b.hostnameVerifier { _, _ -> true }
            return b.build()
        }
    }
}
