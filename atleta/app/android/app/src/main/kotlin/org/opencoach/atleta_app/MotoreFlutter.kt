package org.opencoach.atleta_app

import android.Manifest
import android.app.Activity
import android.app.ActivityManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.provider.Settings
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import java.io.File
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.withTimeout
import org.torproject.jni.TorService

/**
 * Un solo motore Flutter, e quindi un solo nucleo dell'atleta, per processo:
 * lo usano sia l'attività sia le sync in background (§7.4). Due nuclei
 * comanderebbero lo stesso tor e lo stesso archivio, e due tor nello stesso
 * processo non possono convivere.
 *
 * Se lo chiede l'attività il motore parte da `main`; se lo chiede una sync in
 * background parte da `avvioInBackground`, senza interfaccia, e la mostra se
 * poi si apre l'app. Resta vivo finché vive il processo. Va usato dal thread
 * principale.
 */
object MotoreFlutter {
    private const val CANALE_TOR = "org.opencoach.atleta/tor"
    private const val CANALE_BACKGROUND = "org.opencoach.atleta/background"

    /** Tempo concesso al codice Dart per aprire l'archivio e la cassaforte. */
    private const val ATTESA_NUCLEO_MS = 60_000L

    /** Preferenze degli avvisi mostrati all'atleta. */
    private const val AVVISI = "avvisi"
    private const val AVVISO_BATTERIA = "batteria_rimandato_fino"

    private fun avvisi(context: Context) =
        context.getSharedPreferences(AVVISI, Context.MODE_PRIVATE)

    private var motore: FlutterEngine? = null
    private var canale: MethodChannel? = null
    private var conInterfaccia = false
    private var pronto = CompletableDeferred<Unit>()
    private var collegamentoTor: ServiceConnection? = null

    /** Il permesso per le notifiche è stato chiesto prima che l'attività partisse. */
    private var permessoInSospeso = false

    /** L'attività visibile, per chiedere i permessi. */
    var attivita: Activity? = null
        set(valore) {
            field = valore
            if (valore != null && permessoInSospeso) chiediPermessoNotifiche()
        }

    /** Il motore per l'attività: quello del processo, o uno nuovo da `main`. */
    fun perAttivita(context: Context): FlutterEngine {
        val esistente = motore
        if (esistente == null) {
            conInterfaccia = true
            return crea(context, avvio = null)
        }
        if (!conInterfaccia) {
            conInterfaccia = true
            // Se il nucleo non è ancora pronto, lo saprà dalla risposta a «pronto».
            if (pronto.isCompleted) canale?.invokeMethod("mostraInterfaccia", null)
        }
        return esistente
    }

    /**
     * Sincronizza tutti i coach con il nucleo del processo, creando il motore
     * senza interfaccia se non c'è. Restituisce le notifiche da mostrare.
     */
    suspend fun sincronizzaInBackground(context: Context): List<Map<String, Any?>> {
        if (motore == null) crea(context, avvio = "avvioInBackground")
        withTimeout(ATTESA_NUCLEO_MS) { pronto.await() }
        val esito = CompletableDeferred<Any?>()
        canale!!.invokeMethod(
            "sincronizzaInBackground",
            null,
            object : MethodChannel.Result {
                override fun success(risultato: Any?) {
                    esito.complete(risultato)
                }

                override fun error(codice: String, messaggio: String?, dettagli: Any?) {
                    esito.completeExceptionally(IllegalStateException("$codice: $messaggio"))
                }

                override fun notImplemented() {
                    esito.completeExceptionally(IllegalStateException("sync in background non gestita"))
                }
            },
        )
        @Suppress("UNCHECKED_CAST")
        return esito.await() as? List<Map<String, Any?>> ?: emptyList()
    }

