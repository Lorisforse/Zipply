import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:ziply_app/data/models/booking_model.dart';
import 'package:ziply_app/data/models/vehicle_model.dart';
import 'package:ziply_app/presentation/mobile/map/widgets/vehicle_widgets.dart';
import 'package:ziply_app/services/booking_service.dart';

// ── Palette (da Grafica/mappa-handoff) ─────────────────────────────────────
const Color _kBg      = Color(0xFF1A1A1A);
const Color _kBorder  = Color(0xFF333333);
const Color _kText    = Color(0xFFF5F5F5);
const Color _kDim     = Color(0xFF777777);
const Color _kAccent  = Color(0xFFF69659);

/// Esito del flusso di prenotazione restituito da [VehicleBottomSheet.show]:
/// [booking] valorizzato in caso di successo, [error] in caso di fallimento.
class VehicleBookingResult {
  const VehicleBookingResult.success(BookingModel this.booking) : error = null;
  const VehicleBookingResult.failure(String this.error) : booking = null;

  final BookingModel? booking;
  final String? error;

  bool get isSuccess => booking != null;
}

/// [MOBILE] UT.05 + UT.02 — Scheda mezzo e avvio prenotazione.
/// Bottom sheet aperto al tap su un marker: mostra tipo, batteria, tariffa e
/// distanza dall'utente, e consente di prenotare il mezzo. La chiamata a
/// POST /bookings è gestita qui (con loading sul pulsante); l'esito viene
/// restituito al chiamante via [Navigator.pop] come [VehicleBookingResult].
class VehicleBottomSheet extends StatefulWidget {
  const VehicleBottomSheet({
    super.key,
    required this.vehicle,
    this.userPosition,
  });

  final VehicleModel vehicle;

  /// Posizione utente corrente (può essere null se la localizzazione non è
  /// disponibile → la distanza viene mostrata come «—»).
  final LatLng? userPosition;

  /// Apre la scheda come modal bottom sheet: si chiude con swipe verso il
  /// basso o tap fuori (comportamento di default di [showModalBottomSheet]).
  /// Restituisce l'esito della prenotazione, o null se l'utente la chiude.
  static Future<VehicleBookingResult?> show(
    BuildContext context,
    VehicleModel vehicle,
    LatLng? userPosition,
  ) {
    return showModalBottomSheet<VehicleBookingResult>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x8C000000), // rgba(0,0,0,0.55)
      builder: (_) => VehicleBottomSheet(
        vehicle: vehicle,
        userPosition: userPosition,
      ),
    );
  }

  @override
  State<VehicleBottomSheet> createState() => _VehicleBottomSheetState();
}

class _VehicleBottomSheetState extends State<VehicleBottomSheet> {
  final BookingService _bookingService = BookingService();
  bool _isBooking = false;

  /// Avvia la prenotazione mostrando il loading sul pulsante, poi chiude la
  /// scheda restituendone l'esito al chiamante (la mappa).
  Future<void> _book() async {
    setState(() => _isBooking = true);
    final navigator = Navigator.of(context);

    VehicleBookingResult result;
    try {
      final booking = await _bookingService.createBooking(widget.vehicle.id);
      result = VehicleBookingResult.success(booking);
    } on Exception catch (e) {
      result = VehicleBookingResult.failure(
        e.toString().replaceFirst('Exception: ', ''),
      );
    }

    if (!mounted) return; // scheda già chiusa dall'utente durante la chiamata
    navigator.pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final vehicle = widget.vehicle;
    final title = vehicle.type.isEmpty ? 'Mezzo' : vehicle.type;
    final rateText =
        '${(vehicle.hourlyRate / 60).toStringAsFixed(2).replaceAll('.', ',')} €';
    final (distValue, distSecondary) =
        walkingLabels(widget.userPosition, vehicle.latitude, vehicle.longitude);

    return Container(
      decoration: const BoxDecoration(
        color: _kBg,
        border: Border(top: BorderSide(color: _kBorder)),
        boxShadow: [
          BoxShadow(
            color: Color(0x73000000), // rgba(0,0,0,0.45)
            blurRadius: 30,
            offset: Offset(0, -12),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle trascinabile (da handoff: 38×4, raggio 2).
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: _kBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Header: tile-glifo + tipo mezzo + badge batteria.
              Row(
                children: [
                  VehicleGlyphTile(kind: vehicle.kind),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Text(
                      title,
                      style: GoogleFonts.barlowCondensed(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: _kText,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  BatteryBadge(pct: vehicle.batteryLevel),
                ],
              ),
              const SizedBox(height: 18),
              Container(height: 1, color: _kBorder),
              const SizedBox(height: 18),
              // Metriche: tariffa e distanza.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _Metric(
                      label: 'TARIFFA',
                      value: rateText,
                      secondary: 'al minuto',
                    ),
                  ),
                  Expanded(
                    child: _Metric(
                      label: 'DISTANZA',
                      value: distValue,
                      secondary: distSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // CTA prenotazione (UT.02).
              SizedBox(
                height: 52,
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isBooking ? null : _book,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kAccent,
                    foregroundColor: _kBg,
                    disabledBackgroundColor: _kAccent,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  child: _isBooking
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: _kBg,
                          ),
                        )
                      : Text(
                          'PRENOTA',
                          style: GoogleFonts.barlowCondensed(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.5,
                            color: _kBg,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Blocco metrica: etichetta + valore + secondario ────────────────────────
class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, this.secondary});

  final String label;
  final String value;
  final String? secondary;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.barlowCondensed(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 1,
            color: _kDim,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: GoogleFonts.barlowCondensed(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: _kText,
          ),
        ),
        if (secondary != null) ...[
          const SizedBox(height: 4),
          Text(
            secondary!,
            style: GoogleFonts.barlow(fontSize: 12.5, color: _kDim),
          ),
        ],
      ],
    );
  }
}
