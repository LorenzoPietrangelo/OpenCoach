import 'package:protocollo/protocollo.dart';
import 'package:test/test.dart';

void main() {
  final valido = UriTelefonoCoach(
    indirizzo: indirizzoOnionDaChiave(List.filled(32, 7)),
    id: codificaBase32(List.filled(16, 1)),
    segreto: codificaBase32(List.filled(32, 2)),
    chiave: codificaBase32(List.filled(32, 3)),
  );

  test('il QR si rilegge uguale', () {
    final letto = UriTelefonoCoach.analizza(valido.toString());
    expect(letto.indirizzo, valido.indirizzo);
    expect(letto.id, valido.id);
    expect(letto.segreto, valido.segreto);
    expect(letto.chiave, valido.chiave);
  });

  test('un invito di un atleta non è un QR del coach, e viceversa', () {
    final invito = UriInvito(
      indirizzo: valido.indirizzo,
      id: valido.id,
      segreto: valido.segreto,
      chiave: valido.chiave,
    );
    expect(() => UriTelefonoCoach.analizza(invito.toString()), throwsA(isA<InvitoNonValido>()));
    expect(() => UriInvito.analizza(valido.toString()), throwsA(isA<InvitoNonValido>()));
  });

  test('una versione sconosciuta chiede di aggiornare', () {
    expect(
      () => UriTelefonoCoach.analizza(valido.toString().replaceFirst('v=1', 'v=2')),
      throwsA(isA<VersioneInvitoSconosciuta>()),
    );
  });

  test('un testo qualunque non vale', () {
    expect(() => UriTelefonoCoach.analizza('https://esempio.it'), throwsA(isA<InvitoNonValido>()));
  });
}
