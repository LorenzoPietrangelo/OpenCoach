import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:protocollo/protocollo.dart';

import 'archivio.dart';
import 'cifratura.dart';
import 'errori.dart';
import 'portachiavi.dart';
import 'tempo.dart';

const _voceChiaveLocale = 'chiave_locale';

/// Chiave d'identità del coach (Ed25519) e indirizzo onion che ne deriva (§4).
class Identita {
  Identita._(this.seme, this.chiavePubblica)
    : indirizzo = indirizzoOnionDaChiave(chiavePubblica);

  static Future<Identita> genera() => daSeme(byteCasuali(32));

  static Future<Identita> daSeme(List<int> seme) async {
    final coppia = await Ed25519().newKeyPairFromSeed(seme);
    final pubblica = await coppia.extractPublicKey();
    return Identita._(
      Uint8List.fromList(seme),
      Uint8List.fromList(pubblica.bytes),
    );
  }

  final Uint8List seme;
  final Uint8List chiavePubblica;

  /// Indirizzo onion, senza ".onion".
  final String indirizzo;

  /// Chiave nel formato che `ADD_ONION` si aspetta: la chiave segreta espansa
  /// di Ed25519 (SHA-512 del seme, con il clamping) in base64.
  String get chiaveTor {
    final espansa = Uint8List.fromList(crypto.sha512.convert(seme).bytes);
    espansa[0] &= 248;
    espansa[31] &= 63;
    espansa[31] |= 64;
    return 'ED25519-V3:${base64.encode(espansa).replaceAll('=', '')}';
  }
}

/// Carica l'identità dall'archivio o, al primo avvio, la genera.
///
/// Il seme è salvato cifrato con una chiave casuale che vive solo nel
/// [portachiavi] del sistema operativo.
Future<Identita> caricaOCreaIdentita(
  Archivio archivio,
  Portachiavi portachiavi, {
  DateTime Function() adesso = DateTime.now,
}) async {
  var chiaveLocale = await portachiavi.leggi(_voceChiaveLocale);
  final riga = archivio.db
      .select('SELECT seme_cifrato, indirizzo FROM identita WHERE id = 1')
      .firstOrNull;

  if (riga != null) {
    if (chiaveLocale == null) throw const IdentitaIllegibile();
    final Uint8List seme;
    try {
      seme = await decifra(chiaveLocale, riga['seme_cifrato'] as Uint8List);
    } on SecretBoxAuthenticationError {
      throw const IdentitaIllegibile();
    }
    final identita = await Identita.daSeme(seme);
    if (identita.indirizzo != riga['indirizzo']) {
      throw const IdentitaIllegibile();
    }
    return identita;
  }

  if (chiaveLocale == null) {
    chiaveLocale = byteCasuali(32);
    await portachiavi.scrivi(_voceChiaveLocale, chiaveLocale);
  }
  final identita = await Identita.genera();
  final cifrato = await cifra(chiaveLocale, identita.seme);
  archivio.db.execute(
    'INSERT INTO identita (id, seme_cifrato, indirizzo, creata_il) '
    'VALUES (1, ?, ?, ?)',
    [cifrato, identita.indirizzo, istante(adesso())],
  );
  return identita;
}
