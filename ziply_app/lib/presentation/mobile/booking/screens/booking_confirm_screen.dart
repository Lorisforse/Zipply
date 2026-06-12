import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ziply_app/data/models/booking_model.dart';
import 'package:ziply_app/data/models/vehicle_model.dart';

// ── Palette (da Grafica/mappa-handoff) ─────────────────────────────────────
const Color _kBg      = Color(0xFF1A1A1A);
const Color _kSurface = Color(0xFF252525);
const Color _kBorder  = Color(0xFF333333);
const Color _kText    = Color(0xFFF5F5F5);
const Color _kDim     = Color(0xFF777777);
const Color _kAccent  = Color(0xFFF69659);

/// [MOBILE] UT.02 — Conferma prenotazione.
/// Mostra l'esito della prenotazione e un countdown che scala fino a 00:00
/// usando [BookingModel.expiresAt] del backend come riferimento temporale.
class BookingConfirmScreen extends StatefulWidget {
  const BookingConfirmScreen({
    super.key,
    required this.booking,
    required this.vehicle,
  });

  final BookingModel booking;
  final VehicleModel vehicle;

  @override
  State<BookingConfirmScreen> createState() => _BookingConfirmScreenState();
}

class _BookingConfirmScreenState extends State<BookingConfirmScreen> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Tick al secondo: il valore mostrato è ricalcolato da expires_at, non da
    // un contatore locale, così resta allineato al backend.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      if (_remaining() <= Duration.zero) _ticker?.cancel();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Duration _remaining() => widget.booking.expiresAt.difference(DateTime.now());

  String _format(Duration d) {
    final clamped = d.isNegative ? Duration.zero : d;
    final m = clamped.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = clamped.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _onCancel() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: _kSurface,
        content: Text(
          'Funzionalità non ancora disponibile',
          style: GoogleFonts.barlow(fontSize: 14, color: _kText),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final remaining = _remaining();
    final expired = remaining <= Duration.zero;

    return Scaffold(
      backgroundColor: _kBg,
      body: SafeArea(
        child: Column(
          children: [
            // Barra superiore con ritorno alla mappa.
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back, color: _kText),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Conferma.
                    Container(
                      width: 72,
                      height: 72,
                      decoration: const BoxDecoration(
                        color: _kAccent,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check, color: _kBg, size: 38),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'PRENOTAZIONE CONFERMATA',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.barlowCondensed(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: _kText,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Hai prenotato ${widget.vehicle.type}',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.barlow(fontSize: 15, color: _kDim),
                    ),
                    const SizedBox(height: 32),
                    // Countdown.
                    _CountdownCard(
                      value: _format(remaining),
                      expired: expired,
                    ),
                  ],
                ),
              ),
            ),
            // Azioni.
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(
                children: [
                  const _UnlockButtonDisabled(),
                  const SizedBox(height: 8),
                  Text(
                    'Disponibile all\'inizio della corsa',
                    style: GoogleFonts.barlow(fontSize: 12, color: _kDim),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 50,
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _onCancel,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _kDim,
                        side: const BorderSide(color: _kBorder),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      child: Text(
                        'ANNULLA PRENOTAZIONE',
                        style: GoogleFonts.barlowCondensed(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.6,
                          color: _kDim,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Countdown ──────────────────────────────────────────────────────────────
class _CountdownCard extends StatelessWidget {
  const _CountdownCard({required this.value, required this.expired});

  final String value;
  final bool expired;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        children: [
          Text(
            expired ? 'PRENOTAZIONE SCADUTA' : 'TEMPO RIMANENTE',
            style: GoogleFonts.barlowCondensed(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.5,
              color: _kDim,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.barlowCondensed(
              fontSize: 56,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              height: 1,
              color: expired ? _kDim : _kAccent,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Bottone "Sblocca mezzo" — disabilitato (logica → UT.13) ─────────────────
class _UnlockButtonDisabled extends StatelessWidget {
  const _UnlockButtonDisabled();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      width: double.infinity,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: _kBorder),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.lock_outline, color: _kDim, size: 20),
          const SizedBox(width: 10),
          Text(
            'SBLOCCA MEZZO',
            style: GoogleFonts.barlowCondensed(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: _kDim,
            ),
          ),
        ],
      ),
    );
  }
}
