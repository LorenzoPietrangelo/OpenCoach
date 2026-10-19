# Open Coach

Programma per coach e app per atleti, senza server: il PC del coach fa da server per i suoi atleti tramite un onion service Tor. Le regole del sistema sono in [specifiche.md](specifiche.md).

## Stato

| Parte | Cartella | Stato |
| --- | --- | --- |
| Protocollo condiviso | `pacchetti/protocollo` | Fatto: codifiche, inviti, validazione di schede e log, messaggi dell'API, client HTTP via SOCKS5 |
| Nucleo del programma del coach | `coach/nucleo` | Fatto: archivio SQLite, atleti, inviti, abbinamento, schede, sync, server HTTP, gestione di Tor |
| Interfaccia del programma del coach (Flutter desktop) | `coach/app` | Da fare |
| Nucleo dell'app dell'atleta | `atleta/nucleo` | Fatto: archivio SQLite, abbinamento, coda dei log, sync, stati e ritentativi per l'interfaccia, esecuzione degli allenamenti, trasporto Tor sulla porta di controllo |
| App dell'atleta (Flutter) | `atleta/app` | Iniziata: elenco dei coach, abbinamento con il link incollato, cassaforte su Keystore e Keychain, Tor su Android con tor-android (da provare su un telefono). Tor su iOS da fare |
| Backup cifrato, esportazioni, «Reimposta identità» | `coach/nucleo` | Da fare |

## Requisiti

Dart 3.11, quello incluso in Flutter 3.41.

Gli hook di build di Dart, usati da `sqlite3`, non funzionano se l'SDK sta in un percorso con spazi. Su questo PC i comandi vanno lanciati con la copia senza spazi in `D:\opencoach-strumenti\dart-sdk\bin\dart.exe`, oppure con Flutter spostato in un percorso senza spazi, come consiglia la sua documentazione.

Per l'app dell'atleta c'è una copia di Flutter senza spazi in `D:\opencoach-strumenti\flutter`. Per Android servono anche Java 17 e l'Android SDK con la piattaforma 36; Android Studio non è necessario.

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
