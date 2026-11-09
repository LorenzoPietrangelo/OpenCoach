import 'dart:async';
import 'dart:io';

import 'package:coach_nucleo/coach_nucleo.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'l10n/testi.dart';
import 'piattaforma/desktop.dart';
import 'piattaforma/istanza_unica.dart';
import 'piattaforma/percorsi.dart';
import 'piattaforma/portachiavi_sistema.dart';
import 'schermate/principale.dart';
import 'servizi.dart';

/// Versione del programma, la stessa del pubspec.
const versioneProgramma = '1.6.1';

Future<void> main(List<String> argomenti) async {
  WidgetsFlutterBinding.ensureInitialized();
  final cartellaDati = cartellaDatiPredefinita();
  // Se il programma è già aperto gli fa mostrare la finestra e si chiude,
  // prima di mostrarne una propria (§9.1).
  if (await IstanzaUnica.chiediAllaPrima(cartellaDati)) exit(0);

  final testi = lookupTesti(const Locale('it'));
  final avvio = _Avvio(desktop: DesktopReale(), cartellaDati: cartellaDati);
  await avvio.desktop.prepara(
    testi: TestiDesktop(titolo: testi.nomeApp, apri: testi.apriFinestra, esci: testi.esci),
    // All'avvio automatico il programma parte nell'area di notifica (§9.1).
    nascosto: argomenti.contains('--nascosto'),
    richiestaUscita: avvio.richiestaUscita,
  );
  await avvio.avvia();
}

/// Avvia il programma del coach e mostra l'interfaccia giusta: quella
/// normale, oppure una schermata d'errore se il programma è già aperto o se
/// l'identità non si legge.
class _Avvio {
  _Avvio({required this.desktop, required this.cartellaDati});

  final Desktop desktop;
  final String cartellaDati;
  final _navigatore = GlobalKey<NavigatorState>();
  Coach? _coach;
  Portachiavi? _portachiavi;
  IstanzaUnica? _istanza;

  Future<void> avvia() async {
    final portachiavi = _portachiavi ??= await scegliPortachiavi(cartellaDati);
    final tor = trovaTor(cartellaDati);
    try {
      final programma = await ProgrammaCoach.avvia(
        cartellaDati: cartellaDati,
        portachiavi: portachiavi,
        eseguibileTor: tor,
        catalogoCibo: trovaCatalogoCibo(),
        versioneProgramma: versioneProgramma,
        registra: debugPrint,
      );
      final coach = _coach = CoachInEsecuzione(programma, torTrovato: tor != null);
      _istanza ??= await IstanzaUnica.ascolta(
        cartellaDati,
        mostra: () => unawaited(desktop.mostraFinestra()),
      );
      runApp(
        AppCoach(
          coach: coach,
          desktop: desktop,
          ripristina: _ripristina,
          navigatore: _navigatore,
        ),
      );
    } on ProgrammaGiaAvviato {
      _errore((t) => t.giaAvviato);
    } on IdentitaIllegibile {
      _errore((t) => t.identitaIllegibile, recupero: true);
    }
  }

  /// Ripristino dalle impostazioni (§9.4): ferma il programma, sostituisce
  /// l'archivio e riavvia tutto.
  Future<EsitoRipristino> _ripristina(String file, String passphrase) async {
    await _coach?.chiudi();
    _coach = null;
    try {
      return await ProgrammaCoach.ripristina(
        file: file,
        passphrase: passphrase,
        cartellaDati: cartellaDati,
        portachiavi: _portachiavi!,
      );
    } finally {
      await avvia();
    }
  }

  void richiestaUscita() {
    unawaited(desktop.mostraFinestra());
    final contesto = _navigatore.currentContext;
    final coach = _coach;
    if (contesto == null || coach == null) {
      unawaited(desktop.esci());
      return;
    }
    unawaited(chiediUscita(contesto, coach, desktop));
  }

  void _errore(String Function(Testi t) messaggio, {bool recupero = false}) {
    unawaited(desktop.mostraFinestra());
    runApp(
      MaterialApp(
        localizationsDelegates: Testi.localizationsDelegates,
        supportedLocales: Testi.supportedLocales,
        locale: const Locale('it'),
        theme: ThemeData(colorSchemeSeed: Colors.teal),
        home: _SchermataErrore(
          messaggio: messaggio,
          esci: desktop.esci,
          ripristina: recupero ? _ripristinaDaErrore : null,
          nuovaIdentita: recupero ? _nuovaIdentita : null,
          desktop: desktop,
        ),
      ),
    );
  }

  Future<void> _ripristinaDaErrore(String file, String passphrase) async {
    await ProgrammaCoach.ripristina(
      file: file,
      passphrase: passphrase,
      cartellaDati: cartellaDati,
      portachiavi: _portachiavi!,
    );
    await avvia();
  }

  Future<void> _nuovaIdentita() async {
    await ProgrammaCoach.sostituisciIdentitaIllegibile(
      cartellaDati: cartellaDati,
      portachiavi: _portachiavi!,
    );
    await avvia();
  }
}

class _SchermataErrore extends StatefulWidget {
  const _SchermataErrore({
    required this.messaggio,
    required this.esci,
    required this.ripristina,
    required this.nuovaIdentita,
    required this.desktop,
  });

  final String Function(Testi t) messaggio;
  final Future<void> Function() esci;
  final Future<void> Function(String file, String passphrase)? ripristina;
  final Future<void> Function()? nuovaIdentita;
  final Desktop desktop;

  @override
  State<_SchermataErrore> createState() => _SchermataErroreState();
}

class _SchermataErroreState extends State<_SchermataErrore> {
  final _passphrase = TextEditingController();
  String? _file;
  String? _errore;

  @override
  void dispose() {
    _passphrase.dispose();
    super.dispose();
  }

  Future<void> _ripristina() async {
    final t = Testi.of(context);
    final file = _file;
    if (file == null) return;
    try {
      await widget.ripristina!(file, _passphrase.text);
    } on PassphraseErrata {
      setState(() => _errore = t.passphraseErrata);
    } on BackupNonValido catch (e) {
      setState(() => _errore = e.messaggio);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Testi.of(context);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(32),
            children: [
              Text(widget.messaggio(t), style: Theme.of(context).textTheme.titleMedium),
              if (widget.ripristina != null) ...[
                const SizedBox(height: 24),
                Text(t.recuperoDaBackup),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: Text(_file ?? t.nessunFile)),
                    TextButton(
                      onPressed: () async {
                        final scelto = await widget.desktop.scegliFile('ocbackup');
                        if (scelto != null) setState(() => _file = scelto);
                      },
                      child: Text(t.scegliFile),
                    ),
                  ],
                ),
                TextField(
                  controller: _passphrase,
                  obscureText: true,
                  decoration: InputDecoration(labelText: t.passphrase),
                ),
                if (_errore != null) Text(_errore!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton(onPressed: _file == null ? null : _ripristina, child: Text(t.ripristina)),
                ),
                const SizedBox(height: 24),
                Text(t.recuperoNuovaIdentita),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton(onPressed: widget.nuovaIdentita, child: Text(t.creaNuovaIdentita)),
                ),
              ],
              const SizedBox(height: 32),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(onPressed: widget.esci, child: Text(t.chiudiProgramma)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
