# App dell'atleta

App Flutter per Android e iOS sopra il nucleo in `../nucleo`, che contiene tutta la logica: archivio, abbinamento, coda dei log, sync.

## Stato

- Schermate: elenco dei coach con lo stato della sync (§7.5) e abbinamento incollando il link d'invito.
- Cassaforte di chiavi e token su Keystore e Keychain (`lib/piattaforma/cassaforte_sicura.dart`). I backup di Android sono disattivati.
- Testi in `lib/l10n/app_it.arb`, generati con `flutter gen-l10n`.
- Tor su Android: `MainActivity.kt` avvia TorService di [tor-android](https://github.com/guardianproject/tor-android) e `lib/piattaforma/avviatore_android.dart` passa la sua porta di controllo a `TrasportoTorControllato` del nucleo. Il proxy SOCKS ascolta su un socket Unix nella cartella di Tor, così lo usa solo l'app. Non è ancora stato provato su un telefono.
- Tor su iOS non c'è ancora: `lib/piattaforma/tor_non_integrato.dart` è un segnaposto, e ogni sync si ferma con «Tor non parte».
- Mancano schede, esecuzione, storico, scansione del QR, sync in background e notifiche.

## Comandi

Serve Flutter in un percorso senza spazi: su questo PC c'è la copia in `D:\opencoach-strumenti\flutter`. Il progetto non fa parte del workspace Dart della cartella principale, quindi ha un proprio `pubspec.lock`.

```
cd atleta/app
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```
