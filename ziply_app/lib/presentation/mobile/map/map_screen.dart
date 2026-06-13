import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:ziply_app/constants.dart';
import 'package:ziply_app/data/models/booking_model.dart';
import 'package:ziply_app/data/models/forbidden_zone_model.dart';
import 'package:ziply_app/data/models/ride_model.dart';
import 'package:ziply_app/data/models/vehicle_model.dart';
import 'package:ziply_app/presentation/mobile/auth/login_screen.dart';
import 'package:ziply_app/presentation/mobile/booking/screens/booking_cancelled_screen.dart';
import 'package:ziply_app/presentation/mobile/map/widgets/nearby_vehicles_sheet.dart';
import 'package:ziply_app/presentation/mobile/map/widgets/vehicle_bottom_sheet.dart';
import 'package:ziply_app/presentation/mobile/map/widgets/vehicle_marker.dart';
import 'package:ziply_app/presentation/mobile/map/widgets/vehicle_widgets.dart';
import 'package:ziply_app/presentation/mobile/menu/menu_drawer.dart';
import 'package:ziply_app/presentation/mobile/ride/qr_scan_screen.dart';
import 'package:ziply_app/presentation/mobile/ride/ride_screen.dart';
import 'package:ziply_app/services/api_exceptions.dart';
import 'package:ziply_app/services/auth_service.dart';
import 'package:ziply_app/services/booking_service.dart';
import 'package:ziply_app/services/forbidden_zone_service.dart';
import 'package:ziply_app/services/ride_service.dart';
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

// UT.13 — Sblocco per prossimità: abilitato solo se l'utente è entro questa
// distanza (metri) dal mezzo prenotato.
const double _kUnlockRadiusMeters = 50;

enum _ViewState { loading, error, success }

