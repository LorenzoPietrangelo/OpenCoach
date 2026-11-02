import 'package:protocollo/protocollo.dart';

/// Posizione di un dispositivo nel flusso delle modifiche (§7.2). Per l'app
/// è un testo opaco da restituire alla richiesta successiva.
sealed class Cursore {
  const Cursore(this.epoca);

  final String epoca;

  /// Null se [testo] è null o non è un cursore valido: in entrambi i casi il
  /// programma invia lo stato completo.
  static Cursore? analizza(String? testo) {
    if (testo == null) return null;
    final parti = testo.split(':');
    if (parti.length == 4 && parti[0] == '1' && parti[1] == 'i') {
      final sequenza = int.tryParse(parti[3]);
      if (sequenza != null && sequenza >= 0) {
        return CursoreIncrementale(parti[2], sequenza);
      }
    }
    if (parti.length == 6 && parti[0] == '1' && parti[1] == 'c') {
      final istantanea = int.tryParse(parti[3]);
      final fase = int.tryParse(parti[4]);
      final dopo = parti[5].isEmpty ? null : parti[5];
      if (istantanea != null &&
          istantanea >= 0 &&
          fase != null && fase >= 0 && fase <= 4 &&
          (dopo == null || uuidValido(dopo))) {
        return CursoreCompleto(parti[2], istantanea, fase, dopo);
      }
    }
    return null;
  }
}

/// L'app ha ricevuto tutte le modifiche fino a [sequenza].
class CursoreIncrementale extends Cursore {
  const CursoreIncrementale(super.epoca, this.sequenza);

  final int sequenza;

  @override
  String toString() => '1:i:$epoca:$sequenza';
}

/// Invio dello stato completo in corso, fotografato alla sequenza
/// [istantanea].
class CursoreCompleto extends Cursore {
  const CursoreCompleto(super.epoca, this.istantanea, this.fase, this.dopo);

  final int istantanea;

  /// 0 mentre invia le schede, 1 i log, 2 i pesi, 3 i questionari, 4 la
  /// chat.
  final int fase;

  /// Ultimo id già inviato nella fase corrente.
  final String? dopo;

  @override
  String toString() => '1:c:$epoca:$istantanea:$fase:${dopo ?? ''}';
}
