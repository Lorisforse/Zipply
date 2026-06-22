// [MOBILE] UT.13 — Schermata corsa attiva (handoff noleggio-attivo).
// Mostrata dopo lo sblocco riuscito (prossimità o QR): mappa con il mezzo in
// uso e un banner "Noleggio in corso" con timer dal momento dell'avvio e costo
// aggiornato in tempo reale (minuti trascorsi × tariffa al minuto).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:ziply_app/core/theme/app_colors.dart';
import 'package:ziply_app/core/utils/app_logger.dart';
import 'package:ziply_app/data/models/ride_model.dart';
import 'package:ziply_app/data/models/vehicle_model.dart';
import 'package:ziply_app/presentation/mobile/map/widgets/vehicle_marker.dart';
import 'package:ziply_app/presentation/mobile/map/widgets/ziply_tile_layer.dart';
import 'package:ziply_app/presentation/mobile/map/widgets/vehicle_widgets.dart';
import 'package:ziply_app/presentation/mobile/ride/ride_summary_screen.dart';
import 'package:ziply_app/services/api_exceptions.dart';
import 'package:ziply_app/services/ride_service.dart';
import 'package:ziply_app/services/subscription_service.dart';

// ── Palette (da Grafica/noleggio-attivo-handoff) ───────────────────────────
const Color _kBg = AppColors.bg;
const Color _kSurface = AppColors.surface;
const Color _kSurface2 = AppColors.surface2;
const Color _kBorder = AppColors.border;
const Color _kText = AppColors.text;
const Color _kDim = AppColors.dim;
const Color _kAccent = AppColors.accent;

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
  bool _togglingPause = false;

  late String _currentStatus;
  late DateTime _stateEntryTime;
  int _accumulatedActiveSeconds = 0;
  int _accumulatedPauseSeconds = 0;

  // UT.22 — abbonamento attivo per questa tipologia di mezzo.
  bool _subscriptionActive = false;
  bool _loadingSub = true;

  @override
  void initState() {
    super.initState();
    _currentStatus = widget.ride.status;
    _stateEntryTime = widget.ride.startedAt;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _checkSubscription();
  }

  Future<void> _checkSubscription() async {
    try {
      final result = await SubscriptionService().fetchAll();
      if (!mounted) return;
      final vehicleTypeName = widget.vehicle.type;
      final hasActive = result.subscriptions.any(
        (s) => s.vehicleTypeName == vehicleTypeName && s.isActive,
      );
      setState(() {
        _subscriptionActive = hasActive;
        _loadingSub = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingSub = false);
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// Tariffa al minuto derivata dalla tariffa oraria del mezzo.
  double get _ratePerMinute => widget.vehicle.hourlyRate / 60;

  /// Secondi di corsa attiva.
  int get _activeSeconds {
    if (_currentStatus == 'attiva') {
      return _accumulatedActiveSeconds + DateTime.now().difference(_stateEntryTime).inSeconds;
    }
    return _accumulatedActiveSeconds;
  }

  /// Secondi di sosta.
  int get _pauseSeconds {
    if (_currentStatus == 'paused') {
      return _accumulatedPauseSeconds + DateTime.now().difference(_stateEntryTime).inSeconds;
    }
    return _accumulatedPauseSeconds;
  }

  /// Secondi trascorsi totali.
  int get _elapsedSeconds {
    return _activeSeconds + _pauseSeconds;
  }

  /// Minuti di corsa attiva addebitati.
  int get _chargedActiveMinutes {
    final sec = _activeSeconds;
    if (sec < 20) return 0;
    return (sec / 60).ceil();
  }

  /// Minuti di sosta addebitati.
  int get _chargedPauseMinutes {
    final sec = _pauseSeconds;
    if (sec < 20) return 0;
    return (sec / 60).ceil();
  }

  /// Minuti di pausa da pagare (dopo i primi 3 min gratuiti).
  int get _chargeablePauseMinutes {
    final pm = _chargedPauseMinutes;
    return pm > 3 ? pm - 3 : 0;
  }

  /// Costo corrente ricalcolato.
  double get _cost {
    final activeCost = _chargedActiveMinutes * _ratePerMinute;
    final pauseCost = _chargeablePauseMinutes * (_ratePerMinute * 0.50);
    return activeCost + pauseCost;
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

  /// Gestisce la sosta (pausa/ripresa).
  Future<void> _onTogglePause() async {
    if (_togglingPause || _ending) return;
    setState(() => _togglingPause = true);

    final messenger = ScaffoldMessenger.of(context);
    try {
      if (_currentStatus == 'attiva') {
        final newStatus = await _rideService.pauseRide(widget.ride.id);
        if (!mounted) return;
        setState(() {
          _accumulatedActiveSeconds += DateTime.now().difference(_stateEntryTime).inSeconds;
          _stateEntryTime = DateTime.now();
          _currentStatus = newStatus;
        });
      } else {
        final newStatus = await _rideService.resumeRide(widget.ride.id);
        if (!mounted) return;
        setState(() {
          _accumulatedPauseSeconds += DateTime.now().difference(_stateEntryTime).inSeconds;
          _stateEntryTime = DateTime.now();
          _currentStatus = newStatus;
        });
      }
    } on SessionExpiredException catch (e) {
      if (!mounted) return;
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
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: _kSurface,
          content: Text(
            e.toString().replaceFirst('Exception: ', ''),
            style: GoogleFonts.barlow(fontSize: 14, color: _kText),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _togglingPause = false);
      }
    }
  }

  /// Termina il noleggio: chiude la corsa lato backend (così il mezzo torna
  /// disponibile) e mostra il riepilogo di fine corsa.
  Future<void> _onEndRide() async {
    if (_ending || _togglingPause) return;
    // Calcoliamo la CO2 e mostriamo il riepilogo basato sul tempo attivo
    final frozenDuration = Duration(seconds: _activeSeconds);
    zlog('Termino il noleggio ${widget.ride.id}', tag: 'Noleggio');
    setState(() => _ending = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final summary = await _rideService.endRide(widget.ride.id);
      if (!mounted) return;
      zlog('Noleggio terminato: mostro il riepilogo', tag: 'Noleggio');
      await RideSummaryScreen.show(
        navigator.context,
        ride: widget.ride.copyWith(status: _currentStatus),
        vehicle: widget.vehicle,
        duration: frozenDuration,
        cost: summary.totalCost,
        appliedDiscount: summary.appliedDiscount,
        subscriptionApplied: summary.subscriptionApplied,
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
              // Riga stato: pallino + label + tariffa (o badge abbonamento).
              Row(
                children: [
                  const _PulseDot(),
                  const SizedBox(width: 8),
                  Text(
                    _currentStatus == 'paused' ? 'NOLEGGIO IN PAUSA' : 'NOLEGGIO IN CORSO',
                    style: GoogleFonts.barlowCondensed(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                      color: _kAccent,
                    ),
                  ),
                  const Spacer(),
                  if (_subscriptionActive)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.green.withValues(alpha: 0.12),
                        border: Border.all(color: AppColors.green),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        'ABBONAMENTO',
                        style: GoogleFonts.barlowCondensed(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                          color: AppColors.green,
                        ),
                      ),
                    )
                  else
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
                        _loadingSub ? '…' : (_subscriptionActive ? '€ 0,00' : _euro(_cost)),
                        style: GoogleFonts.barlowCondensed(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                          color: _subscriptionActive
                              ? AppColors.green
                              : _kAccent,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (_currentStatus == 'paused') ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: _kSurface2,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: _kBorder, width: 0.5),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded, size: 16, color: _kAccent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'In sosta da ${_formatElapsed(_pauseSeconds)}. I primi 3 min di sosta sono gratuiti, poi al 50% della tariffa standard.',
                          style: GoogleFonts.barlow(fontSize: 12, color: _kText),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              // Azione: termina noleggio (chiude la corsa e libera il mezzo).
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: SizedBox(
                      height: 52,
                      child: OutlinedButton.icon(
                        onPressed: _ending || _togglingPause ? null : _onTogglePause,
                        icon: _togglingPause
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: _kAccent,
                                ),
                              )
                            : Icon(
                                _currentStatus == 'paused'
                                    ? Icons.play_arrow_rounded
                                    : Icons.pause_rounded,
                                size: 20,
                                color: _kAccent,
                              ),
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            _currentStatus == 'paused' ? 'RIPRENDI' : 'PAUSA',
                            style: GoogleFonts.barlowCondensed(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1,
                              color: _kAccent,
                            ),
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: _kAccent, width: 1.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 3,
                    child: SizedBox(
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: _ending || _togglingPause ? null : _onEndRide,
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
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            _ending ? 'TERMINO…' : 'TERMINA NOLEGGIO',
                            style: GoogleFonts.barlowCondensed(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1,
                              color: _kBg,
                            ),
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
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                      ),
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