/// Filtro per tipo di mezzo mostrato sulla mappa e nella lista vicini.
enum _VehicleFilter { all, bike, scooter, car }

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
  final RideService _rideService = RideService();
  final ForbiddenZoneService _forbiddenZoneService = ForbiddenZoneService();
  final MapController _mapController = MapController();
  // Chiave dello Scaffold per aprire il menu (endDrawer) dall'header.
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  _ViewState _state = _ViewState.loading;
  String? _errorMessage;
  List<VehicleModel> _vehicles = const [];
  // UT.18 — Zone vietate: overlay non critico. Un eventuale errore nel
  // recupero non blocca la mappa (resta semplicemente senza poligoni).
  List<ForbiddenZoneModel> _forbiddenZones = const [];
  LatLng _center = _kZootropolisCenter;
  LatLng? _userPosition;

  // Avviso "zona vietata": ascolto la posizione in tempo reale e, se l'utente
  // entra in una zona attiva, mostro un banner non bloccante con il suo nome.
  StreamSubscription<Position>? _positionSub;
  ForbiddenZoneModel? _currentForbiddenZone;

  // Prenotazione attiva (UT.02): il mezzo prenotato resta evidenziato sulla
  // mappa, gli altri "spenti", con il percorso a piedi e un pannello in basso.
  BookingModel? _activeBooking;
  VehicleModel? _bookedVehicle;
  List<LatLng> _walkingRoute = const [];
  bool _cancelling = false;
  // UT.13 — guardia anti doppio-sblocco mentre la chiamata è in corso.
  bool _unlocking = false;

  // Filtro mezzi attivo (browse mode).
  _VehicleFilter _filter = _VehicleFilter.all;

  /// Mezzi visibili in base al filtro corrente.
  List<VehicleModel> get _visibleVehicles {
    switch (_filter) {
      case _VehicleFilter.all:
        return _vehicles;
      case _VehicleFilter.bike:
        return _vehicles
            .where((v) => v.kind == VehicleType.bike)
            .toList(growable: false);
      case _VehicleFilter.scooter:
        return _vehicles
            .where((v) => v.kind == VehicleType.scooter)
            .toList(growable: false);
      case _VehicleFilter.car:
        return _vehicles
            .where((v) => v.kind == VehicleType.car)
            .toList(growable: false);
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    super.dispose();
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
      final forbiddenZones = await _loadForbiddenZones();
      if (!mounted) return;
      setState(() {
        _userPosition = userPos;
        _center = center;
        _vehicles = vehicles;
        _forbiddenZones = forbiddenZones;
        _currentForbiddenZone =
            userPos != null ? _zoneContaining(userPos, forbiddenZones) : null;
        _state = _ViewState.success;
      });
      _startPositionStream();
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

  /// UT.18 — Recupera le zone vietate da disegnare sulla mappa. È un overlay
  /// secondario: in caso di errore restituisce una lista vuota senza far
  /// fallire il caricamento della mappa (stesso spirito di [_loadWalkingRoute]).
  Future<List<ForbiddenZoneModel>> _loadForbiddenZones() async {
    try {
      return await _forbiddenZoneService.getForbiddenZones();
    } on Exception catch (e) {
      debugPrint('forbidden zones load failed: $e');
      return const [];
    }
  }

  /// Si aggancia allo stream GPS (se il permesso c'è) per aggiornare in tempo
  /// reale posizione e banner "zona vietata". Idempotente: annulla l'eventuale
  /// sottoscrizione precedente prima di ricrearla (es. dopo un retry).
  Future<void> _startPositionStream() async {
    await _positionSub?.cancel();
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }
    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // aggiorna ogni ~10 m percorsi
      ),
    ).listen(_onPositionUpdate);
  }

  /// Ogni aggiornamento GPS sposta il puntino utente e ricalcola se è dentro
  /// una zona vietata (per il banner).
  void _onPositionUpdate(Position pos) {
    if (!mounted) return;
    final latlng = LatLng(pos.latitude, pos.longitude);
    setState(() {
      _userPosition = latlng;
      _currentForbiddenZone = _zoneContaining(latlng, _forbiddenZones);
    });
  }

  /// Prima zona attiva che contiene [p], oppure null se [p] è fuori da tutte.
  ForbiddenZoneModel? _zoneContaining(LatLng p, List<ForbiddenZoneModel> zones) {
    for (final zone in zones) {
      if (zone.contains(p)) return zone;
    }
    return null;
  }

  void _recenter() {
    _mapController.move(_center, _kZoom);
  }

  /// Apre la lista "mezzi vicini" (solo via pulsante). Al tap su una riga apre
  /// la scheda del mezzo selezionato.
  Future<void> _showNearbyVehicles() async {
    final selected = await NearbyVehiclesSheet.show(
      context,
      vehicles: _sortedVisibleVehicles(),
      userPosition: _userPosition,
      radiusKm: _kRadiusKm,
    );
    if (selected == null || !mounted) return;
    _onVehicleTap(selected);
  }

  /// Mezzi visibili ordinati per distanza dall'utente (se nota).
  List<VehicleModel> _sortedVisibleVehicles() {
    final list = [..._visibleVehicles];
    final from = _userPosition;
    if (from != null) {
      list.sort((a, b) {
        final da = Geolocator.distanceBetween(
            from.latitude, from.longitude, a.latitude, a.longitude);
        final db = Geolocator.distanceBetween(
            from.latitude, from.longitude, b.latitude, b.longitude);
        return da.compareTo(db);
      });
    }
    return list;
  }

  /// UT.05 + UT.02 + UT.13 — Apre la scheda mezzo al tap sul marker; al ritorno
  /// gestisce l'esito.
  Future<void> _onVehicleTap(VehicleModel vehicle) async {
    // Con una prenotazione attiva gli altri marker sono spenti e inerti.
    if (_activeBooking != null) return;

    final result = await VehicleBottomSheet.show(context, vehicle, _userPosition);
    if (result == null || !mounted) return;
    await _handleSheetResult(result, vehicle);
  }

  /// Gestisce l'esito della scheda mezzo: sblocco → schermata noleggio;
  /// prenotazione → resta sulla mappa in modalità "raggiungi il mezzo";
  /// errore → snackbar.
  Future<void> _handleSheetResult(
    VehicleBookingResult result,
    VehicleModel vehicle,
  ) async {
    if (result.isUnlocked) {
      await _openRide(result.ride!, vehicle);
    } else if (result.isSuccess) {
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
            result.error ?? 'Operazione non riuscita',
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

  /// Annulla la prenotazione: prima chiede conferma, poi chiama il backend e,
  /// se va a buon fine, libera la mappa e mostra la schermata "annullata".
  Future<void> _onCancelBooking() async {
    final booking = _activeBooking;
    final vehicle = _bookedVehicle;
    if (booking == null || vehicle == null || _cancelling) return;

    final confirmed = await _confirmCancel();
    if (confirmed != true || !mounted) return;

    _cancelling = true;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final userPos = _userPosition;
    try {
      await _bookingService.cancelBooking(booking.id);
      if (!mounted) return;
      setState(() {
        _activeBooking = null;
        _bookedVehicle = null;
        _walkingRoute = const [];
      });
      await navigator.push(
        MaterialPageRoute(
          builder: (_) => BookingCancelledScreen(
            booking: booking,
            vehicle: vehicle,
            userPosition: userPos,
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

  /// Dialog di conferma prima di annullare la prenotazione.
  Future<bool?> _confirmCancel() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: Text(
          'Annullare la prenotazione?',
          style: GoogleFonts.barlowCondensed(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: _kText,
          ),
        ),
        content: Text(
          'Sei sicuro di voler annullare la prenotazione? Il mezzo tornerà disponibile a tutti.',
          style: GoogleFonts.barlow(fontSize: 14, height: 1.4, color: _kDim),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'NO',
              style: GoogleFonts.barlowCondensed(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: _kDim,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'SÌ, ANNULLA',
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

  /// UT.13 — Lo sblocco per prossimità è abilitato solo se conosciamo la
  /// posizione utente ed è entro [_kUnlockRadiusMeters] dal mezzo prenotato.
  bool _canUnlockByProximity() {
    final user = _userPosition;
    final vehicle = _bookedVehicle;
    if (user == null || vehicle == null) return false;
    final meters = Geolocator.distanceBetween(
      user.latitude,
      user.longitude,
      vehicle.latitude,
      vehicle.longitude,
    );
    return meters <= _kUnlockRadiusMeters;
  }

  /// UT.13 — Sblocco per prossimità del mezzo prenotato (dal pannello
  /// prenotazione): chiama POST /rides/unlock con il vehicle_id.
  Future<void> _onUnlockProximity() async {
    final vehicle = _bookedVehicle;
    if (vehicle == null || _unlocking) return;
    await _performUnlock(() => _rideService.unlockByProximity(vehicle.id), vehicle);
  }

  /// UT.13 — Scansione QR (globale): apre lo scanner, individua il mezzo dal
  /// codice tra quelli già caricati e ne apre la scheda (tendina con
  /// SBLOCCA/PRENOTA). Lo sblocco da quella scheda avviene via QR — la
  /// scansione prova che sei davanti al mezzo — quindi senza vincolo di distanza.
  Future<void> _onScanQr() async {
    final code = await QrScanScreen.show(context);
    if (code == null || !mounted) return;

    final vehicle = _vehicleForQr(code);
    if (vehicle == null) {
      // Codice non corrispondente a un mezzo disponibile nelle vicinanze.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: _kSurface,
          content: Text(
            'Mezzo non trovato tra quelli disponibili nelle vicinanze',
            style: GoogleFonts.barlow(fontSize: 14, color: _kText),
          ),
        ),
      );
      return;
    }

    final result = await VehicleBottomSheet.show(
      context,
      vehicle,
      _userPosition,
      unlockQrCode: code,
    );
    if (result == null || !mounted) return;
    await _handleSheetResult(result, vehicle);
  }

  /// Mezzo con il [qrCode] indicato tra quelli caricati sulla mappa.
  VehicleModel? _vehicleForQr(String qrCode) {
    for (final v in _vehicles) {
      if (v.qrCode == qrCode) return v;
    }
    return null;
  }

  /// Esegue lo sblocco per prossimità ([unlock]) mostrando il loading, poi apre
  /// la schermata di noleggio. Gestisce 401 e gli altri errori con messaggi.
  Future<void> _performUnlock(
    Future<RideModel> Function() unlock,
    VehicleModel vehicle,
  ) async {
    setState(() => _unlocking = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final ride = await unlock();
      if (!mounted) return;
      setState(() => _unlocking = false);
      await _openRide(ride, vehicle);
    } on SessionExpiredException {
      if (mounted) setState(() => _unlocking = false);
      await _handleSessionExpired();
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _unlocking = false);
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

  /// Libera lo stato di prenotazione (ormai consumata), apre la schermata di
  /// noleggio attivo e — al ritorno — ricarica i mezzi: quello in uso non è più
  /// disponibile finché la corsa non viene terminata (poi torna in lista).
  Future<void> _openRide(RideModel ride, VehicleModel vehicle) async {
    final navigator = Navigator.of(context);
    setState(() {
      _activeBooking = null;
      _bookedVehicle = null;
      _walkingRoute = const [];
    });
    await navigator.push(
      MaterialPageRoute(builder: (_) => RideScreen(ride: ride, vehicle: vehicle)),
    );
    if (!mounted) return;
    _load();
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
      key: _scaffoldKey,
      backgroundColor: _kBg,
      endDrawer: const MenuDrawer(),
      body: SafeArea(
        child: Column(
          children: [
            _Header(onMenu: () => _scaffoldKey.currentState?.openEndDrawer()),
            // Filtri tipo mezzo: solo in browse mode (no prenotazione attiva).
            if (_state == _ViewState.success && _activeBooking == null)
              _FilterBar(
                selected: _filter,
                onChanged: (f) => setState(() => _filter = f),
              ),
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
            // UT.18 — Zone vietate: poligoni rossi semi-trasparenti, sopra le
            // tile ma sotto percorso e marker.
            if (_forbiddenZones.isNotEmpty)
              PolygonLayer(
                polygons: [
                  // Un Polygon per anello: un MultiPolygon (es. quartiere con
                  // più parti staccate) produce così più poligoni distinti.
                  for (final zone in _forbiddenZones)
                    for (final ring in zone.rings)
                      Polygon(
                        points: ring,
                        color: const Color(0x33E53935), // rosso ~20% opacità
                        borderColor: const Color(0xFFE53935),
                        borderStrokeWidth: 2,
                      ),
                ],
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
        // Avviso "zona vietata": appare/sparisce mentre l'utente si muove.
        // Lascia spazio a destra (right: 70) per non finire sotto il recenter.
        if (_currentForbiddenZone != null)
          Positioned(
            left: 12,
            right: 70,
            top: 16,
            child: _ForbiddenZoneBanner(zone: _currentForbiddenZone!),
          ),
        // Pulsante per aprire la lista mezzi vicini (solo in browse mode).
        if (_activeBooking == null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 24,
            child: Center(
              child: _NearbyButton(
                count: _visibleVehicles.length,
                onTap: _showNearbyVehicles,
              ),
            ),
          ),
        // UT.13 — Sblocco via QR (globale): arriva davanti al mezzo, scansiona e
        // parte la corsa, senza bisogno di prenotare.
        if (_activeBooking == null)
          Positioned(
            right: 16,
            bottom: 24,
            child: _ScanQrButton(
              busy: _unlocking,
              onTap: _unlocking ? null : _onScanQr,
            ),
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
              canUnlockByProximity: _canUnlockByProximity(),
              unlocking: _unlocking,
              onUnlockProximity: _onUnlockProximity,
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
    final vehicles = _visibleVehicles;
    final points = vehicles
        .map((v) => camera.project(LatLng(v.latitude, v.longitude)))
        .toList(growable: false);
    final used = List<bool>.filled(vehicles.length, false);
    final clusters = <_Cluster>[];
    for (var i = 0; i < vehicles.length; i++) {
      if (used[i]) continue;
      used[i] = true;
      final members = <VehicleModel>[vehicles[i]];
      for (var j = i + 1; j < vehicles.length; j++) {
        if (used[j]) continue;
        if (points[i].distanceTo(points[j]) <= _kClusterRadiusPx) {
          used[j] = true;
          members.add(vehicles[j]);
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
  const _Header({required this.onMenu});

  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: _kBg,
      padding: const EdgeInsets.fromLTRB(18, 8, 8, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
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
          const Spacer(),
          // Apre il menu (endDrawer) con profilo, metodi di pagamento, ecc.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onMenu,
            child: const SizedBox(
              width: 40,
              height: 40,
              child: Icon(Icons.menu, color: _kText, size: 24),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Barra filtri tipo mezzo (da handoff) ───────────────────────────────────
class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.selected, required this.onChanged});

  final _VehicleFilter selected;
  final ValueChanged<_VehicleFilter> onChanged;

  // (filtro, etichetta, tipo per il glifo — null = "TUTTI").
  static const List<(_VehicleFilter, String, VehicleType?)> _items = [
    (_VehicleFilter.all, 'TUTTI', null),
    (_VehicleFilter.bike, 'BICI', VehicleType.bike),
    (_VehicleFilter.scooter, 'SCOOTER', VehicleType.scooter),
    (_VehicleFilter.car, 'AUTO', VehicleType.car),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _kBg,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          for (final (filter, label, kind) in _items)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(filter),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(2, 11, 2, 10),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: filter == selected ? _kAccent : _kBorder,
                        width: filter == selected ? 2 : 1,
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (kind != null) ...[
                        vehicleGlyph(
                          kind,
                          color: filter == selected ? _kAccent : _kDim,
                          size: 15,
                        ),
                        const SizedBox(width: 5),
                      ],
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.barlowCondensed(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.6,
                            color: filter == selected ? _kText : _kDim,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Pulsante "mezzi vicini" (apre la lista, bottom-center) ──────────────────
class _NearbyButton extends StatelessWidget {
  const _NearbyButton({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: _kSurface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _kBorder),
            boxShadow: const [
              BoxShadow(
                color: Color(0x73000000), // rgba(0,0,0,0.45)
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.format_list_bulleted, color: _kAccent, size: 18),
              const SizedBox(width: 9),
              Text(
                '$count ${count == 1 ? 'MEZZO VICINO' : 'MEZZI VICINI'}',
                style: GoogleFonts.barlowCondensed(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: _kText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Pulsante "scansiona QR" (sblocco diretto, bottom-right) ────────────────
class _ScanQrButton extends StatelessWidget {
  const _ScanQrButton({required this.onTap, required this.busy});

  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _kAccent,
            borderRadius: BorderRadius.circular(28),
            boxShadow: const [
              BoxShadow(
                color: Color(0x73000000), // rgba(0,0,0,0.45)
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: busy
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: _kBg),
                )
              : const Icon(Icons.qr_code_scanner, color: _kBg, size: 26),
        ),
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

// ── Banner "zona vietata" (in-mappa, non bloccante) ────────────────────────
class _ForbiddenZoneBanner extends StatelessWidget {
  const _ForbiddenZoneBanner({required this.zone});

  final ForbiddenZoneModel zone;

  static const Color _kRed = Color(0xFFE53935);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42, // stessa altezza del tasto di localizzazione
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _kRed),
        boxShadow: const [
          BoxShadow(
            color: Color(0x73000000), // rgba(0,0,0,0.45)
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: _kRed, size: 20),
          const SizedBox(width: 8),
          Text(
            'ZONA VIETATA',
            style: GoogleFonts.barlowCondensed(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: _kRed,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              zone.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.barlow(fontSize: 13, color: _kText),
            ),
          ),
        ],
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
    required this.canUnlockByProximity,
    required this.unlocking,
    required this.onUnlockProximity,
    required this.onCancel,
  });

  final BookingModel booking;
  final VehicleModel vehicle;

  /// True quando l'utente è abbastanza vicino al mezzo per sbloccarlo per
  /// prossimità (≤ 50 m); ricalcolato dal parent a ogni aggiornamento GPS.
  final bool canUnlockByProximity;

  /// True mentre una chiamata di sblocco è in corso (loading sui pulsanti).
  final bool unlocking;

  final VoidCallback onUnlockProximity;
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
              // UT.13 — Sblocco per prossimità: abilitato solo entro 50 m dal
              // mezzo e finché la prenotazione non è scaduta.
              _UnlockButton(
                enabled: widget.canUnlockByProximity && !expired,
                loading: widget.unlocking,
                onTap: widget.onUnlockProximity,
              ),
              // Suggerimento quando si è ancora troppo lontani.
              if (!expired && !widget.canUnlockByProximity) ...[
                const SizedBox(height: 6),
                Text(
                  'Avvicinati al mezzo (entro 50 m) per sbloccarlo.',
                  style: GoogleFonts.barlow(
                    fontSize: 12.5,
                    height: 1.3,
                    color: _kDim,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              SizedBox(
                height: 44,
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: widget.unlocking ? null : widget.onCancel,
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

// ── Pulsante "sblocca mezzo" (prossimità, UT.13) ───────────────────────────
class _UnlockButton extends StatelessWidget {
  const _UnlockButton({
    required this.enabled,
    required this.loading,
    required this.onTap,
  });

  /// Abilitato (accent) solo quando l'utente è abbastanza vicino; altrimenti
  /// resta "spento" (surface + testo dim) come invito ad avvicinarsi.
  final bool enabled;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      width: double.infinity,
      child: ElevatedButton(
        onPressed: (enabled && !loading) ? onTap : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: _kAccent,
          foregroundColor: _kBg,
          disabledBackgroundColor: _kSurface,
          disabledForegroundColor: _kDim,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
            side: enabled ? BorderSide.none : const BorderSide(color: _kBorder),
          ),
        ),
        child: loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: _kBg),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.lock_open_rounded,
                    color: enabled ? _kBg : _kDim,
                    size: 19,
                  ),
                  const SizedBox(width: 9),
                  Text(
                    'SBLOCCA MEZZO',
                    style: GoogleFonts.barlowCondensed(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: enabled ? _kBg : _kDim,
                    ),
                  ),
                ],
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
