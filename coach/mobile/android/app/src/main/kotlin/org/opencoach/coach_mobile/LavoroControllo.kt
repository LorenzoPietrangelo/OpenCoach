package org.opencoach.coach_mobile

import android.content.Context
import android.util.Log
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** Un controllo in background: manda la coda, guarda le novità e le annuncia (§16.4). */
class LavoroControllo(context: Context, parametri: WorkerParameters) :
    CoroutineWorker(context, parametri) {

    override suspend fun doWork(): Result {
        try {
            // Il motore Flutter si usa solo dal thread principale.
            val notifiche = withContext(Dispatchers.Main) {
                MotoreFlutter.controllaInBackground(applicationContext)
            }
            Notifiche.mostra(applicationContext, notifiche)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            // Il PC può essere spento: si riprova alla prossima occasione.
            Log.w("LavoroControllo", "Controllo in background non riuscito")
        }
        return Result.success()
    }
}
