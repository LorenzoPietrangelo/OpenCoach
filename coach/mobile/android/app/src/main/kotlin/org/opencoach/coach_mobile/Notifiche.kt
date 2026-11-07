package org.opencoach.coach_mobile

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build

/**
 * Le novità trovate in background (§16.4). Dicono chi ha scritto e quanti sono,
 * mai il testo. Il nome dell'atleta è comunque un dato personale: sullo schermo
 * bloccato si legge solo che ci sono novità.
 */
object Notifiche {
    private const val CANALE = "novita"

    /** Una notifica per atleta: la successiva dello stesso atleta la sostituisce. */
    private const val ID_PRIMO_ATLETA = 1000

    /** [notifiche] arriva dal codice Dart: per ogni atleta, id, titolo e testo. */
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
                CANALE,
                context.getString(R.string.canale_novita),
                NotificationManager.IMPORTANCE_DEFAULT,
            ),
        )
        val apri = PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_IMMUTABLE,
        )
        val pubblica = Notification.Builder(context, CANALE)
            .setSmallIcon(R.drawable.ic_notifica)
            .setContentTitle(context.getString(R.string.nome_app))
            .setContentText(context.getString(R.string.novita_schermo_bloccato))
            .build()
        for (dati in notifiche) {
            val atleta = dati["atleta"] as String
            val notifica = Notification.Builder(context, CANALE)
                .setSmallIcon(R.drawable.ic_notifica)
                .setContentTitle(dati["titolo"] as String)
                .setContentText(dati["testo"] as String)
                .setContentIntent(apri)
                .setAutoCancel(true)
                .setVisibility(Notification.VISIBILITY_PRIVATE)
                .setPublicVersion(pubblica)
                .build()
            gestore.notify(ID_PRIMO_ATLETA + (atleta.hashCode() and 0xFFFF), notifica)
        }
    }
}
