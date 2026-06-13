import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:ziply_app/data/models/booking_model.dart';
import 'package:ziply_app/data/models/ride_model.dart';
import 'package:ziply_app/data/models/vehicle_model.dart';
import 'package:ziply_app/presentation/mobile/map/widgets/vehicle_widgets.dart';
import 'package:ziply_app/services/booking_service.dart';
import 'package:ziply_app/services/ride_service.dart';

// ── Palette (da Grafica/mappa-handoff) ─────────────────────────────────────
const Color _kBg      = Color(0xFF1A1A1A);
const Color _kSurface = Color(0xFF252525);
const Color _kBorder  = Color(0xFF333333);
const Color _kText    = Color(0xFFF5F5F5);
const Color _kDim     = Color(0xFF777777);
const Color _kAccent  = Color(0xFFF69659);

// UT.13 — Sblocco per prossimità abilitato solo entro questa distanza (metri).
const double _kUnlockRadiusMeters = 50;

/// Esito delle azioni della scheda mezzo restituito da [VehicleBottomSheet.show]:
/// [booking] se è stata creata una prenotazione, [ride] se il mezzo è stato
/// sbloccato direttamente, [error] in caso di fallimento.
class VehicleBookingResult {
  const VehicleBookingResult.success(BookingModel this.booking)
      : ride = null,
        error = null;
  const VehicleBookingResult.unlocked(RideModel this.ride)
      : booking = null,
        error = null;
  const VehicleBookingResult.failure(String this.error)
      : booking = null,
        ride = null;

  final BookingModel? booking;
  final RideModel? ride;
  final String? error;

  bool get isSuccess => booking != null;
  bool get isUnlocked => ride != null;
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
  final RideService _rideService = RideService();
  bool _isBooking = false;
  bool _isUnlocking = false;

  /// True quando l'utente è abbastanza vicino al mezzo da poterlo sbloccare
  /// per prossimità (≤ 50 m). Se la posizione non è nota, lo sblocco di
  /// prossimità non è disponibile (resta il QR dalla mappa).
  bool get _canUnlock {
    final from = widget.userPosition;
    if (from == null) return false;
    final meters = Geolocator.distanceBetween(
      from.latitude,
      from.longitude,
      widget.vehicle.latitude,
      widget.vehicle.longitude,
    );
    return meters <= _kUnlockRadiusMeters;
  }

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

  /// UT.13 — Sblocca direttamente il mezzo per prossimità (senza prenotare),
  /// poi chiude la scheda restituendo la corsa avviata al chiamante (la mappa).
  Future<void> _unlock() async {
    setState(() => _isUnlocking = true);
    final navigator = Navigator.of(context);

    VehicleBookingResult result;
    try {
      final ride = await _rideService.unlockByProximity(widget.vehicle.id);
      result = VehicleBookingResult.unlocked(ride);
    } on Exception catch (e) {
      result = VehicleBookingResult.failure(
        e.toString().replaceFirst('Exception: ', ''),
      );
    }

    if (!mounted) return;
    navigator.pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final vehicle = widget.vehicle;
    final busy = _isBooking || _isUnlocking;
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
              // UT.13 — Sblocco diretto per prossimità (azione principale):
              // abilitato solo entro 50 m dal mezzo.
              SizedBox(
                height: 52,
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (_canUnlock && !busy) ? _unlock : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kAccent,
                    foregroundColor: _kBg,
                    disabledBackgroundColor: _kSurface,
                    disabledForegroundColor: _kDim,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                      side: _canUnlock
                          ? BorderSide.none
                          : const BorderSide(color: _kBorder),
                    ),
                  ),
                  child: _isUnlocking
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: _kBg,
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.lock_open_rounded,
                              size: 20,
                              color: _canUnlock ? _kBg : _kDim,
                            ),
                            const SizedBox(width: 9),
                            Text(
                              'SBLOCCA MEZZO',
                              style: GoogleFonts.barlowCondensed(
                                fontSize: 19,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.2,
                                color: _canUnlock ? _kBg : _kDim,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              if (!_canUnlock) ...[
                const SizedBox(height: 6),
                Text(
                  'Avvicinati al mezzo (entro 50 m) per sbloccarlo, oppure usa «Scansiona QR» sulla mappa.',
                  style: GoogleFonts.barlow(
                    fontSize: 12.5,
                    height: 1.3,
                    color: _kDim,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              // UT.02 — Prenotazione (opzionale): tiene il mezzo per te finché
              // non ci arrivi.
              SizedBox(
                height: 46,
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: busy ? null : _book,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _kAccent,
                    side: const BorderSide(color: _kAccent),
                    disabledForegroundColor: _kDim,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  child: _isBooking
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: _kAccent,
                          ),
                        )
                      : Text(
                          'PRENOTA',
                          style: GoogleFonts.barlowCondensed(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.5,
                            color: _kAccent,
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
