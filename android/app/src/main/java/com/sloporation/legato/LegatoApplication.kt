package com.sloporation.legato

import android.app.Application

/** One library and one player for the whole app, so they outlive the activity (rotating, or coming back from the background). */
class LegatoApplication : Application() {
    val library by lazy { LibraryStore(this) }
    val player by lazy { PlayerConnection(this, library) }
}
