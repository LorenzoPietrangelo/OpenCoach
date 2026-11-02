package org.opencoach.atleta_app

import android.content.Context
import android.media.MediaMetadataRetriever
import androidx.annotation.OptIn
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.FrameDropEffect
import androidx.media3.effect.Presentation
import androidx.media3.transformer.Composition
import androidx.media3.transformer.DefaultEncoderFactory
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.Transformer
import androidx.media3.transformer.VideoEncoderSettings
import io.flutter.plugin.common.MethodChannel
import java.io.File
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Comprime il video di una serie prima di mandarlo al coach (§8.7): H.264 a
 * 480p sul lato corto, 30 fotogrammi al secondo, senza audio, circa 1 Mbit/s.
 * Un minuto pesa così sui 7–8 MB, che attraverso Tor passano in qualche
 * decina di secondi.
 *
 * Il file compresso può tenere i metadati dell'originale, compresa la
 * posizione: li toglie il nucleo prima di calcolarne l'impronta.
 */
@OptIn(UnstableApi::class)
object CompressioneVideo {
    const val CANALE = "org.opencoach.atleta/video"

    private const val LATO_CORTO = 480
    private const val FOTOGRAMMI = 30f
    private const val BITRATE = 1_000_000

    fun gestisci(app: Context, sorgente: String, destinazione: String, massimoS: Int, risultato: MethodChannel.Result) {
        val (larghezza, altezza, durataMs) = try {
            misura(sorgente)
        } catch (e: Exception) {
            risultato.error("non_leggibile", e.message, null)
            return
        }
        if (durataMs > massimoS * 1000L + 500) {
            risultato.error("troppo_lungo", null, durataMs)
            return
        }
        val effetti = mutableListOf<androidx.media3.common.Effect>(
            FrameDropEffect.createDefaultFrameDropEffect(FOTOGRAMMI),
        )
        val corto = min(larghezza, altezza)
        if (corto > LATO_CORTO) {
            val scala = LATO_CORTO.toDouble() / corto
            effetti += Presentation.createForWidthAndHeight(
                pari(larghezza * scala),
                pari(altezza * scala),
                Presentation.LAYOUT_SCALE_TO_FIT,
            )
        }
        val video = EditedMediaItem.Builder(MediaItem.fromUri(File(sorgente).toURI().toString()))
            .setRemoveAudio(true)
            .setEffects(Effects(emptyList(), effetti))
            .build()
        File(destinazione).delete()
        Transformer.Builder(app)
            .setVideoMimeType(MimeTypes.VIDEO_H264)
            .setEncoderFactory(
                DefaultEncoderFactory.Builder(app)
                    .setRequestedVideoEncoderSettings(
                        VideoEncoderSettings.Builder().setBitrate(BITRATE).build(),
                    )
                    .build(),
            )
            .addListener(object : Transformer.Listener {
                override fun onCompleted(composition: Composition, esito: ExportResult) {
                    risultato.success(mapOf("durata_ms" to esito.durationMs))
                }

                override fun onError(composition: Composition, esito: ExportResult, errore: ExportException) {
                    File(destinazione).delete()
                    risultato.error("compressione", errore.message, null)
                }
            })
            .build()
            .start(video, destinazione)
    }

    /** Larghezza e altezza come si vede il video, e durata. */
    private fun misura(percorso: String): Triple<Int, Int, Long> {
        val lettore = MediaMetadataRetriever()
        try {
            lettore.setDataSource(percorso)
            fun numero(chiave: Int) = lettore.extractMetadata(chiave)?.toLongOrNull() ?: 0L
            val larghezza = numero(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH).toInt()
            val altezza = numero(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT).toInt()
            if (larghezza <= 0 || altezza <= 0) throw IllegalArgumentException("Nessuna traccia video")
            val ruotato = numero(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION) % 180 != 0L
            val durata = numero(MediaMetadataRetriever.METADATA_KEY_DURATION)
            return if (ruotato) Triple(altezza, larghezza, durata) else Triple(larghezza, altezza, durata)
        } finally {
            lettore.release()
        }
    }

    private fun pari(valore: Double) = (valore / 2).roundToInt() * 2
}
