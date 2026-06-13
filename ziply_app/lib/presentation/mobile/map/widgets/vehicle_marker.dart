import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ziply_app/data/models/vehicle_model.dart';

// ── Stile marker (da Grafica/mappa-handoff) ────────────────────────────────
// Cerchio di sfondo #D4580A con icona bianca #FFFFFF; l'unica differenza tra i
// tipi è l'icona. Attorno, un anello di tacche indica la carica della batteria.
const Color _kMarkerFill = Color(0xFFD4580A);
const Color _kMarkerIcon = Color(0xFFFFFFFF);

// Anello batteria (da convenzione badge: verde se >70%, altrimenti accent).
const Color _kBatteryFull  = Color(0xFF5DCAA5);
const Color _kBatteryLow   = Color(0xFFF69659);
const Color _kBatteryTrack = Color(0x4DFFFFFF); // tacche "vuote"

const double _kCoreDiameter = 38; // cerchio interno con icona
const double _kRingDiameter = 50; // anello batteria attorno al core

/// Pin del mezzo sulla mappa: cerchio #D4580A con icona bianca, circondato da
/// un anello di tacche (tratteggiato) che indica la carica della batteria.
class VehicleMarker extends StatelessWidget {
  const VehicleMarker({
    super.key,
    required this.kind,
    required this.batteryLevel,
    this.dimmed = false,
  });

  final VehicleType kind;
  final int batteryLevel;

  /// Quando true il marker è "spento" (opacità ridotta): usato per i mezzi non
  /// prenotati mentre è attiva una prenotazione.
  final bool dimmed;

  /// Lato del box del marker (include l'anello batteria).
  static const double diameter = 54;

  @override
  Widget build(BuildContext context) {
    final marker = _RingedMarker(kind: kind, batteryLevel: batteryLevel);
    return SizedBox(
      width: diameter,
      height: diameter,
      child: Center(
        child: dimmed ? Opacity(opacity: 0.3, child: marker) : marker,
      ),
    );
  }
}

/// Variante evidenziata del marker: più grande e pulsante, per il mezzo
/// prenotato. Gli altri mezzi vengono mostrati con [VehicleMarker.dimmed].
class ActiveVehicleMarker extends StatefulWidget {
  const ActiveVehicleMarker({
    super.key,
    required this.kind,
    required this.batteryLevel,
  });

  final VehicleType kind;
  final int batteryLevel;

  /// Lato del box: più ampio per contenere l'alone pulsante senza clipping.
  static const double activeDiameter = 96;

  @override
  State<ActiveVehicleMarker> createState() => _ActiveVehicleMarkerState();
}

class _ActiveVehicleMarkerState extends State<ActiveVehicleMarker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: ActiveVehicleMarker.activeDiameter,
      height: ActiveVehicleMarker.activeDiameter,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final t = Curves.easeInOut.transform(_controller.value);
          final scale = 1.15 + 0.18 * t;            // "respiro" del marker
          final haloScale = 1.0 + 0.95 * _controller.value;
          final haloOpacity = (1 - _controller.value) * 0.35;
          return Stack(
            alignment: Alignment.center,
            children: [
              Transform.scale(
                scale: haloScale,
                child: Container(
                  width: _kRingDiameter,
                  height: _kRingDiameter,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _kBatteryLow.withValues(alpha: haloOpacity),
                  ),
                ),
              ),
              Transform.scale(scale: scale, child: child),
            ],
          );
        },
        child: _RingedMarker(
          kind: widget.kind,
          batteryLevel: widget.batteryLevel,
        ),
      ),
    );
  }
}

/// Cerchio centrale con icona + anello batteria attorno (dimensione fissa).
class _RingedMarker extends StatelessWidget {
  const _RingedMarker({required this.kind, required this.batteryLevel});

  final VehicleType kind;
  final int batteryLevel;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _kRingDiameter,
      height: _kRingDiameter,
      child: CustomPaint(
        painter: _BatteryRingPainter(level: batteryLevel),
        child: Center(child: _core(kind)),
      ),
    );
  }
}

/// Cerchio centrale arancione con l'icona del mezzo.
Widget _core(VehicleType kind) {
  return Container(
    width: _kCoreDiameter,
    height: _kCoreDiameter,
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

/// Marker di cluster: stesso cerchio dei marker singoli (#D4580A, stessa
/// ombra), ma con il numero di mezzi aggregati al centro al posto dell'icona.
class ClusterMarker extends StatelessWidget {
  const ClusterMarker({super.key, required this.count});

  final int count;

  static const double diameter = 44;

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
      child: Text(
        '$count',
        style: GoogleFonts.barlowCondensed(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          height: 1,
          color: _kMarkerIcon,
        ),
      ),
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
      return SvgPicture.string(kScooterGlyphSvg, width: 24, height: 24);
    case VehicleType.unknown:
      return const Icon(Icons.location_on, color: _kMarkerIcon, size: 22);
  }
}

/// Anello batteria: tacche ad arco attorno al marker, riempite in proporzione
/// alla carica. Tacche piene verdi se >70% (altrimenti accent), vuote tenui.
class _BatteryRingPainter extends CustomPainter {
  const _BatteryRingPainter({required this.level});

  final int level;

  static const int _segments = 12;
  static const double _gapDegrees = 9; // spazio tra le tacche
  static const double _stroke = 3.5;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide - _stroke) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final clamped = level.clamp(0, 100);
    final filled = (clamped / 100 * _segments).round();
    final fullColor = clamped > 70 ? _kBatteryFull : _kBatteryLow;

    const segmentSweep = (2 * pi) / _segments;
    const gap = _gapDegrees * pi / 180;
    const arcSweep = segmentSweep - gap;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < _segments; i++) {
      // Parte dall'alto (-90°) e procede in senso orario.
      final startAngle = -pi / 2 + i * segmentSweep + gap / 2;
      paint.color = i < filled ? fullColor : _kBatteryTrack;
      canvas.drawArc(rect, startAngle, arcSweep, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BatteryRingPainter oldDelegate) =>
      oldDelegate.level != level;
}

// Monopattino: icona Material Symbols "scooter", riempita di bianco (#FFFFFF).
// Pubblica per riuso nella scheda mezzo (vehicle_bottom_sheet), dove viene
// ricolorata in accent via ColorFilter.
const String kScooterGlyphSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 -960 960 960" '
    'fill="#FFFFFF"><path d="M788.5-251.5Q800-263 800-280t-11.5-28.5Q777-320 '
    '760-320t-28.5 11.5Q720-297 720-280t11.5 28.5Q743-240 760-240t28.5-11.5ZM760-160q-50 '
    '0-85-35t-35-85q0-50 35-85t85-35q50 0 85 35t35 85q0 50-35 85t-85 35Zm-531.5-91.5Q240-263 '
    '240-280t-11.5-28.5Q217-320 200-320t-28.5 11.5Q160-297 160-280t11.5 28.5Q183-240 '
    '200-240t28.5-11.5ZM200-160q-50 0-85-35t-35-85q0-50 35-85t85-35q38 0 69 22t44 58h211q11-69 '
    '56.5-119.5T692-510l-56-250H480v-80h156q28 0 50 17t28 45l76 338h-30q-66 0-113 47t-47 '
    '113v40H313q-13 36-44 58t-69 22Z"/></svg>';
