import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:ziply_app/data/models/vehicle_model.dart';
import 'package:ziply_app/presentation/mobile/map/widgets/vehicle_widgets.dart';

// ── Palette (da Grafica/mappa-handoff) ─────────────────────────────────────
const Color _kBg     = Color(0xFF1A1A1A);
const Color _kBorder = Color(0xFF333333);
const Color _kText   = Color(0xFFF5F5F5);
const Color _kDim    = Color(0xFF777777);
const Color _kAccent = Color(0xFFF69659);

/// [MOBILE] Lista "mezzi vicino a te" (handoff mappa). Bottom sheet aperto da un
/// pulsante (NON sempre presente): mostra i mezzi già filtrati e ordinati per
/// distanza come righe tappabili. Pop con il [VehicleModel] selezionato.
class NearbyVehiclesSheet extends StatelessWidget {
  const NearbyVehiclesSheet({
    super.key,
    required this.vehicles,
    required this.userPosition,
    required this.radiusKm,
  });

  final List<VehicleModel> vehicles;
  final LatLng? userPosition;
  final double radiusKm;

  static Future<VehicleModel?> show(
    BuildContext context, {
    required List<VehicleModel> vehicles,
    required LatLng? userPosition,
    required double radiusKm,
  }) {
    return showModalBottomSheet<VehicleModel>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x8C000000), // rgba(0,0,0,0.55)
      isScrollControlled: true,
      builder: (_) => NearbyVehiclesSheet(
        vehicles: vehicles,
        userPosition: userPosition,
        radiusKm: radiusKm,
      ),
    );
  }

  String _radiusLabel() {
    if (radiusKm >= 1) {
      final s = radiusKm
          .toStringAsFixed(radiusKm % 1 == 0 ? 0 : 1)
          .replaceAll('.', ',');
      return 'nel raggio di $s km';
    }
    return 'nel raggio di ${(radiusKm * 1000).round()} m';
  }

  @override
  Widget build(BuildContext context) {
    final count = vehicles.length;
    final maxHeight = MediaQuery.of(context).size.height * 0.7;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle.
            Container(
              width: 38,
              height: 4,
              margin: const EdgeInsets.fromLTRB(0, 8, 0, 14),
              decoration: BoxDecoration(
                color: _kBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header.
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$count ${count == 1 ? 'MEZZO' : 'MEZZI'} VICINO A TE',
                    style: GoogleFonts.barlowCondensed(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      color: _kText,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _radiusLabel(),
                    style: GoogleFonts.barlow(fontSize: 13, color: _kDim),
                  ),
                ],
              ),
            ),
            Container(height: 1, color: _kBorder),
            Flexible(
              child: count == 0
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Nessun mezzo di questo tipo nelle vicinanze.',
                        style: GoogleFonts.barlow(fontSize: 14, color: _kDim),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.only(top: 4, bottom: 8),
                      itemCount: count,
                      separatorBuilder: (_, __) =>
                          Container(height: 0.5, color: _kBorder),
                      itemBuilder: (context, i) => _NearbyRow(
                        vehicle: vehicles[i],
                        userPosition: userPosition,
                        // Il primo (più vicino) è evidenziato come da handoff.
                        nearest: i == 0 && userPosition != null,
                        onTap: () => Navigator.of(context).pop(vehicles[i]),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NearbyRow extends StatelessWidget {
  const _NearbyRow({
    required this.vehicle,
    required this.userPosition,
    required this.nearest,
    required this.onTap,
  });

  final VehicleModel vehicle;
  final LatLng? userPosition;
  final bool nearest;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final title = vehicle.type.isEmpty ? 'Mezzo' : vehicle.type;
    final (dist, secondary) =
        walkingLabels(userPosition, vehicle.latitude, vehicle.longitude);
    final distLine = secondary == null ? dist : '$dist · $secondary';

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          // Bordo sinistro accent per il mezzo più vicino (da handoff).
          border: Border(
            left: BorderSide(
              color: nearest ? _kAccent : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Row(
          children: [
            VehicleGlyphTile(kind: vehicle.kind),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.barlowCondensed(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                      color: _kText,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    distLine,
                    style: GoogleFonts.barlow(fontSize: 12.5, color: _kDim),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            BatteryBadge(pct: vehicle.batteryLevel),
          ],
        ),
      ),
    );
  }
}
