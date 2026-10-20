# Programma del coach

Interfaccia desktop di Open Coach (Windows, macOS, Linux) sopra `coach_nucleo`. Comandi e requisiti sono nel [README principale](../../README.md).

- `lib/main.dart`: avvio, scelta del portachiavi e di Tor, schermate d'errore all'avvio.
- `lib/servizi.dart`: ciò che l'interfaccia usa del programma, per poterlo sostituire nei test.
- `lib/piattaforma/`: area di notifica, finestra, avvio automatico, notifiche, portachiavi, percorsi.
- `lib/schermate/`: le schermate.
- `lib/l10n/app_it.arb`: i testi.
