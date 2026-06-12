import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:ziply_app/data/models/vehicle_model.dart';

// ── Stile marker (da Grafica/mappa-handoff) ────────────────────────────────
// Tutti i marker sono identici: stesso cerchio di sfondo #D4580A e stessa
// icona bianca #FFFFFF. L'unica differenza tra i tipi è l'icona.
const Color _kMarkerFill = Color(0xFFD4580A);
const Color _kMarkerIcon = Color(0xFFFFFFFF);

/// Pin del mezzo sulla mappa: cerchio con fill #D4580A e icona bianca centrata.
/// Resa uniforme per ogni tipo, cambia solo l'icona.
class VehicleMarker extends StatelessWidget {
  const VehicleMarker({super.key, required this.kind});

  final VehicleType kind;

  static const double diameter = 38;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: diameter,
      height: diameter,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: _kMarkerFill,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Color(0x8C000000), // rgba(0,0,0,0.55)
            blurRadius: 14,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: _glyph(kind),
    );
  }
}

/// Glifo del mezzo. Bici e auto: icone Material piene. Monopattino: SVG
/// fornito (Material Symbols "scooter"), riempito di bianco.
Widget _glyph(VehicleType kind) {
  switch (kind) {
    case VehicleType.bike:
      return const Icon(Icons.pedal_bike, color: _kMarkerIcon, size: 22);
    case VehicleType.car:
      return const Icon(Icons.directions_car, color: _kMarkerIcon, size: 22);
    case VehicleType.scooter:
      return SvgPicture.string(_kScooterSvg, width: 24, height: 24);
    case VehicleType.unknown:
      return const Icon(Icons.location_on, color: _kMarkerIcon, size: 22);
  }
}

// Monopattino: icona Material Symbols "scooter", riempita di bianco (#FFFFFF).
const String _kScooterSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 -960 960 960" '
    'fill="#FFFFFF"><path d="M788.5-251.5Q800-263 800-280t-11.5-28.5Q777-320 '
    '760-320t-28.5 11.5Q720-297 720-280t11.5 28.5Q743-240 760-240t28.5-11.5ZM760-160q-50 '
    '0-85-35t-35-85q0-50 35-85t85-35q50 0 85 35t35 85q0 50-35 85t-85 35Zm-531.5-91.5Q240-263 '
    '240-280t-11.5-28.5Q217-320 200-320t-28.5 11.5Q160-297 160-280t11.5 28.5Q183-240 '
    '200-240t28.5-11.5ZM200-160q-50 0-85-35t-35-85q0-50 35-85t85-35q38 0 69 22t44 58h211q11-69 '
    '56.5-119.5T692-510l-56-250H480v-80h156q28 0 50 17t28 45l76 338h-30q-66 0-113 47t-47 '
    '113v40H313q-13 36-44 58t-69 22Z"/></svg>';
