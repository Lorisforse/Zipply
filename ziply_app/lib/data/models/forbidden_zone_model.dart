// Modello dati per una zona vietata (ZTL, parchi, ...).
// Mappa la response di GET /forbidden-zones del backend Ziply.

import 'package:latlong2/latlong.dart';

/// Zona vietata da disegnare come overlay sulla mappa. Le coordinate GeoJSON
/// arrivano dal backend come `[lng, lat]` e qui vengono già convertite in
/// [LatLng] (`[lat, lng]`), pronte per flutter_map.
class ForbiddenZoneModel {
  const ForbiddenZoneModel({
    required this.id,
    required this.nome,
    required this.polygon,
  });

  final String id;
  final String nome;

  /// Anello esterno del poligono, in ordine `[lat, lng]`.
  final List<LatLng> polygon;

  factory ForbiddenZoneModel.fromJson(Map<String, dynamic> json) {
    final polygonJson = (json['polygon'] as Map<String, dynamic>?) ?? const {};
    final rings = (polygonJson['coordinates'] as List<dynamic>?) ?? const [];
    // GeoJSON Polygon: il primo anello è il bordo esterno; gli eventuali
    // successivi sono fori, qui non utilizzati.
    final ring = rings.isNotEmpty ? rings.first as List<dynamic> : const [];
    final points = ring.map((pair) {
      final coord = pair as List<dynamic>;
      final lng = (coord[0] as num).toDouble();
      final lat = (coord[1] as num).toDouble();
      return LatLng(lat, lng); // inversione [lng,lat] → [lat,lng]
    }).toList(growable: false);

    return ForbiddenZoneModel(
      id: json['id'] as String,
      nome: (json['nome'] as String?) ?? '',
      polygon: points,
    );
  }
}
