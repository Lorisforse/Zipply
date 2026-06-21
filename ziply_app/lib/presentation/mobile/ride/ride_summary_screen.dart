import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ziply_app/core/theme/app_colors.dart';
import 'package:ziply_app/data/models/ride_model.dart';
import 'package:ziply_app/data/models/vehicle_model.dart';
import 'package:ziply_app/presentation/mobile/map/widgets/vehicle_widgets.dart';
import 'package:ziply_app/presentation/mobile/ride/malfunction_report_screen.dart';
import 'package:ziply_app/services/payment_method_service.dart';

// ── Palette (da Grafica/annullata-handoff, allineata a booking_cancelled) ──
const Color _kBg      = AppColors.bg;
const Color _kSurface = AppColors.surface;
const Color _kBorder  = AppColors.border;
const Color _kText    = AppColors.text;
const Color _kDim     = AppColors.dim;
const Color _kAccent  = AppColors.accent;
const Color _kGreen   = AppColors.green;

// ── Stima CO2 risparmiata ───────────────────────────────────────────────────
// La corsa non viene tracciata via GPS, quindi la distanza è stimata dalla
// durata e da una velocità media urbana per tipo di mezzo; il risparmio è
// quella distanza moltiplicata per il fattore di emissione di un'auto a
// benzina media urbana (la corsa "verde" evita quel viaggio in auto).
const double _kCarCo2GramsPerKm = 130;

double _avgSpeedKmh(VehicleType kind) {
  switch (kind) {
    case VehicleType.bike:
      return 13;
    case VehicleType.scooter:
      return 17;
    case VehicleType.car:
      return 25;
    case VehicleType.unknown:
      return 15;
  }
}

int _estimateCo2SavedGrams(VehicleType kind, Duration d) {
  final km = _avgSpeedKmh(kind) * d.inSeconds / 3600;
  return (km * _kCarCo2GramsPerKm).round();
}

/// [MOBILE] UT.04 — Schermata "Riepilogo fine corsa".
/// Mostrata dopo aver terminato un noleggio (POST /rides/{id}/end). L'endpoint
/// restituisce solo lo stato, quindi i dati del riepilogo — durata e costo —
/// sono quelli già calcolati e mostrati dalla schermata di noleggio attivo e
/// vengono passati qui congelati; la CO2 risparmiata è stimata dalla durata e
/// il metodo di pagamento è recuperato dalla carta predefinita dell'utente.
/// Mirroring di [BookingCancelledScreen]: stesso stile, layout e palette.
class RideSummaryScreen extends StatefulWidget {
  const RideSummaryScreen({
    super.key,
    required this.ride,
    required this.vehicle,
    required this.duration,
    required this.cost,
    this.appliedDiscount = 0,
    this.subscriptionApplied = false,
  });

  final RideModel ride;
  final VehicleModel vehicle;

  /// Durata effettiva della corsa (congelata al momento del termine).
  final Duration duration;

  /// Costo addebitato server-autoritativo, già al netto dell'eventuale sconto.
  final double cost;

  /// UT.09 — importo scontato applicato (0 se nessuno sconto). Quando > 0 il
  /// riepilogo mostra il subtotale e la riga sconto.
  final double appliedDiscount;

  /// UT.22 — true se il costo è azzerato da un abbonamento attivo.
  final bool subscriptionApplied;

  /// Apre la schermata sostituendo la rotta corrente: dopo aver terminato non
  /// si torna alla schermata di noleggio (ormai conclusa). Entra con una
  /// dissolvenza + leggero scorrimento verso l'alto, per staccare dalla corsa
  /// senza il push laterale di default.
  static Future<void> show(
    BuildContext context, {
    required RideModel ride,
    required VehicleModel vehicle,
    required Duration duration,
    required double cost,
    double appliedDiscount = 0,
    bool subscriptionApplied = false,
  }) {
    return Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 420),
        reverseTransitionDuration: const Duration(milliseconds: 280),
        pageBuilder: (_, __, ___) => RideSummaryScreen(
          ride: ride,
          vehicle: vehicle,
          duration: duration,
          cost: cost,
          appliedDiscount: appliedDiscount,
          subscriptionApplied: subscriptionApplied,
        ),
        transitionsBuilder: (context, animation, _, child) {
          final curved =
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.06),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  State<RideSummaryScreen> createState() => _RideSummaryScreenState();
}

