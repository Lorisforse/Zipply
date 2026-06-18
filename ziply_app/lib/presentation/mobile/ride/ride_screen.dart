// [MOBILE] UT.13 — Schermata corsa attiva (handoff noleggio-attivo).
// Mostrata dopo lo sblocco riuscito (prossimità o QR): mappa con il mezzo in
// uso e un banner "Noleggio in corso" con timer dal momento dell'avvio e costo
// aggiornato in tempo reale (minuti trascorsi × tariffa al minuto).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:ziply_app/core/utils/app_logger.dart';
import 'package:ziply_app/data/models/ride_model.dart';
import 'package:ziply_app/data/models/vehicle_model.dart';
import 'package:ziply_app/presentation/mobile/map/widgets/vehicle_marker.dart';
import 'package:ziply_app/presentation/mobile/map/widgets/ziply_tile_layer.dart';
import 'package:ziply_app/presentation/mobile/map/widgets/vehicle_widgets.dart';
import 'package:ziply_app/presentation/mobile/ride/ride_summary_screen.dart';
import 'package:ziply_app/services/api_exceptions.dart';
import 'package:ziply_app/services/ride_service.dart';

// ── Palette (da Grafica/noleggio-attivo-handoff) ───────────────────────────
const Color _kBg = Color(0xFF1A1A1A);
const Color _kSurface = Color(0xFF252525);
const Color _kSurface2 = Color(0xFF2D2D2D);
const Color _kBorder = Color(0xFF333333);
const Color _kText = Color(0xFFF5F5F5);
const Color _kDim = Color(0xFF777777);
const Color _kAccent = Color(0xFFF69659);

const double _kZoom = 16;

/// [MOBILE] UT.13 — Noleggio attivo. Riceve la corsa appena avviata e il mezzo
/// sbloccato (i cui dati — tipo, tariffa, batteria — sono già nel contesto).
class RideScreen extends StatelessWidget {
  const RideScreen({super.key, required this.ride, required this.vehicle});

  final RideModel ride;
  final VehicleModel vehicle;

