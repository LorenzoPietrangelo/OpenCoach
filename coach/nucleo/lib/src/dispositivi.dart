import 'package:crypto/crypto.dart' as crypto;
import 'package:protocollo/protocollo.dart';
import 'package:sqlite3/sqlite3.dart';

import 'contesto.dart';
import 'modelli.dart';
import 'tempo.dart';

/// Hash con cui il programma conserva un token (§4).
List<int> hashToken(List<int> token) => crypto.sha256.convert(token).bytes;

/// Telefoni abbinati agli atleti.
class GestioneDispositivi {
  GestioneDispositivi(this._c);

  final ContestoCoach _c;

  Database get _db => _c.archivio.db;

  Dispositivo? attivo(String atletaId) {
    final riga = _db.select(
      "SELECT * FROM dispositivi WHERE atleta_id = ? AND stato = 'attivo'",
      [atletaId],
    ).firstOrNull;
    return riga == null ? null : Dispositivo.daRiga(riga);
  }

  List<Dispositivo> elenco(String atletaId) => [
    for (final riga in _db.select(
      'SELECT * FROM dispositivi WHERE atleta_id = ? ORDER BY abbinato_il DESC',
      [atletaId],
    ))
      Dispositivo.daRiga(riga),
  ];

  /// Revoca il dispositivo: il token smette subito di valere e il servizio
  /// viene ripubblicato senza la sua chiave (§9.3).
  void revoca(String dispositivoId) {
    _db.execute(
      "UPDATE dispositivi SET stato = 'revocato', revocato_il = ? "
      "WHERE id = ? AND stato = 'attivo'",
      [istante(_c.adesso()), dispositivoId],
    );
    if (_db.updatedRows > 0) _c.segnalaChiaviCambiate();
  }

  /// Dispositivo attivo che corrisponde all'intestazione `Authorization`,
  /// oppure null.
  Dispositivo? autentica(String? intestazione) {
    if (intestazione == null || !intestazione.startsWith('Bearer ')) {
      return null;
    }
    final token = decodificaChiave32(intestazione.substring(7).trim());
    if (token == null) return null;
    final riga = _db.select(
      "SELECT * FROM dispositivi WHERE hash_token = ? AND stato = 'attivo'",
      [hashToken(token)],
    ).firstOrNull;
    return riga == null ? null : Dispositivo.daRiga(riga);
  }
}
