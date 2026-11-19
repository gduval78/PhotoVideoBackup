package gduvalsc.pvb.core

import org.xml.sax.Attributes
import org.xml.sax.InputSource
import org.xml.sax.helpers.DefaultHandler
import java.io.ByteArrayInputStream
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import javax.xml.parsers.SAXParserFactory

/** One resource of a `207 Multi-Status` answer. */
data class WebDavEntry(
    /** Percent-decoded path as the server reports it (`/remote.php/dav/files/me/Backup/IMG 1.jpg`). */
    val path: String,
    val isCollection: Boolean,
    val size: Long?,
    val modifiedMs: Long?,
) {
    val name: String get() = path.trimEnd('/').substringAfterLast('/')
}

/** Parses a `PROPFIND` answer. Works on local names, so `d:`, `D:` or a default namespace all read alike. */
object WebDavMultiStatus {
    fun parse(data: ByteArray): List<WebDavEntry> {
        val handler = Handler()
        val factory = SAXParserFactory.newInstance().apply { isNamespaceAware = true }
        runCatching { factory.newSAXParser().parse(InputSource(ByteArrayInputStream(data)), handler) }
        return handler.entries
    }

    private class Handler : DefaultHandler() {
        val entries = ArrayList<WebDavEntry>()
        private val text = StringBuilder()
        private var href: String? = null
        private var isCollection = false
        private var size: Long? = null
        private var modified: Long? = null
        private var inResponse = false

        override fun startElement(uri: String?, localName: String?, qName: String?, attributes: Attributes?) {
            text.setLength(0)
            when (localName ?: qName?.substringAfter(':')) {
                "response" -> { inResponse = true; href = null; isCollection = false; size = null; modified = null }
                "collection" -> if (inResponse) isCollection = true
            }
        }

        override fun characters(ch: CharArray, start: Int, length: Int) { text.append(ch, start, length) }

        override fun endElement(uri: String?, localName: String?, qName: String?) {
            val value = text.toString().trim()
            when (localName ?: qName?.substringAfter(':')) {
                "href" -> if (inResponse && href == null) href = value
                "getcontentlength" -> size = value.toLongOrNull()
                "getlastmodified" -> modified = runCatching { ZonedDateTime.parse(value, DateTimeFormatter.RFC_1123_DATE_TIME).toInstant().toEpochMilli() }.getOrNull()
                "response" -> {
                    href?.let { entries += WebDavEntry(decodedPath(it), isCollection, size, modified) }
                    inResponse = false
                }
            }
            text.setLength(0)
        }

        /** An href can be a full URL or an absolute path, and is percent-encoded. */
        private fun decodedPath(href: String): String {
            val path = if (href.contains("://")) href.substringAfter("://").let { "/" + it.substringAfter('/', "") } else href
            return percentDecode(path.substringBefore('?'))
        }
    }

    /** Decodes `%XX` (UTF-8) only — a `+` stays a plus, unlike a form decoder. */
    fun percentDecode(s: String): String {
        if (!s.contains('%')) return s
        val out = java.io.ByteArrayOutputStream()
        var i = 0
        val bytes = s.toByteArray(Charsets.UTF_8)
        while (i < bytes.size) {
            val b = bytes[i]
            if (b == '%'.code.toByte() && i + 2 < bytes.size + 0 && hex(bytes[i + 1]) >= 0 && hex(bytes[i + 2]) >= 0) {
                out.write(hex(bytes[i + 1]) * 16 + hex(bytes[i + 2])); i += 3
            } else { out.write(b.toInt()); i++ }
        }
        return out.toString("UTF-8")
    }

    private fun hex(b: Byte): Int = when (b.toInt().toChar()) { in '0'..'9' -> b - '0'.code.toByte(); in 'a'..'f' -> b - 'a'.code.toByte() + 10; in 'A'..'F' -> b - 'A'.code.toByte() + 10; else -> -1 }
}
