package gduvalsc.photovideobackup

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.annotation.OptIn
import androidx.media3.common.Effect
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.SingleColorLut
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.Transformer
import gduvalsc.pvb.core.CubeLut
import kotlinx.coroutines.suspendCancellableCoroutine
import java.io.File
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/**
 * Re-encodes one video through a 3D LUT with Media3 Transformer — the Android counterpart of the iOS
 * `AVAssetExportSession` + `CIColorCubeWithColorSpace`. H.265 (HEVC) in an `.mp4`; where the phone has no HEVC
 * encoder Transformer falls back to H.264 rather than failing. Transformer must be driven from a thread with a
 * Looper, so everything here runs on the main thread (the encoding itself happens on its own threads).
 */
@OptIn(UnstableApi::class)
object VideoGrader {

    /** The LUT as a Media3 video effect. */
    fun effect(lut: CubeLut): Effect = SingleColorLut.createFromCube(lut.toArgbCube())

    /**
     * H.265 first (smaller files, what the iOS app writes). A phone whose HEVC encoder cannot be configured for this
     * video — Transformer's own fallback only covers "no encoder at all" — is retried once in H.264 instead of
     * losing the clip.
     */
    suspend fun grade(context: Context, source: Uri, output: File, lut: CubeLut) {
        try {
            run(context, source, output, lut, MimeTypes.VIDEO_H265)
        } catch (e: ExportException) {
            gduvalsc.pvb.core.Diag.write("[GRADE_FALLBACK] HEVC failed (${e.errorCodeName}), retrying in H.264")
            output.delete()
            run(context, source, output, lut, MimeTypes.VIDEO_H264)
        }
    }

    private suspend fun run(context: Context, source: Uri, output: File, lut: CubeLut, mime: String) {
        val main = Handler(Looper.getMainLooper())
        suspendCancellableCoroutine<Unit> { cont ->
            main.post {
                try {
                    val edited = EditedMediaItem.Builder(MediaItem.fromUri(source))
                        .setEffects(Effects(emptyList(), listOf(effect(lut))))
                        .build()
                    val transformer = Transformer.Builder(context)
                        .setVideoMimeType(mime)
                        .addListener(object : Transformer.Listener {
                            override fun onCompleted(composition: Composition, exportResult: ExportResult) { if (cont.isActive) cont.resume(Unit) }
                            override fun onError(composition: Composition, exportResult: ExportResult, exportException: ExportException) {
                                if (cont.isActive) cont.resumeWithException(exportException)
                            }
                        })
                        .build()
                    output.parentFile?.mkdirs()
                    transformer.start(edited, output.absolutePath)
                    cont.invokeOnCancellation { main.post { runCatching { transformer.cancel() } } }
                } catch (e: Exception) {
                    if (cont.isActive) cont.resumeWithException(e)
                }
            }
        }
    }
}
