package com.sloporation.legato.ui

import android.net.Uri
import android.provider.DocumentsContract
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.ListItem
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.sloporation.legato.LibraryStore
import com.sloporation.legato.PlaylistChange
import com.sloporation.legato.PlaylistChange.Op
import com.sloporation.legato.Track
import kotlinx.coroutines.launch

/** Add to playlist: the playlists the track isn't in yet, or a new one named here. */
@Composable
fun AddToPlaylistDialog(library: LibraryStore, track: Track, close: () -> Unit) {
    val scope = rememberCoroutineScope()
    var naming by remember { mutableStateOf(false) }
    if (naming) {
        NameDialog("New playlist", "Create", "") { name ->
            if (name != null) scope.launch {
                val free = library.freeName(name)
                library.change(PlaylistChange(Op.create, free), PlaylistChange(Op.add, free, track = track.id))
            }
            close()
        }
        return
    }
    val others = library.playlists.filter { track.id !in it.tracks }
    AlertDialog(
        onDismissRequest = close,
        title = { Text("Add to playlist") },
        text = {
            LazyColumn(Modifier.heightIn(max = 360.dp)) {
                item {
                    ListItem(
                        headlineContent = { Text("New playlist…") },
                        leadingContent = { Icon(Glyph.plus, size = 20.dp) },
                        modifier = Modifier.clickable { naming = true },
                    )
                    if (others.isNotEmpty()) HorizontalDivider()
                }
                items(others, key = { it.name }) { p ->
                    ListItem(
                        headlineContent = { Text(p.name) },
                        leadingContent = { Icon(Glyph.playlist, size = 20.dp) },
                        modifier = Modifier.clickable {
                            scope.launch { library.change(PlaylistChange(Op.add, p.name, track = track.id)) }
                            close()
                        },
                    )
                }
            }
        },
        confirmButton = {},
        dismissButton = { TextButton(close) { Text("Cancel") } },
    )
}

/** A name for a playlist: [done] gets it, or null when cancelled. */
@Composable
fun NameDialog(title: String, action: String, initial: String, done: (String?) -> Unit) {
    var name by remember { mutableStateOf(initial) }
    AlertDialog(
        onDismissRequest = { done(null) },
        title = { Text(title) },
        text = { OutlinedTextField(name, { name = it }, singleLine = true, label = { Text("Name") }) },
        confirmButton = { TextButton({ done(name) }) { Text(action) } },
        dismissButton = { TextButton({ done(null) }) { Text("Cancel") } },
    )
}

/** The folder was chosen before Legato could change it: choosing it again lets the playlist changes be saved. */
@Composable
fun WriteAccessDialog(library: LibraryStore) {
    val scope = rememberCoroutineScope()
    val pick = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
        if (uri != null) scope.launch { library.choose(uri) } else library.needsWriteAccess = false
    }
    AlertDialog(
        onDismissRequest = { library.needsWriteAccess = false },
        title = { Text("Let Legato change the Legato folder") },
        text = {
            Text(
                "Changes to playlists are kept in the Legato folder until your computer takes them at the next sync. " +
                    "Choose the folder again (Music › Legato) and allow access, then make the change again.",
            )
        },
        confirmButton = { TextButton({ pick.launch(legatoFolder) }) { Text("Choose the Folder") } },
        dismissButton = { TextButton({ library.needsWriteAccess = false }) { Text("Not Now") } },
    )
}

/** Opens the system picker at Music/Legato (on the phone's own storage). */
val legatoFolder: Uri = DocumentsContract.buildDocumentUri("com.android.externalstorage.documents", "primary:Music/Legato")
