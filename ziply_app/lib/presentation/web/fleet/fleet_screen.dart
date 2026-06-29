import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:ziply_app/core/theme/app_colors.dart';
import 'package:ziply_app/core/theme/app_text_styles.dart';
import 'package:ziply_app/core/utils/app_logger.dart';
import 'package:ziply_app/data/models/operator_vehicle_model.dart';
import 'package:ziply_app/presentation/mobile/map/widgets/ziply_tile_layer.dart';
import 'package:ziply_app/services/operator_service.dart';

/// Colore del pannello flottante (semitrasparente sopra la mappa).
final Color _panelColor = AppColors.surface.withValues(alpha: 0.96);

/// OP.01 — Mappa flotta in tempo reale per l'operatore: posizione, tipologia,
/// stato e livello di carica di tutti i mezzi, con filtri per tipologia e
/// ricerca per zona/ID. La lista viene aggiornata periodicamente.
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
  bool _isLoading = true;
  String? _selectedVehicleId;
  String _selectedFilter = 'tutti'; // 'tutti', 'bike', 'scooter', 'car'
  String _searchQuery = '';
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadVehicles();
    // Aggiornamento periodico per la visualizzazione in tempo reale (OP.01).
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) => _loadVehicles(silent: true));
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

  Future<void> _loadVehicles({bool silent = false}) async {
    if (!silent) {
      setState(() => _isLoading = _vehicles.isEmpty);
    }
    try {
      final loaded = await _operatorService.getVehicles();
      if (mounted) {
        setState(() {
          _vehicles = loaded;
          _isLoading = false;
        });
      }
    } catch (e) {
      zlog('Errore caricamento flotta: $e', tag: 'WebFleet');
      if (mounted) {
        setState(() => _isLoading = false);
      }
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

  /// Filtra i veicoli per tipologia e per ricerca (ID o QR code).
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

  /// Conteggi per stato, usati da KPI e legenda.
  Map<String, int> get _statusCounts {
    final counts = {'disponibile': 0, 'prenotato': 0, 'in_uso': 0, 'manutenzione': 0};
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
                    child: Icon(_getTypeIcon(v.kind), color: AppColors.bg, size: 20),
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
                  child: Icon(_getTypeIcon(v.kind), color: AppColors.bg, size: 17),
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

    return Stack(
      children: [
        // Mappa di sfondo.
        Positioned.fill(
          child: FlutterMap(
            mapController: _mapController,
            options: const MapOptions(
              // Centro di default: Bari.
              initialCenter: LatLng(41.1257, 16.8694),
              initialZoom: 14.0,
              maxZoom: 18.0,
              minZoom: 11.0,
            ),
            children: [
              ziplyTileLayer(context),
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
                      ],
                    ),
                  ),

                  const Divider(color: AppColors.border, height: 1),

                  // Barra di ricerca.
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

                  // Lista scorribile dei mezzi.
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
                                onTap: () => _centerOnVehicle(v),
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
                                            child: Icon(_getTypeIcon(v.kind), color: AppColors.text, size: 20),
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

        // Filtri categoria + legenda, in alto a destra.
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
              Container(
                width: 180,
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

/// Marker con anello pulsante esterno per il mezzo selezionato.
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
