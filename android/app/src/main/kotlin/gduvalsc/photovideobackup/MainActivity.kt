package gduvalsc.photovideobackup

import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.appcompat.app.AppCompatActivity
import gduvalsc.photovideobackup.ui.AppRoot
import gduvalsc.photovideobackup.ui.PvbTheme

class MainActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent { PvbTheme { AppRoot() } }
    }
}
