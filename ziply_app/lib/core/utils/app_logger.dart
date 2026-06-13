import 'package:flutter/foundation.dart';

/// Log applicativo facilmente riconoscibile: ogni riga inizia con "[Ziply]"
/// (oppure "[Ziply][Area]" se passi un [tag], es. "Auth", "Mappa", "Noleggio").
///
/// Attivo solo in debug: in release viene compilato via senza lasciare output.
/// Esempio: zlog('4 mezzi nelle vicinanze', tag: 'Mappa')
///          → [Ziply][Mappa] 4 mezzi nelle vicinanze
void zlog(String message, {String? tag}) {
  if (!kDebugMode) return;
  final prefix = tag == null ? '[Ziply]' : '[Ziply][$tag]';
  debugPrint('$prefix $message');
}
