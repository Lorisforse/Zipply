import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Servizio di routing pedonale: ottiene il percorso a piedi più breve tra due
/// punti da un server OSRM con profilo "foot". Usa l'istanza pubblica OSM
/// (la stessa di openstreetmap.org), quindi senza API key.
class RoutingService {
  RoutingService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const Duration _timeout = Duration(seconds: 10);

  // OSRM pubblico con profilo pedonale.
  static const String _baseUrl = 'https://routing.openstreetmap.de/routed-foot';

  /// Restituisce i punti del percorso a piedi da [from] a [to], oppure null se
  /// il routing non è disponibile (la UI ricade su una linea diretta).
  Future<List<LatLng>?> walkingRoute(LatLng from, LatLng to) async {
    final uri = Uri.parse(
      '$_baseUrl/route/v1/foot/'
      '${from.longitude},${from.latitude};${to.longitude},${to.latitude}'
      '?overview=full&geometries=geojson',
    );

    final http.Response response;
    try {
      response = await _client.get(uri).timeout(_timeout);
    } on http.ClientException {
      return null;
    } on TimeoutException {
      return null;
    }

    if (response.statusCode != 200) return null;

    try {
      final body =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final routes = body['routes'] as List<dynamic>?;
      if (routes == null || routes.isEmpty) return null;
      final geometry =
          (routes.first as Map<String, dynamic>)['geometry']
              as Map<String, dynamic>?;
      final coordinates = geometry?['coordinates'] as List<dynamic>?;
      if (coordinates == null || coordinates.isEmpty) return null;

      // GeoJSON: ogni coordinata è [lon, lat].
      return coordinates.map((c) {
        final pair = c as List<dynamic>;
        return LatLng((pair[1] as num).toDouble(), (pair[0] as num).toDouble());
      }).toList(growable: false);
    } on FormatException {
      return null;
    }
  }
}
