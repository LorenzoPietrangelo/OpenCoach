# App dell'atleta

App Flutter per Android e iOS sopra il nucleo in `../nucleo`, che contiene tutta la logica: archivio, abbinamento, coda dei log, sync.

## Stato

- Schermate (`lib/schermate`):
  - elenco dei coach con lo stato della sync (§7.5) e le schede da vedere;
  - abbinamento con il QR d'invito o con il link incollato. La scansione usa [flutter_zxing](https://pub.dev/packages/flutter_zxing), che decodifica con zxing-cpp sul telefono senza servizi Google;
  - apertura del link `opencoach://invito` da un'altra app (§5.3): porta all'abbinamento sopra la schermata in cui si trova l'atleta. Il sistema passa il link a Flutter come una rotta, e `lib/piattaforma/inviti_in_arrivo.dart` lo raccoglie. Su Android lo passa `MainActivity.kt`, perché Flutter da solo perderebbe il link che apre l'app: il motore del processo esegue già il codice Dart. `MainActivity` è `singleTask`, così il link non crea una seconda attività sullo stesso motore;
  - pagina del coach con lo stato della sync, «Sincronizza ora», le schede (avviso «Da vedere», «Archivio») e lo storico. Ogni allenamento dello storico mostra se è in attesa, inviato o rifiutato, e si modifica, si elimina o si rimette in coda;
  - dettaglio della scheda con sedute, esercizi e prescrizione;
  - esecuzione di una seduta o di un allenamento libero, con le serie precompilate dalla prescrizione, il timer di recupero, note e RPE;
  - impostazioni: coach collegati con indirizzo e ultima sync, scollegamento e cancellazione dei dati, frequenza della sync in background ed esportazione JSON. L'esportazione passa dalla condivisione del sistema con [share_plus](https://pub.dev/packages/share_plus).
- Cassaforte di chiavi e token su Keystore e Keychain (`lib/piattaforma/cassaforte_sicura.dart`). I backup di Android sono disattivati.
- Testi in `lib/l10n/app_it.arb`, generati con `flutter gen-l10n`.
- Tor su Android: `MainActivity.kt` avvia TorService di [tor-android](https://github.com/guardianproject/tor-android) e `lib/piattaforma/avviatore_android.dart` passa la sua porta di controllo a `TrasportoTorControllato` del nucleo. Il proxy SOCKS ascolta su un socket Unix nella cartella di Tor, così lo usa solo l'app. Provato su un telefono contro `coach_dev` sulla rete Tor vera.
- Tor su iOS non c'è ancora: `lib/piattaforma/tor_non_integrato.dart` è un segnaposto, e ogni sync si ferma con «Tor non parte».
- Su iOS mancano anche la sync in background e una prova di compilazione: serve un Mac. Anche l'apertura dei link (`CFBundleURLTypes` nell'Info.plist, la gestione dei link di Flutter) non è stata provata.

## Comandi

Serve Flutter in un percorso senza spazi: su questo PC c'è la copia in `D:\opencoach-strumenti\flutter`. Il progetto non fa parte del workspace Dart della cartella principale, quindi ha un proprio `pubspec.lock`.

```
cd atleta/app
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

Dopo aver cambiato i testi in `lib/l10n/app_it.arb` va rigenerata la classe `Testi`: `flutter test` e `flutter analyze` non sempre lo fanno da sé.

```
flutter gen-l10n
```