    /** [avvio] è la funzione Dart da cui partire; null per `main`. */
    private fun crea(context: Context, avvio: String?): FlutterEngine {
        val app = context.applicationContext
        // Il motore inizializza il loader di Flutter: i punti d'ingresso Dart
        // si possono costruire solo dopo.
        val nuovo = FlutterEngine(app)
        val messaggi = nuovo.dartExecutor.binaryMessenger
        MethodChannel(messaggi, CANALE_TOR).setMethodCallHandler { chiamata, risultato ->
            when (chiamata.method) {
                "avvia" -> {
                    avviaTor(app)
                    risultato.success(socketDiControllo(app).absolutePath)
                }
                else -> risultato.notImplemented()
            }
        }
        MethodChannel(messaggi, CompressioneVideo.CANALE).setMethodCallHandler { chiamata, risultato ->
            when (chiamata.method) {
                "comprimi" -> CompressioneVideo.gestisci(
                    app,
                    chiamata.argument<String>("sorgente")!!,
                    chiamata.argument<String>("destinazione")!!,
                    chiamata.argument<Int>("massimo_s")!!,
                    risultato,
                )
                else -> risultato.notImplemented()
            }
        }
        val background = MethodChannel(messaggi, CANALE_BACKGROUND)
        background.setMethodCallHandler { chiamata, risultato ->
            when (chiamata.method) {
                "pronto" -> {
                    pronto.complete(Unit)
                    risultato.success(conInterfaccia)
                }
                "pianifica" -> {
                    PianificazioneSync.aggiorna(app, chiamata.argument<Boolean>("attiva") == true)
                    risultato.success(null)
                }
                "frequenza" -> risultato.success(PianificazioneSync.minuti(app))
                "impostaFrequenza" -> {
                    PianificazioneSync.impostaMinuti(
                        app,
                        chiamata.argument<Int>("minuti") ?: PianificazioneSync.MINUTI_PREDEFINITI,
                        chiamata.argument<Boolean>("attiva") == true,
                    )
                    risultato.success(null)
                }
                "prosegui" -> {
                    PianificazioneSync.prosegui(app)
                    risultato.success(null)
                }
                "permessoNotifiche" -> {
                    chiediPermessoNotifiche()
                    risultato.success(null)
                }
                // Con la batteria «Limitata» il sistema non esegue i lavori
                // in background dell'app.
                "limitata" -> risultato.success(
                    Build.VERSION.SDK_INT >= 28 &&
                        app.getSystemService(ActivityManager::class.java).isBackgroundRestricted,
                )
                // «Limitata»: nessun lavoro in background. «Senza restrizioni»:
                // l'app è esclusa dall'ottimizzazione della batteria, e i
                // lavori periodici partono quasi in orario. «Ottimizzata», il
                // default: Android può rimandarli anche di ore.
                "statoBatteria" -> risultato.success(
                    when {
                        Build.VERSION.SDK_INT >= 28 &&
                            app.getSystemService(ActivityManager::class.java)
                                .isBackgroundRestricted -> "limitata"
                        app.getSystemService(PowerManager::class.java)
                            .isIgnoringBatteryOptimizations(app.packageName) -> "senza_restrizioni"
                        else -> "ottimizzata"
                    },
                )
                // Fino a quando non riproporre il consiglio sulla batteria,
                // in millisecondi dal 1970; 0 se non è stato rimandato.
                "avvisoBatteriaRimandato" -> risultato.success(
                    avvisi(app).getLong(AVVISO_BATTERIA, 0L),
                )
                "rimandaAvvisoBatteria" -> {
                    avvisi(app).edit()
                        .putLong(
                            AVVISO_BATTERIA,
                            chiamata.argument<Number>("fino")?.toLong() ?: 0L,
                        )
                        .apply()
                    risultato.success(null)
                }
                "apriImpostazioniApp" -> {
                    app.startActivity(
                        Intent(
                            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            Uri.fromParts("package", app.packageName, null),
                        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                    )
                    risultato.success(null)
                }
                else -> risultato.notImplemented()
            }
        }
        canale = background
        pronto = CompletableDeferred()
        motore = nuovo
        nuovo.dartExecutor.executeDartEntrypoint(
            if (avvio == null) {
                DartExecutor.DartEntrypoint.createDefault()
            } else {
                DartExecutor.DartEntrypoint(
                    FlutterInjector.instance().flutterLoader().findAppBundlePath(),
                    avvio,
                )
            },
        )
        return nuovo
    }

    /**
     * Tor resta legato al processo: con l'app chiusa il trasporto gli toglie
     * la rete (`DisableNetwork`), e il sistema lo chiude insieme al processo.
     */
    private fun avviaTor(app: Context) {
        if (collegamentoTor != null) return
        val nuovo = object : ServiceConnection {
            override fun onServiceConnected(nome: ComponentName?, servizio: IBinder?) {}

            override fun onServiceDisconnected(nome: ComponentName?) {}
        }
        app.bindService(Intent(app, TorService::class.java), nuovo, Context.BIND_AUTO_CREATE)
        collegamentoTor = nuovo
    }

    /**
     * La porta di controllo che TorService passa a tor (--ControlSocket): un
     * socket Unix nella sua cartella dati, accessibile solo all'app.
     */
    private fun socketDiControllo(app: Context) =
        File(File(app.getDir("TorService", Context.MODE_PRIVATE), "data"), "ControlSocket")

    /**
     * Da Android 13 le notifiche chiedono un permesso. All'apertura il codice
     * Dart lo chiede prima che l'attività sia partita: allora la richiesta
     * aspetta l'attività.
     */
    private fun chiediPermessoNotifiche() {
        if (Build.VERSION.SDK_INT < 33) return
        val visibile = attivita
        permessoInSospeso = visibile == null
        if (visibile == null) return
        val permesso = Manifest.permission.POST_NOTIFICATIONS
        if (visibile.checkSelfPermission(permesso) == PackageManager.PERMISSION_GRANTED) return
        visibile.requestPermissions(arrayOf(permesso), 1)
    }
}
