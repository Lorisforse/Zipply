import 'package:flutter/material.dart';

/// Palette unica dell'app Ziply. Unica fonte di verità per i colori: le
/// schermate vi fanno riferimento invece di ridefinire gli stessi valori
/// esadecimali in locale.
class AppColors {
  const AppColors._();

  /// Sfondo principale (scaffold).
  static const Color bg = Color(0xFF1A1A1A);

  /// Superfici/card sopra lo sfondo.
  static const Color surface = Color(0xFF252525);

  /// Superficie alternativa, leggermente più chiara (usata nelle corse).
  static const Color surface2 = Color(0xFF2D2D2D);

  /// Bordi e separatori.
  static const Color border = Color(0xFF333333);

  /// Testo principale.
  static const Color text = Color(0xFFF5F5F5);

  /// Testo attenuato/secondario.
  static const Color dim = Color(0xFF777777);

  /// Arancione brand (accento primario).
  static const Color accent = Color(0xFFF69659);

  /// Variante scura dell'accento (riempimento marker e dot sulla mappa).
  static const Color accentDark = Color(0xFFD4580A);

  /// Verde (credito, stati positivi).
  static const Color green = Color(0xFF5DCAA5);

  /// Rosso (errori, azioni distruttive).
  static const Color red = Color(0xFFE53935);

  /// Icona dentro il marker (bianco pieno).
  static const Color markerIcon = Color(0xFFFFFFFF);

  /// Tacche "vuote" della batteria (bianco semitrasparente).
  static const Color batteryTrack = Color(0x4DFFFFFF);
}
