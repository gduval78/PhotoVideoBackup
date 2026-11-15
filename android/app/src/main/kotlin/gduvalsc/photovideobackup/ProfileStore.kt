package gduvalsc.photovideobackup

import android.content.Context
import android.net.Uri
import gduvalsc.pvb.core.BackupProfile
import gduvalsc.pvb.core.Diag
import gduvalsc.pvb.core.ProfileMigration
import gduvalsc.pvb.core.ProfileSettings

/**
 * The user's backups, persisted in [Prefs]. The Android counterpart of the iOS `ProfileStore`: the
 * pure rules (free tier, overlap, migration) live in `core/Profiles.kt` and are unit-tested there.
 */
object ProfileStore {
    val profiles: List<BackupProfile> get() = Prefs.profiles

    fun find(id: String): BackupProfile? = profiles.firstOrNull { it.id == id }
    fun indexOf(id: String): Int = profiles.indexOfFirst { it.id == id }

    fun add(p: BackupProfile) { Prefs.profiles = profiles + p }

    /** Replaces a stored profile with an edited copy, keeping its place. */
    fun update(p: BackupProfile) { Prefs.profiles = profiles.map { if (it.id == p.id) p else it } }

    fun rename(id: String, name: String) {
        val n = name.trim()
        if (n.isEmpty()) return
        Prefs.profiles = profiles.map { if (it.id == id) it.copy(name = n) else it }
    }

    /**
     * Removes the backup, its NAS password, the folder grants no other backup uses, and the SD card / USB
     * source no other backup uses. Files already copied stay where they are.
     */
    fun delete(context: Context, id: String) {
        val gone = find(id) ?: return
        val rest = profiles.filter { it.id != id }
        SecretStore.remove(context, gone.nasSecretName)
        val stillUsed = rest.flatMap { it.folders.map { f -> f.uri } }.toSet()
        for (f in gone.folders) if (f.uri !in stillUsed) runCatching { Saf.release(context, Uri.parse(f.uri)) }
        Prefs.profiles = rest
        val sourceId = gone.source.sourceId
        if (sourceId != null && rest.none { it.source.sourceId == sourceId }) {
            Prefs.sources.firstOrNull { it.id == sourceId }?.let { runCatching { Saf.release(context, Uri.parse(it.uri)) } }
            Prefs.sources = Prefs.sources.filter { it.id != sourceId }
        }
    }

    /**
     * Runs once, the first time a version with backups starts: the destinations, NAS, SD card / USB sources
     * and settings the user already had become backups, so an upgrade needs no reconfiguration. Idempotent;
     * a fresh install starts with no backup and shows the empty state.
     */
    fun migrateIfNeeded(context: Context) {
        if (Prefs.profilesMigrated) return
        if (Prefs.profiles.isEmpty()) {
            val settings = ProfileSettings(
                folderOrganizationRaw = Prefs.folderOrganization.raw,
                namingEnabled = Prefs.namingEnabled,
                namingPattern = Prefs.namingPattern,
                fileLimit = Prefs.backupFileLimit,
                customExtensions = Prefs.customExtensions,
            )
            val migrated = ProfileMigration.profiles(
                folders = Prefs.destinations, nas = Prefs.nas,
                sources = Prefs.sources.map { ProfileMigration.LegacySource(it.id, it.name) },
                photosName = context.getString(R.string.gallery), settings = settings,
            )
            val password = SecretStore.get(context, SecretStore.NAS_PASSWORD)
            for (p in migrated) if (p.nas != null && password != null) SecretStore.put(context, p.nasSecretName, password)
            Prefs.profiles = migrated
            Diag.write("[PROFILES] migrated ${migrated.size} backup(s) from the previous setup")
        }
        Prefs.profilesMigrated = true
    }
}
