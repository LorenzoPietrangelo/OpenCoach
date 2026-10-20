package org.opencoach.atleta_app

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import androidx.work.ForegroundInfo

/**
 * Notifiche locali: le schede nuove dopo una sync in background (§7.4) e la
 * sync in corso, quando un lavoro accelerato gira come servizio in primo
 * piano.
 */
object NotificheSchede {
    private const val CANALE_SCHEDE = "schede"
    private const val CANALE_SYNC = "sync"
    private const val ID_SYNC = 1

    /** Una notifica per coach: la successiva dello stesso coach la sostituisce. */
    private const val ID_PRIMO_COACH = 1000

    /** [notifiche] arriva dal nucleo: per ogni coach, il suo id, titolo e testo. */
    fun mostra(context: Context, notifiche: List<Map<String, Any?>>) {
        if (notifiche.isEmpty()) return
        if (Build.VERSION.SDK_INT >= 33 &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        val gestore = context.getSystemService(NotificationManager::class.java)
        gestore.createNotificationChannel(
            NotificationChannel(
                CANALE_SCHEDE,
                context.getString(R.string.canale_schede),
                NotificationManager.IMPORTANCE_DEFAULT,
            ),
        )
        val apri = PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_IMMUTABLE,
        )
        for (dati in notifiche) {
            val coach = (dati["coach"] as Number).toInt()
            val notifica = Notification.Builder(context, CANALE_SCHEDE)
                .setSmallIcon(R.drawable.ic_notifica)
                .setContentTitle(dati["titolo"] as String)
                .setContentText(dati["testo"] as String)
                .setContentIntent(apri)
                .setAutoCancel(true)
                .build()
            gestore.notify(ID_PRIMO_COACH + coach, notifica)
        }
    }

    fun syncInCorso(context: Context): ForegroundInfo {
        val gestore = context.getSystemService(NotificationManager::class.java)
        gestore.createNotificationChannel(
            NotificationChannel(
                CANALE_SYNC,
                context.getString(R.string.canale_sync),
                NotificationManager.IMPORTANCE_LOW,
            ),
        )
        val notifica = Notification.Builder(context, CANALE_SYNC)
            .setSmallIcon(R.drawable.ic_notifica)
            .setContentTitle(context.getString(R.string.sync_in_corso))
            .setOngoing(true)
            .build()
        return if (Build.VERSION.SDK_INT >= 29) {
            ForegroundInfo(ID_SYNC, notifica, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            ForegroundInfo(ID_SYNC, notifica)
        }
    }
}