class _RideSummaryScreenState extends State<RideSummaryScreen> {
  final PaymentMethodService _paymentService = PaymentMethodService();

  /// Ultime 4 cifre della carta usata; null finché non è caricata o se non c'è
  /// alcun metodo di pagamento disponibile.
  String? _cardLastFour;

  @override
  void initState() {
    super.initState();
    _loadPaymentMethod();
  }

  /// Recupera la carta predefinita (o la prima disponibile) per mostrare le
  /// ultime 4 cifre. È un dettaglio non critico: in caso di errore la riga
  /// resta su "—" senza disturbare il riepilogo.
  Future<void> _loadPaymentMethod() async {
    try {
      final methods = await _paymentService.getPaymentMethods();
      if (!mounted || methods.isEmpty) return;
      final card = methods.firstWhere(
        (m) => m.isDefault,
        orElse: () => methods.first,
      );
      setState(() => _cardLastFour = card.cardLastFour);
    } on Exception {
      // Dettaglio non essenziale: lasciamo "—".
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar: wordmark + close.
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 8, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'ZIPLY',
                    style: GoogleFonts.barlowCondensed(
                      fontSize: 23,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: _kAccent,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close, color: _kDim),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Column(
                  children: [
                    const SizedBox(height: 24),
                    const _SuccessBadge(),
                    const SizedBox(height: 26),
                    Text(
                      'NOLEGGIO COMPLETATO',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.barlowCondensed(
                        fontSize: 31,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        height: 1,
                        color: _kText,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Grazie per aver viaggiato con Ziply. Ecco il riepilogo della tua corsa.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.barlow(
                        fontSize: 14.5,
                        height: 1.5,
                        color: _kDim,
                      ),
                    ),
                    const SizedBox(height: 26),
                    _SummaryCard(
                      ride: widget.ride,
                      vehicle: widget.vehicle,
                      duration: widget.duration,
                      cost: widget.cost,
                      appliedDiscount: widget.appliedDiscount,
                      subscriptionApplied: widget.subscriptionApplied,
                      cardLastFour: _cardLastFour,
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
            // Azioni in basso.
            Container(
              decoration: const BoxDecoration(
                color: _kBg,
                border: Border(top: BorderSide(color: _kBorder)),
              ),
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 54,
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.map_outlined, size: 19, color: _kBg),
                      label: Text(
                        'TORNA ALLA MAPPA',
                        style: GoogleFonts.barlowCondensed(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                          color: _kBg,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kAccent,
                        foregroundColor: _kBg,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 54,
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        MalfunctionReportScreen.show(
                          context,
                          rideId: widget.ride.id,
                          vehicleId: widget.vehicle.id,
                        );
                      },
                      icon: const Icon(Icons.warning_amber_outlined, size: 19, color: _kText),
                      label: Text(
                        'SEGNALA MALFUNZIONAMENTO',
                        style: GoogleFonts.barlowCondensed(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                          color: _kText,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: _kBorder),
                        foregroundColor: _kText,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
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

// ── Badge ✓ (doppio anello, verde successo) ────────────────────────────────
class _SuccessBadge extends StatelessWidget {
  const _SuccessBadge();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 96,
      height: 96,
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _kSurface,
                border: Border.all(color: _kBorder),
              ),
            ),
          ),
          Positioned.fill(
            child: Container(
              margin: const EdgeInsets.all(13),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _kGreen.withOpacity(0.08),
                border: Border.all(
                  color: _kGreen.withOpacity(0.9),
                  width: 2,
                ),
              ),
              child: const Icon(Icons.check, color: _kGreen, size: 34),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Card riepilogo corsa completata ────────────────────────────────────────
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.ride,
    required this.vehicle,
    required this.duration,
    required this.cost,
    required this.appliedDiscount,
    required this.subscriptionApplied,
    required this.cardLastFour,
  });

  final RideModel ride;
  final VehicleModel vehicle;
  final Duration duration;
  final double cost;
  final double appliedDiscount;
  final bool subscriptionApplied;
  final String? cardLastFour;

  String _shortCode() {
    final id = ride.id.replaceAll('-', '');
    final head = id.length >= 8 ? id.substring(0, 8) : id;
    return 'ZP-${head.toUpperCase()}';
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    String two(int n) => n.toString().padLeft(2, '0');
    if (h > 0) return '$h h ${two(m)} min';
    if (m > 0) return s > 0 ? '$m min ${two(s)} s' : '$m min';
    return '$s s';
  }

  String _euro(double value) =>
      '€ ${value.toStringAsFixed(2).replaceAll('.', ',')}';

  @override
  Widget build(BuildContext context) {
    final title = vehicle.type.isEmpty ? 'Mezzo' : vehicle.type;
    final co2 = _estimateCo2SavedGrams(vehicle.kind, duration);
    final payment = cardLastFour == null ? '—' : '•••• $cardLastFour';

    return Container(
      decoration: BoxDecoration(
        color: _kSurface,
        border: Border.all(color: _kBorder),
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
      child: Column(
        children: [
          // Riga mezzo.
          Row(
            children: [
              VehicleGlyphTile(kind: vehicle.kind, size: 46),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.barlowCondensed(
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                        color: _kText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Corsa conclusa',
                      style: GoogleFonts.barlow(fontSize: 12.5, color: _kDim),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const _StatusBadge(),
            ],
          ),
          const SizedBox(height: 14),
          Container(height: 1, color: _kBorder),
          const SizedBox(height: 14),
          _DetailRow(label: 'Codice corsa', value: _shortCode()),
          const SizedBox(height: 10),
          _DetailRow(label: 'Durata', value: _formatDuration(duration)),
          const SizedBox(height: 10),
          _DetailRow(
            label: 'CO₂ risparmiata',
            value: '$co2 g',
            valueColor: _kGreen,
          ),
          const SizedBox(height: 10),
          _DetailRow(label: 'Metodo di pagamento', value: payment),
          const SizedBox(height: 14),
          Container(height: 1, color: _kBorder),
          const SizedBox(height: 14),
          // UT.22 — abbonamento applicato: costo gratuito in verde.
          if (subscriptionApplied) ...[
            _DetailRow(
              label: 'Abbonamento applicato',
              value: '− ${_euro(appliedDiscount)}',
              valueColor: _kGreen,
            ),
            const SizedBox(height: 10),
            _DetailRow(
              label: 'Costo totale',
              value: _euro(cost),
              valueColor: _kGreen,
            ),
          // UT.09 — sconto codice/promozione: mostra subtotale e riga sconto.
          ] else if (appliedDiscount > 0) ...[
            _DetailRow(label: 'Subtotale', value: _euro(cost + appliedDiscount)),
            const SizedBox(height: 10),
            _DetailRow(
              label: 'Sconto',
              value: '− ${_euro(appliedDiscount)}',
              valueColor: _kGreen,
            ),
            const SizedBox(height: 10),
            _DetailRow(
              label: 'Costo totale',
              value: _euro(cost),
              valueColor: _kAccent,
            ),
          ] else ...[
            _DetailRow(
              label: 'Costo totale',
              value: _euro(cost),
              valueColor: _kAccent,
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(7, 4, 7, 3),
      decoration: BoxDecoration(
        color: _kGreen.withOpacity(0.10),
        border: Border.all(color: _kGreen.withOpacity(0.55)),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(
        'COMPLETATA',
        style: GoogleFonts.barlowCondensed(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
          height: 1,
          color: _kGreen,
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.valueColor = _kText,
  });

  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: GoogleFonts.barlow(fontSize: 13.5, color: _kDim)),
        Text(
          value,
          style: GoogleFonts.barlowCondensed(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}
