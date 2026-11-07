package org.opencoach.coach_mobile

import android.content.Context
import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * L'interfaccia dell'app. Il motore Flutter, con Tor e la coda dei messaggi, è
 * quello del processo ([MotoreFlutter]): sopravvive all'attività, così i
 * controlli in background lo ritrovano. È una FragmentActivity perché il
 * dialogo del blocco (local_auth) la chiede.
 */
class MainActivity : FlutterFragmentActivity() {
    override fun provideFlutterEngine(context: Context): FlutterEngine =
        MotoreFlutter.perAttivita(context)

    override fun shouldDestroyEngineWithHost() = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (savedInstanceState == null &&
            (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) == 0
        ) {
            apriLink(intent)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        apriLink(intent)
    }

    override fun onStart() {
        super.onStart()
        MotoreFlutter.attivita = this
    }

    override fun onStop() {
        if (MotoreFlutter.attivita === this) MotoreFlutter.attivita = null
        super.onStop()
    }

    /** Il link di prova: esiste solo nel manifest della build di debug. */
    private fun apriLink(intent: Intent) {
        val link = intent.data ?: return
        flutterEngine?.navigationChannel?.pushRouteInformation(link.toString())
    }
}
