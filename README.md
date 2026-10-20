# Open Coach

Programma per coach e app per atleti, senza server: il PC del coach fa da server per i suoi atleti tramite un onion service Tor. Le regole del sistema sono in [specifiche.md](specifiche.md).

## Stato

| Parte | Cartella | Stato |
| --- | --- | --- |
| Protocollo condiviso | `pacchetti/protocollo` | Fatto: codifiche, inviti, validazione di schede e log, messaggi dell'API, client HTTP via SOCKS5 |
| Nucleo del programma del coach | `coach/nucleo` | Fatto: archivio SQLite, atleti, inviti, abbinamento, schede, sync, server HTTP, gestione di Tor |
| Interfaccia del programma del coach (Flutter desktop) | `coach/app` | Da fare |
| Nucleo dell'app dell'atleta | `atleta/nucleo` | Fatto: archivio SQLite, abbinamento, coda dei log, sync, stati e ritentativi per l'interfaccia, esecuzione degli allenamenti, trasporto Tor sulla porta di controllo, provato sulla rete Tor vera con `atleta_dev` |
| App dell'atleta (Flutter) | `atleta/app` | Iniziata: elenco dei coach, abbinamento con il link incollato, cassaforte su Keystore e Keychain, Tor su Android con tor-android, provato su un telefono (abbinamento e sync sulla rete Tor vera), sync in background con WorkManager e notifiche delle schede nuove su Android, impostazioni con la frequenza della sync. Tor e sync in background su iOS da fare |
| Backup cifrato, esportazioni, «Reimposta identità» | `coach/nucleo` | Da fare |

## Requisiti

Dart 3.11, quello incluso in Flutter 3.41.

Gli hook di build di Dart, usati da `sqlite3`, non funzionano se l'SDK sta in un percorso con spazi. Su questo PC i comandi vanno lanciati con la copia senza spazi in `D:\opencoach-strumenti\dart-sdk\bin\dart.exe`, oppure con Flutter spostato in un percorso senza spazi, come consiglia la sua documentazione.

Per l'app dell'atleta c'è una copia di Flutter senza spazi in `D:\opencoach-strumenti\flutter`. Per Android servono anche Java 17 e l'Android SDK con le piattaforme 36 e 37 (tor-android chiede di compilare con la 37); Android Studio non è necessario.

## Comandi

Dalla cartella principale:

```
dart pub get
```

Test del protocollo e dei due nuclei:

```
cd pacchetti/protocollo && dart test
cd coach/nucleo && dart test
cd atleta/nucleo && dart test
```

App dell'atleta, con Flutter. Non fa parte del workspace Dart: ha le sue dipendenze, da prendere con `flutter pub get`:

```
cd atleta/app
flutter pub get
flutter test
flutter build apk --debug
```

Su un telefono collegato con il debug USB, nelle build di debug una sync in background parte subito, senza aspettare il lavoro periodico di WorkManager:

```
adb shell am broadcast -n org.opencoach.atleta_app/.SyncDiProva
```

Le sync in background partono solo se nelle impostazioni del telefono la batteria dell'app non è «Limitata»; le impostazioni dell'app lo segnalano.

Prova sulla rete Tor vera, che dura qualche minuto. Serve l'eseguibile `tor` del Tor Expert Bundle:

```
cd coach/nucleo
OPENCOACH_TOR=<percorso di tor.exe> dart test test/tor_reale_test.dart
```

Programma del coach da riga di comando, per le prove manuali:

```
cd coach/nucleo
dart run coach_nucleo:coach_dev --dati dati_dev --tor <percorso di tor.exe>
```

Senza `--tor` il server resta raggiungibile solo in locale.

Telefono dell'atleta da riga di comando, per provare l'app contro `coach_dev` sulla rete Tor vera. Ogni comando avvia tor, fa il suo lavoro e lo chiude; la cartella dati conserva archivio, chiavi e stato di tor, così gli avvii successivi sono rapidi:

```
cd atleta/nucleo
dart run atleta_nucleo:atleta_dev --dati dati_dev --tor <percorso di tor.exe> invito "<link dell'invito>"
dart run atleta_nucleo:atleta_dev --dati dati_dev --tor <percorso di tor.exe> allenamento
```

Gli altri comandi sono `sync`, `stato` e `schede`. `--verboso` mostra il registro del nucleo e quello di tor; con `--log-tor "[rend]info notice"` tor registra anche i passi dei servizi onion. Il link va tra virgolette, perché contiene `&`. Nella cartella dati chiavi e token stanno in chiaro: serve solo per le prove.
