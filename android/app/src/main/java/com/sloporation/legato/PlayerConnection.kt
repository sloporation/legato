package com.sloporation.legato

import android.content.ComponentName
import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.ContextCompat
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken

enum class RepeatMode { Off, All, One }

/**
 * The app's side of the player: it hands [PlaybackService] a list to play (`play(tracks, index)`) and shows what it is doing. The order
 * is kept here, so the rules match Legato Desktop's and the iPhone's: shuffle plays the chosen track first and each of the rest once;
 * repeat one restarts the track when it ends but Next still moves on; previous restarts a track well under way; at the end of the list
 * (repeat off) it goes back to the first track, stopped; a track that won't play is skipped.
 */
class PlayerConnection(context: Context, private val library: LibraryStore) {
    var current by mutableStateOf<Track?>(null); private set
    var isPlaying by mutableStateOf(false); private set
    var duration by mutableStateOf(0.0); private set     // seconds (the tags' length when there is one)
    var shuffle by mutableStateOf(false); private set
    var repeat by mutableStateOf(RepeatMode.Off); private set
    var problem by mutableStateOf<String?>(null); private set

    /** Where it is in the track, in seconds (read it while showing the position; it isn't observed). */
    val position: Double get() = (controller?.currentPosition ?: 0L) / 1000.0

    private var controller: MediaController? = null
    private var original: List<Track> = emptyList()      // the list as given, for turning shuffle off again
    private var queued: List<Track> = emptyList()        // in playing order: what the player holds
    private var failures = 0

    init {
        val token = SessionToken(context, ComponentName(context, PlaybackService::class.java))
        val future = MediaController.Builder(context, token).buildAsync()
        future.addListener({
            controller = future.get().also { it.addListener(listener) }
            sync()
        }, ContextCompat.getMainExecutor(context))
    }

    // what the app asks for

    fun play(tracks: List<Track>, index: Int = 0) {
        val c = controller ?: return
        if (tracks.isEmpty()) return
        original = tracks
        val start = index.coerceIn(tracks.indices)
        queued = if (shuffle) listOf(tracks[start]) + (tracks.indices - start).shuffled().map { tracks[it] } else tracks
        failures = 0
        c.setMediaItems(queued.map(::item), if (shuffle) 0 else start, 0)
        c.prepare()
        c.play()
    }

    /** Shuffle the whole list, starting anywhere. */
    fun shufflePlay(tracks: List<Track>) {
        if (tracks.isEmpty()) return
        shuffle = true
        play(tracks, tracks.indices.random())
    }

    fun toggle() { controller?.let { if (it.isPlaying) it.pause() else { if (it.playbackState == Player.STATE_IDLE) it.prepare(); it.play() } } }
    fun next() { failures = 0; controller?.seekToNextMediaItem() }
    fun previous() { controller?.seekToPrevious() }      // restarts a track more than 3 s in (ExoPlayer's rule, as ours)
    fun seek(seconds: Double) { controller?.seekTo((seconds * 1000).toLong()) }

    fun cycleRepeat() {
        repeat = when (repeat) { RepeatMode.Off -> RepeatMode.All; RepeatMode.All -> RepeatMode.One; RepeatMode.One -> RepeatMode.Off }
        controller?.repeatMode = when (repeat) {
            RepeatMode.Off -> Player.REPEAT_MODE_OFF
            RepeatMode.All -> Player.REPEAT_MODE_ALL
            RepeatMode.One -> Player.REPEAT_MODE_ONE
        }
    }

    /** Shuffle on or off. What is playing goes on; only what comes after it changes. */
    fun changeShuffle(on: Boolean) {
        if (on == shuffle) return
        shuffle = on
        val c = controller ?: return
        val playing = current ?: return
        val now = c.currentMediaItemIndex
        val rest = if (on) (original - playing).shuffled() else original.drop(original.indexOf(playing) + 1)
        val before = if (on) emptyList() else original.take(original.indexOf(playing))
        // replace everything around the playing track, leaving it alone so it doesn't stop
        if (now + 1 < c.mediaItemCount) c.removeMediaItems(now + 1, c.mediaItemCount)
        if (now > 0) c.removeMediaItems(0, now)
        c.addMediaItems(rest.map(::item))
        c.addMediaItems(0, before.map(::item))
        queued = before + playing + rest
    }

    // what the player is doing

    private val listener = object : Player.Listener {
        override fun onEvents(player: Player, events: Player.Events) {
            sync()
            // the end of the list with repeat off: back to the first track, stopped, as a CD player does
            if (events.contains(Player.EVENT_PLAYBACK_STATE_CHANGED) && player.playbackState == Player.STATE_ENDED && player.mediaItemCount > 0) {
                player.pause()
                player.seekTo(0, 0)
            }
        }

        override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
            if (reason != Player.MEDIA_ITEM_TRANSITION_REASON_REPEAT) problem = null
        }

        override fun onPlayerError(error: PlaybackException) {
            val c = controller ?: return
            problem = "Couldn't play “${current?.displayTitle ?: ""}”: ${error.errorCodeName}"
            // move on, unless nothing in the list will play
            if (++failures < c.mediaItemCount && c.hasNextMediaItem()) {
                c.seekToNextMediaItem()
                c.prepare()
                c.play()
            }
        }
    }

    private fun sync() {
        val c = controller ?: return
        val id = c.currentMediaItem?.mediaId
        current = queued.firstOrNull { it.id == id } ?: id?.let { tid -> library.tracks.firstOrNull { it.id == tid } }
        isPlaying = c.isPlaying
        if (c.isPlaying) failures = 0
        duration = current?.duration?.takeIf { it > 0 } ?: (c.duration.takeIf { it > 0 }?.div(1000.0) ?: 0.0)
    }

    private fun item(t: Track): MediaItem = MediaItem.Builder()
        .setMediaId(t.id)
        .setUri(library.uri(t))
        .setMediaMetadata(
            MediaMetadata.Builder()
                .setTitle(t.displayTitle)
                .setArtist(t.artist)
                .setAlbumTitle(t.album)
                .setAlbumArtist(t.albumArtist)
                .setArtworkUri(library.coverUri(t.cover))
                .build(),
        )
        .build()
}
