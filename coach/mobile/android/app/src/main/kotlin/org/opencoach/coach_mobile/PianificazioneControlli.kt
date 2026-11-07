package org.opencoach.coach_mobile

import android.content.Context
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import java.util.concurrent.TimeUnit

/**
 * Controlli in background con WorkManager (§16.4): un lavoro periodico,
 * predefinito ogni 15 minuti, il minimo di Android, solo con la rete e la
 * batteria non scarica. C'è solo con il telefono collegato.
 */
object PianificazioneControlli {
    const val MINUTI_PREDEFINITI = 15

    private const val PREFERENZE = "controlli_in_background"
    private const val MINUTI = "minuti"
    private const val PERIODICO = "controllo_periodico"

    fun minuti(context: Context) = preferenze(context).getInt(MINUTI, MINUTI_PREDEFINITI)

    /** Nuova frequenza scelta dal coach; 0 la disattiva. */
    fun impostaMinuti(context: Context, minuti: Int, attiva: Boolean) {
        preferenze(context).edit().putInt(MINUTI, minuti).apply()
        pianifica(context, attiva, ExistingPeriodicWorkPolicy.UPDATE)
    }

    /** Allinea il lavoro al collegamento, senza spostarne la scadenza. */
    fun aggiorna(context: Context, attiva: Boolean) =
        pianifica(context, attiva, ExistingPeriodicWorkPolicy.KEEP)

    private fun pianifica(context: Context, attiva: Boolean, politica: ExistingPeriodicWorkPolicy) {
        val lavori = WorkManager.getInstance(context)
        val minuti = minuti(context)
        if (!attiva || minuti <= 0) {
            lavori.cancelUniqueWork(PERIODICO)
            return
        }
        val vincoli = Constraints.Builder()
            .setRequiredNetworkType(NetworkType.CONNECTED)
            .setRequiresBatteryNotLow(true)
            .build()
        val richiesta = PeriodicWorkRequestBuilder<LavoroControllo>(minuti.toLong(), TimeUnit.MINUTES)
            .setConstraints(vincoli)
            .build()
        lavori.enqueueUniquePeriodicWork(PERIODICO, politica, richiesta)
    }

    private fun preferenze(context: Context) =
        context.getSharedPreferences(PREFERENZE, Context.MODE_PRIVATE)
}
