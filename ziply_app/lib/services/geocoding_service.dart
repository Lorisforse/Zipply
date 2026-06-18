import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Risultato di una ricerca testuale di destinazione (geocoding).
class GeoResult {
  const GeoResult({required this.label, required this.point});

  final String label;
  final LatLng point;
}

/// Geocoding testuale tramite Nominatim (OpenStreetMap), senza API key. Usato
/// per l'inserimento della destinazione (UT.07). In caso di errore ritorna una
/// lista vuota: la UI mostra semplicemente "nessun risultato".
class GeocodingService {
  GeocodingService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const Duration _timeout = Duration(seconds: 8);
  static const String _baseUrl = 'https://nominatim.openstreetmap.org';

  /// Cerca [query] e restituisce fino a 6 risultati (vuoto se nulla o errore).
  /// Se [near] è fornito, limita i risultati a un riquadro attorno a quel punto
  /// (~30-40 km, viewbox + bounded=1), così la ricerca resta pertinente alla
  /// zona invece di restituire vie omonime sparse nel mondo.
  Future<List<GeoResult>> search(String query, {LatLng? near}) async {
    final q = query.trim();
    if (q.isEmpty) return const [];

    final params = <String, String>{
      'q': q,
      'format': 'jsonv2',
      'limit': '6',
    };
    if (near != null) {
      const d = 0.4; // ~30-40 km di lato attorno alla posizione
      params['viewbox'] = '${near.longitude - d},${near.latitude + d},'
          '${near.longitude + d},${near.latitude - d}';
      params['bounded'] = '1';
    }

    final uri = Uri.parse('$_baseUrl/search').replace(queryParameters: params);

    final http.Response response;
    try {
      response = await _client.get(
        uri,
        // Nominatim richiede uno User-Agent identificativo.
        headers: {'User-Agent': 'ziply-app/1.0 (smart mobility Zootropolis)'},
      ).timeout(_timeout);
    } on http.ClientException {
      return const [];
    } on TimeoutException {
      return const [];
    }

    if (response.statusCode != 200) return const [];

    final data = jsonDecode(utf8.decode(response.bodyBytes)) as List<dynamic>;
    final results = <GeoResult>[];
    for (final e in data) {
      final m = e as Map<String, dynamic>;
      final lat = double.tryParse(m['lat']?.toString() ?? '');
      final lon = double.tryParse(m['lon']?.toString() ?? '');
      final name = m['display_name']?.toString() ?? '';
      if (lat == null || lon == null || name.isEmpty) continue;
      results.add(GeoResult(label: name, point: LatLng(lat, lon)));
    }
    return results;
  }
}
