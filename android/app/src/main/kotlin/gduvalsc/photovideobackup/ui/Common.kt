package gduvalsc.photovideobackup.ui

import android.content.Context
import android.os.Build
import android.text.format.Formatter
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import gduvalsc.photovideobackup.Msg
import gduvalsc.photovideobackup.R
import java.text.DateFormat
import java.util.Date
import java.util.Locale

private val Blue = Color(0xFF1F5FBF)

@Composable
fun PvbTheme(content: @Composable () -> Unit) {
    val dark = isSystemInDarkTheme()
    val ctx = LocalContext.current
    val scheme = when {
        Build.VERSION.SDK_INT >= 31 -> if (dark) dynamicDarkColorScheme(ctx) else dynamicLightColorScheme(ctx)
        dark -> darkColorScheme(primary = Color(0xFF9CC2FF))
        else -> lightColorScheme(primary = Blue)
    }
    MaterialTheme(colorScheme = scheme, content = content)
}

// MARK: Semantic colors (readable in light and dark)

object Tone {
    val ok = Color(0xFF2E9E5B)
    val warn = Color(0xFFE08A00)
    val bad = Color(0xFFD64545)
    val info = Color(0xFF14A3A3)
}

// MARK: Formatting (all through the app's locale, not the phone's)

fun bytes(context: Context, n: Long): String = Formatter.formatFileSize(context, n)

fun dateTime(ms: Long, locale: Locale = Locale.getDefault()): String =
    DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT, locale).format(Date(ms))

fun duration(ms: Long): String {
    val s = ms / 1000
    return if (s < 60) "%.1f s".format(ms / 1000.0) else "%d min %02d s".format(s / 60, s % 60)
}

@Composable
fun msgText(m: Msg): String = stringResource(m.res, *m.args.toTypedArray())

// MARK: Building blocks

@Composable
fun SectionHeader(text: String) {
    Text(
        text.uppercase(Locale.getDefault()),
        style = MaterialTheme.typography.labelMedium,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 20.dp, bottom = 6.dp),
    )
}

/** A settings-style row: title, optional subtitle, optional trailing content. */
@Composable
fun Row2(
    title: String,
    subtitle: String? = null,
    locked: Boolean = false,
    onClick: (() -> Unit)? = null,
    trailing: @Composable (() -> Unit)? = null,
) {
    Row(
        Modifier
            .fillMaxWidth()
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyLarge)
            if (subtitle != null) {
                Text(
                    subtitle, style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 2, overflow = TextOverflow.Ellipsis,
                )
            }
        }
        if (locked) {
            Spacer(Modifier.width(8.dp))
            Icon(Icons.Default.Lock, contentDescription = stringResource(R.string.pro_feature), tint = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        if (trailing != null) { Spacer(Modifier.width(8.dp)); trailing() }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SubScreenBar(title: String, onBack: () -> Unit, actions: @Composable () -> Unit = {}) {
    CenterAlignedTopAppBar(
        title = { Text(title, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis) },
        navigationIcon = {
            IconButton(onClick = onBack) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.back))
            }
        },
        actions = { actions() },
    )
}
