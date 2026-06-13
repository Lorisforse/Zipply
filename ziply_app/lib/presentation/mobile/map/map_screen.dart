import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:ziply_app/constants.dart';
import 'package:ziply_app/data/models/booking_model.dart';
import 'package:ziply_app/data/models/vehicle_model.dart';
import 'package:ziply_app/presentation/mobile/auth/login_screen.dart';
import 'package:ziply_app/presentation/mobile/map/widgets/vehicle_bottom_sheet.dart';
import 'package:ziply_app/presentation/mobile/map/widgets/vehicle_marker.dart';
import 'package:ziply_app/services/api_exceptions.dart';
import 'package:ziply_app/services/auth_service.dart';
import 'package:ziply_app/services/booking_service.dart';
import 'package:ziply_app/services/routing_service.dart';
import 'package:ziply_app/services/vehicle_service.dart';

// ── Palette (da Grafica/mappa-handoff) ─────────────────────────────────────
const Color _kBg      = Color(0xFF1A1A1A);
const Color _kSurface = Color(0xFF252525);
const Color _kBorder  = Color(0xFF333333);
const Color _kText    = Color(0xFFF5F5F5);
const Color _kDim     = Color(0xFF777777);
const Color _kAccent  = Color(0xFFF69659);

// Centro di Zootropolis: fallback quando la posizione non è disponibile.
const LatLng _kZootropolisCenter = LatLng(45.4654, 9.1859);
const double _kRadiusKm = 2.0;
const double _kZoom = 15;

// Clustering: mezzi entro questo raggio (px schermo, al livello di zoom
// corrente) vengono aggregati in un unico marker con il conteggio.
const double _kClusterRadiusPx = 70;

enum _ViewState { loading, error, success }

