package gduvalsc.pvb.core

import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Assumptions.assumeTrue
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

/**
 * A real round trip against a WebDAV server (a throwaway Nextcloud in Docker behind a self-signed TLS proxy).
 * Skipped unless `PVB_WEBDAV_URL`, `PVB_WEBDAV_USER` and `PVB_WEBDAV_PASSWORD` are set — no credentials in the
 * repository. Run: `PVB_WEBDAV_URL=https://localhost:8443/remote.php/dav/files/admin/ PVB_WEBDAV_USER=… PVB_WEBDAV_PASSWORD=… gradle :core:test --tests '*Live*'`.
 */
class LiveWebDavIntegrationTests {
    private val url = System.getenv("PVB_WEBDAV_URL")
    private val user = System.getenv("PVB_WEBDAV_USER")
    private val password = System.getenv("PVB_WEBDAV_PASSWORD")
    private val temp = java.nio.file.Files.createTempDirectory("pvb_live").toFile()

    private fun target(pin: String?, base: String) = WebDavTarget(url, base, user, password, "Live", temp, null, pin, chunkThreshold = 1_000_000, chunkSize = 400_000)

    // SCENARIO: untrusted → fingerprint probe → pinned → connection, plain and chunked upload, verification, never overwritten, cleanup
    @Test fun nextcloudRoundTrip() = runBlocking {
        assumeTrue(url != null && user != null && password != null, "no live WebDAV server configured")
        val u = java.net.URI(url)
        // 1. Without a pin the self-signed certificate is refused and named as such.
        val ex = assertFailsWith<WebDavException> { target(null, "PvbLive").testConnection() }
        assertEquals(WebDavException.Kind.UNTRUSTED_CERTIFICATE, ex.kind)
        // 2. The presented fingerprint is read without sending anything, then pinned.
        val fp = assertNotNull(WebDavTrust.presentedFingerprint(u.host, if (u.port > 0) u.port else 443))
        // 3. A wrong pin is "certificate changed", never "trust anything".
        assertEquals(WebDavException.Kind.CERTIFICATE_CHANGED, assertFailsWith<WebDavException> { target("00" + fp.drop(2), "PvbLive").testConnection() }.kind)
        // 4. The right pin connects; Nextcloud advertises chunking.
        val base = "PvbLive-" + System.currentTimeMillis()
        val t = target(fp, base)
        assertTrue(t.testConnection(), "chunking capability")
        val small = ByteArray(10_000) { (it % 251).toByte() }
        val big = ByteArray(1_300_000) { (it * 31 % 253).toByte() }          // above the test threshold → chunked
        t.openOutput("Cam/2024-01-14/small é#1.jpg").use { it.write(small) }
        t.openOutput("Cam/2024-01-14/big.mp4").use { it.write(big) }
        assertEquals(sha256Hex(small.inputStream()), t.sha256("Cam/2024-01-14/small é#1.jpg"))
        assertEquals(sha256Hex(big.inputStream()), t.sha256("Cam/2024-01-14/big.mp4"))
        assertEquals(big.size.toLong(), t.existingSize("Cam/2024-01-14/big.mp4"))
        // 5. A taken name is never overwritten, by a plain PUT or by the chunked MOVE.
        assertEquals(WebDavException.Kind.ALREADY_EXISTS, assertFailsWith<WebDavException> { target(fp, base).openOutput("Cam/2024-01-14/small é#1.jpg").use { it.write(ByteArray(5)) } }.kind)
        assertEquals(WebDavException.Kind.ALREADY_EXISTS, assertFailsWith<WebDavException> { target(fp, base).openOutput("Cam/2024-01-14/big.mp4").use { it.write(big) } }.kind)
        assertEquals(small.size.toLong(), t.existingSize("Cam/2024-01-14/small é#1.jpg"))
        // 6. Listing, then cleanup (the whole test folder).
        assertEquals(setOf("small é#1.jpg", "big.mp4"), t.list("Cam/2024-01-14").map { it.name }.toSet())
        t.deleteAny("")
        assertEquals(null, t.existingSize("Cam/2024-01-14/big.mp4"))
    }
}
