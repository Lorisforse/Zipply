import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:ziply_app/data/models/vehicle_model.dart';

// ── Palette (da Grafica/mappa-handoff) ─────────────────────────────────────
const Color _kBg      = Color(0xFF1A1A1A);
const Color _kSurface = Color(0xFF252525);
const Color _kBorder  = Color(0xFF333333);
const Color _kText    = Color(0xFFF5F5F5);
const Color _kDim     = Color(0xFF777777);
const Color _kAccent  = Color(0xFFF69659);
const Color _kGreen   = Color(0xFF5DCAA5);

/// [MOBILE] UT.05 — Scheda mezzo.
/// Bottom sheet informativo aperto al tap su un marker: mostra tipo, batteria,
/// tariffa e distanza dall'utente. Nessuna logica di prenotazione (→ UT.02).
class VehicleBottomSheet extends StatelessWidget {
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
  static Future<void> show(
    BuildContext context,
    VehicleModel vehicle,
    LatLng? userPosition,
  ) {
    return showModalBottomSheet<void>(
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
  Widget build(BuildContext context) {
    final title = vehicle.type.isEmpty ? 'Mezzo' : vehicle.type;
    final rateText =
        '${(vehicle.hourlyRate / 60).toStringAsFixed(2).replaceAll('.', ',')} €';
    final (distValue, distSecondary) = _distanceLabels();

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
                  _GlyphTile(kind: vehicle.kind),
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
                  _BatteryBadge(pct: vehicle.batteryLevel),
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
            ],
          ),
        ),
      ),
    );
  }

  /// Calcola distanza (Haversine via geolocator) e stima a piedi.
  /// Restituisce (valore, secondario). Senza posizione utente → («—», null).
  (String, String?) _distanceLabels() {
    final pos = userPosition;
    if (pos == null) return ('—', null);

    final meters = Geolocator.distanceBetween(
      pos.latitude,
      pos.longitude,
      vehicle.latitude,
      vehicle.longitude,
    );

    final String value;
    if (meters >= 1000) {
      value = '${(meters / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';
    } else {
      value = '${meters.round()} m';
    }

    // Stima a piedi come da handoff: ~80 m/min, minimo 1 min.
    final walk = (meters / 80).round();
    return (value, 'a ${walk < 1 ? 1 : walk} min');
  }
}

// ── Tile-glifo del mezzo (da handoff: 42×42, raggio 4, glifo accent) ────────
class _GlyphTile extends StatelessWidget {
  const _GlyphTile({required this.kind});

  final VehicleType kind;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: _kBorder, width: 0.5),
      ),
      child: Icon(_iconFor(kind), color: _kAccent, size: 21),
    );
  }

  IconData _iconFor(VehicleType kind) {
    switch (kind) {
      case VehicleType.bike:
        return Icons.pedal_bike;
      case VehicleType.scooter:
        return Icons.electric_scooter;
      case VehicleType.car:
        return Icons.directions_car;
      case VehicleType.unknown:
        return Icons.location_on;
    }
  }
}

// ── Badge batteria (da handoff: verde se >70%, altrimenti accent) ──────────
class _BatteryBadge extends StatelessWidget {
  const _BatteryBadge({required this.pct});

  final int pct;

  @override
  Widget build(BuildContext context) {
    final ok = pct > 70;
    final color = ok ? _kGreen : _kAccent;
    final bg = ok
        ? const Color(0x1A5DCAA5) // rgba(93,202,165,0.10)
        : const Color(0x1FD4580A); // rgba(212,88,10,0.12)

    return Container(
      padding: const EdgeInsets.fromLTRB(5, 2, 6, 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: color, width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bolt, color: color, size: 12),
          const SizedBox(width: 3),
          Text(
            '$pct%',
            style: GoogleFonts.barlowCondensed(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
              height: 1,
              color: color,
            ),
          ),
        ],
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
