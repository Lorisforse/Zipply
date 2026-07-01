import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:ziply_app/core/theme/app_colors.dart';
import 'package:ziply_app/core/theme/app_text_styles.dart';
import 'package:ziply_app/core/utils/app_logger.dart';
import 'package:ziply_app/data/models/operator_vehicle_model.dart';
import 'package:ziply_app/data/models/parking_zone_model.dart';
import 'package:ziply_app/presentation/mobile/map/widgets/ziply_tile_layer.dart';
import 'package:ziply_app/services/operator_service.dart';

/// Colore del pannello flottante (semitrasparente sopra la mappa).
final Color _panelColor = AppColors.surface.withValues(alpha: 0.96);

/// Colore per i mezzi bloccati (OP.11).
const Color _blockedColor = Color(0xFF9C27B0);

/// OP.01 / OP.04 / OP.11 — Mappa flotta in tempo reale per l'operatore:
/// posizione, tipologia, stato e livello di carica di tutti i mezzi, con
/// filtri per tipologia e ricerca per zona/ID. Overlay zone parcheggio come
/// cerchi verdi. Blocco/sblocco remoto via dialog al tap riga.
class FleetScreen extends StatefulWidget {
  const FleetScreen({super.key});

  @override
  State<FleetScreen> createState() => _FleetScreenState();
}

class _FleetScreenState extends State<FleetScreen> with TickerProviderStateMixin {
  final OperatorService _operatorService = OperatorService();
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();

