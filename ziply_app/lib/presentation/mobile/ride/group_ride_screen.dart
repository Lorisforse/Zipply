// [MOBILE] UT.16 — Schermata noleggio di gruppo (prenotazione multipla).
// Dopo lo sblocco simultaneo mostra tutti i mezzi del gruppo su una mappa, un
// timer condiviso (le corse partono insieme) e il costo totale aggiornato in
// tempo reale. "Termina gruppo" chiude tutte le corse in un colpo.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:ziply_app/core/utils/app_logger.dart';
import 'package:ziply_app/data/models/ride_model.dart';
import 'package:ziply_app/data/models/vehicle_model.dart';
import 'package:ziply_app/presentation/mobile/map/widgets/vehicle_marker.dart';
import 'package:ziply_app/presentation/mobile/map/widgets/vehicle_widgets.dart';
import 'package:ziply_app/presentation/mobile/map/widgets/ziply_tile_layer.dart';
import 'package:ziply_app/services/api_exceptions.dart';
import 'package:ziply_app/services/ride_service.dart';

const Color _kBg = Color(0xFF1A1A1A);
const Color _kSurface = Color(0xFF252525);
const Color _kSurface2 = Color(0xFF2D2D2D);
const Color _kBorder = Color(0xFF333333);
const Color _kText = Color(0xFFF5F5F5);
const Color _kDim = Color(0xFF777777);
const Color _kAccent = Color(0xFFF69659);

const double _kZoom = 15.5;

/// [MOBILE] UT.16 — Noleggio di gruppo. Riceve i mezzi sbloccati e le corse
/// avviate (tutte sotto lo stesso group_id).
class GroupRideScreen extends StatefulWidget {
  const GroupRideScreen({
    super.key,
    required this.groupId,
    required this.vehicles,
    required this.rides,
  });

  final String groupId;
  final List<VehicleModel> vehicles;
  final List<RideModel> rides;

  @override
  State<GroupRideScreen> createState() => _GroupRideScreenState();
}

class _GroupRideScreenState extends State<GroupRideScreen> {
  final RideService _rideService = RideService();
  Timer? _ticker;
  bool _ending = false;

  late final DateTime _startedAt;
  late final double _totalRatePerMinute;

