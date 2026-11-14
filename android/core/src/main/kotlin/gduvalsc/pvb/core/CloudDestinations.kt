package gduvalsc.pvb.core

/** A cloud storage app that exposes its folders through the Storage Access Framework. */
enum class CloudProvider(val displayName: String) {
    GOOGLE_DRIVE("Google Drive"),
    ONEDRIVE("OneDrive"),
    DROPBOX("Dropbox"),
}

/**
 * Recognises a destination that is really a cloud service and decides when to warn about it.
 *
 * Such a folder is not a disk: files go through the provider app, which uploads them on its own
 * schedule, may keep them on the phone meanwhile, shares a quota with the user's other data (Google
 * Drive's 15 GB is shared with Gmail and Google Photos) and makes the SHA-256 read-back slow. The iOS
 * app learned this with iCloud Drive in the field; the rules mirror `DashboardViewModel` there.
 */
object CloudDestinations {

    /** Below this much free space on the phone, a cloud destination is warned about first. */
    const val WARN_BELOW_FREE_BYTES: Long = 10L * 1024 * 1024 * 1024

    /** The cloud provider behind a SAF tree URI (`content://<authority>/tree/…`), or null for a disk. */
    fun providerOf(treeUri: String): CloudProvider? {
        if (!treeUri.startsWith("content://")) return null
        val authority = treeUri.removePrefix("content://").substringBefore('/').substringAfter('@')
        return when {
            authority.startsWith("com.google.android.apps.docs") -> CloudProvider.GOOGLE_DRIVE
            authority.startsWith("com.microsoft.skydrive") -> CloudProvider.ONEDRIVE
            authority.startsWith("com.dropbox") -> CloudProvider.DROPBOX
            else -> null
        }
    }

    /** First cloud provider among the destinations, or null. */
    fun firstCloud(treeUris: List<String>): CloudProvider? = treeUris.firstNotNullOfOrNull { providerOf(it) }

    /** Warn only with a cloud destination and a free space that could not absorb the pending copies. An unreadable free space never warns. */
    fun shouldWarn(provider: CloudProvider?, freeBytes: Long?): Boolean =
        provider != null && freeBytes != null && freeBytes < WARN_BELOW_FREE_BYTES
}
