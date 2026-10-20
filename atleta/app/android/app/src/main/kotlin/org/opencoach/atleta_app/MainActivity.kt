package org.opencoach.atleta_app

import android.content.Context
import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * L'interfaccia dell'app. Il motore Flutter, con il nucleo e Tor, è quello del
 * processo ([MotoreFlutter]): sopravvive all'attività, così le sync in
 * background lo ritrovano.
 */
class MainActivity : FlutterActivity() {
    override fun provideFlutterEngine(context: Context): FlutterEngine =
        MotoreFlutter.perAttivita(context)

    override fun shouldDestroyEngineWithHost() = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Ricreata dal sistema o riaperta dalle app recenti, l'attività riceve
        // di nuovo l'intent con cui era partita: quel link è già stato aperto.
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

    /**
     * Passa al codice Dart (InvitiInArrivo) il link d'invito aperto da
     * un'altra app (§5.3), come una rotta da aprire. Flutter lo farebbe da
     * solo, ma all'avvio lo consegna solo se è l'attività a far partire il
     * codice Dart: qui lo fa partire sempre [MotoreFlutter], e il link
     * andrebbe perso. Per questo nel manifest la gestione di Flutter è spenta.
     */
    private fun apriLink(intent: Intent) {
        val link = intent.data ?: return
        flutterEngine?.navigationChannel?.pushRouteInformation(link.toString())
    }
}
