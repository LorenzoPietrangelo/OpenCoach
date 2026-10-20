package org.opencoach.atleta_app

import android.content.Context
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

    override fun onStart() {
        super.onStart()
        MotoreFlutter.attivita = this
    }

    override fun onStop() {
        if (MotoreFlutter.attivita === this) MotoreFlutter.attivita = null
        super.onStop()
    }
}
