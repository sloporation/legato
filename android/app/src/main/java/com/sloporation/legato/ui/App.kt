package com.sloporation.legato.ui

import android.net.Uri
import android.provider.DocumentsContract
import android.text.format.Formatter
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import com.sloporation.legato.LibraryStore
import com.sloporation.legato.PlayerConnection
import com.sloporation.legato.PlaylistChange
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** Where a tab can go: an album's, an artist's or a playlist's tracks (long-press a track), or a page from the cog menu. */
sealed interface Route {
    data class Album(val key: String) : Route
    data class Artist(val name: String) : Route       // lowercased
    data class Playlist(val name: String) : Route
    data object Settings : Route
    data object Equaliser : Route
    data object WatchSync : Route
}

private enum class Tab(val title: String, val glyph: String) { Music("Music", Glyph.music), Playlists("Playlists", Glyph.playlist) }

/** Two tabs, Music (every track, searchable) and Playlists, each keeping its own pages; the mini player sits above the tab bar. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun App(library: LibraryStore, player: PlayerConnection) {
    var tab by rememberSaveable { mutableStateOf(Tab.Music) }
    val stacks = remember { Tab.entries.associateWith { mutableStateListOf<Route>() } }
    val stack = stacks.getValue(tab)
    val go: (Route) -> Unit = { stack.add(it) }
    var nowPlaying by remember { mutableStateOf(false) }
    var cogMenu by remember { mutableStateOf(false) }

    // Legato Desktop may sync while the app is open: look at the manifest now and then (it is only read when it changed)
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    LaunchedEffect(library.folder) {
        lifecycle.repeatOnLifecycle(Lifecycle.State.RESUMED) {
            while (true) {
                library.reload()
                delay(3000)
            }
        }
    }

    BackHandler(enabled = stack.isNotEmpty()) { stack.removeAt(stack.lastIndex) }

    val route = stack.lastOrNull()
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(title(library, tab, route), maxLines = 1) },
                navigationIcon = {
                    if (route != null) IconButton({ stack.removeAt(stack.lastIndex) }) { Icon(Glyph.back) }
                },
                actions = {
                    Box {
                        IconButton({ cogMenu = true }) { Icon(Glyph.settings) }
                        DropdownMenu(cogMenu, { cogMenu = false }) {
                            DropdownMenuItem({ Text("Settings") }, { cogMenu = false; go(Route.Settings) }, leadingIcon = { Icon(Glyph.settings, size = 18.dp) })
                            DropdownMenuItem({ Text("Equaliser") }, { cogMenu = false; go(Route.Equaliser) }, leadingIcon = { Icon(Glyph.equaliser, size = 18.dp) })
                            DropdownMenuItem({ Text("Watch Sync") }, { cogMenu = false; go(Route.WatchSync) }, leadingIcon = { Icon(Glyph.watch, size = 18.dp) })
                        }
                    }
                },
            )
        },
        bottomBar = {
            Column {
                if (player.current != null) MiniPlayer(library, player) { nowPlaying = true }
                NavigationBar {
                    for (t in Tab.entries) {
                        NavigationBarItem(
                            selected = t == tab,
                            // tapping the tab you're on goes back to its start
                            onClick = { if (t == tab) stacks.getValue(t).clear() else tab = t },
                            icon = { Icon(t.glyph, color = if (t == tab) MaterialTheme.colorScheme.onSecondaryContainer else MaterialTheme.colorScheme.onSurfaceVariant) },
                            label = { Text(t.title) },
                        )
                    }
                }
            }
        },
    ) { padding ->
        if (library.needsWriteAccess) WriteAccessDialog(library)
        Box(Modifier.padding(padding).fillMaxSize()) {
            when {
                library.folder == null && route !is Route.Settings -> ChooseFolder(library)
                route == null && tab == Tab.Music -> MusicPage(library, player, go)
                route == null -> PlaylistsPage(library, go)
                else -> RoutePage(route, library, player, go)
            }
        }
    }
    if (nowPlaying) NowPlaying(library, player) { nowPlaying = false }
}

private fun title(library: LibraryStore, tab: Tab, route: Route?): String = when (route) {
    null -> tab.title
    is Route.Album -> library.albums.firstOrNull { it.key == route.key }?.title ?: ""
    is Route.Artist -> library.artists.firstOrNull { it.name.lowercase() == route.name }?.name ?: ""
    is Route.Playlist -> route.name
    Route.Settings -> "Settings"
    Route.Equaliser -> "Equaliser"
    Route.WatchSync -> "Watch Sync"
}

@Composable
private fun RoutePage(route: Route, library: LibraryStore, player: PlayerConnection, go: (Route) -> Unit) {
    when (route) {
        is Route.Album -> {
            val album = library.albums.firstOrNull { it.key == route.key }
                ?: return Empty(Glyph.disc, "This album is no longer on your phone", "")
            LazyColumn {
                item {
                    Column(Modifier.fillMaxWidth().padding(top = 16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                        Cover(library, album.cover, 220.dp)
                        Spacer(Modifier.height(12.dp))
                        Text(album.title, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center, modifier = Modifier.padding(horizontal = 24.dp))
                        Text(album.artist, style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.primary)
                        Text(listOfNotNull(album.genre.ifEmpty { null }, album.year.takeIf { it > 0 }?.toString()).joinToString(" · "),
                            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        PlayShuffleButtons(player, album.tracks)
                    }
                }
                itemsIndexed(album.tracks, key = { _, t -> t.id }) { i, _ -> TrackRow(library, player, album.tracks, i, numbered = true, here = route, go = go) }
            }
        }
        is Route.Artist -> {
            val artist = library.artists.firstOrNull { it.name.lowercase() == route.name }
                ?: return Empty(Glyph.artist, "This artist is no longer on your phone", "")
            val tracks = artist.tracks
            LazyColumn {
                item { PlayShuffleButtons(player, tracks) }
                itemsIndexed(tracks, key = { _, t -> t.id }) { i, _ -> TrackRow(library, player, tracks, i, numbered = false, here = route, go = go) }
            }
        }
        is Route.Playlist -> {
            val playlist = library.playlists.firstOrNull { it.name == route.name }
                ?: return Empty(Glyph.playlist, "This playlist is no longer on your phone", "")
            val tracks = library.tracks(playlist)
            LazyColumn {
                item { PlayShuffleButtons(player, tracks) }
                itemsIndexed(tracks, key = { i, t -> "$i-${t.id}" }) { i, _ -> TrackRow(library, player, tracks, i, numbered = false, here = route, go = go) }
            }
        }
        Route.Settings -> SettingsPage(library)
        Route.Equaliser -> Empty(Glyph.equaliser, "Equaliser", "Coming soon.")
        Route.WatchSync -> Empty(Glyph.watch, "Watch Sync", "Legato for Wear OS is coming. Once it's here, you'll choose the music for your watch on this page.")
    }
}

/** The Music tab: every track, grouped by artist and album; search narrows it, and Play and Shuffle play what's listed. */
@Composable
private fun MusicPage(library: LibraryStore, player: PlayerConnection, go: (Route) -> Unit) {
    var search by rememberSaveable { mutableStateOf("") }
    val all = library.tracksInAlbumOrder
    val tracks = if (search.isBlank()) all else all.filter { t ->
        listOf(t.displayTitle, t.artist, t.albumArtist, t.album).any { it.contains(search.trim(), ignoreCase = true) }
    }
    if (all.isEmpty()) {
        Empty(Glyph.music, "No Music Yet", library.problem
            ?: "Plug your phone into your computer, open Legato there, and choose the playlists, artists and albums to put on it.")
        return
    }
    LazyColumn {
        item {
            TextField(
                search, { search = it },
                Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp),
                placeholder = { Text("Songs, artists, albums") },
                leadingIcon = { Icon(Glyph.search, size = 20.dp, color = MaterialTheme.colorScheme.onSurfaceVariant) },
                trailingIcon = { if (search.isNotEmpty()) IconButton({ search = "" }) { Icon(Glyph.x, size = 18.dp) } },
                singleLine = true,
                shape = RoundedCornerShape(28.dp),
                colors = TextFieldDefaults.colors(focusedIndicatorColor = Color.Transparent, unfocusedIndicatorColor = Color.Transparent),
            )
        }
        item { PlayShuffleButtons(player, tracks) }
        if (tracks.isEmpty()) item { Empty(Glyph.search, "No Results", "Nothing matches “$search”.") }
        itemsIndexed(tracks, key = { _, t -> t.id }) { i, _ -> TrackRow(library, player, tracks, i, numbered = false, here = null, go = go) }
    }
}

