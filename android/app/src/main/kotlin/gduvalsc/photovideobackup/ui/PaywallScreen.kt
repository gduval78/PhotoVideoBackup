package gduvalsc.photovideobackup.ui

import android.app.Activity
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Cloud
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material.icons.filled.SdCard
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import gduvalsc.photovideobackup.Pro
import gduvalsc.photovideobackup.R

@Composable
fun PaywallScreen(onClose: () -> Unit) {
    val activity = LocalContext.current as Activity
    LaunchedEffect(Pro.isPro) { if (Pro.isPro) onClose() }

    Column(Modifier.fillMaxSize()) {
        SubScreenBar(stringResource(R.string.pro), onClose)
        Column(
            Modifier.verticalScroll(rememberScrollState()).padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Icon(Icons.Default.Star, null, Modifier.size(56.dp), tint = Tone.warn)
            Text(stringResource(R.string.pro_title), style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
            Text(stringResource(R.string.one_time_purchase), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(Modifier.height(8.dp))
            FeatureRow(Icons.Default.PhotoLibrary, stringResource(R.string.feature_gallery), free = true)
            FeatureRow(Icons.Default.SdCard, stringResource(R.string.feature_sources), free = false)
            FeatureRow(Icons.Default.ContentCopy, stringResource(R.string.feature_second_destination), free = false)
            FeatureRow(Icons.Default.Cloud, stringResource(R.string.feature_nas), free = false)
            Spacer(Modifier.height(12.dp))

            when {
                Pro.isLoadingProduct -> CircularProgressIndicator()
                Pro.productLoadFailed -> {
                    Text(stringResource(R.string.product_load_failed), color = Tone.bad)
                    TextButton(onClick = { Pro.refresh() }) { Text(stringResource(R.string.retry)) }
                }
                else -> Button(onClick = { Pro.purchase(activity) }, enabled = !Pro.isBusy, modifier = Modifier.fillMaxWidth()) {
                    Text(stringResource(R.string.upgrade_for_fmt, Pro.price.orEmpty()))
                }
            }
            Pro.purchaseError?.let { Text(it, color = Tone.bad, textAlign = TextAlign.Center, style = MaterialTheme.typography.bodySmall) }
            TextButton(onClick = { Pro.refresh() }) { Text(stringResource(R.string.restore_purchases)) }
        }
    }
}

@Composable
private fun FeatureRow(icon: ImageVector, text: String, free: Boolean) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, tint = MaterialTheme.colorScheme.primary)
        Spacer(Modifier.width(12.dp))
        Text(text, Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
        Text(
            stringResource(if (free) R.string.free else R.string.pro),
            style = MaterialTheme.typography.labelMedium,
            color = if (free) MaterialTheme.colorScheme.onSurfaceVariant else Tone.warn,
            fontWeight = FontWeight.SemiBold,
        )
    }
}
