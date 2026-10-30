package com.sloporation.legato.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Slider
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.sloporation.legato.LibraryStore
import com.sloporation.legato.PlayerConnection
import com.sloporation.legato.RepeatMode
import kotlinx.coroutines.delay

/** The bar above the tabs: what's playing, play/pause and next. Tapping it opens Now Playing. */
@Composable
fun MiniPlayer(library: LibraryStore, player: PlayerConnection, open: () -> Unit) {
    val track = player.current ?: return
    Surface(
        Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 4.dp).clickable(onClick = open),
        shape = RoundedCornerShape(14.dp),
        tonalElevation = 3.dp,
    ) {
        Row(Modifier.padding(8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Cover(library, track.cover, 40.dp)
            Column(Modifier.weight(1f)) {
                Text(track.displayTitle, maxLines = 1, overflow = TextOverflow.Ellipsis, fontWeight = FontWeight.Medium)
                Text(track.artist, maxLines = 1, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            IconButton(player::toggle) { Icon(if (player.isPlaying) Glyph.pause else Glyph.play) }
            IconButton(player::next) { Icon(Glyph.next) }
        }
    }
}

/** Now Playing: the cover, where it is in the track, the controls, shuffle and repeat. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NowPlaying(library: LibraryStore, player: PlayerConnection, close: () -> Unit) {
    val track = player.current ?: return close()
    var position by remember { mutableDoubleStateOf(player.position) }
    var scrubbing by remember { mutableStateOf<Double?>(null) }
    LaunchedEffect(player.isPlaying, track.id) {
        while (true) { position = player.position; delay(500) }
    }
    ModalBottomSheet(close, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        Column(Modifier.padding(horizontal = 28.dp).padding(bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Cover(library, track.cover, 320.dp, Modifier.fillMaxWidth().aspectRatio(1f).align(Alignment.CenterHorizontally))
            Column {
                Text(track.displayTitle, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(track.artist, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
                player.problem?.let { Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall) }
            }
            // a file that doesn't say how long it is can't be skipped through
            Column {
                val length = player.duration
                Slider(
                    value = (scrubbing ?: position).toFloat().coerceIn(0f, maxOf(1f, length.toFloat())),
                    onValueChange = { scrubbing = it.toDouble() },
                    onValueChangeFinished = { scrubbing?.let(player::seek); scrubbing = null },
                    valueRange = 0f..maxOf(1f, length.toFloat()),
                    enabled = length > 0,
                )
                Row {
                    Text(formatTime(scrubbing ?: position), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Spacer(Modifier.weight(1f))
                    Text(if (length > 0) "-" + formatTime(length - (scrubbing ?: position)) else "--:--", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly, verticalAlignment = Alignment.CenterVertically) {
                IconButton(player::previous) { Icon(Glyph.previous, size = 30.dp) }
                IconButton(player::toggle, Modifier.height(64.dp)) { Icon(if (player.isPlaying) Glyph.pause else Glyph.play, size = 44.dp) }
                IconButton(player::next) { Icon(Glyph.next, size = 30.dp) }
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                val on = MaterialTheme.colorScheme.primary
                val off = MaterialTheme.colorScheme.onSurfaceVariant
                IconButton({ player.changeShuffle(!player.shuffle) }) { Icon(Glyph.shuffle, color = if (player.shuffle) on else off) }
                IconButton(player::cycleRepeat) {
                    Icon(if (player.repeat == RepeatMode.One) Glyph.repeatOnce else Glyph.repeat, color = if (player.repeat == RepeatMode.Off) off else on)
                }
            }
        }
    }
}
