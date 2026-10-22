package gduvalsc.pvb.core

// Path helpers with the semantics of Foundation's NSString path methods, which the iOS engine relies on
// (`lastPathComponent`, `pathExtension`, `deletingPathExtension`…). Paths here are always "/"-separated
// strings: destination paths come from `BackupTarget.absolutePath`, relative paths from `FolderOrganization`.

fun lastPathComponent(path: String): String = path.trimEnd('/').substringAfterLast('/')

fun deletingLastPathComponent(path: String): String {
    val i = path.lastIndexOf('/')
    return if (i < 0) "" else path.substring(0, i)
}

/** "a.b" → "b"; ".hidden", "name" and "name." → "". */
fun pathExtension(name: String): String {
    val i = name.lastIndexOf('.')
    return if (i <= 0 || i == name.length - 1) "" else name.substring(i + 1)
}

fun deletingPathExtension(name: String): String {
    val ext = pathExtension(name)
    return if (ext.isEmpty()) name else name.dropLast(ext.length + 1)
}

/**
 * True when [path] lies inside [root]. Compares whole path components: a plain `startsWith` made
 * `/Volumes/SSD/Backup` "contain" `/Volumes/SSD/Backup 2/…`.
 */
fun isPath(path: String, underRoot: String): Boolean {
    val prefix = if (underRoot.endsWith("/")) underRoot else "$underRoot/"
    return path == underRoot || path.startsWith(prefix)
}

/**
 * `a/b/X.mp4` → `a/b/X-1.mp4` (n = 1). Used only to keep from overwriting a *different* file that
 * happens to carry the same name; it plays no part in deciding whether to copy.
 */
fun relativePath(rel: String, withCollisionIndex: Int): String {
    val n = withCollisionIndex
    if (n <= 0) return rel
    val lastComponent = lastPathComponent(rel)
    val ext = pathExtension(lastComponent)
    val stem = deletingPathExtension(lastComponent)
    val dir = deletingLastPathComponent(rel)
    val name = if (ext.isEmpty()) "$stem-$n" else "$stem-$n.$ext"
    return if (dir.isEmpty()) name else "$dir/$name"
}
