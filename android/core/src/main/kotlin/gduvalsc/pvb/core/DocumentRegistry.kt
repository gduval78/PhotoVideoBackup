package gduvalsc.pvb.core

// MARK: - Telling a lagging listing from a deletion
//
// A cloud provider (Google Drive, OneDrive…) can serve a folder listing that does not show a file or a
// folder the app created minutes ago. "Not in the listing" then means one of two things: the provider is
// late (the file is there), or the user deleted it. The listing alone cannot tell them apart, but the
// provider can answer a question about ONE document by its id without going through the listing.
//
// So the app remembers, per destination, the provider document id of every file and folder it creates
// (or finds). When a name is missing from the listing but remembered, it asks the provider about that
// id: still there ⇒ the provider is late (treat the name as taken, never copy it again, never create the
// folder twice); gone ⇒ really deleted (forget it, as before).

/** Provider document ids remembered for the paths of one destination (relative paths). */
interface DocumentRegistry {
    fun get(rel: String): String?
    fun put(rel: String, docId: String)
    fun remove(rel: String)
}

class InMemoryDocumentRegistry : DocumentRegistry {
    private val ids = java.util.concurrent.ConcurrentHashMap<String, String>()
    override fun get(rel: String): String? = ids[rel]
    override fun put(rel: String, docId: String) { ids[rel] = docId }
    override fun remove(rel: String) { ids.remove(rel) }
    val size: Int get() = ids.size
}

/** What the provider answers about one remembered document. */
sealed interface Remembered<out T> {
    class Found<T>(val doc: T) : Remembered<T>
    /** The provider says the document does not exist (any more). */
    data object Gone : Remembered<Nothing>
    /** The provider failed to answer: nothing can be concluded either way. */
    data object Unknown : Remembered<Nothing>
}

/**
 * The document remembered for [rel], if the provider still has it. A document the provider reports gone
 * is dropped from [registry]; an unanswered question changes nothing (and yields null, so a failing
 * provider behaves as before the registry existed).
 */
fun <T> verifyRemembered(rel: String, registry: DocumentRegistry, fetch: (String) -> Remembered<T>): T? {
    val id = registry.get(rel) ?: return null
    return when (val answer = fetch(id)) {
        is Remembered.Found -> answer.doc
        Remembered.Gone -> { registry.remove(rel); null }
        Remembered.Unknown -> null
    }
}
