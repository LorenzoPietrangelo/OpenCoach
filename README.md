# Open Coach

Programma per coach e app per atleti, senza server: il PC del coach fa da server per i suoi atleti tramite un onion service Tor. Le regole del sistema sono in [specifiche.md](specifiche.md).

## Stato

| Parte | Cartella | Stato |
| --- | --- | --- |
| Protocollo condiviso | `pacchetti/protocollo` | Fatto: codifiche, inviti, validazione di schede e log, messaggi dell'API, client HTTP via SOCKS5 |
| Nucleo del programma del coach | `coach/nucleo` | Fatto: archivio SQLite, atleti, inviti, abbinamento, schede, sync, server HTTP, gestione di Tor, backup cifrato e ripristino, esportazioni JSON e CSV, «Reimposta identità», registro tecnico; provato sulla rete Tor vera |
| Interfaccia del programma del coach (Flutter desktop) | `coach/app` | Scritta e provata con i test dei widget: primo avvio, atleti, inviti con QR, telefono e revoca, editor delle schede, allenamenti ricevuti, stato del servizio, impostazioni (backup, ripristino, Tor esterno, «Reimposta identità»), area di notifica, finestra che si riduce, avvio automatico, notifiche. Mai avviata come programma Windows: serve Visual Studio |
| Nucleo dell'app dell'atleta | `atleta/nucleo` | Fatto: archivio SQLite, abbinamento, coda dei log, sync, stati e ritentativi per l'interfaccia, esecuzione degli allenamenti, trasporto Tor sulla porta di controllo, provato sulla rete Tor vera con `atleta_dev` |
| App dell'atleta (Flutter) | `atleta/app` | Iniziata: elenco dei coach, abbinamento con il link incollato, cassaforte su Keystore e Keychain, Tor su Android con tor-android, provato su un telefono (abbinamento e sync sulla rete Tor vera), sync in background con WorkManager e notifiche delle schede nuove su Android, impostazioni con la frequenza della sync. Tor e sync in background su iOS da fare |

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

Programma del coach, con Flutter. Anche questo ha le sue dipendenze:

```
cd coach/app
flutter pub get
flutter test
flutter build windows
```

Per `flutter build windows` servono Visual Studio Build Tools con il carico di lavoro «Sviluppo di applicazioni desktop con C++» e la Modalità sviluppatore di Windows, che i plugin chiedono per i collegamenti simbolici. Per includere Tor nel programma (§9.2), copia il contenuto della cartella `tor` del Tor Expert Bundle in `coach/app/windows/tor`: la build lo mette accanto a `OpenCoach.exe`, dove il programma lo cerca. In sviluppo basta la variabile `OPENCOACH_TOR`. Le icone si rigenerano con `dart run tool/genera_icone.dart`.

L'installer si crea con Inno Setup 6 dopo la build: `iscc /DVersione=1.0.0 installer\opencoach.iss` dalla cartella `coach/app`. Installa per il solo utente, senza privilegi di amministratore, e alla disinstallazione lascia i dati in `%APPDATA%\OpenCoach`.

Senza Visual Studio in locale, la build la fa GitHub: il flusso `.github/workflows/build.yml` esegue tutti i test su Linux, poi su Windows scarica il Tor Expert Bundle, ne verifica la somma SHA-256 con l'elenco ufficiale, compila il programma e crea l'installer, che si scarica dagli artifact dell'esecuzione. Parte a ogni push su `master` e si può avviare a mano.

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
