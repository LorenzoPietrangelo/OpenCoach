import 'dart:async';
import 'dart:convert';

import 'package:atleta_app/l10n/testi.dart';
import 'package:atleta_app/piattaforma/tor_non_integrato.dart';
import 'package:atleta_nucleo/atleta_nucleo.dart';
import 'package:flutter/material.dart';
import 'package:protocollo/protocollo.dart';

/// Orologio del telefono di prova: fermo finché il test non lo fa avanzare.
/// I timer del nucleo (sync periodica, ritentativi) non scattano mai.
class OrologioFermo implements Orologio {
  var ora = DateTime(2026, 10, 21, 18, 30);

  void avanza(Duration durata) => ora = ora.add(durata);

  @override
  DateTime adesso() => ora;

  @override
  Future<void> attendi(Duration durata) async => avanza(durata);

  @override
  Timer timer(Duration durata, void Function() azione) => _TimerFermo();
}

class _TimerFermo implements Timer {
  var _attivo = true;

  @override
  bool get isActive => _attivo;

  @override
  int get tick => 0;

  @override
  void cancel() => _attivo = false;
}

/// Telefono dell'atleta per le prove delle schermate: archivio in memoria e
/// Tor non integrato, quindi ogni sync si ferma con «Tor non parte», se il
/// test non passa un altro [tor]. Coach e schede si scrivono direttamente
/// nell'archivio, come se fossero arrivati con l'abbinamento e la sync.
class TelefonoDiProva {
  TelefonoDiProva({TrasportoTor tor = const TorNonIntegrato()}) {
    nucleo = NucleoAtleta(
      archivio: archivio,
      cassaforte: CassaforteMemoria(),
      tor: tor,
      orologio: orologio,
      dispositivo: const DatiDispositivo(
        nome: 'Telefono di prova',
        piattaforma: 'android',
        versioneApp: '1.0.0',
      ),
    );
  }

  final archivio = ArchivioAtleta.inMemoria();
  final orologio = OrologioFermo();
  late final NucleoAtleta nucleo;

  Future<void> chiudi() async {
    await nucleo.chiudi();
    archivio.chiudi();
  }

  /// Un coach a cui il telefono è abbinato; restituisce l'id del collegamento.
  int aggiungiCoach(
    String nome, {
    StatoCollegamento stato = StatoCollegamento.attivo,
    DateTime? ultimaSync,
    ProblemaSync? problema,
  }) {
    archivio.db.execute(
      'INSERT INTO coach (indirizzo, nome_coach, nome_atleta, atleta_id, '
      'dispositivo_id, stato, conferma_in_sospeso, abbinato_il, ultima_sync, '
      'problema) VALUES (?, ?, ?, ?, ?, ?, 0, ?, ?, ?)',
      [
        indirizzoOnionDaChiave(byteCasuali(32)),
        nome,
        'Giulia Rossi',
        nuovoUuid(),
        nuovoUuid(),
        stato.name,
        _istante(orologio.ora),
        switch (ultimaSync) {
          final DateTime quando => _istante(quando),
          null => null,
        },
        problema?.name,
      ],
    );
    return archivio.db.lastInsertRowId;
  }

  /// Una scheda arrivata dal coach; con [vista] l'atleta l'ha già aperta.
  void aggiungiScheda(
    int coachId,
    Map<String, Object?> scheda, {
    bool vista = false,
  }) {
    final revisione = scheda['revisione']! as int;
    archivio.db.execute(
      'INSERT INTO schede (coach_id, id, revisione, archiviata, contenuto, '
      'ricevuta_il, revisione_vista) VALUES (?, ?, ?, ?, ?, ?, ?)',
      [
        coachId,
        scheda['id'],
        revisione,
        scheda['stato'] == 'archiviata' ? 1 : 0,
        jsonEncode(scheda),
        _istante(orologio.ora),
        vista ? revisione : 0,
      ],
    );
  }

  /// Il coach ha confermato di avere il log.
  void confermaLog(String id) => archivio.db.execute(
    'UPDATE log SET rev_confermata = rev WHERE id = ?',
    [id],
  );

