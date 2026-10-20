package org.opencoach.atleta_app

import android.content.Context
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.OutOfQuotaPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import java.util.concurrent.TimeUnit

/**
 * Sync in background con WorkManager (§7.4): un lavoro periodico,
 * predefinito ogni 60 minuti e impostabile dall'atleta, solo con la rete e la
 * batteria non scarica. C'è solo se almeno un coach è collegato.
 */
object PianificazioneSync {
    const val MINUTI_PREDEFINITI = 60

    private const val PREFERENZE = "sync_in_background"
    private const val MINUTI = "minuti"
    private const val PERIODICA = "sync_periodica"
    private const val IN_CHIUSURA = "sync_in_chiusura"

    fun minuti(context: Context) = preferenze(context).getInt(MINUTI, MINUTI_PREDEFINITI)

    /** Nuova frequenza scelta dall'atleta; 0 la disattiva. */
    fun impostaMinuti(context: Context, minuti: Int, attiva: Boolean) {
        preferenze(context).edit().putInt(MINUTI, minuti).apply()
        pianifica(context, attiva, ExistingPeriodicWorkPolicy.UPDATE)
    }

    /** Allinea il lavoro ai coach collegati, senza spostarne la scadenza. */
    fun aggiorna(context: Context, attiva: Boolean) =
        pianifica(context, attiva, ExistingPeriodicWorkPolicy.KEEP)

    /**
     * Una sync iniziata in primo piano prosegue come lavoro accelerato se
     * l'app viene chiusa.
     */
    fun prosegui(context: Context) {
        val richiesta = OneTimeWorkRequestBuilder<LavoroSync>()
            .setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
            .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
            .build()
        WorkManager.getInstance(context)
            .enqueueUniqueWork(IN_CHIUSURA, ExistingWorkPolicy.KEEP, richiesta)
    }

    private fun pianifica(context: Context, attiva: Boolean, politica: ExistingPeriodicWorkPolicy) {
        val lavori = WorkManager.getInstance(context)
        val minuti = minuti(context)
        if (!attiva || minuti <= 0) {
            lavori.cancelUniqueWork(PERIODICA)
            return
        }
        val vincoli = Constraints.Builder()
            .setRequiredNetworkType(NetworkType.CONNECTED)
            .setRequiresBatteryNotLow(true)
            .build()
        val richiesta = PeriodicWorkRequestBuilder<LavoroSync>(minuti.toLong(), TimeUnit.MINUTES)
            .setConstraints(vincoli)
            .build()
        lavori.enqueueUniquePeriodicWork(PERIODICA, politica, richiesta)
    }

    private fun preferenze(context: Context) =
        context.getSharedPreferences(PREFERENZE, Context.MODE_PRIVATE)
}
