package org.opencoach.atleta_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager

/**
 * Solo nelle build di debug: una sync in background subito, senza aspettare
 * il lavoro periodico, che WorkManager non anticipa. Per le prove sul
 * telefono:
 *
 *     adb shell am broadcast -n org.opencoach.atleta_app/.SyncDiProva
 */
class SyncDiProva : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        WorkManager.getInstance(context).enqueue(OneTimeWorkRequestBuilder<LavoroSync>().build())
    }
}