  /// Il coach ha rifiutato il log.
  void rifiutaLog(String id, String motivo) => archivio.db.execute(
    'UPDATE log SET rifiuto = ? WHERE id = ?',
    [motivo, id],
  );
}

String _istante(DateTime quando) => quando.toUtc().toIso8601String();

/// Il testo di un invito valido (§5.2), di un coach che non esiste.
String linkInvito() => UriInvito(
  indirizzo: indirizzoOnionDaChiave(byteCasuali(32)),
  id: codificaBase32(byteCasuali(16)),
  segreto: codificaBase32(byteCasuali(32)),
  chiave: codificaBase32(byteCasuali(32)),
).toString();

/// [schermata] dentro un'app con i testi italiani.
Widget conTesti(Widget schermata) => MaterialApp(
  localizationsDelegates: Testi.localizationsDelegates,
  supportedLocales: Testi.supportedLocales,
  home: schermata,
);

/// Scheda con due sedute. «Giorno A»: squat 4 × 6-8 al 75% 1RM con 2:30 di
/// recupero, panca 2 × 8 con 60 kg e 1:30 di recupero, plank 3 × 30 s.
/// «Giorno B»: stacco 3 × 5 con 100 kg.
Map<String, Object?> schedaForza({
  String titolo = 'Forza – blocco 2',
  int revisione = 1,
  bool archiviata = false,
}) => {
  'id': nuovoUuid(),
  'revisione': revisione,
  'stato': archiviata ? 'archiviata' : 'pubblicata',
  'titolo': titolo,
  'note': 'Riscaldamento di 10 minuti prima di ogni seduta.',
  'valida_dal': '2026-10-20',
  'valida_al': '2026-11-16',
  'pubblicata_il': '2026-10-18T21:00:00+02:00',
  'sedute': [
    {
      'id': nuovoUuid(),
      'nome': 'Giorno A',
      'note': '',
      'esercizi': [
        {
          'id': nuovoUuid(),
          'nome': 'Squat',
          'note': 'Pausa di 1 s in buca',
          'prescrizione': [
            {
              'serie': 4,
              'ripetizioni': '6-8',
              'carico': '75% 1RM',
              'recupero_s': 150,
              'rir': '1-2',
            },
          ],
        },
        {
          'id': nuovoUuid(),
          'nome': 'Panca',
          'prescrizione': [
            {
              'serie': 2,
              'ripetizioni': '8',
              'carico': '60 kg',
              'recupero_s': 90,
            },
          ],
        },
        {
          'id': nuovoUuid(),
          'nome': 'Plank',
          'prescrizione': [
            {'serie': 3, 'ripetizioni': '30 s'},
          ],
        },
      ],
    },
    {
      'id': nuovoUuid(),
      'nome': 'Giorno B',
      'esercizi': [
        {
          'id': nuovoUuid(),
          'nome': 'Stacco',
          'prescrizione': [
            {
              'serie': 3,
              'ripetizioni': '5',
              'carico': '100 kg',
              'recupero_s': 180,
            },
          ],
        },
      ],
    },
  ],
};

/// Id della seduta «Giorno A» di una scheda fatta da [schedaForza].
String idGiornoA(Map<String, Object?> scheda) =>
    ((scheda['sedute']! as List<Object?>).first! as Map<String, Object?>)['id']!
        as String;

/// Un allenamento libero di un solo esercizio, come lo salva l'app (§8.2).
Map<String, Object?> logLibero(
  String esercizio, {
  required DateTime eseguitoIl,
  int durataMin = 40,
}) => {
  'scheda_id': null,
  'scheda_revisione': null,
  'seduta_id': null,
  'eseguito_il': formattaDataOra(eseguitoIl),
  'durata_min': durataMin,
  'note': '',
  'esercizi': [
    {
      'esercizio_id': null,
      'nome': esercizio,
      'note': '',
      'serie': [
        {'durata_s': durataMin * 60, 'completata': true},
      ],
    },
  ],
};
