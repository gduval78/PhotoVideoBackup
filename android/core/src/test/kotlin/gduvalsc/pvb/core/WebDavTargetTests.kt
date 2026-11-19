package gduvalsc.pvb.core

import kotlinx.coroutines.runBlocking
import java.io.File
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class WebDavTargetTests {
    private lateinit var server: FakeWebDavServer
    private val temp = java.nio.file.Files.createTempDirectory("pvb_dav_spool").toFile()

    @BeforeTest fun up() { server = FakeWebDavServer() }
    @AfterTest fun down() { server.close(); temp.deleteRecursively() }

    private fun target(
        path: String = "/remote.php/dav/files/me/", base: String = "Backups", chunking: Boolean? = null,
        threshold: Long = 1000, chunk: Int = 400, host: String = server.baseUrl, pin: String? = null,
    ) = WebDavTarget(host + path, base, "me", "secret", "Fake", temp, chunking, pin, threshold, chunk).also {
        server.file(path).mkdirs(); server.file("/remote.php/dav/uploads/me").mkdirs()
    }

    private fun WebDavTarget.write(rel: String, bytes: ByteArray) = runBlocking { openOutput(rel).use { it.write(bytes) } }
    private fun bytes(n: Int) = ByteArray(n) { (it * 7 % 251).toByte() }

    // SCENARIO: PROPFIND answers are read whatever namespace prefix the server uses
    @Test fun parserReadsPrefixesDefaultNamespaceAndEncodedHrefs() {
        val xml = """<?xml version="1.0"?><D:multistatus xmlns:D="DAV:"><D:response><D:href>/dav/Backups/</D:href>
            <D:propstat><D:prop><D:resourcetype><D:collection/></D:resourcetype></D:prop></D:propstat></D:response>
            <D:response><D:href>https://h/dav/Backups/IMG%201%20%C3%A9+x.jpg</D:href><D:propstat><D:prop><D:resourcetype/>
            <D:getcontentlength>42</D:getcontentlength><D:getlastmodified>Tue, 14 Jan 2025 10:00:00 GMT</D:getlastmodified></D:prop></D:propstat></D:response></D:multistatus>"""
        val e = WebDavMultiStatus.parse(xml.toByteArray())
        assertEquals(2, e.size)
        assertTrue(e[0].isCollection)
        assertEquals("/dav/Backups/IMG 1 é+x.jpg", e[1].path)
        assertEquals("IMG 1 é+x.jpg", e[1].name)
        assertEquals(42L, e[1].size)
        assertNotNull(e[1].modifiedMs)
        val dflt = """<multistatus xmlns="DAV:"><response><href>/a/</href><propstat><prop><resourcetype><collection/></resourcetype></prop></propstat></response></multistatus>"""
        assertTrue(WebDavMultiStatus.parse(dflt.toByteArray()).single().isCollection)
    }

    // SCENARIO: names with spaces, accents and URL-reserved characters are encoded once, per component
    @Test fun urlEncodesEachComponentOnce() {
        val t = target()
        assertEquals("${server.baseUrl}/remote.php/dav/files/me/Backups/a%20b/%C3%A9%23%25%2B%3F.jpg", t.url("a b/é#%+?.jpg"))
        assertTrue(t.url("x", folder = true).endsWith("/x/"))
    }

    // SCENARIO: upload creates the folders, stores the bytes, and the file is then found and verified
    @Test fun uploadCreatesFoldersAndVerifies() = runBlocking {
        val t = target()
        val data = bytes(500)
        t.write("Cam/2024-01-14/a.jpg", data)
        assertEquals(data.toList(), server.file("/remote.php/dav/files/me/Backups/Cam/2024-01-14/a.jpg").readBytes().toList())
        assertEquals(500L, t.existingSize("Cam/2024-01-14/a.jpg"))
        assertEquals(sha256Hex(data.inputStream()), t.sha256("Cam/2024-01-14/a.jpg"))
    }

    // SCENARIO: folders already created in this run are not created again
    @Test fun rememberedFoldersNoRepeatedMkcol() {
        val t = target()
        t.write("Cam/a.jpg", bytes(10)); val first = server.count("MKCOL")
        t.write("Cam/b.jpg", bytes(10))
        assertEquals(first, server.count("MKCOL"))
    }

    // SCENARIO: a different file is never overwritten — a 412 is reported, the existing file is untouched, and a failed copy does not delete it
    @Test fun uploadNeverOverwrites() = runBlocking {
        val t = target()
        t.write("a.jpg", bytes(10))
        val other = target()   // another run: it did not write a.jpg
        val ex = assertFailsWith<WebDavException> { other.write("a.jpg", bytes(20)) }
        assertEquals(WebDavException.Kind.ALREADY_EXISTS, ex.kind)
        other.delete("a.jpg")   // what the engine does after a failed copy
        assertEquals(10L, other.existingSize("a.jpg"))
        Unit
    }

    // SCENARIO: a size limit at the server or proxy gets its own error
    @Test fun status413IsTooLarge() {
        val t = target(); server.putStatusOverride = 413
        assertEquals(WebDavException.Kind.TOO_LARGE, assertFailsWith<WebDavException> { t.write("a.mp4", bytes(10)) }.kind)
    }

    // SCENARIO: wrong credentials are reported, not swallowed
    @Test fun wrongPasswordIsUnauthorized() {
        val t = target(); server.expectedAuthorization = "Basic nope"
        assertEquals(WebDavException.Kind.UNAUTHORIZED, assertFailsWith<WebDavException> { t.testConnection() }.kind)
    }

    // SCENARIO: the connection test writes, reads back and cleans up, and reports chunking support
    @Test fun connectionTestSucceedsAndCleansUp() {
        val t = target()
        assertTrue(t.testConnection())
        assertTrue(server.file("/remote.php/dav/files/me/Backups").listFiles().orEmpty().none { it.name.startsWith(".pvb-test-") })
        server.chunkingCapability = false
        assertFalse(target().testConnection())
    }

    // SCENARIO: a missing file, or a folder, is "not present"
    @Test fun existingSizeNullForMissingAndFolders() = runBlocking {
        val t = target(); t.write("d/a.jpg", bytes(5))
        assertNull(t.existingSize("nope.jpg")); assertNull(t.existingSize("d"))
        assertEquals(5L, t.existingSize("d/a.jpg"))
    }

    // SCENARIO: the sidecar index is written, replaced and read back
    @Test fun smallFileReplaceAndRead() = runBlocking {
        val t = target()
        t.writeSmallFile("one".toByteArray(), ".pvb-index.json"); t.writeSmallFile("two".toByteArray(), ".pvb-index.json")
        assertEquals("two", t.readSmallFile(".pvb-index.json")!!.decodeToString())
        assertNull(t.readSmallFile("absent.json"))
    }

    // SCENARIO: Browse listing — hidden entries and the folder itself dropped
    @Test fun listDropsSelfAndHidden() = runBlocking {
        val t = target(); t.write("Cam/a.jpg", bytes(3)); t.write("b.jpg", bytes(4)); t.writeSmallFile(byteArrayOf(1), ".pvb-index.json")
        val l = t.list("")
        assertEquals(setOf("Cam", "b.jpg"), l.map { it.name }.toSet())
        assertTrue(l.first { it.name == "Cam" }.isDirectory)
        assertEquals(4L, l.first { it.name == "b.jpg" }.size)
        assertEquals(listOf("a.jpg"), t.list("Cam").map { it.name })
    }

    // SCENARIO: an unreachable server is "offline", not "empty"
    @Test fun offlineIsNotReachable() = runBlocking {
        val t = target(); assertTrue(t.isReachable())
        server.close(); server = FakeWebDavServer()
        val dead = WebDavTarget("http://127.0.0.1:1/dav/", "B", "me", "x", "x", temp)
        assertFalse(dead.isReachable())
    }

    // SCENARIO: a server that ignores If-None-Match is still protected by the name chain
    @Test fun ignoredIfNoneMatchStillVisibleToTheNameChain() = runBlocking {
        val t = target(); server.ignoreIfNoneMatch = true
        t.write("a.jpg", bytes(10))
        assertEquals(10L, target().existingSize("a.jpg"))   // coverage sees the taken name before any copy
    }

    // SCENARIO: a large file goes up in chunks and is assembled at its final name; no upload folder is left
    @Test fun chunkedUploadAssemblesFile() = runBlocking {
        val t = target(chunking = true); val data = bytes(1300)
        t.write("big.mp4", data)
        assertEquals(data.toList(), server.file("/remote.php/dav/files/me/Backups/big.mp4").readBytes().toList())
        assertEquals(4, server.requests.count { it.first == "PUT" && it.second.contains("/dav/uploads/me/") })   // 400+400+400+100
        assertEquals(1, server.count("MOVE"))
        assertTrue(server.file("/remote.php/dav/uploads/me").listFiles().orEmpty().isEmpty())
    }

    // SCENARIO: a small file is a plain PUT even on a chunking server; without capability, any size is plain
    @Test fun belowThresholdOrNoCapabilityPlainPut() {
        target(chunking = true).write("s.jpg", bytes(900))
        assertEquals(0, server.count("MOVE"))
        server.chunkingCapability = false
        target().write("big.bin", bytes(3000))
        assertEquals(0, server.count("MOVE"))
    }

    // SCENARIO: an interrupted upload resumes — chunks already on the server are not sent again
    @Test fun chunkedResumeSkipsPresentChunks() {
        val data = bytes(1300)
        server.failChunkAlways = "000003"; server.ignoreDelete = true       // the run dies at chunk 3 and cannot clean up
        assertFailsWith<WebDavException> { target(chunking = true).write("big.mp4", data) }
        server.failChunkAlways = null; server.ignoreDelete = false
        val before = server.requests.count { it.first == "PUT" }
        target(chunking = true).write("big.mp4", data)
        assertEquals(2, server.requests.count { it.first == "PUT" } - before)   // only chunks 3 and 4
        assertEquals(data.toList(), server.file("/remote.php/dav/files/me/Backups/big.mp4").readBytes().toList())
        assertTrue(server.file("/remote.php/dav/uploads/me").listFiles().orEmpty().isEmpty())
    }

    // SCENARIO: a failed chunk removes the upload folder (no orphan chunks using quota)
    @Test fun chunkedFailureCleansUp() {
        server.putStatusOverride = 500
        assertFailsWith<WebDavException> { target(chunking = true).write("big.mp4", bytes(1300)) }
        server.putStatusOverride = null
        assertTrue(server.file("/remote.php/dav/uploads/me").listFiles().orEmpty().isEmpty())
    }

    // SCENARIO: a taken final name is never overwritten by the MOVE
    @Test fun chunkedExistingFinalNameIsNotOverwritten() {
        val t = target(chunking = true)
        t.write("big.mp4", bytes(10))
        val ex = assertFailsWith<WebDavException> { target(chunking = true).write("big.mp4", bytes(1300)) }
        assertEquals(WebDavException.Kind.ALREADY_EXISTS, ex.kind)
        assertEquals(10L, server.file("/remote.php/dav/files/me/Backups/big.mp4").length())
        assertTrue(server.file("/remote.php/dav/uploads/me").listFiles().orEmpty().isEmpty())
    }

    // SCENARIO: a failing MOVE is reported and cleaned up
    @Test fun chunkedMoveFailureIsReportedAndCleaned() {
        server.moveStatusOverride = 500
        assertFailsWith<WebDavException> { target(chunking = true).write("big.mp4", bytes(1300)) }
        assertTrue(server.file("/remote.php/dav/uploads/me").listFiles().orEmpty().isEmpty())
    }

    // SCENARIO: an abandoned copy (abort) uploads nothing
    @Test fun abortUploadsNothing() = runBlocking {
        val t = target()
        val out = t.openOutput("partial.mp4"); out.write(bytes(10)); abandon(out)
        assertNull(t.existingSize("partial.mp4"))
        assertTrue(temp.listFiles().orEmpty().isEmpty())
    }

    // SCENARIO: a server that redirects folders to their slash form keeps the credentials (pCloud)
    @Test fun redirectedFoldersKeepCredentials() = runBlocking {
        val t = target(path = "/", base = "Backups")
        t.write("Cam/a.jpg", bytes(10))
        server.redirectCollections = true
        val fresh = target(path = "/", base = "Backups")
        fresh.write("Cam/b.jpg", bytes(10))                      // MKCOL on an existing folder → 301 → followed with the header
        assertEquals(listOf("a.jpg", "b.jpg"), fresh.list("Cam").map { it.name }.sorted())
        assertEquals("Basic bWU6c2VjcmV0", server.lastAuthorization)
    }

    // SCENARIO: a mistyped address that redirects to another host reads "redirects somewhere else"
    @Test fun redirectToAnotherHostIsExplained() {
        val t = target(); server.redirectToOtherHost = true
        assertEquals(WebDavException.Kind.REDIRECTED, assertFailsWith<WebDavException> { t.testConnection() }.kind)
        assertEquals(WebDavException.Kind.REDIRECTED, WebDavException.forWrite(308)!!.kind)
    }

    // SCENARIO: a pinned certificate is accepted only when it is exactly that one; the fingerprint is a SHA-256 shown in groups
    @Test fun trustPinDecision() {
        assertNull(WebDavTrust.accepts(null, "ab")); assertNull(WebDavTrust.accepts("", "ab"))
        assertEquals(true, WebDavTrust.accepts("AB12", "ab12")); assertEquals(false, WebDavTrust.accepts("ab12", "cd34")); assertEquals(false, WebDavTrust.accepts("ab12", null))
        assertEquals(64, WebDavTrust.fingerprint(byteArrayOf(1, 2, 3)).length)
        assertEquals("AB:CD:01", WebDavTrust.displayFingerprint("abcd01"))
    }

    // SCENARIO: a non-pinned HTTPS handshake against an untrusted server is mapped to "certificate not trusted"
    @Test fun untrustedCertificateIsMapped() {
        // a TLS server with a self-signed certificate is exercised by the live test (docker Nextcloud); here the mapping alone
        val e = javax.net.ssl.SSLHandshakeException("PKIX path building failed")
        assertTrue(WebDavTrust.isCertificateError(e))
        assertFalse(WebDavTrust.isCertificateError(java.io.IOException("boom")))
    }
}
