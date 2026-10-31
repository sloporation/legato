package com.sloporation.legato

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.sloporation.legato.ui.App
import com.sloporation.legato.ui.LegatoTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val app = application as LegatoApplication
        setContent {
            LegatoTheme { App(app.library, app.player) }
        }
    }
}