/// [MOBILE] UC-02 — Visualizza mappa con mezzi.
/// Schermata principale post-login: mappa OpenStreetMap con i mezzi disponibili.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final VehicleService _vehicleService = VehicleService();
  final AuthService _authService = AuthService();
  final RoutingService _routingService = RoutingService();
  final BookingService _bookingService = BookingService();
  final MapController _mapController = MapController();

  _ViewState _state = _ViewState.loading;
  String? _errorMessage;
  List<VehicleModel> _vehicles = const [];
  LatLng _center = _kZootropolisCenter;
  LatLng? _userPosition;

  // Prenotazione attiva (UT.02): il mezzo prenotato resta evidenziato sulla
  // mappa, gli altri "spenti", con il percorso a piedi e un pannello in basso.
  BookingModel? _activeBooking;
  VehicleModel? _bookedVehicle;
  List<LatLng> _walkingRoute = const [];
  bool _cancelling = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Risolve la posizione, recupera i mezzi e gestisce i tre stati UI.
  Future<void> _load() async {
    setState(() => _state = _ViewState.loading);
    try {
      final userPos = await _resolvePosition();
      final List<VehicleModel> vehicles;
      final LatLng center;
      if (userPos != null) {
        center = userPos;
        vehicles = await _vehicleService.getAvailableVehicles(
          lat: userPos.latitude,
          lng: userPos.longitude,
          radius: _kRadiusKm,
        );
      } else {
        center = _kZootropolisCenter;
        vehicles = await _vehicleService.getAvailableVehicles();
      }
      if (!mounted) return;
      setState(() {
        _userPosition = userPos;
        _center = center;
        _vehicles = vehicles;
        _state = _ViewState.success;
      });
    } on SessionExpiredException {
      await _handleSessionExpired();
    } on Exception catch (e) {
      debugPrint('map load failed: $e');
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
        _state = _ViewState.error;
      });
    }
  }

  /// Restituisce la posizione dell'utente, o null se il permesso è negato o
  /// la localizzazione non è disponibile (→ fallback sul centro di Zootropolis).
  Future<LatLng?> _resolvePosition() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
      final pos = await Geolocator.getCurrentPosition();
      return LatLng(pos.latitude, pos.longitude);
    } catch (_) {
      return null;
    }
  }

  void _recenter() {
    _mapController.move(_center, _kZoom);
  }

  /// UT.05 + UT.02 — Apre la scheda mezzo; al ritorno, se la prenotazione va a
  /// buon fine, resta sulla mappa in modalità "raggiungi il mezzo" (mezzo
  /// evidenziato, altri spenti, percorso a piedi, pannello in basso).
  Future<void> _onVehicleTap(VehicleModel vehicle) async {
    // Con una prenotazione attiva gli altri marker sono spenti e inerti.
    if (_activeBooking != null) return;

    final result = await VehicleBottomSheet.show(context, vehicle, _userPosition);
    if (result == null || !mounted) return;

    if (result.isSuccess) {
      setState(() {
        _activeBooking = result.booking;
        _bookedVehicle = vehicle;
        // Linea diretta come fallback immediato, poi sostituita dal percorso
        // pedonale reale appena disponibile.
        _walkingRoute = _userPosition != null
            ? [_userPosition!, LatLng(vehicle.latitude, vehicle.longitude)]
            : const [];
      });
      _loadWalkingRoute(vehicle);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: _kSurface,
          content: Text(
            result.error ?? 'Prenotazione non riuscita',
            style: GoogleFonts.barlow(fontSize: 14, color: _kText),
          ),
        ),
      );
    }
  }

  /// Recupera il percorso a piedi reale verso il mezzo prenotato; finché non
  /// arriva (o se il routing non risponde) resta la linea diretta.
  Future<void> _loadWalkingRoute(VehicleModel vehicle) async {
    final from = _userPosition;
    if (from == null) return;
    final route = await _routingService.walkingRoute(
      from,
      LatLng(vehicle.latitude, vehicle.longitude),
    );
    if (!mounted || route == null || route.isEmpty) return;
    setState(() => _walkingRoute = route);
  }

  /// Annulla la prenotazione attiva: chiama il backend, poi libera la mappa
  /// (il mezzo torna disponibile fra i marker normali) e avvisa l'utente.
  Future<void> _onCancelBooking() async {
    final booking = _activeBooking;
    if (booking == null || _cancelling) return;
    _cancelling = true;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await _bookingService.cancelBooking(booking.id);
      if (!mounted) return;
      setState(() {
        _activeBooking = null;
        _bookedVehicle = null;
        _walkingRoute = const [];
      });
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: _kSurface,
          content: Text(
            'Prenotazione annullata',
            style: GoogleFonts.barlow(fontSize: 14, color: _kText),
          ),
        ),
      );
    } on SessionExpiredException {
      await _handleSessionExpired();
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
      _cancelling = false;
    }
  }

  /// Token assente/scaduto (401): pulisce il token, avvisa e torna al login.
  Future<void> _handleSessionExpired() async {
    await _authService.logout();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: _kSurface,
        content: Text(
          'Sessione scaduta, effettua di nuovo l\'accesso',
          style: GoogleFonts.barlow(fontSize: 14, color: _kText),
        ),
      ),
    );
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: SafeArea(
        child: Column(
          children: [
            const _Header(),
            Expanded(child: _buildBody(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (_state) {
      case _ViewState.loading:
        return const Center(
          child: CircularProgressIndicator(color: _kAccent, strokeWidth: 2.5),
        );
      case _ViewState.error:
        return _ErrorView(message: _errorMessage, onRetry: _load);
      case _ViewState.success:
        return _buildMap(context);
    }
  }

  Widget _buildMap(BuildContext context) {
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _center,
            initialZoom: _kZoom,
            backgroundColor: _kBg,
          ),
          children: [
            TileLayer(
              urlTemplate:
                  'https://tiles.stadiamaps.com/tiles/alidade_smooth_dark/{z}/{x}/{y}{r}.png?api_key=$kStadiaApiKey',
              retinaMode: RetinaMode.isHighDensity(context),
              userAgentPackageName: 'it.lorisamato.ziply',
            ),
            // Percorso a piedi verso il mezzo prenotato (sotto i marker).
            if (_walkingRoute.length >= 2)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _walkingRoute,
                    strokeWidth: 4,
                    color: _kAccent,
                  ),
                ],
              ),
            // Marker con clustering dipendente dallo zoom: il Builder legge la
            // camera corrente e si ricostruisce a ogni pan/zoom (MapCamera.of).
            Builder(
              builder: (context) =>
                  MarkerLayer(markers: _buildMarkers(MapCamera.of(context))),
            ),
          ],
        ),
        Positioned(
          right: 16,
          top: 16,
          child: _RecenterButton(onTap: _recenter),
        ),
        // Pannello prenotazione attiva: non bloccante, la mappa resta visibile.
        if (_activeBooking != null && _bookedVehicle != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _BookingPanel(
              booking: _activeBooking!,
              vehicle: _bookedVehicle!,
              onCancel: _onCancelBooking,
            ),
          ),
      ],
    );
  }

  /// Costruisce i marker applicando il clustering per lo zoom corrente: i mezzi
  /// vicini (entro [_kClusterRadiusPx] sullo schermo) diventano un unico marker
  /// con il conteggio; quelli isolati restano marker individuali.
  List<Marker> _buildMarkers(MapCamera camera) {
    final markers = <Marker>[];
    if (_activeBooking != null) {
      markers.addAll(_buildBookingMarkers());
    } else {
      for (final cluster in _clusterize(camera)) {
        if (cluster.isSingle) {
          final v = cluster.members.first;
          markers.add(
            Marker(
              point: LatLng(v.latitude, v.longitude),
              width: VehicleMarker.diameter,
              height: VehicleMarker.diameter,
              rotate: true, // resta dritto quando la mappa viene ruotata
              child: GestureDetector(
                onTap: () => _onVehicleTap(v),
                child: VehicleMarker(kind: v.kind, batteryLevel: v.batteryLevel),
              ),
            ),
          );
        } else {
          markers.add(
            Marker(
              point: cluster.center,
              width: ClusterMarker.diameter,
              height: ClusterMarker.diameter,
              rotate: true,
              child: GestureDetector(
                onTap: () => _onClusterTap(cluster),
                child: ClusterMarker(count: cluster.members.length),
              ),
            ),
          );
        }
      }
    }
    if (_userPosition != null) {
      markers.add(
        Marker(
          point: _userPosition!,
          width: 20,
          height: 20,
          child: const _UserDot(),
        ),
      );
    }
    return markers;
  }

  /// Marker in modalità prenotazione attiva: tutti i mezzi "spenti" tranne
  /// quello prenotato, evidenziato e pulsante. Nessun clustering.
  List<Marker> _buildBookingMarkers() {
    final bookedId = _bookedVehicle?.id;
    final markers = <Marker>[];
    for (final v in _vehicles) {
      if (v.id == bookedId) continue;
      markers.add(
        Marker(
          point: LatLng(v.latitude, v.longitude),
          width: VehicleMarker.diameter,
          height: VehicleMarker.diameter,
          rotate: true,
          child: VehicleMarker(
            kind: v.kind,
            batteryLevel: v.batteryLevel,
            dimmed: true,
          ),
        ),
      );
    }
    final booked = _bookedVehicle;
    if (booked != null) {
      markers.add(
        Marker(
          point: LatLng(booked.latitude, booked.longitude),
          width: ActiveVehicleMarker.activeDiameter,
          height: ActiveVehicleMarker.activeDiameter,
          rotate: true,
          child: ActiveVehicleMarker(
            kind: booked.kind,
            batteryLevel: booked.batteryLevel,
          ),
        ),
      );
    }
    return markers;
  }

  /// Raggruppa i mezzi proiettati ai pixel del livello di zoom corrente con un
  /// clustering greedy a distanza: ad alto zoom le distanze in pixel crescono e
  /// i cluster si sciolgono in marker individuali.
  List<_Cluster> _clusterize(MapCamera camera) {
    final points = _vehicles
        .map((v) => camera.project(LatLng(v.latitude, v.longitude)))
        .toList(growable: false);
    final used = List<bool>.filled(_vehicles.length, false);
    final clusters = <_Cluster>[];
    for (var i = 0; i < _vehicles.length; i++) {
      if (used[i]) continue;
      used[i] = true;
      final members = <VehicleModel>[_vehicles[i]];
      for (var j = i + 1; j < _vehicles.length; j++) {
        if (used[j]) continue;
        if (points[i].distanceTo(points[j]) <= _kClusterRadiusPx) {
          used[j] = true;
          members.add(_vehicles[j]);
        }
      }
      clusters.add(_Cluster(members));
    }
    return clusters;
  }

  /// Tap su un cluster: zoom-in verso il suo centro per separare i mezzi.
  void _onClusterTap(_Cluster cluster) {
    final target = (_mapController.camera.zoom + 2).clamp(1.0, 18.0);
    _mapController.move(cluster.center, target);
  }
}