/**
 * The Playlists tab: the playlists synced from the desktop, each opening its tracks in its own order. + makes a new one; long-pressing
 * one renames or deletes it. The desktop gets the changes at the next sync.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun PlaylistsPage(library: LibraryStore, go: (Route) -> Unit) {
    val scope = rememberCoroutineScope()
    var creating by remember { mutableStateOf(false) }
    var renaming by remember { mutableStateOf<String?>(null) }
    var deleting by remember { mutableStateOf<String?>(null) }
    var menuFor by remember { mutableStateOf<String?>(null) }
    Box(Modifier.fillMaxSize()) {
        if (library.playlists.isEmpty()) {
            Empty(Glyph.playlist, "No Playlists", "Make one with +, or choose playlists to put on your phone in Legato on your computer.")
        }
        LazyColumn {
            items(library.playlists, key = { it.name }) { p ->
                val tracks = library.tracks(p)
                Box {
                    ListItem(
                        headlineContent = { Text(p.name) },
                        supportingContent = { Text(if (tracks.size == 1) "1 song" else "${tracks.size} songs") },
                        leadingContent = { Cover(library, tracks.firstOrNull()?.cover, 52.dp) },
                        modifier = Modifier.combinedClickable(onClick = { go(Route.Playlist(p.name)) }, onLongClick = { menuFor = p.name }),
                    )
                    DropdownMenu(menuFor == p.name, { menuFor = null }) {
                        DropdownMenuItem({ Text("Rename…") }, { menuFor = null; renaming = p.name }, leadingIcon = { Icon(Glyph.rename, size = 18.dp) })
                        DropdownMenuItem({ Text("Delete") }, { menuFor = null; deleting = p.name }, leadingIcon = { Icon(Glyph.delete, size = 18.dp) })
                    }
                }
            }
        }
        FloatingActionButton({ creating = true }, Modifier.align(Alignment.BottomEnd).padding(16.dp)) {
            Icon(Glyph.plus, size = 24.dp, color = MaterialTheme.colorScheme.onPrimaryContainer)
        }
    }
    if (creating) NameDialog("New playlist", "Create", "") { name ->
        creating = false
        if (name != null) scope.launch { library.change(PlaylistChange(PlaylistChange.Op.create, library.freeName(name))) }
    }
    renaming?.let { old ->
        NameDialog("Rename playlist", "Rename", old) { name ->
            renaming = null
            if (name != null && name.trim().isNotEmpty() && name.trim() != old)
                scope.launch { library.change(PlaylistChange(PlaylistChange.Op.rename, old, to = library.freeName(name))) }
        }
    }
    deleting?.let { name ->
        AlertDialog(
            onDismissRequest = { deleting = null },
            title = { Text("Delete “$name”?") },
            text = { Text("The songs stay. Your computer moves the playlist to the Trash at the next sync.") },
            confirmButton = {
                TextButton({ deleting = null; scope.launch { library.change(PlaylistChange(PlaylistChange.Op.delete, name)) } }) { Text("Delete") }
            },
            dismissButton = { TextButton({ deleting = null }) { Text("Cancel") } },
        )
    }
}

/** First run: Android only lets the app read the synced folder once you've chosen it. */
@Composable
private fun ChooseFolder(library: LibraryStore) {
    val scope = rememberCoroutineScope()
    val pick = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
        if (uri != null) scope.launch { library.choose(uri) }
    }
    Empty(
        Glyph.folder, "Where's your music?",
        "Legato on your computer puts your music in Music › Legato on this phone, over USB. Choose that folder so Legato can play it.",
    ) {
        Button({ pick.launch(legatoFolder) }, Modifier.padding(top = 8.dp)) { Text("Choose the Legato Folder") }
    }
}


@Composable
private fun SettingsPage(library: LibraryStore) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val pick = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
        if (uri != null) scope.launch { library.choose(uri) }
    }
    LazyColumn {
        item { Text("On this phone", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary, modifier = Modifier.padding(16.dp)) }
        item { ListItem(headlineContent = { Text("Songs") }, trailingContent = { Text("${library.tracks.size}") }) }
        item { ListItem(headlineContent = { Text("Size") }, trailingContent = { Text(Formatter.formatShortFileSize(context, library.totalSize)) }) }
        library.manifest?.source?.let { item { ListItem(headlineContent = { Text("From") }, trailingContent = { Text(it) }) } }
        item { HorizontalDivider() }
        item {
            ListItem(
                headlineContent = { Text("Music folder") },
                supportingContent = { Text(library.folder?.lastPathSegment?.substringAfter(':') ?: "Not chosen") },
                trailingContent = { OutlinedButton({ pick.launch(legatoFolder) }) { Text("Change") } },
            )
        }
    }
}