  @override
  void initState() {
    super.initState();
    // Tutte le corse partono insieme: prendo l'avvio più vecchio come
    // riferimento per il timer condiviso.
    _startedAt = widget.rides
        .map((r) => r.startedAt)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    // Tariffa totale al minuto = somma delle tariffe dei mezzi del gruppo.
    _totalRatePerMinute = widget.vehicles
        .fold<double>(0, (sum, v) => sum + v.hourlyRate / 60);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  int get _elapsedSeconds => DateTime.now().difference(_startedAt).inSeconds;

  /// Minuti addebitati a scatti (sotto i 20 s non si addebita).
  int get _chargedMinutes {
    final sec = _elapsedSeconds;
    if (sec < 20) return 0;
    return (sec / 60).ceil();
  }

  double get _cost => _chargedMinutes * _totalRatePerMinute;

  LatLng get _center {
    var lat = 0.0;
    var lng = 0.0;
    for (final v in widget.vehicles) {
      lat += v.latitude;
      lng += v.longitude;
    }
    final n = widget.vehicles.length;
    return n == 0 ? const LatLng(45.4654, 9.1859) : LatLng(lat / n, lng / n);
  }

  String _formatElapsed(int sec) {
    final h = sec ~/ 3600;
    final m = (sec % 3600) ~/ 60;
    final s = sec % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  String _euro(double value) =>
      '€ ${value.toStringAsFixed(2).replaceAll('.', ',')}';

  Future<void> _onEndGroup() async {
    if (_ending) return;
    zlog('Termino il noleggio di gruppo ${widget.groupId}', tag: 'Noleggio');
    setState(() => _ending = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final summary = await _rideService.endGroup(widget.groupId);
      if (!mounted) return;
      await _showSummaryDialog(summary);
      if (!mounted) return;
      navigator.pop();
    } on SessionExpiredException catch (e) {
      if (!mounted) return;
      setState(() => _ending = false);
      messenger.showSnackBar(SnackBar(
        backgroundColor: _kSurface,
        content: Text(e.message,
            style: GoogleFonts.barlow(fontSize: 14, color: _kText)),
      ));
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _ending = false);
      messenger.showSnackBar(SnackBar(
        backgroundColor: _kSurface,
        content: Text(e.toString().replaceFirst('Exception: ', ''),
            style: GoogleFonts.barlow(fontSize: 14, color: _kText)),
      ));
    }
  }

  Future<void> _showSummaryDialog(RideEndSummary summary) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: Text(
          'Noleggio di gruppo concluso',
          style: GoogleFonts.barlowCondensed(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: _kText,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _summaryRow('Mezzi', '${widget.vehicles.length}'),
            _summaryRow('Durata', '${summary.durationMinutes} min'),
            _summaryRow('CO₂ risparmiata',
                '${summary.co2SavedGrams.toStringAsFixed(0)} g'),
            if (summary.appliedDiscount > 0)
              _summaryRow('Sconto', '−${_euro(summary.appliedDiscount)}'),
            const SizedBox(height: 4),
            _summaryRow('Totale', _euro(summary.totalCost), highlight: true),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'CHIUDI',
              style: GoogleFonts.barlowCondensed(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: _kAccent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: GoogleFonts.barlow(fontSize: 14, color: _kDim)),
          Text(
            value,
            style: GoogleFonts.barlowCondensed(
              fontSize: highlight ? 20 : 16,
              fontWeight: FontWeight.w700,
              color: highlight ? _kAccent : _kText,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: Stack(
        children: [
          Positioned.fill(
            child: FlutterMap(
              options: MapOptions(
                initialCenter: _center,
                initialZoom: _kZoom,
                backgroundColor: _kBg,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
                ),
              ),
              children: [
                ziplyTileLayer(context),
                MarkerLayer(
                  markers: [
                    for (final v in widget.vehicles)
                      Marker(
                        point: LatLng(v.latitude, v.longitude),
                        width: ActiveVehicleMarker.activeDiameter,
                        height: ActiveVehicleMarker.activeDiameter,
                        rotate: true,
                        child: ActiveVehicleMarker(
                          kind: v.kind,
                          batteryLevel: v.batteryLevel,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(left: 18, top: 8),
              child: Align(
                alignment: Alignment.topLeft,
                child: Text(
                  'ZIPLY',
                  style: GoogleFonts.barlowCondensed(
                    fontSize: 23,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: _kAccent,
                  ),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: _buildBanner(),
          ),
        ],
      ),
    );
  }

  Widget _buildBanner() {
    return Container(
      decoration: const BoxDecoration(
        color: _kSurface,
        border: Border(top: BorderSide(color: _kAccent, width: 2)),
        boxShadow: [
          BoxShadow(
            color: Color(0x80000000),
            blurRadius: 34,
            offset: Offset(0, -14),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'NOLEGGIO DI GRUPPO',
                    style: GoogleFonts.barlowCondensed(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                      color: _kAccent,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${widget.vehicles.length} mezzi · ${_euro(_totalRatePerMinute)}/min',
                    style: GoogleFonts.barlow(fontSize: 12.5, color: _kDim),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Glifi dei mezzi del gruppo.
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final v in widget.vehicles)
                    Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _kSurface2,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: _kBorder, width: 0.5),
                      ),
                      child: vehicleGlyph(v.kind, size: 20),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Text(
                      _formatElapsed(_elapsedSeconds),
                      style: GoogleFonts.barlowCondensed(
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        height: 1,
                        color: _kText,
                      ),
                    ),
                  ),
                  Text(
                    _euro(_cost),
                    style: GoogleFonts.barlowCondensed(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      height: 1,
                      color: _kAccent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 52,
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _ending ? null : _onEndGroup,
                  icon: _ending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: _kBg),
                        )
                      : const Icon(Icons.stop_rounded, size: 20, color: _kBg),
                  label: Text(
                    _ending ? 'TERMINO…' : 'TERMINA GRUPPO',
                    style: GoogleFonts.barlowCondensed(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: _kBg,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kAccent,
                    foregroundColor: _kBg,
                    disabledBackgroundColor: _kAccent,
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
      ),
    );
  }
}
