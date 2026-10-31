package com.sloporation.legato

import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.DocumentsContract.Document
import android.util.LruCache
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * The synced music: `Music/Legato/` on the phone's shared storage, where Legato Desktop copies it over USB (MTP), with
 * `manifest.json` and the files beside it (docs/sync.md). Android only lets an app read such a folder once the person has chosen it
 * in the system's folder picker, so the app asks once and keeps the permission. Tracks whose file is missing are left out.
 *
 * The playlists can be changed here: the changes go into `changes.json` beside the manifest for the desktop to take at the next sync
 * (docs/sync.md), and the playlists show them made. That needs the folder's write permission, which a folder chosen before this
 * version doesn't have: [needsWriteAccess] says so, and choosing it again gives it.
 */
class LibraryStore(private val context: Context) {
    var tracks by mutableStateOf(emptyList<Track>()); private set
    var playlists by mutableStateOf(emptyList<Playlist>()); private set
    var albums by mutableStateOf(emptyList<Album>()); private set
    var artists by mutableStateOf(emptyList<Artist>()); private set
    var manifest by mutableStateOf<Manifest?>(null); private set
    /** Why the music couldn't be read, if it couldn't. */
    var problem by mutableStateOf<String?>(null); private set
    /** The Legato folder the person chose; null until they have. */
    var folder by mutableStateOf(savedFolder()); private set
    /** A change couldn't be saved because the folder was chosen without write permission: it needs choosing again. */
    var needsWriteAccess by mutableStateOf(false)

    /** Every track by artist, then album, then album order: how the Music tab lists them. */
    val tracksInAlbumOrder: List<Track> get() = albums.flatMap { it.tracks }

    private var files: Map<String, Uri> = emptyMap()       // "Music/x.opus" → its document
    private var manifestModified = -1L
    private var base: List<Playlist> = emptyList()          // the manifest's, before the changes made here
    private var rootId: String? = null                      // the Legato folder's document, where changes.json goes
    private val byId get() = tracks.associateBy { it.id }

    fun uri(track: Track): Uri? = files[track.file]
    fun coverUri(relative: String?): Uri? = relative?.let { files[it] }
    fun tracks(playlist: Playlist): List<Track> = byId.let { ids -> playlist.tracks.mapNotNull { ids[it] } }
    fun playlistsContaining(track: Track): List<Playlist> = playlists.filter { track.id in it.tracks }
    val totalSize: Long get() = tracks.sumOf { it.size }