  /// Apre la schermata sostituendo la rotta corrente: dopo lo sblocco non si
  /// torna indietro alla scheda di prenotazione (ormai consumata).
  static Future<void> show(
    BuildContext context, {
    required RideModel ride,
    required VehicleModel vehicle,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
          builder: (_) => RideScreen(ride: ride, vehicle: vehicle)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vehiclePos = LatLng(vehicle.latitude, vehicle.longitude);
    return Scaffold(
      backgroundColor: _kBg,
      body: Stack(
        children: [
          // Mappa di sfondo centrata sul mezzo in uso.
          Positioned.fill(
            child: FlutterMap(
              options: MapOptions(
                initialCenter: vehiclePos,
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
                    Marker(
                      point: vehiclePos,
                      width: ActiveVehicleMarker.activeDiameter,
                      height: ActiveVehicleMarker.activeDiameter,
                      rotate: true,
                      child: ActiveVehicleMarker(
                        kind: vehicle.kind,
                        batteryLevel: vehicle.batteryLevel,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Wordmark in alto a sinistra (come da handoff).
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
          // Banner "Noleggio in corso" ancorato in basso.
          Align(
            alignment: Alignment.bottomCenter,
            child: _ActiveRentalBanner(ride: ride, vehicle: vehicle),
          ),
        ],
      ),
    );
  }
}

// ── Banner noleggio in corso (timer + costo live) ─────────────────────────
class _ActiveRentalBanner extends StatefulWidget {
  const _ActiveRentalBanner({required this.ride, required this.vehicle});

  final RideModel ride;
  final VehicleModel vehicle;

  @override
  State<_ActiveRentalBanner> createState() => _ActiveRentalBannerState();
}

class _ActiveRentalBannerState extends State<_ActiveRentalBanner> {
  final RideService _rideService = RideService();
  Timer? _ticker;
  bool _ending = false;

  @override
  void initState() {
    super.initState();
    // Tick al secondo: timer e costo sono ricalcolati da started_at.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// Tariffa al minuto derivata dalla tariffa oraria del mezzo.
  double get _ratePerMinute => widget.vehicle.hourlyRate / 60;

  /// Secondi trascorsi dall'avvio della corsa (mai negativi).
  int get _elapsedSeconds {
    final diff = DateTime.now().difference(widget.ride.startedAt).inSeconds;
    return diff < 0 ? 0 : diff;
  }

  /// Minuti addebitati: l'importo non cambia ogni secondo ma a "scatti di
  /// minuto" (per non addebitare cifre irrisorie tipo 0,03 €). Sotto i 20
  /// secondi è gratis; dai 20 secondi in poi si paga 1 minuto pieno; ogni
  /// secondo oltre il minuto pieno fa scattare il minuto successivo
  /// (es. 01:01 → 2 minuti). Cioè: 0 se < 20 s, altrimenti ceil(secondi/60).
  int get _chargedMinutes {
    final sec = _elapsedSeconds;
    if (sec < 20) return 0;
    return (sec / 60).ceil();
  }

  /// Costo corrente: minuti addebitati × tariffa al minuto.
  double get _cost => _chargedMinutes * _ratePerMinute;

  String _formatElapsed(int sec) {
    final h = sec ~/ 3600;
    final m = (sec % 3600) ~/ 60;
    final s = sec % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  String _euro(double value) =>
      '€ ${value.toStringAsFixed(2).replaceAll('.', ',')}';

  /// Termina il noleggio: chiude la corsa lato backend (così il mezzo torna
  /// disponibile) e mostra il riepilogo di fine corsa (UT.04) con durata e
  /// costo congelati al momento del termine. In caso di errore resta sulla
  /// schermata mostrando il messaggio.
  Future<void> _onEndRide() async {
    if (_ending) return;
    // Congela durata e costo come mostrati nel banner al momento del termine:
    // l'endpoint /end restituisce solo lo stato, quindi il riepilogo riusa i
    // valori già calcolati qui.
    final duration = Duration(seconds: _elapsedSeconds);
    final cost = _cost;
    zlog('Termino il noleggio ${widget.ride.id}', tag: 'Noleggio');
    setState(() => _ending = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _rideService.endRide(widget.ride.id);
      if (!mounted) return;
      zlog('Noleggio terminato: mostro il riepilogo', tag: 'Noleggio');
      await RideSummaryScreen.show(
        navigator.context,
        ride: widget.ride,
        vehicle: widget.vehicle,
        duration: duration,
        cost: cost,
      );
    } on SessionExpiredException catch (e) {
      if (!mounted) return;
      setState(() => _ending = false);
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: _kSurface,
          content: Text(
            e.message,
            style: GoogleFonts.barlow(fontSize: 14, color: _kText),
          ),
        ),
      );
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _ending = false);
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: _kSurface,
          content: Text(
            e.toString().replaceFirst('Exception: ', ''),
            style: GoogleFonts.barlow(fontSize: 14, color: _kText),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.vehicle.type.isEmpty ? 'Mezzo' : widget.vehicle.type;

    return Container(
      decoration: const BoxDecoration(
        color: _kSurface,
        border: Border(top: BorderSide(color: _kAccent, width: 2)),
        boxShadow: [
          BoxShadow(
            color: Color(0x80000000), // rgba(0,0,0,0.5)
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
              // Riga stato: pallino pulsante + "NOLEGGIO IN CORSO" + tariffa.
              Row(
                children: [
                  const _PulseDot(),
                  const SizedBox(width: 8),
                  Text(
                    'NOLEGGIO IN CORSO',
                    style: GoogleFonts.barlowCondensed(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                      color: _kAccent,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'tariffa ${_euro(_ratePerMinute)}/min',
                    style: GoogleFonts.barlow(fontSize: 12.5, color: _kDim),
                  ),
                ],
              ),
              const SizedBox(height: 13),
              // Riga principale: mezzo | timer + costo.
              Row(
                children: [
                  // Tile-glifo del mezzo.
                  Container(
                    width: 48,
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _kSurface2,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: _kBorder, width: 0.5),
                    ),
                    child: vehicleGlyph(widget.vehicle.kind, size: 24),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.barlowCondensed(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                            height: 1.1,
                            color: _kText,
                          ),
                        ),
                        const SizedBox(height: 4),
                        BatteryBadge(pct: widget.vehicle.batteryLevel),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Timer + costo allineati a destra.
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _formatElapsed(_elapsedSeconds),
                        style: GoogleFonts.barlowCondensed(
                          fontSize: 30,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                          height: 1,
                          color: _kText,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _euro(_cost),
                        style: GoogleFonts.barlowCondensed(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                          color: _kAccent,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // Azione: termina noleggio (chiude la corsa e libera il mezzo).
              SizedBox(
                height: 52,
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _ending ? null : _onEndRide,
                  icon: _ending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: _kBg,
                          ),
                        )
                      : const Icon(Icons.stop_rounded, size: 20, color: _kBg),
                  label: Text(
                    _ending ? 'TERMINO…' : 'TERMINA NOLEGGIO',
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

// ── Pallino pulsante di stato ──────────────────────────────────────────────
class _PulseDot extends StatefulWidget {
  const _PulseDot();

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        final haloScale = 1.0 + 1.6 * t;
        final haloOpacity = (1 - t) * 0.55;
        return Stack(
          alignment: Alignment.center,
          children: [
            Transform.scale(
              scale: haloScale,
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _kAccent.withValues(alpha: haloOpacity),
                ),
              ),
            ),
            child!,
          ],
        );
      },
      child: Container(
        width: 9,
        height: 9,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: _kAccent,
        ),
      ),
    );
  }
}
