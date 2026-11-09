package org.opencoach.atleta_app

import android.content.Context
import android.media.AudioAttributes
import android.media.Ringtone
import android.media.RingtoneManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager

/**
 * Il segnale di fine recupero (§10.2). `SystemSound.alert` di Flutter su
 * Android non suona niente, e `HapticFeedback` dipende dalla vibrazione al
 * tocco nelle impostazioni del telefono: qui suona il suono delle notifiche
 * del telefono come una sveglia (volume della sveglia, si sente anche con il
 * telefono in silenzioso e sopra la musica) e vibra.
 */
object SuonoRecupero {
    const val CANALE = "org.opencoach.atleta/suono"

    /** Oltre questo tempo il suono si ferma, anche se è lungo. */
    private const val DURATA_MASSIMA_MS = 4_000L

    private val vibrazione = longArrayOf(0, 400, 200, 400, 200, 400)

    private var inCorso: Ringtone? = null
    private val principale = Handler(Looper.getMainLooper())

    fun suona(context: Context) {
        vibra(context)
        val uri = RingtoneManager.getActualDefaultRingtoneUri(context, RingtoneManager.TYPE_NOTIFICATION)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            ?: return
        val suono = RingtoneManager.getRingtone(context, uri) ?: return
        suono.audioAttributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        inCorso?.stop()
        inCorso = suono
        suono.play()
        principale.postDelayed({
            suono.stop()
            if (inCorso === suono) inCorso = null
        }, DURATA_MASSIMA_MS)
    }

    private fun vibra(context: Context) {
        val vibratore = if (Build.VERSION.SDK_INT >= 31) {
            context.getSystemService(VibratorManager::class.java)?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Vibrator::class.java)
        } ?: return
        if (!vibratore.hasVibrator()) return
        vibratore.vibrate(
            VibrationEffect.createWaveform(vibrazione, -1),
            AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM).build(),
        )
    }
}
