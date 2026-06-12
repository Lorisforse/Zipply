import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:ziply_app/data/models/vehicle_model.dart';
import 'package:ziply_app/presentation/mobile/map/widgets/vehicle_marker.dart';
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
  final MapController _mapController = MapController();

  _ViewState _state = _ViewState.loading;
  String? _errorMessage;
  List<VehicleModel> _vehicles = const [];
  LatLng _center = _kZootropolisCenter;
  LatLng? _userPosition;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: SafeArea(
        child: Column(
          children: [
            const _Header(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case _ViewState.loading:
        return const Center(
          child: CircularProgressIndicator(color: _kAccent, strokeWidth: 2.5),
        );
      case _ViewState.error:
        return _ErrorView(message: _errorMessage, onRetry: _load);
      case _ViewState.success:
        return _buildMap();
    }
  }

  Widget _buildMap() {
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
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'it.lorisamato.ziply',
            ),
            MarkerLayer(markers: _buildMarkers()),
          ],
        ),
        Positioned(
          right: 16,
          top: 16,
          child: _RecenterButton(onTap: _recenter),
        ),
      ],
    );
  }

  List<Marker> _buildMarkers() {
    final markers = <Marker>[
      for (final v in _vehicles)
        Marker(
          point: LatLng(v.latitude, v.longitude),
          width: VehicleMarker.diameter,
          height: VehicleMarker.diameter,
          child: VehicleMarker(kind: v.kind),
        ),
    ];
    if (_userPosition != null) {
      markers.add(
        Marker(
          point: _userPosition!,
          width: 18,
          height: 18,
          child: const _UserDot(),
        ),
      );
    }
    return markers;
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
      decoration: BoxDecoration(
        color: _kText,
        shape: BoxShape.circle,
        border: Border.all(color: _kBg, width: 2),
        boxShadow: const [
          BoxShadow(color: Color(0x66F5F5F5), blurRadius: 0, spreadRadius: 1),
        ],
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