/// Gruppo di mezzi aggregati in un singolo marker; [center] è il centroide
/// delle coordinate dei membri.
class _Cluster {
  _Cluster(this.members) : center = _centroid(members);

  final List<VehicleModel> members;
  final LatLng center;

  bool get isSingle => members.length == 1;

  static LatLng _centroid(List<VehicleModel> members) {
    var lat = 0.0;
    var lng = 0.0;
    for (final m in members) {
      lat += m.latitude;
      lng += m.longitude;
    }
    return LatLng(lat / members.length, lng / members.length);
  }
}

// ── Header brand (ZIPLY · Zootropolis) ─────────────────────────────────────
class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: _kBg,
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            'ZIPLY',
            style: GoogleFonts.barlowCondensed(
              fontSize: 27,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: _kAccent,
            ),
          ),
          const SizedBox(width: 9),
          Text(
            'ZOOTROPOLIS',
            style: GoogleFonts.barlowCondensed(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.5,
              color: _kDim,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Recenter control (top-right) ───────────────────────────────────────────
class _RecenterButton extends StatelessWidget {
  const _RecenterButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: _kSurface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: _kBorder),
          boxShadow: const [
            BoxShadow(
              color: Color(0x73000000), // rgba(0,0,0,0.45)
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: const Icon(Icons.my_location, color: _kAccent, size: 20),
      ),
    );
  }
}

