package com.sloporation.legato

import org.json.JSONObject

/** What is synced: `Legato/manifest.json`, written by Legato Desktop (docs/sync.md). Missing keys take their defaults; unknown ones are ignored. */
data class Manifest(
    val version: Int = 1,
    val generated: String? = null,      // ISO 8601
    val source: String? = null,
    val tracks: List<Track> = emptyList(),
    val playlists: List<Playlist> = emptyList(),
) {
    companion object {
        fun parse(json: String): Manifest {
            val o = JSONObject(json)
            val tracks = o.optJSONArray("tracks")
            val playlists = o.optJSONArray("playlists")
            return Manifest(
                version = o.optInt("version", 1),
                generated = o.optStringOrNull("generated"),
                source = o.optStringOrNull("source"),
                tracks = (0 until (tracks?.length() ?: 0)).map { Track.from(tracks!!.getJSONObject(it)) },
                playlists = (0 until (playlists?.length() ?: 0)).map {
                    val p = playlists!!.getJSONObject(it)
                    val ids = p.optJSONArray("tracks")
                    Playlist(p.getString("name"), (0 until (ids?.length() ?: 0)).map { i -> ids!!.getString(i) })
                },
            )
        }
    }
}

data class Track(
    val id: String,                 // stable across syncs
    val file: String,               // relative to the Legato folder: "Music/<id>.<ext>"
    val title: String = "",
    val artist: String = "",
    val album: String = "",
    val albumArtist: String = "",
    val genre: String = "",
    val year: Int = 0,
    val trackNumber: Int = 0,
    val discNumber: Int = 0,
    val duration: Double = 0.0,     // seconds; 0 when the file doesn't say
    val size: Long = 0,
    val cover: String? = null,      // relative to the Legato folder
) {
    /** What to show when the tags say nothing: the file's name. */
    val displayTitle: String get() = title.ifEmpty { file.substringAfterLast('/') }
    /** Whose album it is: the album artist, else the artist. */
    val albumArtistOrArtist: String get() = albumArtist.ifEmpty { artist }
    /** Which album it is on, as the desktop groups them: album artist (else artist) and album title, ignoring case. */
    val albumKey: String get() = albumArtistOrArtist.lowercase() + "\u001f" + album.lowercase()

    companion object {
        fun from(o: JSONObject) = Track(
            id = o.getString("id"),
            file = o.getString("file"),
            title = o.optString("title"),
            artist = o.optString("artist"),
            album = o.optString("album"),
            albumArtist = o.optString("albumArtist"),
            genre = o.optString("genre"),
            year = o.optInt("year"),
            trackNumber = o.optInt("trackNumber"),
            discNumber = o.optInt("discNumber"),
            duration = o.optDouble("duration", 0.0).takeIf { !it.isNaN() } ?: 0.0,
            size = o.optLong("size"),
            cover = o.optStringOrNull("cover"),
        )

        /** Album order: disc (none counts as 1), then track number (numbered ones first), then title. */
        val albumOrder: Comparator<Track> = compareBy<Track> { maxOf(1, it.discNumber) }
            .thenBy { if (it.trackNumber > 0) it.trackNumber else Int.MAX_VALUE }
            .thenBy(String.CASE_INSENSITIVE_ORDER) { it.displayTitle }
    }
}

data class Playlist(val name: String, val tracks: List<String> = emptyList())     // track ids, in playlist order

data class Album(
    val key: String,
    val title: String,
    val artist: String,
    val year: Int,
    val genre: String,
    val tracks: List<Track>,        // album order
    val cover: String?,
)

data class Artist(val name: String, val albums: List<Album>) {
    val tracks: List<Track> get() = albums.flatMap { it.tracks }
}

/** Albums and artists, grouped from the tracks the same way as on the desktop and the iPhone. */
object Grouping {
    const val UNKNOWN_ALBUM = "Unknown Album"
    const val UNKNOWN_ARTIST = "Unknown Artist"

    /** Albums, by artist then title. */
    fun albums(tracks: List<Track>): List<Album> =
        tracks.groupBy { it.albumKey }.values.map { group ->
            val sorted = group.sortedWith(Track.albumOrder)
            val first = group.first()
            Album(
                key = first.albumKey,
                title = first.album.ifEmpty { UNKNOWN_ALBUM },
                artist = first.albumArtistOrArtist.ifEmpty { UNKNOWN_ARTIST },
                year = group.maxOf { it.year },
                genre = group.firstOrNull { it.genre.isNotEmpty() }?.genre ?: "",
                tracks = sorted,
                cover = group.firstNotNullOfOrNull { it.cover },
            )
        }.sortedWith(compareBy<Album, String>(String.CASE_INSENSITIVE_ORDER) { it.artist }.thenBy(String.CASE_INSENSITIVE_ORDER) { it.title })

    /** Artists, by name, each with their albums oldest first. */
    fun artists(albums: List<Album>): List<Artist> =
        albums.groupBy { it.artist.lowercase() }.values
            .map { Artist(it.first().artist, it.sortedWith(compareBy<Album> { a -> a.year }.thenBy(String.CASE_INSENSITIVE_ORDER) { a -> a.title })) }
            .sortedWith(compareBy(String.CASE_INSENSITIVE_ORDER) { it.name })
}

private fun JSONObject.optStringOrNull(key: String): String? = if (has(key) && !isNull(key)) optString(key) else null
