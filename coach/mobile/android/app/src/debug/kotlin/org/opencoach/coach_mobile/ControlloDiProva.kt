package org.opencoach.coach_mobile

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager

/**
 * Solo per le prove: fa partire subito un controllo in background, senza
 * aspettare il lavoro periodico.
 *
 *     adb shell am broadcast -n org.opencoach.coach_mobile/.ControlloDiProva
 */
class ControlloDiProva : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        WorkManager.getInstance(context).enqueue(OneTimeWorkRequestBuilder<LavoroControllo>().build())
    }
}
