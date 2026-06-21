import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:ziply_app/core/theme/app_colors.dart';
import 'package:ziply_app/data/models/vehicle_model.dart';
import 'package:ziply_app/presentation/mobile/map/widgets/vehicle_marker.dart';

// Palette (alias di AppColors).
const Color _kSurface = AppColors.surface;
const Color _kBorder  = AppColors.border;
const Color _kAccent  = AppColors.accent;
const Color _kGreen   = AppColors.green;

/// Glifo del mezzo coerente col marker sulla mappa (monopattino = stesso SVG,
/// NON Icons.electric_scooter col fulmine), colorato in [color].
Widget vehicleGlyph(VehicleType kind, {Color color = _kAccent, double size = 21}) {
  switch (kind) {
    case VehicleType.bike:
      return Icon(Icons.pedal_bike, color: color, size: size);
    case VehicleType.car:
      return Icon(Icons.directions_car, color: color, size: size);
    case VehicleType.scooter:
      return SvgPicture.string(
        kScooterGlyphSvg,
        width: size + 1,
        height: size + 1,
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      );
    case VehicleType.unknown:
      return Icon(Icons.location_on, color: color, size: size);
  }
}

/// Tile quadrato (surface, bordo sottile) con il glifo del mezzo in accent.
/// Da handoff: 42×42, raggio 4.
class VehicleGlyphTile extends StatelessWidget {
  const VehicleGlyphTile({super.key, required this.kind, this.size = 42});

  final VehicleType kind;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: _kBorder, width: 0.5),
      ),
      child: vehicleGlyph(kind),
    );
  }
}

/// Badge batteria (da handoff: verde se >70%, altrimenti accent).
class BatteryBadge extends StatelessWidget {
  const BatteryBadge({super.key, required this.pct});

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

/// Distanza a piedi (valore + stima minuti, ~80 m/min) da [from] al punto del
/// mezzo. Restituisce («—», null) se [from] è assente.
(String, String?) walkingLabels(LatLng? from, double lat, double lng) {
  if (from == null) return ('—', null);

  final meters = Geolocator.distanceBetween(from.latitude, from.longitude, lat, lng);
  final String value;
  if (meters >= 1000) {
    value = '${(meters / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';
  } else {
    value = '${meters.round()} m';
  }

  final walk = (meters / 80).round();
  return (value, 'a ${walk < 1 ? 1 : walk} min');
}
