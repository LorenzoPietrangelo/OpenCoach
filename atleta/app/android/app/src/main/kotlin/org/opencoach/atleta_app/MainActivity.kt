package org.opencoach.atleta_app

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.IBinder
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import org.torproject.jni.TorService

/**
 * Avvia Tor (TorService di tor-android) quando lo chiede il codice Dart, che
 * poi lo comanda dalla porta di controllo: vedi TrasportoTorControllato nel
 * nucleo dell'atleta.
 */
class MainActivity : FlutterActivity() {
    private var collegamento: ServiceConnection? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "org.opencoach.atleta/tor")
            .setMethodCallHandler { chiamata, risultato ->
                when (chiamata.method) {
                    "avvia" -> {
                        avviaTor()
                        risultato.success(socketDiControllo().absolutePath)
                    }
                    else -> risultato.notImplemented()
                }
            }
    }

    /** Tor resta legato all'attività: si ferma quando il sistema la chiude. */
    private fun avviaTor() {
        if (collegamento != null) return
        val nuovo = object : ServiceConnection {
            override fun onServiceConnected(nome: ComponentName?, servizio: IBinder?) {}

            override fun onServiceDisconnected(nome: ComponentName?) {}
        }
        bindService(Intent(this, TorService::class.java), nuovo, Context.BIND_AUTO_CREATE)
        collegamento = nuovo
    }

    override fun onDestroy() {
        collegamento?.let { unbindService(it) }
        collegamento = null
        super.onDestroy()
    }

    /**
     * La porta di controllo che TorService passa a tor (--ControlSocket): un
     * socket Unix nella sua cartella dati, accessibile solo all'app.
     */
    private fun socketDiControllo() =
        File(File(getDir("TorService", Context.MODE_PRIVATE), "data"), "ControlSocket")
}
