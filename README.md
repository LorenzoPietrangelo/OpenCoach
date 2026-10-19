# Open Coach

Programma per coach e app per atleti, senza server: il PC del coach fa da server per i suoi atleti tramite un onion service Tor. Le regole del sistema sono in [specifiche.md](specifiche.md).

## Stato

| Parte | Cartella | Stato |
| --- | --- | --- |
| Protocollo condiviso | `pacchetti/protocollo` | Fatto: codifiche, inviti, validazione di schede e log, messaggi dell'API, client HTTP via SOCKS5 |
| Nucleo del programma del coach | `coach/nucleo` | Fatto: archivio SQLite, atleti, inviti, abbinamento, schede, sync, server HTTP, gestione di Tor |
| Interfaccia del programma del coach (Flutter desktop) | `coach/app` | Da fare |
| Nucleo dell'app dell'atleta | `atleta/nucleo` | Fatto: archivio SQLite, abbinamento, coda dei log, sync, stati e ritentativi per l'interfaccia |
| App dell'atleta (Flutter) | `atleta/app` | Da fare |
| Backup cifrato, esportazioni, «Reimposta identità» | `coach/nucleo` | Da fare |

## Requisiti

Dart 3.11, quello incluso in Flutter 3.41.

Gli hook di build di Dart, usati da `sqlite3`, non funzionano se l'SDK sta in un percorso con spazi. Su questo PC i comandi vanno lanciati con la copia senza spazi in `D:\opencoach-strumenti\dart-sdk\bin\dart.exe`, oppure con Flutter spostato in un percorso senza spazi, come consiglia la sua documentazione.

## Comandi

Dalla cartella principale:

```
dart pub get
```

Test del protocollo e del nucleo:

```
cd pacchetti/protocollo && dart test
cd coach/nucleo && dart test
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