    /** The folder chosen in the system picker (ACTION_OPEN_DOCUMENT_TREE): keep the permission and read it. */
    suspend fun choose(tree: Uri) {
        context.contentResolver.takePersistableUriPermission(tree, Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        needsWriteAccess = false
        context.getSharedPreferences("legato", Context.MODE_PRIVATE).edit().putString("folder", tree.toString()).apply()
        folder = tree
        reload(force = true)
    }

    private fun savedFolder(): Uri? {
        val saved = context.getSharedPreferences("legato", Context.MODE_PRIVATE).getString("folder", null) ?: return null
        val uri = Uri.parse(saved)
        // (the permission goes if the app is reinstalled, or the person takes it back in Settings)
        return uri.takeIf { context.contentResolver.persistedUriPermissions.any { it.uri == uri && it.isReadPermission } }
    }

    /** Reads the manifest again if it changed (or always, with [force]). */
    suspend fun reload(force: Boolean = false) {
        val tree = folder ?: return
        val result = withContext(Dispatchers.IO) { runCatching { read(tree, force) } }
        result.onSuccess { read ->
            if (read == null) return@onSuccess      // unchanged
            files = read.files
            val here = read.manifest.tracks.filter { it.file in read.files }
            manifest = read.manifest
            tracks = here
            base = read.manifest.playlists
            showPlaylists(read.changes)
            albums = Grouping.albums(here)
            artists = Grouping.artists(albums)
            problem = null
        }.onFailure {
            problem = "The synced music couldn't be read. Sync again from Legato on your computer, or choose the Legato folder again in Settings."
        }
    }

    private fun showPlaylists(changes: List<PlaylistChange>) {
        playlists = base.applying(changes).sortedWith(compareBy(String.CASE_INSENSITIVE_ORDER) { it.name })
    }

    private class Read(val manifest: Manifest, val files: Map<String, Uri>, val changes: List<PlaylistChange>)

    private fun read(tree: Uri, force: Boolean): Read? {
        var rootId = DocumentsContract.getTreeDocumentId(tree)
        var root = children(tree, rootId)
        // chose the Music folder (or the phone's storage) rather than Legato itself: look inside
        if ("manifest.json" !in root) root["Legato"]?.let { rootId = it.id; root = children(tree, it.id) }
        this.rootId = rootId
        val entry = root["manifest.json"] ?: return Read(Manifest(), emptyMap(), emptyList()).also { manifestModified = -1 }
        // (the changes count too: the desktop takes them away at a sync)
        val stamp = entry.modified + (root["changes.json"]?.modified ?: 0) * 31 + (root["changes.applying.json"]?.modified ?: 0) * 17
        if (!force && stamp == manifestModified) return null
        val text = context.contentResolver.openInputStream(entry.uri(tree))!!.use { it.readBytes().decodeToString() }
        val changes = listOf("changes.applying.json", "changes.json").flatMap { name ->
            root[name]?.let { c -> runCatching { readText(c.uri(tree)) }.getOrNull()?.let(PlaylistChange::parseLog) } ?: emptyList()
        }
        val files = HashMap<String, Uri>()
        for (dir in listOf("Music", "Covers")) {
            val folder = root[dir] ?: continue
            for ((name, child) in children(tree, folder.id)) files["$dir/$name"] = child.uri(tree)
        }
        manifestModified = stamp
        return Read(Manifest.parse(text), files, changes)
    }

    private fun readText(uri: Uri): String = context.contentResolver.openInputStream(uri)!!.use { it.readBytes().decodeToString() }

    // changing the playlists

    /** Makes the change here and keeps it for the desktop. False if it couldn't be saved (see [needsWriteAccess]). */
    suspend fun change(vararg change: PlaylistChange): Boolean {
        val tree = folder ?: return false
        val saved = withContext(Dispatchers.IO) {
            runCatching {
                val dir = rootId ?: DocumentsContract.getTreeDocumentId(tree)
                val existing = children(tree, dir)
                val log = existing["changes.json"]?.uri(tree)
                val now = log?.let { PlaylistChange.parseLog(readText(it)) } ?: emptyList()
                val target = log ?: DocumentsContract.createDocument(
                    context.contentResolver, DocumentsContract.buildDocumentUriUsingTree(tree, dir), "application/json", "changes.json",
                )!!
                context.contentResolver.openOutputStream(target, "wt")!!.use {
                    it.write(PlaylistChange.log(now + change).encodeToByteArray())
                }
                val applying = existing["changes.applying.json"]?.let { c -> PlaylistChange.parseLog(readText(c.uri(tree))) } ?: emptyList()
                applying + now + change
            }
        }
        return saved.fold(
            onSuccess = { showPlaylists(it); true },
            onFailure = { e ->
                if (e is SecurityException || context.contentResolver.persistedUriPermissions.none { it.uri == tree && it.isWritePermission })
                    needsWriteAccess = true
                false
            },
        )
    }

    /** A name for a new playlist that no playlist has yet: the one asked for, else with a number after it. */
    fun freeName(name: String): String {
        val base = name.trim().ifEmpty { "New Playlist" }
        var candidate = base
        var n = 2
        while (playlists.any { it.name.equals(candidate, ignoreCase = true) }) candidate = "$base ${n++}"
        return candidate
    }

    private class Child(val id: String, val modified: Long) {
        fun uri(tree: Uri): Uri = DocumentsContract.buildDocumentUriUsingTree(tree, id)
    }

    private fun children(tree: Uri, parentId: String): MutableMap<String, Child> {
        val out = HashMap<String, Child>()
        val query = DocumentsContract.buildChildDocumentsUriUsingTree(tree, parentId)
        val columns = arrayOf(Document.COLUMN_DOCUMENT_ID, Document.COLUMN_DISPLAY_NAME, Document.COLUMN_LAST_MODIFIED)
        context.contentResolver.query(query, columns, null, null, null)?.use { c ->
            while (c.moveToNext()) out[c.getString(1)] = Child(c.getString(0), c.getLong(2))
        }
        return out
    }

    // covers, decoded at the size they're shown and kept for scrolling back
    private val covers = LruCache<String, ImageBitmap>(64)

    suspend fun cover(relative: String?, size: Int): ImageBitmap? {
        val uri = coverUri(relative) ?: return null
        val key = "$uri#$size"
        covers.get(key)?.let { return it }
        return withContext(Dispatchers.IO) {
            runCatching {
                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                context.contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
                var sample = 1
                while (bounds.outWidth / (sample * 2) >= size) sample *= 2
                context.contentResolver.openInputStream(uri)?.use {
                    BitmapFactory.decodeStream(it, null, BitmapFactory.Options().apply { inSampleSize = sample })
                }?.asImageBitmap()
            }.getOrNull()
        }?.also { covers.put(key, it) }
    }
}
