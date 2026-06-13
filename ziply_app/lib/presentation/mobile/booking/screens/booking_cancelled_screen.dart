import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:ziply_app/data/models/booking_model.dart';
import 'package:ziply_app/data/models/vehicle_model.dart';
import 'package:ziply_app/presentation/mobile/map/widgets/vehicle_widgets.dart';

// ── Palette (da Grafica/annullata-handoff) ─────────────────────────────────
const Color _kBg       = Color(0xFF1A1A1A);
const Color _kSurface  = Color(0xFF252525);
const Color _kBorder   = Color(0xFF333333);
const Color _kText     = Color(0xFFF5F5F5);
const Color _kDim      = Color(0xFF777777);
const Color _kAccent   = Color(0xFFF69659);
const Color _kGreen    = Color(0xFF5DCAA5);

/// [MOBILE] UT.02 — Schermata "Prenotazione annullata" (handoff annullata).
/// Mostrata dopo l'annullamento riuscito; entrambi i pulsanti tornano alla
/// mappa (la prenotazione è già annullata e lo stato è stato ripulito).
class BookingCancelledScreen extends StatelessWidget {
  const BookingCancelledScreen({
    super.key,
    required this.booking,
    required this.vehicle,
    this.userPosition,
  });

  final BookingModel booking;
  final VehicleModel vehicle;
  final LatLng? userPosition;

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
                    const _CancelBadge(),
                    const SizedBox(height: 26),
                    Text(
                      'PRENOTAZIONE ANNULLATA',
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
                      'Il mezzo è di nuovo disponibile per gli altri. Non ti è stato addebitato alcun importo.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.barlow(
                        fontSize: 14.5,
                        height: 1.5,
                        color: _kDim,
                      ),
                    ),
                    const SizedBox(height: 26),
                    _SummaryCard(
                      booking: booking,
                      vehicle: vehicle,
                      userPosition: userPosition,
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Badge X (doppio anello) ─────────────────────────────────────────────────
class _CancelBadge extends StatelessWidget {
  const _CancelBadge();

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
                color: _kAccent.withValues(alpha: 0.08),
                border: Border.all(
                  color: _kAccent.withValues(alpha: 0.9),
                  width: 2,
                ),
              ),
              child: const Icon(Icons.close, color: _kAccent, size: 34),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Card riepilogo prenotazione annullata ──────────────────────────────────
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.booking,
    required this.vehicle,
    required this.userPosition,
  });

  final BookingModel booking;
  final VehicleModel vehicle;
  final LatLng? userPosition;

  String _shortCode() {
    final id = booking.id.replaceAll('-', '');
    final head = id.length >= 8 ? id.substring(0, 8) : id;
    return 'ZP-${head.toUpperCase()}';
  }

  String _cancelledAt() {
    final now = DateTime.now();
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    return 'oggi · $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final title = vehicle.type.isEmpty ? 'Mezzo' : vehicle.type;
    final (dist, secondary) =
        walkingLabels(userPosition, vehicle.latitude, vehicle.longitude);
    final meta = secondary == null ? 'Mezzo prenotato' : '$dist · era $secondary da te';

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
                        decoration: TextDecoration.lineThrough,
                        decorationColor: _kDim,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      meta,
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
          _DetailRow(label: 'Codice prenotazione', value: _shortCode()),
          const SizedBox(height: 10),
          _DetailRow(label: 'Annullata alle', value: _cancelledAt()),
          const SizedBox(height: 10),
          const _DetailRow(
            label: 'Importo addebitato',
            value: '€ 0,00',
            valueColor: _kGreen,
          ),
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
        color: _kAccent.withValues(alpha: 0.10),
        border: Border.all(color: _kAccent.withValues(alpha: 0.55)),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(
        'ANNULLATA',
        style: GoogleFonts.barlowCondensed(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
          height: 1,
          color: _kAccent,
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
