import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ziply_app/core/theme/app_colors.dart';

/// Helper di testo condivisi dell'app.
///
/// [appCond] usa Barlow Condensed (titoli, etichette, numeri compatti),
/// [appBody] usa Barlow (testo corrente). Sostituiscono gli helper `_cond`/
/// `_body` che prima erano duplicati identici in ogni schermata.

/// Stile Barlow Condensed.
TextStyle appCond({
  double size = 14,
  FontWeight w = FontWeight.w700,
  Color c = AppColors.text,
  double ls = 0,
}) =>
    GoogleFonts.barlowCondensed(
      fontSize: size,
      fontWeight: w,
      color: c,
      letterSpacing: ls,
    );

/// Stile Barlow (testo corrente).
TextStyle appBody({
  double size = 15,
  FontWeight w = FontWeight.w400,
  Color c = AppColors.text,
}) =>
    GoogleFonts.barlow(fontSize: size, fontWeight: w, color: c);
