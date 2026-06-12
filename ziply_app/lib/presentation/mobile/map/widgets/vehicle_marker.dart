import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:ziply_app/data/models/vehicle_model.dart';

// ── Palette (da Grafica/mappa-handoff) ─────────────────────────────────────
const Color _kAccent     = Color(0xFFF69659);
const Color _kAccentDark = Color(0xFFD4580A);
const Color _kSurface    = Color(0xFF252525);

/// Pin del mezzo sulla mappa: cerchio con glifo del veicolo all'interno,
/// differenziato per tipo secondo il design handoff.
///   bike    → cerchio pieno accent, glifo bianco
///   scooter → cerchio pieno accentDark, glifo bianco
///   car     → cerchio surface con bordo accent, glifo accent
class VehicleMarker extends StatelessWidget {
  const VehicleMarker({super.key, required this.kind});

  final VehicleType kind;

  static const double diameter = 38;

  @override
  Widget build(BuildContext context) {
    final bool isCar = kind == VehicleType.car;
    final Color fill = switch (kind) {
      VehicleType.bike => _kAccent,
      VehicleType.scooter => _kAccentDark,
      VehicleType.car => _kSurface,
      VehicleType.unknown => _kSurface,
    };
    final Color iconColor = isCar ? _kAccent : Colors.white;

    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: isCar ? Border.all(color: _kAccent, width: 2) : null,
        boxShadow: const [
          BoxShadow(
            color: Color(0x8C000000), // rgba(0,0,0,0.55)
            blurRadius: 14,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Center(
        child: SvgPicture.string(
          _glyphSvg(kind, iconColor),
          width: 19,
          height: 19,
        ),
      ),
    );
  }
}

/// Costruisce il glifo SVG del mezzo (stroke), riusando i tracciati del design.
String _glyphSvg(VehicleType kind, Color color) {
  final String stroke = _hex(color);
  final String inner = switch (kind) {
    VehicleType.bike =>
      '<circle cx="5.5" cy="17" r="3.5"/><circle cx="18.5" cy="17" r="3.5"/>'
          '<path d="M5.5 17l4-9h5l-3 9M9.5 8h4M15 8l3.5 9"/>',
    VehicleType.scooter =>
      '<circle cx="5" cy="18" r="2.6"/><circle cx="19" cy="18" r="2.6"/>'
          '<path d="M16.4 18H7.6M16.5 18L15 5h3.5M9 9l6.5-0.5"/>',
    VehicleType.car =>
      '<path d="M3 13l1.8-5.2A2 2 0 016.7 6.5h10.6a2 2 0 011.9 1.3L21 13'
          'M3 13v4.5h2.5M21 13v4.5h-2.5M3 13h18M6.5 17.5v1.5M17.5 17.5v1.5"/>'
          '<circle cx="7.2" cy="13.4" r="1"/><circle cx="16.8" cy="13.4" r="1"/>',
    VehicleType.unknown => '<circle cx="12" cy="12" r="5"/>',
  };
  return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" '
      'fill="none" stroke="$stroke" stroke-width="2" '
      'stroke-linecap="round" stroke-linejoin="round">$inner</svg>';
}

/// Converte un [Color] nel formato esadecimale #RRGGBB usato dall'SVG.
String _hex(Color color) {
  final int rgb = color.toARGB32() & 0x00FFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0')}';
}
