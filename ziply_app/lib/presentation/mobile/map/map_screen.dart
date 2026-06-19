import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:ziply_app/core/utils/app_logger.dart';
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
import 'package:ziply_app/presentation/mobile/map/widgets/ziply_tile_layer.dart';
import 'package:ziply_app/presentation/mobile/menu/menu_drawer.dart';
import 'package:ziply_app/presentation/mobile/ride/qr_scan_screen.dart';
import 'package:ziply_app/presentation/mobile/ride/ride_screen.dart';
import 'package:ziply_app/services/api_exceptions.dart';
import 'package:ziply_app/services/auth_service.dart';
import 'package:ziply_app/services/booking_service.dart';
import 'package:ziply_app/services/forbidden_zone_service.dart';
import 'package:ziply_app/services/geocoding_service.dart';
import 'package:ziply_app/services/ride_service.dart';
import 'package:ziply_app/services/route_service.dart';
import 'package:ziply_app/services/routing_service.dart';
import 'package:ziply_app/services/vehicle_service.dart';

// ── Palette (da Grafica/mappa-handoff) ─────────────────────────────────────
const Color _kBg = Color(0xFF1A1A1A);
const Color _kSurface = Color(0xFF252525);
const Color _kBorder = Color(0xFF333333);
const Color _kText = Color(0xFFF5F5F5);
const Color _kDim = Color(0xFF777777);
const Color _kAccent = Color(0xFFF69659);
const Color _kGreen = Color(0xFF5DCAA5);

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

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  final VehicleService _vehicleService = VehicleService();
  final AuthService _authService = AuthService();
  final RoutingService _routingService = RoutingService();
  final BookingService _bookingService = BookingService();
  final RideService _rideService = RideService();
  final ForbiddenZoneService _forbiddenZoneService = ForbiddenZoneService();
  final RouteService _routeService = RouteService();
  final GeocodingService _geocodingService = GeocodingService();
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

  // UT.07 — Destinazione e percorso (mezzo→destinazione). La destinazione si
  // imposta da una ricerca testuale; toccando un mezzo si vede il percorso per
  // tipologia, calcolato dal backend (ORS) ed evitando le zone vietate.
  LatLng? _destination;
  String? _destinationLabel;
  List<LatLng> _routePoints = const [];
  VehicleModel? _routeVehicle;
  double? _routeDistanceKm;
  double? _routeDurationMin;
  double? _routeCost;
  bool _routeFallback = false;
  bool _routing = false;
  // UT.08 — tipologia consigliata per il tragitto corrente (null = nessun
  // consiglio disponibile). Best-effort: un errore non blocca il percorso.
  SuggestedCategory? _suggestion;

  // Auto-refresh mezzi: la lista è una "fotografia" all'apertura, qui la
  // riallineiamo silenziosamente ogni 10 s (solo in browse mode).
  Timer? _refreshTimer;
  static const Duration _kRefreshInterval = Duration(seconds: 10);

  // Contatore che innesca il "ping" sul puntino utente al recenter: ogni
  // incremento fa partire un'onda one-shot in [_UserDot].
  int _recenterPing = 0;

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
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }

  /// Avvia il refresh periodico dei mezzi (idempotente).
  void _startAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer =
        Timer.periodic(_kRefreshInterval, (_) => _refreshVehicles());
  }

  /// Riallinea silenziosamente la lista mezzi, senza toccare camera né stato di
  /// caricamento. Salta il giro se la mappa non è pronta o se c'è una
  /// prenotazione attiva (lì i marker seguono la prenotazione, non la lista).
  /// In caso di errore mantiene la lista corrente.
  Future<void> _refreshVehicles() async {
    if (_state != _ViewState.success || _activeBooking != null) return;
    try {
      final pos = _userPosition;
      final vehicles = pos != null
          ? await _vehicleService.getAvailableVehicles(
              lat: pos.latitude,
              lng: pos.longitude,
              radius: _kRadiusKm,
            )
          : await _vehicleService.getAvailableVehicles();
      // Tra l'await e qui lo stato può essere cambiato (prenotazione avviata,
      // schermata chiusa): riverifica prima di applicare.
      if (!mounted || _state != _ViewState.success || _activeBooking != null) {
        return;
      }
      setState(() => _vehicles = vehicles);
      zlog('Auto-refresh: ${vehicles.length} mezzi', tag: 'Mappa');
    } on Exception {
      // Refresh silenzioso: ignora l'errore e riprova al prossimo giro.
    }
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
      zlog(
        'Mappa pronta: ${vehicles.length} mezzi, GPS '
        '${userPos != null ? 'attivo' : 'non disponibile'}',
        tag: 'Mappa',
      );
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
  ForbiddenZoneModel? _zoneContaining(
      LatLng p, List<ForbiddenZoneModel> zones) {
    for (final zone in zones) {
      if (zone.contains(p)) return zone;
    }
    return null;
  }

  /// Centra (animato) sulla posizione utente. Se il GPS non è disponibile
  /// avvisa invece di saltare sul centro di fallback, e innesca il "ping" sul
  /// puntino per dare conferma anche quando sei già al centro.
  void _recenter() {
    final pos = _userPosition;
    if (pos == null) {
      zlog('Recenter richiesto ma GPS non disponibile', tag: 'Mappa');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: _kSurface,
          content: Text(
            'Attiva la localizzazione per trovarti sulla mappa',
            style: GoogleFonts.barlow(fontSize: 14, color: _kText),
          ),
        ),
      );
      return;
    }
    zlog('Ricentro sulla posizione utente', tag: 'Mappa');
    _animatedMapMove(pos, _kZoom);
    setState(() => _recenterPing++);
  }

  /// Sposta la camera verso [dest]/[destZoom] interpolando centro e zoom, invece
  /// dello scatto secco di [MapController.move]. Usato sia dal recenter sia dal
  /// tap sul cluster (lo zoom graduale scioglie naturalmente l'aggregato).
  void _animatedMapMove(LatLng dest, double destZoom) {
    final camera = _mapController.camera;
    final latTween =
        Tween<double>(begin: camera.center.latitude, end: dest.latitude);
    final lngTween =
        Tween<double>(begin: camera.center.longitude, end: dest.longitude);
    final zoomTween = Tween<double>(begin: camera.zoom, end: destZoom);

    final controller = AnimationController(
      duration: const Duration(milliseconds: 650),
      vsync: this,
    );
    final animation =
        CurvedAnimation(parent: controller, curve: Curves.easeInOutCubic);

    controller.addListener(() {
      _mapController.move(
        LatLng(latTween.evaluate(animation), lngTween.evaluate(animation)),
        zoomTween.evaluate(animation),
      );
    });
    controller.addStatusListener((status) {
      if (status == AnimationStatus.completed ||
          status == AnimationStatus.dismissed) {
        controller.dispose();
      }
    });
    controller.forward();
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

    // UT.07 — Con una destinazione impostata il tap mostra SOLO il percorso
    // mezzo→destinazione (niente scheda): si prosegue dal pannello anteprima.
    if (_destination != null) {
      await _computeRouteFor(vehicle);
      return;
    }

    final result =
        await VehicleBottomSheet.show(context, vehicle, _userPosition);
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
      zlog('Mezzo prenotato: ${vehicle.type}', tag: 'Prenotazione');
      setState(() {
        _activeBooking = result.booking;
        _bookedVehicle = vehicle;
        // Linea diretta come fallback immediato, poi sostituita dal percorso
        // pedonale reale appena disponibile.
        _walkingRoute = _userPosition != null
            ? [_userPosition!, LatLng(vehicle.latitude, vehicle.longitude)]
            : const [];
        // La destinazione/percorso si azzerano: la mappa passa in modalità
        // "raggiungi il mezzo prenotato".
        _destination = null;
        _destinationLabel = null;
        _routePoints = const [];
        _routeVehicle = null;
        _routeDistanceKm = null;
        _routeDurationMin = null;
        _routeCost = null;
        _routeFallback = false;
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

  /// UT.07 — Apre la ricerca testuale della destinazione; al risultato la imposta
  /// e azzera l'eventuale percorso precedente, inquadrandola sulla mappa.
  Future<void> _openDestinationSearch() async {
    final result = await _DestinationSearchScreen.show(
      context,
      _geocodingService,
      _userPosition ?? _center,
    );
    if (result == null || !mounted) return;
    setState(() {
      _destination = result.point;
      _destinationLabel = result.label;
      _routePoints = const [];
      _routeVehicle = null;
      _routeDistanceKm = null;
      _routeDurationMin = null;
      _routeCost = null;
      _routeFallback = false;
    });
    _animatedMapMove(result.point, _kZoom);
  }

  /// UT.07 — Pulisce destinazione e percorso, tornando alla mappa "libera".
  void _clearDestination() {
    setState(() {
      _destination = null;
      _destinationLabel = null;
      _routePoints = const [];
      _routeVehicle = null;
      _routeDistanceKm = null;
      _routeDurationMin = null;
      _routeCost = null;
      _routeFallback = false;
      _suggestion = null;
    });
  }

  /// UT.07 — Calcola e disegna il percorso dal [vehicle] alla destinazione
  /// impostata, mostrando distanza e durata. Errore → snackbar non bloccante.
  Future<void> _computeRouteFor(VehicleModel vehicle) async {
    final dest = _destination;
    if (dest == null) return;
    setState(() {
      _routing = true;
      _suggestion = null;
    });
    try {
      final route = await _routeService.computeRoute(
        vehicleId: vehicle.id,
        destination: dest,
      );
      if (!mounted) return;
      setState(() {
        _routePoints = route.points;
        _routeVehicle = vehicle;
        _routeDistanceKm = route.distanceKm;
        _routeDurationMin = route.durationMinutes;
        _routeCost = route.estimatedCost;
        _routeFallback = route.fallback;
        _suggestion = route.suggestion;
        _routing = false;
      });
    } on SessionExpiredException {
      if (mounted) setState(() => _routing = false);
      await _handleSessionExpired();
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _routing = false);
      ScaffoldMessenger.of(context).showSnackBar(
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

  /// UT.07 — Dal pannello anteprima percorso: apre la scheda del mezzo scelto
  /// per prenotare o sbloccare.
  Future<void> _openSheetForRouteVehicle() async {
    final vehicle = _routeVehicle;
    if (vehicle == null) return;
    final result =
        await VehicleBottomSheet.show(context, vehicle, _userPosition);
    if (result == null || !mounted) return;
    await _handleSheetResult(result, vehicle);
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
      zlog('Prenotazione annullata', tag: 'Prenotazione');
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
    await _performUnlock(
        () => _rideService.unlockByProximity(vehicle.id), vehicle);
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
    zlog('Mezzo sbloccato (${vehicle.type}): apro la corsa', tag: 'Noleggio');
    final navigator = Navigator.of(context);
    setState(() {
      _activeBooking = null;
      _bookedVehicle = null;
      _walkingRoute = const [];
      _destination = null;
      _destinationLabel = null;
      _routePoints = const [];
      _routeVehicle = null;
    });
    await navigator.push(
      MaterialPageRoute(
          builder: (_) => RideScreen(ride: ride, vehicle: vehicle)),
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
      resizeToAvoidBottomInset: false,
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
            // UT.07 — Barra destinazione: ricerca testuale del punto di arrivo.
            if (_state == _ViewState.success && _activeBooking == null)
              _DestinationBar(
                label: _destinationLabel,
                onTap: _openDestinationSearch,
                onClear: _clearDestination,
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
        return const _BrandLoader();
      case _ViewState.error:
        return _ErrorView(message: _errorMessage, onRetry: _load);
      case _ViewState.success:
        // La mappa entra in dissolvenza (+ micro scale) quando i dati sono
        // pronti, raccordandosi al wordmark pulsante del loader.
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOut,
          builder: (context, t, child) => Opacity(
            opacity: t,
            child: Transform.scale(scale: 1.02 - 0.02 * t, child: child),
          ),
          child: _buildMap(context),
        );
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
            ziplyTileLayer(context),
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
            // UT.07 — Percorso mezzo→destinazione (verde), sopra il pedonale.
            if (_routePoints.length >= 2)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _routePoints,
                    strokeWidth: 5,
                    color: _kGreen,
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
        // UT.07 — Banner "scegli un mezzo": destinazione impostata ma mezzo
        // ancora non scelto. Scende sotto il banner "zona vietata" se presente.
        if (_destination != null &&
            _routeVehicle == null &&
            _activeBooking == null)
          Positioned(
            left: 12,
            right: 70,
            top: _currentForbiddenZone != null ? 66 : 16,
            child: const _SelectVehicleBanner(),
          ),
        if (_routing)
          const Positioned(
            left: 0,
            right: 0,
            top: 70,
            child: Center(child: _RoutingChip()),
          ),
        // Pulsante mezzi vicini + scan QR: solo in browse mode e quando non è
        // mostrato il pannello anteprima percorso (che occupa il fondo).
        if (_activeBooking == null && _routeVehicle == null)
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
        if (_activeBooking == null && _routeVehicle == null)
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
        // UT.07 — Anteprima percorso: mezzo scelto + distanza/durata, con CTA
        // per procedere a prenota/sblocco. La scheda NON si apre da sola.
        if (_activeBooking == null &&
            _destination != null &&
            _routeVehicle != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _RoutePreviewPanel(
              vehicle: _routeVehicle!,
              distanceKm: _routeDistanceKm ?? 0,
              durationMin: _routeDurationMin ?? 0,
              estimatedCost: _routeCost ?? 0,
              fallback: _routeFallback,
              suggestion: _suggestion,
              onContinue: _openSheetForRouteVehicle,
              onClear: _clearDestination,
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
                // Scatto-in quando il mezzo emerge da un cluster (key per id:
                // finché resta singolo non si ripete).
                child: _PopIn(
                  key: ValueKey('veh-${v.id}'),
                  child:
                      VehicleMarker(kind: v.kind, batteryLevel: v.batteryLevel),
                ),
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
          // Box più ampio del puntino per contenere l'alone pulsante.
          width: 56,
          height: 56,
          child: _UserDot(key: const ValueKey('user-dot'), ping: _recenterPing),
        ),
      );
    }
    // UT.07 — Pin della destinazione impostata.
    if (_destination != null) {
      markers.add(
        Marker(
          point: _destination!,
          width: 40,
          height: 40,
          rotate: true,
          child: const _DestinationMarker(),
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

  /// Tap su un cluster: zoom-in animato verso il suo centro. Lo zoom graduale
  /// fa "scomporre" l'aggregato nei singoli mezzi durante l'animazione (il
  /// clustering è ricalcolato a ogni frame in base alla camera).
  void _onClusterTap(_Cluster cluster) {
    zlog('Espando cluster di ${cluster.members.length} mezzi', tag: 'Mappa');
    final target = (_mapController.camera.zoom + 2).clamp(1.0, 18.0);
    _animatedMapMove(cluster.center, target);
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
                  child:
                      CircularProgressIndicator(strokeWidth: 2.5, color: _kBg),
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
/// Puntino utente "vivo": un alone tenue che respira di continuo (così la
/// posizione sembra in tempo reale) e un'onda one-shot più ampia che parte a
/// ogni recenter, innescata dall'incremento di [ping].
class _UserDot extends StatefulWidget {
  const _UserDot({super.key, required this.ping});

  /// Contatore di "ping": quando cambia, parte l'onda one-shot di conferma.
  final int ping;

  @override
  State<_UserDot> createState() => _UserDotState();
}

class _UserDotState extends State<_UserDot> with TickerProviderStateMixin {
  static const Color _kDotColor = Color(0xFFD4580A);

  // Respiro lento e continuo dell'alone di accuratezza.
  late final AnimationController _idle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat();

  // Onda one-shot di conferma al recenter.
  late final AnimationController _pingCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  @override
  void didUpdateWidget(covariant _UserDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.ping != oldWidget.ping) {
      _pingCtrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _idle.dispose();
    _pingCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_idle, _pingCtrl]),
      builder: (context, _) {
        final idleT = _idle.value;
        final idleScale = 1.0 + 0.9 * idleT;
        final idleOpacity = (1 - idleT) * 0.16;

        final pingT = _pingCtrl.value;
        final showPing = _pingCtrl.isAnimating;
        final pingScale = 1.0 + 2.6 * pingT;
        final pingOpacity = (1 - pingT) * 0.5;

        return SizedBox(
          width: 56,
          height: 56,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Alone idle (respiro continuo).
              Transform.scale(
                scale: idleScale,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _kDotColor.withValues(alpha: idleOpacity),
                  ),
                ),
              ),
              // Onda di conferma (solo durante il ping).
              if (showPing)
                Transform.scale(
                  scale: pingScale,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _kDotColor.withValues(alpha: pingOpacity),
                        width: 2,
                      ),
                    ),
                  ),
                ),
              // Puntino centrale.
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: _kDotColor, width: 2),
                ),
                child: Center(
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: _kDotColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Loader brandizzato (wordmark ZIPLY pulsante) ───────────────────────────
/// Schermata di attesa mentre la mappa carica: il wordmark "ZIPLY" respira
/// (opacità + scala) finché i dati non sono pronti, poi la mappa entra in
/// dissolvenza (vedi [_buildBody]).
class _BrandLoader extends StatefulWidget {
  const _BrandLoader();

  @override
  State<_BrandLoader> createState() => _BrandLoaderState();
}

class _BrandLoaderState extends State<_BrandLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = Curves.easeInOut.transform(_controller.value);
          return Opacity(
            opacity: 0.55 + 0.45 * t,
            child: Transform.scale(
              scale: 0.96 + 0.06 * t,
              child: Text(
                'ZIPLY',
                style: GoogleFonts.barlowCondensed(
                  fontSize: 44,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 3,
                  color: _kAccent,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Scatto-in marker (emersione da cluster) ────────────────────────────────
/// Fa comparire il [child] con un breve scale-in. Con una [key] stabile per
/// mezzo l'animazione parte una sola volta, quando il marker passa da cluster a
/// singolo, e non si ripete a ogni rebuild della mappa.
class _PopIn extends StatefulWidget {
  const _PopIn({super.key, required this.child});

  final Widget child;

  @override
  State<_PopIn> createState() => _PopInState();
}

class _PopInState extends State<_PopIn> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  )..forward();

  late final Animation<double> _scale =
      Tween<double>(begin: 0.6, end: 1).animate(
    CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(scale: _scale, child: widget.child);
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
              if (widget.booking.appliedPromotion != null) ...[
                const SizedBox(height: 12),
                _buildPromoBanner(
                  widget.booking.appliedPromotion!,
                  widget.booking.promotionPercentage ?? 0,
                ),
              ],
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

  Widget _buildPromoBanner(String description, double percentage) {
    final s = percentage
        .toStringAsFixed(percentage.truncateToDouble() == percentage ? 0 : 1)
        .replaceAll('.', ',');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _kGreen.withOpacity(0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: _kGreen.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.local_offer, size: 16, color: _kGreen),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Sconto automatico del $s% applicato: $description',
              style: GoogleFonts.barlow(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _kGreen,
              ),
            ),
          ),
        ],
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

// ── UT.07 · Barra destinazione (ricerca testuale) ──────────────────────────
class _DestinationBar extends StatelessWidget {
  const _DestinationBar({
    required this.label,
    required this.onTap,
    required this.onClear,
  });

  final String? label;
  final VoidCallback onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final has = label != null;
    return Container(
      color: _kBg,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Container(
        height: 42,
        padding: const EdgeInsets.only(left: 12, right: 4),
        decoration: BoxDecoration(
          color: _kSurface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: has ? _kGreen : _kBorder),
        ),
        child: Row(
          children: [
            Icon(Icons.place_outlined, color: has ? _kGreen : _kDim, size: 19),
            const SizedBox(width: 9),
            // Area tappabile (riempie lo spazio) per aprire la ricerca.
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onTap,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    has ? label! : 'Imposta una destinazione',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.barlow(
                      fontSize: 14,
                      color: has ? _kText : _kDim,
                    ),
                  ),
                ),
              ),
            ),
            // X indipendente (IconButton con il proprio tap: niente annidamento
            // di GestureDetector, che prima "mangiava" il tocco sulla X).
            if (has)
              IconButton(
                onPressed: onClear,
                icon: const Icon(Icons.close, color: _kDim, size: 18),
                splashRadius: 18,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                tooltip: 'Rimuovi destinazione',
              ),
          ],
        ),
      ),
    );
  }
}

// ── UT.07 · Pin destinazione ───────────────────────────────────────────────
class _DestinationMarker extends StatelessWidget {
  const _DestinationMarker();

  @override
  Widget build(BuildContext context) {
    return const Icon(Icons.place, color: _kGreen, size: 38);
  }
}

// ── UT.07 · Banner "tocca un mezzo" (stile banner zona vietata, in verde) ──
class _SelectVehicleBanner extends StatelessWidget {
  const _SelectVehicleBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _kGreen),
        boxShadow: const [
          BoxShadow(
            color: Color(0x73000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.touch_app_outlined, color: _kGreen, size: 20),
          const SizedBox(width: 8),
          Text(
            'TOCCA UN MEZZO',
            style: GoogleFonts.barlowCondensed(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: _kGreen,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'per vedere il percorso',
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

// ── UT.07 · Pannello anteprima percorso (mezzo scelto + km/min + CTA) ──────
class _RoutePreviewPanel extends StatelessWidget {
  const _RoutePreviewPanel({
    required this.vehicle,
    required this.distanceKm,
    required this.durationMin,
    required this.estimatedCost,
    required this.fallback,
    required this.suggestion,
    required this.onContinue,
    required this.onClear,
  });

  final VehicleModel vehicle;
  final double distanceKm;
  final double durationMin;
  final double estimatedCost;
  final bool fallback;

  /// UT.08 — tipologia consigliata per il tragitto (null = nessun consiglio).
  final SuggestedCategory? suggestion;

  final VoidCallback onContinue;
  final VoidCallback onClear;

  /// UT.08 — Riga di consiglio: conferma se il mezzo scelto è la tipologia
  /// consigliata, altrimenti suggerisce l'alternativa. null = niente consiglio.
  Widget? _consiglio() {
    final s = suggestion;
    if (s == null || s == SuggestedCategory.unknown) return null;
    final selected = vehicle.kind == VehicleType.car
        ? SuggestedCategory.auto
        : SuggestedCategory.biciScooter;
    final match = selected == s;
    final label = s == SuggestedCategory.auto ? "l'auto" : 'bici o monopattino';
    final text = match
        ? 'Ottima scelta: è il mezzo consigliato per questo tragitto.'
        : 'Per questo tragitto consigliamo $label.';
    final color = match ? _kGreen : _kAccent;
    final icon = match ? Icons.check_circle_outline : Icons.lightbulb_outline;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.barlow(fontSize: 13, color: _kText),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mins = durationMin <= 0 ? 1 : durationMin.ceil();
    final title = vehicle.type.isEmpty ? 'Mezzo' : vehicle.type;
    final consiglio = _consiglio();
    return Container(
      decoration: const BoxDecoration(
        color: _kBg,
        border: Border(top: BorderSide(color: _kBorder)),
        boxShadow: [
          BoxShadow(
            color: Color(0x73000000),
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
                          'PERCORSO VERSO LA DESTINAZIONE',
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
                        'COSTO STIMATO',
                        style: GoogleFonts.barlowCondensed(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.8,
                          color: _kDim,
                        ),
                      ),
                      Text(
                        '€${estimatedCost.toStringAsFixed(2)}',
                        style: GoogleFonts.barlowCondensed(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          height: 1,
                          color: _kGreen,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${distanceKm.toStringAsFixed(1)} km · ~$mins min'
                        '${fallback ? ' ca.' : ''}',
                        style: GoogleFonts.barlow(fontSize: 12, color: _kDim),
                      ),
                    ],
                  ),
                ],
              ),
              if (consiglio != null) ...[
                const SizedBox(height: 12),
                consiglio,
              ],
              const SizedBox(height: 14),
              SizedBox(
                height: 50,
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onContinue,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kAccent,
                    foregroundColor: _kBg,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  child: Text(
                    'PRENOTA O SBLOCCA',
                    style: GoogleFonts.barlowCondensed(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: _kBg,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Tocca un altro mezzo per confrontare il percorso.',
                style: GoogleFonts.barlow(
                  fontSize: 12.5,
                  height: 1.3,
                  color: _kDim,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 44,
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: onClear,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _kDim,
                    side: const BorderSide(color: _kBorder),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  child: Text(
                    'ANNULLA DESTINAZIONE',
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

// ── UT.07 · Indicatore "calcolo percorso" ──────────────────────────────────
class _RoutingChip extends StatelessWidget {
  const _RoutingChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: _kGreen),
          ),
          const SizedBox(width: 10),
          Text(
            'Calcolo percorso…',
            style: GoogleFonts.barlow(fontSize: 13, color: _kText),
          ),
        ],
      ),
    );
  }
}

// ── UT.07 · Pagina ricerca destinazione (full-screen, niente jank da sheet) ──
class _DestinationSearchScreen extends StatefulWidget {
  const _DestinationSearchScreen(this.geocoding, this.near);

  final GeocodingService geocoding;

  /// Centro attorno a cui limitare la ricerca (posizione utente o centro mappa).
  final LatLng near;

  static Future<GeoResult?> show(
    BuildContext context,
    GeocodingService geocoding,
    LatLng near,
  ) {
    return Navigator.of(context).push<GeoResult>(
      MaterialPageRoute(
        builder: (_) => _DestinationSearchScreen(geocoding, near),
      ),
    );
  }

  @override
  State<_DestinationSearchScreen> createState() =>
      _DestinationSearchScreenState();
}

class _DestinationSearchScreenState extends State<_DestinationSearchScreen> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  List<GeoResult> _results = const [];
  bool _searching = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () => _search(value));
  }

  Future<void> _search(String value) async {
    final q = value.trim();
    if (q.length < 3) {
      if (mounted) {
        setState(() {
          _results = const [];
          _searching = false;
        });
      }
      return;
    }
    setState(() => _searching = true);
    final results = await widget.geocoding.search(q, near: widget.near);
    if (!mounted) return;
    setState(() {
      _results = results;
      _searching = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final typedEnough = _controller.text.trim().length >= 3;
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        elevation: 0,
        iconTheme: const IconThemeData(color: _kText),
        titleSpacing: 0,
        title: TextField(
          controller: _controller,
          autofocus: true,
          onChanged: _onChanged,
          onSubmitted: _search,
          textInputAction: TextInputAction.search,
          style: GoogleFonts.barlow(fontSize: 16, color: _kText),
          decoration: InputDecoration(
            hintText: 'Cerca un indirizzo o un luogo',
            hintStyle: GoogleFonts.barlow(fontSize: 15, color: _kDim),
            border: InputBorder.none,
          ),
        ),
        actions: [
          if (_controller.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close, color: _kDim),
              tooltip: 'Cancella',
              onPressed: () {
                _controller.clear();
                setState(() => _results = const []);
              },
            ),
        ],
      ),
      body: _buildResults(typedEnough),
    );
  }

  Widget _buildResults(bool typedEnough) {
    if (_searching) {
      return const Center(
        child: CircularProgressIndicator(strokeWidth: 2.5, color: _kAccent),
      );
    }
    if (_results.isEmpty) {
      return Center(
        child: Text(
          typedEnough ? 'Nessun risultato' : 'Scrivi almeno 3 caratteri',
          style: GoogleFonts.barlow(fontSize: 14, color: _kDim),
        ),
      );
    }
    return ListView.separated(
      itemCount: _results.length,
      separatorBuilder: (_, __) => const Divider(height: 1, color: _kBorder),
      itemBuilder: (context, i) {
        final r = _results[i];
        return ListTile(
          leading: const Icon(Icons.place_outlined, color: _kAccent, size: 20),
          title: Text(
            r.label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.barlow(fontSize: 14, color: _kText),
          ),
          onTap: () => Navigator.of(context).pop(r),
        );
      },
    );
  }
}
