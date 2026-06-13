// Modello dati per una zona vietata (ZTL, parchi, quartieri, ...).
// Mappa la response di GET /forbidden-zones del backend Ziply.

import 'package:latlong2/latlong.dart';

/// Zona vietata da disegnare come overlay sulla mappa. La geometria GeoJSON può
/// essere un `Polygon` o un `MultiPolygon`; in entrambi i casi qui viene
/// normalizzata in [rings]: la lista degli anelli esterni da disegnare (uno per
/// un Polygon, più di uno per un MultiPolygon). Le coordinate GeoJSON arrivano
/// come `[lng, lat]` e qui sono già convertite in [LatLng] (`[lat, lng]`).
class ForbiddenZoneModel {
  const ForbiddenZoneModel({
    required this.id,
    required this.nome,
    required this.rings,
  });

  final String id;
  final String nome;

  /// Anelli esterni da disegnare, ognuno in ordine `[lat, lng]`. Gli eventuali
  /// fori interni (ring successivi al primo di ogni poligono) sono ignorati.
  final List<List<LatLng>> rings;

  factory ForbiddenZoneModel.fromJson(Map<String, dynamic> json) {
    final geometry = (json['polygon'] as Map<String, dynamic>?) ?? const {};
    final type = geometry['type'] as String?;
    final coords = (geometry['coordinates'] as List<dynamic>?) ?? const [];

    final rings = <List<LatLng>>[];
    if (type == 'MultiPolygon') {
      // coordinates: [ [outerRing, hole?, ...], [outerRing, ...], ... ]
      for (final polygon in coords) {
        final polyRings = polygon as List<dynamic>;
        if (polyRings.isEmpty) continue;
        rings.add(_ring(polyRings.first as List<dynamic>));
      }
    } else {
      // Polygon: coordinates: [ outerRing, hole?, ... ]
      if (coords.isNotEmpty) rings.add(_ring(coords.first as List<dynamic>));
    }

    return ForbiddenZoneModel(
      id: json['id'] as String,
      nome: (json['nome'] as String?) ?? '',
      rings: rings,
    );
  }

  /// Converte un anello GeoJSON (`[[lng, lat], ...]`) in punti `[lat, lng]`.
  static List<LatLng> _ring(List<dynamic> ring) {
    return ring.map((pair) {
      final coord = pair as List<dynamic>;
      final lng = (coord[0] as num).toDouble();
      final lat = (coord[1] as num).toDouble();
      return LatLng(lat, lng);
    }).toList(growable: false);
  }
}
