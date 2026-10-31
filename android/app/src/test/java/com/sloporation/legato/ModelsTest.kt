package com.sloporation.legato

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ModelsTest {
    @Test
    fun readsTheFormatInSyncMd() {
        val m = Manifest.parse(
            """
            {
              "version": 1, "generated": "2026-10-30T12:00:00Z", "source": "Legato on a Mac",
              "tracks": [
                { "id": "a", "file": "Music/a.opus", "title": "Critical Acclaim", "artist": "Avenged Sevenfold",
                  "album": "Avenged Sevenfold", "albumArtist": "Avenged Sevenfold", "genre": "Rock", "year": 2007,
                  "trackNumber": 1, "discNumber": 1, "duration": 315.18, "size": 5223493,
                  "modified": "2026-10-30T10:19:00Z", "cover": "Covers/x.jpg", "somethingNew": true }
              ],
              "playlists": [ { "name": "Rainy Day", "tracks": ["a"] } ]
            }
            """,
        )
        assertEquals(1, m.tracks.size)
        assertEquals("Critical Acclaim", m.tracks[0].title)
        assertEquals(315.18, m.tracks[0].duration, 0.001)
        assertEquals("Covers/x.jpg", m.tracks[0].cover)
        assertEquals(listOf("a"), m.playlists[0].tracks)
        assertEquals("Legato on a Mac", m.source)
    }

    @Test
    fun missingFieldsTakeDefaults() {
        val m = Manifest.parse("""{ "tracks": [ { "id": "a", "file": "Music/untagged recording.wav" } ] }""")
        assertEquals(1, m.version)
        assertEquals("", m.tracks[0].title)
        assertEquals("untagged recording.wav", m.tracks[0].displayTitle)
        assertNull(m.tracks[0].cover)
        assertTrue(m.playlists.isEmpty())
    }

    /** The same grouping as the desktop and the iPhone: album artist (else artist) and album, ignoring case; disc, track, title. */
    @Test
    fun groupsAlbumsLikeTheDesktop() {
        val tracks = listOf(
            Track("1", "Music/1.mp3", title = "B side", artist = "Ada Lune", album = "Harbour", trackNumber = 2),
            Track("2", "Music/2.mp3", title = "Opener", artist = "Ada Lune feat. Ö", album = "HARBOUR", albumArtist = "ada lune", trackNumber = 1),
            Track("3", "Music/3.mp3", title = "Unnumbered", artist = "Ada Lune", album = "Harbour"),
            Track("4", "Music/4.mp3", title = "Disc two", artist = "Ada Lune", album = "Harbour", trackNumber = 1, discNumber = 2),
            Track("5", "Music/5.mp3", title = "Other", artist = "Northern Static", album = "Glass Weather"),
        )
        val albums = Grouping.albums(tracks)
        assertEquals(listOf("Harbour", "Glass Weather"), albums.map { it.title })
        assertEquals(listOf("Opener", "B side", "Unnumbered", "Disc two"), albums[0].tracks.map { it.title })
        val artists = Grouping.artists(albums)
        assertEquals(listOf("Ada Lune", "Northern Static"), artists.map { it.name })
        assertEquals(4, artists[0].tracks.size)
    }

    // playlist changes made on the phone (docs/sync.md, "Phone → desktop")

    private val base = listOf(Playlist("Rainy Day", listOf("a", "b", "c")), Playlist("Old", listOf("a")))

    @Test fun eachKindOfChange() {
        val lists = base.applying(listOf(
            PlaylistChange(PlaylistChange.Op.create, "Gym"),
            PlaylistChange(PlaylistChange.Op.add, "Gym", track = "c"),
            PlaylistChange(PlaylistChange.Op.add, "Gym", track = "a"),
            PlaylistChange(PlaylistChange.Op.move, "Gym", track = "a"),
            PlaylistChange(PlaylistChange.Op.remove, "Rainy Day", track = "b"),
            PlaylistChange(PlaylistChange.Op.move, "Rainy Day", track = "a", after = "c"),
            PlaylistChange(PlaylistChange.Op.rename, "Gym", to = "Lifting"),
            PlaylistChange(PlaylistChange.Op.delete, "Old"),
        ))
        assertEquals(listOf("Rainy Day", "Lifting"), lists.map { it.name })
        assertEquals(listOf("c", "a"), lists[0].tracks)
        assertEquals(listOf("a", "c"), lists[1].tracks)
    }

    @Test fun madeTwiceComesToTheSame() {
        val changes = listOf(
            PlaylistChange(PlaylistChange.Op.create, "Gym"),
            PlaylistChange(PlaylistChange.Op.add, "Gym", track = "b"),
            PlaylistChange(PlaylistChange.Op.remove, "Rainy Day", track = "a"),
            PlaylistChange(PlaylistChange.Op.move, "Rainy Day", track = "c"),
            PlaylistChange(PlaylistChange.Op.rename, "Old", to = "Older"),
        )
        val once = base.applying(changes)
        assertEquals(once, once.applying(changes))
    }

    @Test fun theLogReadsBackWhatWasWritten() {
        val text = PlaylistChange.log(listOf(PlaylistChange(PlaylistChange.Op.move, "R", track = "a"), PlaylistChange(PlaylistChange.Op.move, "R", track = "a", after = "c")))
        val back = PlaylistChange.parseLog(text)
        assertEquals(listOf(null, "c"), back.map { it.after })
        assertEquals(PlaylistChange.Op.move, back[0].op)
    }
}