  List<OperatorVehicleModel> _vehicles = [];
  List<ParkingZoneModel> _parkingZones = [];
  bool _isLoading = true;
  bool _showZones = true;
  String? _selectedVehicleId;
  String _selectedFilter = 'tutti';
  String _searchQuery = '';
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadAll();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _loadVehicles(silent: true),
    );
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _searchController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = _vehicles.isEmpty);
    await Future.wait([_loadVehicles(silent: true), _loadParkingZones()]);
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadVehicles({bool silent = false}) async {
    try {
      final loaded = await _operatorService.getVehicles();
      if (mounted) setState(() => _vehicles = loaded);
    } catch (e) {
      zlog('Errore caricamento flotta: $e', tag: 'WebFleet');
      if (mounted && !silent) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadParkingZones() async {
    try {
      final loaded = await _operatorService.getParkingZones();
      if (mounted) setState(() => _parkingZones = loaded);
    } catch (e) {
      zlog('Errore caricamento zone parcheggio: $e', tag: 'WebFleet');
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'disponibile':
        return AppColors.green;
      case 'prenotato':
        return AppColors.accent;
      case 'in_uso':
        return AppColors.red;
      case 'manutenzione':
        return AppColors.dim;
      case 'bloccato':
        return _blockedColor;
      default:
        return AppColors.dim;
    }
  }

  String _getStatusLabel(String status) {
    switch (status) {
      case 'disponibile':
        return 'Disponibile';
      case 'prenotato':
        return 'Prenotato';
      case 'in_uso':
        return 'In uso';
      case 'manutenzione':
        return 'Manutenzione';
      case 'bloccato':
        return 'Bloccato';
      default:
        return status;
    }
  }

  IconData _getTypeIcon(OperatorVehicleType type) {
    switch (type) {
      case OperatorVehicleType.bike:
        return Icons.directions_bike_rounded;
      case OperatorVehicleType.scooter:
        return Icons.electric_scooter_rounded;
      case OperatorVehicleType.car:
        return Icons.directions_car_rounded;
      default:
        return Icons.help_outline_rounded;
    }
  }

  List<OperatorVehicleModel> get _filteredVehicles {
    return _vehicles.where((v) {
      if (_selectedFilter != 'tutti') {
        if (_selectedFilter == 'bike' && v.kind != OperatorVehicleType.bike) return false;
        if (_selectedFilter == 'scooter' && v.kind != OperatorVehicleType.scooter) return false;
        if (_selectedFilter == 'car' && v.kind != OperatorVehicleType.car) return false;
      }
      if (_searchQuery.isNotEmpty) {
        final idMatches = v.id.toLowerCase().contains(_searchQuery);
        final qrMatches = v.qrCode.toLowerCase().contains(_searchQuery);
        if (!idMatches && !qrMatches) return false;
      }
      return true;
    }).toList();
  }

  Map<String, int> get _statusCounts {
    final counts = {
      'disponibile': 0,
      'prenotato': 0,
      'in_uso': 0,
      'manutenzione': 0,
      'bloccato': 0,
    };
    for (final v in _filteredVehicles) {
      if (counts.containsKey(v.status)) {
        counts[v.status] = counts[v.status]! + 1;
      }
    }
    return counts;
  }

  void _centerOnVehicle(OperatorVehicleModel v) {
    setState(() => _selectedVehicleId = v.id);
    _mapController.move(LatLng(v.latitude, v.longitude), 16.0);
  }

  // --- Blocco/sblocco (OP.11) ---

  Future<void> _showVehicleActions(OperatorVehicleModel v) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _VehicleActionDialog(
        vehicle: v,
        onBlock: () async {
          await _operatorService.blockVehicle(v.id);
          await _loadVehicles(silent: true);
        },
        onUnblock: () async {
          Navigator.of(ctx).pop();
          try {
            await _operatorService.unblockVehicle(v.id);
            await _loadVehicles(silent: true);
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Errore sblocco: $e')),
              );
            }
          }
        },
        statusColor: _getStatusColor(v.status),
        statusLabel: _getStatusLabel(v.status),
        typeIcon: _getTypeIcon(v.kind),
      ),
    );
  }

  // --- Creazione zona parcheggio (OP.04) ---

  Future<void> _showCreateZoneDialog() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => _CreateZoneDialog(
        onSave: (name, lat, lng, radiusM, bonus) async {
          await _operatorService.createParkingZone(
            name: name,
            lat: lat,
            lng: lng,
            radiusMeters: radiusM,
            bonusCredit: bonus,
          );
        },
      ),
    );
    if (created == true) await _loadParkingZones();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent),
        ),
      );
    }

    final filteredList = _filteredVehicles;
    final counts = _statusCounts;

    final List<Marker> markers = filteredList.map((v) {
      final isSelected = v.id == _selectedVehicleId;
      final statusColor = _getStatusColor(v.status);

      final markerWidget = GestureDetector(
        onTap: () => _centerOnVehicle(v),
        child: Container(
          width: isSelected ? 58 : 38,
          height: isSelected ? 58 : 38,
          alignment: Alignment.center,
          child: isSelected
              ? PulsingMarker(
                  color: statusColor,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: statusColor.withValues(alpha: 0.22),
                          blurRadius: 10,
                          spreadRadius: 3,
                        ),
                        const BoxShadow(
                          color: Colors.black45,
                          blurRadius: 12,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      v.status == 'bloccato' ? Icons.lock_rounded : _getTypeIcon(v.kind),
                      color: AppColors.bg,
                      size: 20,
                    ),
                  ),
                )
              : Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: statusColor.withValues(alpha: 0.22),
                        blurRadius: 6,
                        spreadRadius: 2,
                      ),
                      const BoxShadow(
                        color: Colors.black38,
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    v.status == 'bloccato' ? Icons.lock_rounded : _getTypeIcon(v.kind),
                    color: AppColors.bg,
                    size: 17,
                  ),
                ),
        ),
      );

      return Marker(
        point: LatLng(v.latitude, v.longitude),
        width: 58,
        height: 58,
        child: markerWidget,
      );
    }).toList();

    // Cerchi per le zone parcheggio (OP.04).
    final List<CircleMarker> zoneCircles = _showZones
        ? _parkingZones.map((z) {
            return CircleMarker(
              point: z.center.latLng,
              radius: z.center.radius,
              useRadiusInMeter: true,
              color: AppColors.green.withValues(alpha: 0.12),
              borderColor: AppColors.green.withValues(alpha: 0.55),
              borderStrokeWidth: 2.0,
            );
          }).toList()
        : [];

    return Stack(
      children: [
        // Mappa di sfondo.
        Positioned.fill(
          child: FlutterMap(
            mapController: _mapController,
            options: const MapOptions(
              initialCenter: LatLng(41.1257, 16.8694),
              initialZoom: 14.0,
              maxZoom: 18.0,
              minZoom: 11.0,
            ),
            children: [
              ziplyTileLayer(context),
              if (zoneCircles.isNotEmpty) CircleLayer(circles: zoneCircles),
              MarkerLayer(markers: markers),
            ],
          ),
        ),

        // Pannello flottante sinistro: KPI, ricerca e lista mezzi.
        Positioned(
          left: 16,
          top: 16,
          bottom: 16,
          width: 320,
          child: Container(
            decoration: BoxDecoration(
              color: _panelColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 40,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'STATO FLOTTA',
                              style: appCond(size: 19, w: FontWeight.bold, ls: 0.8),
                            ),
                            Text(
                              '${filteredList.length}/${_vehicles.length}',
                              style: appBody(size: 12.5, c: AppColors.dim),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        GridView.count(
                          crossAxisCount: 2,
                          shrinkWrap: true,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                          childAspectRatio: 2.2,
                          physics: const NeverScrollableScrollPhysics(),
                          children: [
                            _buildKPISubCard('DISPONIBILE', counts['disponibile']!, AppColors.green),
                            _buildKPISubCard('PRENOTATO', counts['prenotato']!, AppColors.accent),
                            _buildKPISubCard('IN USO', counts['in_uso']!, AppColors.red),
                            _buildKPISubCard('MANUTENZIONE', counts['manutenzione']!, AppColors.dim),
                          ],
                        ),
                        if ((counts['bloccato'] ?? 0) > 0) ...[
                          const SizedBox(height: 8),
                          _buildKPISubCard('BLOCCATO', counts['bloccato']!, _blockedColor),
                        ],
                      ],
                    ),
                  ),

                  const Divider(color: AppColors.border, height: 1),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Container(
                      height: 38,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 10),
                            child: Icon(Icons.search_rounded, color: AppColors.dim, size: 16),
                          ),
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              style: appBody(size: 13.5, c: AppColors.text),
                              decoration: const InputDecoration(
                                hintText: 'Cerca ID o QR...',
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(vertical: 10),
                              ),
                            ),
                          ),
                          if (_searchQuery.isNotEmpty)
                            IconButton(
                              icon: const Icon(Icons.clear_rounded, color: AppColors.dim, size: 14),
                              onPressed: () => _searchController.clear(),
                            ),
                        ],
                      ),
                    ),
                  ),

                  const Divider(color: AppColors.border, height: 1),

                  Expanded(
                    child: filteredList.isEmpty
                        ? Center(
                            child: Text(
                              'Nessun mezzo',
                              style: appBody(size: 13, c: AppColors.dim),
                            ),
                          )
                        : ListView.builder(
                            itemCount: filteredList.length,
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            itemBuilder: (context, index) {
                              final v = filteredList[index];
                              final isSelected = v.id == _selectedVehicleId;
                              final statusColor = _getStatusColor(v.status);
                              final batteryLow = v.batteryLevel <= 30;

                              return InkWell(
                                onTap: () {
                                  _centerOnVehicle(v);
                                  _showVehicleActions(v);
                                },
                                child: Container(
                                  decoration: BoxDecoration(
                                    border: Border(
                                      left: BorderSide(
                                        color: isSelected ? AppColors.accent : Colors.transparent,
                                        width: 3,
                                      ),
                                    ),
                                    color: isSelected
                                        ? AppColors.accent.withValues(alpha: 0.10)
                                        : Colors.transparent,
                                  ),
                                  padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
                                  child: Row(
                                    children: [
                                      Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          Container(
                                            width: 38,
                                            height: 38,
                                            decoration: BoxDecoration(
                                              color: AppColors.surface2,
                                              borderRadius: BorderRadius.circular(7),
                                              border: Border.all(color: AppColors.border, width: 0.5),
                                            ),
                                            alignment: Alignment.center,
                                            child: Icon(
                                              v.status == 'bloccato'
                                                  ? Icons.lock_rounded
                                                  : _getTypeIcon(v.kind),
                                              color: v.status == 'bloccato' ? _blockedColor : AppColors.text,
                                              size: 20,
                                            ),
                                          ),
                                          Positioned(
                                            top: -3,
                                            right: -3,
                                            child: Container(
                                              width: 11,
                                              height: 11,
                                              decoration: BoxDecoration(
                                                color: statusColor,
                                                shape: BoxShape.circle,
                                                border: Border.all(color: AppColors.bg, width: 2),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              crossAxisAlignment: CrossAxisAlignment.baseline,
                                              textBaseline: TextBaseline.alphabetic,
                                              children: [
                                                Flexible(
                                                  child: Text(
                                                    v.qrCode,
                                                    style: appCond(size: 18, w: FontWeight.bold),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  _getStatusLabel(v.status).toUpperCase(),
                                                  style: appCond(
                                                    size: 11,
                                                    w: FontWeight.w600,
                                                    c: statusColor,
                                                    ls: 1.0,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              v.type,
                                              style: appBody(size: 12, c: AppColors.dim),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.bolt_rounded,
                                            size: 11,
                                            color: batteryLow ? AppColors.red : AppColors.dim,
                                          ),
                                          Text(
                                            '${v.batteryLevel}%',
                                            style: appCond(
                                              size: 13,
                                              w: FontWeight.w600,
                                              c: batteryLow ? AppColors.red : AppColors.dim,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Filtri, legenda e controlli zone, in alto a destra.
        Positioned(
          right: 16,
          top: 16,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: _panelColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.45),
                      blurRadius: 26,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    _buildFilterTab('tutti', 'Tutti', null),
                    _buildFilterTab('bike', 'Bici', OperatorVehicleType.bike),
                    _buildFilterTab('scooter', 'Scooter', OperatorVehicleType.scooter),
                    _buildFilterTab('car', 'Auto', OperatorVehicleType.car),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              // Legenda stato + conteggi.
              Container(
                width: 190,
                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
                decoration: BoxDecoration(
                  color: _panelColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.45),
                      blurRadius: 26,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    _buildLegendItem('disponibile', counts['disponibile']!, AppColors.green),
                    const SizedBox(height: 8),
                    _buildLegendItem('prenotato', counts['prenotato']!, AppColors.accent),
                    const SizedBox(height: 8),
                    _buildLegendItem('in_uso', counts['in_uso']!, AppColors.red),
                    const SizedBox(height: 8),
                    _buildLegendItem('manutenzione', counts['manutenzione']!, AppColors.dim),
                    const SizedBox(height: 8),
                    _buildLegendItem('bloccato', counts['bloccato']!, _blockedColor),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              // Controlli zone parcheggio (OP.04).
              Container(
                width: 190,
                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
                decoration: BoxDecoration(
                  color: _panelColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.45),
                      blurRadius: 26,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: AppColors.green.withValues(alpha: 0.50),
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.green, width: 1.5),
                          ),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text('Zone parcheggio', style: appBody(size: 12.5, c: AppColors.text)),
                        ),
                        Text(
                          '${_parkingZones.length}',
                          style: appCond(size: 14, w: FontWeight.bold, c: AppColors.dim),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => setState(() => _showZones = !_showZones),
                            icon: Icon(
                              _showZones ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                              size: 13,
                            ),
                            label: Text(_showZones ? 'Nascondi' : 'Mostra'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.dim,
                              side: const BorderSide(color: AppColors.border),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              textStyle: appBody(size: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        OutlinedButton(
                          onPressed: _showCreateZoneDialog,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.green,
                            side: BorderSide(color: AppColors.green.withValues(alpha: 0.40)),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            minimumSize: Size.zero,
                          ),
                          child: const Icon(Icons.add_rounded, size: 16),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildKPISubCard(String title, int count, Color color) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: appCond(size: 11, w: FontWeight.bold, c: AppColors.dim, ls: 0.5),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          Text('$count', style: appCond(size: 24, w: FontWeight.bold).copyWith(height: 1)),
        ],
      ),
    );
  }

  Widget _buildFilterTab(String key, String label, OperatorVehicleType? iconType) {
    final isSelected = _selectedFilter == key;

    return GestureDetector(
      onTap: () => setState(() => _selectedFilter = key),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Row(
          children: [
            if (iconType != null) ...[
              Icon(
                _getTypeIcon(iconType),
                color: isSelected ? AppColors.bg : AppColors.dim,
                size: 16,
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: appCond(
                size: 15,
                w: FontWeight.w600,
                c: isSelected ? AppColors.bg : AppColors.dim,
                ls: 0.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(String status, int count, Color color) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.22),
                blurRadius: 4,
                spreadRadius: 1,
              ),
            ],
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(_getStatusLabel(status), style: appBody(size: 12.5, c: AppColors.text)),
        ),
        Text('$count', style: appCond(size: 14, w: FontWeight.bold, c: AppColors.dim)),
      ],
    );
  }
}

// --- Dialog azioni mezzo (OP.11) ---

class _VehicleActionDialog extends StatefulWidget {
  final OperatorVehicleModel vehicle;
  final Future<void> Function() onBlock;
  final VoidCallback onUnblock;
  final Color statusColor;
  final String statusLabel;
  final IconData typeIcon;

  const _VehicleActionDialog({
    required this.vehicle,
    required this.onBlock,
    required this.onUnblock,
    required this.statusColor,
    required this.statusLabel,
    required this.typeIcon,
  });

  @override
  State<_VehicleActionDialog> createState() => _VehicleActionDialogState();
}

class _VehicleActionDialogState extends State<_VehicleActionDialog> {
  bool _confirming = false;
  bool _isBlocking = false;
  bool _blocked = false;
  String? _blockError;

  void _requestBlock() => setState(() => _confirming = true);

  void _cancel() => setState(() => _confirming = false);

  Future<void> _doBlock() async {
    setState(() { _isBlocking = true; _blockError = null; });
    try {
      await widget.onBlock();
      if (mounted) setState(() { _blocked = true; _isBlocking = false; _confirming = false; });
    } catch (e) {
      if (mounted) setState(() { _blockError = e.toString(); _isBlocking = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.vehicle;
    final isBlocked = v.status == 'bloccato';

    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: widget.statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      isBlocked ? Icons.lock_rounded : widget.typeIcon,
                      color: widget.statusColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(v.qrCode, style: appCond(size: 20, w: FontWeight.bold)),
                        const SizedBox(height: 2),
                        Text(v.type, style: appBody(size: 13, c: AppColors.dim)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: widget.statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      widget.statusLabel.toUpperCase(),
                      style: appCond(size: 11, w: FontWeight.bold, c: widget.statusColor, ls: 0.6),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.bg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _infoCell('Batteria', '${v.batteryLevel}%'),
                    _infoCell('Tariffa', '${(v.tariffaAlMinuto).toStringAsFixed(2)} €/min'),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              if (_blocked) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.green.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.green.withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_rounded, color: AppColors.green, size: 20),
                      const SizedBox(width: 10),
                      Text('Mezzo bloccato', style: appCond(size: 15, w: FontWeight.w600, c: AppColors.green)),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.dim,
                      side: const BorderSide(color: AppColors.border),
                    ),
                    child: const Text('Chiudi'),
                  ),
                ),
              ] else if (_confirming) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.red.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.red.withValues(alpha: 0.30)),
                  ),
                  child: Text(
                    'Confermi il blocco remoto del mezzo ${v.qrCode}? Il mezzo non sara\' piu\' prenotabile ne\' sbloccabile dagli utenti.',
                    style: appBody(size: 13, c: AppColors.text),
                  ),
                ),
                if (_blockError != null) ...[
                  const SizedBox(height: 8),
                  Text(_blockError!, style: appBody(size: 12, c: AppColors.red)),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isBlocking ? null : _cancel,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.dim,
                          side: const BorderSide(color: AppColors.border),
                        ),
                        child: const Text('ANNULLA'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isBlocking ? null : _doBlock,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.red,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: AppColors.red.withValues(alpha: 0.50),
                        ),
                        child: _isBlocking
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('BLOCCA'),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                Row(
                  children: [
                    if (!isBlocked)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _requestBlock,
                          icon: const Icon(Icons.lock_rounded, size: 16),
                          label: const Text('Blocca mezzo'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.red,
                            side: BorderSide(color: AppColors.red.withValues(alpha: 0.40)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    if (isBlocked)
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: widget.onUnblock,
                          icon: const Icon(Icons.lock_open_rounded, size: 16),
                          label: const Text('Sblocca mezzo'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.green,
                            foregroundColor: AppColors.bg,
                          ),
                        ),
                      ),
                    const SizedBox(width: 10),
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.dim,
                        side: const BorderSide(color: AppColors.border),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                      child: const Text('Chiudi'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoCell(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: appBody(size: 11, c: AppColors.dim)),
        const SizedBox(height: 2),
        Text(value, style: appCond(size: 16, w: FontWeight.bold)),
      ],
    );
  }
}

// --- Dialog creazione zona parcheggio (OP.04) ---

class _CreateZoneDialog extends StatefulWidget {
  final Future<void> Function(String name, double lat, double lng, double radiusM, double bonus) onSave;

  const _CreateZoneDialog({required this.onSave});

  @override
  State<_CreateZoneDialog> createState() => _CreateZoneDialogState();
}

class _CreateZoneDialogState extends State<_CreateZoneDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _latCtrl = TextEditingController();
  final _lngCtrl = TextEditingController();
  final _radiusCtrl = TextEditingController(text: '100');
  final _bonusCtrl = TextEditingController(text: '0');
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _latCtrl.dispose();
    _lngCtrl.dispose();
    _radiusCtrl.dispose();
    _bonusCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(
        _nameCtrl.text.trim(),
        double.parse(_latCtrl.text.trim()),
        double.parse(_lngCtrl.text.trim()),
        double.parse(_radiusCtrl.text.trim()),
        double.tryParse(_bonusCtrl.text.trim()) ?? 0,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Nuova zona parcheggio', style: appCond(size: 20, w: FontWeight.bold)),
                const SizedBox(height: 20),
                _buildField(_nameCtrl, 'Nome zona', validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Campo obbligatorio' : null),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildField(_latCtrl, 'Latitudine',
                          keyboard: TextInputType.number,
                          validator: (v) => double.tryParse(v ?? '') == null ? 'Numero non valido' : null),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildField(_lngCtrl, 'Longitudine',
                          keyboard: TextInputType.number,
                          validator: (v) => double.tryParse(v ?? '') == null ? 'Numero non valido' : null),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildField(_radiusCtrl, 'Raggio (m)',
                          keyboard: TextInputType.number,
                          validator: (v) {
                            final d = double.tryParse(v ?? '');
                            return (d == null || d <= 0) ? 'Valore non valido' : null;
                          }),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildField(_bonusCtrl, 'Bonus (€)',
                          keyboard: TextInputType.number,
                          validator: (v) => double.tryParse(v ?? '') == null ? 'Numero non valido' : null),
                    ),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: appBody(size: 12, c: AppColors.red)),
                ],
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.dim,
                          side: const BorderSide(color: AppColors.border),
                        ),
                        child: const Text('ANNULLA'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _saving ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.green,
                          foregroundColor: AppColors.bg,
                        ),
                        child: _saving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('CREA ZONA'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField(
    TextEditingController ctrl,
    String label, {
    TextInputType? keyboard,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: ctrl,
      keyboardType: keyboard,
      validator: validator,
      style: appBody(size: 14, c: AppColors.text),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: appBody(size: 13, c: AppColors.dim),
        filled: true,
        fillColor: AppColors.bg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(7),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(7),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        isDense: true,
      ),
    );
  }
}

// --- PulsingMarker (invariato) ---

class PulsingMarker extends StatefulWidget {
  final Color color;
  final Widget child;

  const PulsingMarker({super.key, required this.color, required this.child});

  @override
  State<PulsingMarker> createState() => _PulsingMarkerState();
}

class _PulsingMarkerState extends State<PulsingMarker> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final scale = 0.85 + 0.40 * _controller.value;
            final opacity = 0.90 * (1 - _controller.value);
            return Container(
              width: 58 * scale,
              height: 58 * scale,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: widget.color.withValues(alpha: opacity),
                  width: 2,
                ),
              ),
            );
          },
        ),
        widget.child,
      ],
    );
  }
}
