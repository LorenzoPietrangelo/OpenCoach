package org.opencoach.atleta_app

import android.content.Context
import android.util.Log
import androidx.work.CoroutineWorker
import androidx.work.ForegroundInfo
import androidx.work.WorkerParameters
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Una sync di tutti i coach in background, poi le notifiche delle schede
 * nuove (§7.4).
 */
class LavoroSync(context: Context, parametri: WorkerParameters) :
    CoroutineWorker(context, parametri) {

    override suspend fun doWork(): Result {
        try {
            // Il motore Flutter si usa solo dal thread principale.
            val notifiche = withContext(Dispatchers.Main) {
                MotoreFlutter.sincronizzaInBackground(applicationContext)
            }
            NotificheSchede.mostra(applicationContext, notifiche)
            // Per ultimo: può annullare anche questo lavoro, se è uno dei
            // controlli ravvicinati.
            if (notifiche.any { it["conversazione"] == true }) {
                PianificazioneSync.controlliRavvicinati(applicationContext)
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            // Il problema per l'interfaccia l'ha già salvato il nucleo; si
            // riprova alla prossima occasione.
            Log.w("LavoroSync", "Sync in background non riuscita", e)
        }
        return Result.success()
    }

    override suspend fun getForegroundInfo(): ForegroundInfo =
        NotificheSchede.syncInCorso(applicationContext)
}