// ── User location dot ──────────────────────────────────────────────────────
class _UserDot extends StatelessWidget {
  const _UserDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: Colors.transparent,
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFD4580A), width: 2),
      ),
      child: Center(
        child: Container(
          width: 10,
          height: 10,
          decoration: const BoxDecoration(
            color: Color(0xFFD4580A),
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

// ── Pannello prenotazione attiva (in-mappa, non bloccante) ──────────────────
class _BookingPanel extends StatefulWidget {
  const _BookingPanel({
    required this.booking,
    required this.vehicle,
    required this.onCancel,
  });

  final BookingModel booking;
  final VehicleModel vehicle;
  final VoidCallback onCancel;

  @override
  State<_BookingPanel> createState() => _BookingPanelState();
}

class _BookingPanelState extends State<_BookingPanel> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Tick al secondo: il countdown è ricalcolato da expires_at del backend.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      if (_remaining() <= Duration.zero) _ticker?.cancel();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Duration _remaining() => widget.booking.expiresAt.difference(DateTime.now());

  String _format(Duration d) {
    final clamped = d.isNegative ? Duration.zero : d;
    final m = clamped.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = clamped.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final remaining = _remaining();
    final expired = remaining <= Duration.zero;
    final title = widget.vehicle.type.isEmpty ? 'Mezzo' : widget.vehicle.type;

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
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'PRENOTAZIONE ATTIVA',
                          style: GoogleFonts.barlowCondensed(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.2,
                            color: _kDim,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          title,
                          style: GoogleFonts.barlowCondensed(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                            color: _kText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        expired ? 'SCADUTA' : 'SCADE TRA',
                        style: GoogleFonts.barlowCondensed(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1,
                          color: _kDim,
                        ),
                      ),
                      Text(
                        _format(remaining),
                        style: GoogleFonts.barlowCondensed(
                          fontSize: 30,
                          fontWeight: FontWeight.w700,
                          height: 1,
                          color: expired ? _kDim : _kAccent,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // Sblocca mezzo: disabilitato per ora (logica → UT.13).
              Container(
                height: 50,
                width: double.infinity,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _kSurface,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: _kBorder),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.lock_outline, color: _kDim, size: 19),
                    const SizedBox(width: 9),
                    Text(
                      'SBLOCCA MEZZO',
                      style: GoogleFonts.barlowCondensed(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                        color: _kDim,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 44,
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: widget.onCancel,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _kDim,
                    side: const BorderSide(color: _kBorder),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  child: Text(
                    'ANNULLA PRENOTAZIONE',
                    style: GoogleFonts.barlowCondensed(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.6,
                      color: _kDim,
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

// ── Error state ────────────────────────────────────────────────────────────
class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String? message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.location_off_outlined, color: _kDim, size: 48),
            const SizedBox(height: 16),
            Text(
              message ?? 'Si è verificato un errore',
              textAlign: TextAlign.center,
              style: GoogleFonts.barlow(fontSize: 15, color: _kText),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: onRetry,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kAccent,
                  foregroundColor: _kBg,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                child: Text(
                  'RIPROVA',
                  style: GoogleFonts.barlowCondensed(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: _kBg,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
