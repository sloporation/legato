package com.sloporation.legato.ui

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.sloporation.legato.LibraryStore
import com.sloporation.legato.PlayerConnection
import com.sloporation.legato.R
import com.sloporation.legato.Track

/** Legato's colour (the icon's) as the accent, light and dark. */
@Composable
fun LegatoTheme(content: @Composable () -> Unit) {
    val scheme = if (isSystemInDarkTheme()) {
        darkColorScheme(primary = Color(0xFFE8A097), onPrimary = Color(0xFF4A1410), primaryContainer = Color(0xFF7E302A), onPrimaryContainer = Color.White)
    } else {
        lightColorScheme(primary = Color(0xFF7E302A), onPrimary = Color.White, primaryContainer = Color(0xFFF6D9D5), onPrimaryContainer = Color(0xFF3A0D09))
    }
    MaterialTheme(colorScheme = scheme, content = content)
}

/** Tabler icons (the same set as Legato Desktop's), by name. */
object Glyph {
    val font = FontFamily(Font(R.font.tabler_icons))
    const val settings = ""
    const val search = "ﶪ"
    const val x = ""
    const val play = ""
    const val pause = ""
    const val next = ""
    const val previous = ""
    const val shuffle = ""
    const val repeat = ""
    const val repeatOnce = ""
    const val music = ""
    const val playlist = ""
    const val disc = ""
    const val artist = ""
    const val back = ""
    const val volume = ""
    const val watch = ""
    const val equaliser = ""
    const val folder = "﫷"
}

@Composable
fun Icon(glyph: String, modifier: Modifier = Modifier, size: Dp = 22.dp, color: Color = MaterialTheme.colorScheme.onSurface) {
    val px = with(LocalDensity.current) { size.toSp() }
    Text(glyph, modifier, color = color, fontFamily = Glyph.font, fontSize = px)
}

/** An album cover from the synced files, or a placeholder. */
@Composable
fun Cover(library: LibraryStore, path: String?, size: Dp, modifier: Modifier = Modifier) {
    val px = with(LocalDensity.current) { size.roundToPx() }
    val image: ImageBitmap? by produceState<ImageBitmap?>(null, path, px) { value = library.cover(path, px) }
    Box(
        modifier.size(size).clip(RoundedCornerShape(size * 0.08f)).background(MaterialTheme.colorScheme.surfaceVariant),
        contentAlignment = Alignment.Center,
    ) {
        image?.let { Image(it, null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop) }
            ?: Icon(Glyph.music, size = size * 0.4f, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

fun formatTime(seconds: Double): String {
    val s = maxOf(0, seconds.toInt())
    return "%d:%02d".format(s / 60, s % 60)
}

/** Play from the top, or shuffle everything. */
@Composable
fun PlayShuffleButtons(player: PlayerConnection, tracks: List<Track>, modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        FilledTonalButton({ player.changeShuffle(false); player.play(tracks) }, Modifier.weight(1f), enabled = tracks.isNotEmpty()) {
            Icon(Glyph.play, size = 18.dp, color = MaterialTheme.colorScheme.onSecondaryContainer)
            Text("  Play")
        }
        FilledTonalButton({ player.shufflePlay(tracks) }, Modifier.weight(1f), enabled = tracks.isNotEmpty()) {
            Icon(Glyph.shuffle, size = 18.dp, color = MaterialTheme.colorScheme.onSecondaryContainer)
            Text("  Shuffle")
        }
    }
}

/**
 * One track in a list. Tapping plays [tracks] from it; long-pressing offers to play it, or to go to its album, its artist or a
 * playlist it is in (leaving out the one the list already is, [here]).
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun TrackRow(
    library: LibraryStore,
    player: PlayerConnection,
    tracks: List<Track>,
    index: Int,
    numbered: Boolean,
    here: Route?,
    go: (Route) -> Unit,
) {
    val track = tracks[index]
    val playing = player.current?.id == track.id
    val haptics = LocalHapticFeedback.current
    var menu by remember { mutableStateOf(false) }
    val accent = MaterialTheme.colorScheme.primary
    Box {
        Row(
            Modifier.fillMaxWidth()
                .combinedClickable(
                    onClick = { player.play(tracks, index) },
                    onLongClick = { haptics.performHapticFeedback(HapticFeedbackType.LongPress); menu = true },
                    onLongClickLabel = "More",
                )
                .padding(horizontal = 16.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            if (numbered) {
                Box(Modifier.width(28.dp), contentAlignment = Alignment.CenterEnd) {
                    if (playing) Icon(Glyph.volume, size = 18.dp, color = accent)
                    else Text(if (track.trackNumber > 0) "${track.trackNumber}" else "", color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            } else {
                Cover(library, track.cover, 48.dp)
            }
            Column(Modifier.weight(1f)) {
                Text(track.displayTitle, maxLines = 1, overflow = TextOverflow.Ellipsis, color = if (playing) accent else MaterialTheme.colorScheme.onSurface)
                val detail = if (numbered) track.artist.takeIf { it != track.albumArtistOrArtist } else listOf(track.artist, track.album).filter { it.isNotEmpty() }.joinToString(" — ")
                if (!detail.isNullOrEmpty()) {
                    Text(detail, maxLines = 1, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            if (!numbered && playing) Icon(Glyph.volume, size = 16.dp, color = accent)
            if (track.duration > 0) Text(formatTime(track.duration), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        DropdownMenu(menu, { menu = false }) {
            DropdownMenuItem({ Text("Play") }, { menu = false; player.play(tracks, index) }, leadingIcon = { Icon(Glyph.play, size = 18.dp) })
            if (here != Route.Album(track.albumKey)) {
                DropdownMenuItem({ Text("Go to Album") }, { menu = false; go(Route.Album(track.albumKey)) }, leadingIcon = { Icon(Glyph.disc, size = 18.dp) })
            }
            val artist = track.albumArtistOrArtist.lowercase()
            if (here != Route.Artist(artist)) {
                DropdownMenuItem({ Text("Go to Artist") }, { menu = false; go(Route.Artist(artist)) }, leadingIcon = { Icon(Glyph.artist, size = 18.dp) })
            }
            for (p in library.playlistsContaining(track).filter { here != Route.Playlist(it.name) }) {
                DropdownMenuItem({ Text("Go to “${p.name}”") }, { menu = false; go(Route.Playlist(p.name)) }, leadingIcon = { Icon(Glyph.playlist, size = 18.dp) })
            }
        }
    }
}

@Composable
fun Empty(glyph: String, title: String, detail: String, modifier: Modifier = Modifier, action: (@Composable () -> Unit)? = null) {
    Column(modifier.fillMaxWidth().padding(32.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Icon(glyph, size = 44.dp, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(title, fontWeight = FontWeight.SemiBold, fontSize = 18.sp)
        Text(detail, color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodyMedium, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
        action?.invoke()
    }
}
