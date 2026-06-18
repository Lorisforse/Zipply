import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:ziply_app/constants.dart';
import 'package:ziply_app/services/api_exceptions.dart';

/// Percorso calcolato dal backend (UT.07): punti da disegnare sulla mappa più
/// distanza e durata stimate.
class RouteResult {
  const RouteResult({
    required this.points,
    required this.distanceKm,
    required this.durationMinutes,
    required this.estimatedCost,
    required this.fallback,
  });

  final List<LatLng> points;
  final double distanceKm;
  final double durationMinutes;

  /// UT.03 — stima costo (€) del tragitto per il mezzo selezionato.
  final double estimatedCost;

  /// true quando il backend ha usato una linea diretta perché OpenRouteService
  /// non era disponibile.
  final bool fallback;
}

/// Calcolo del percorso mezzo→destinazione tramite il backend (POST /routes),
/// che a sua volta interroga OpenRouteService. Allinea le convenzioni degli
/// altri service: package http, token JWT da secure storage, 401 → sessione
/// scaduta.
class RouteService {
  RouteService({http.Client? client, FlutterSecureStorage? storage})
      : _client = client ?? http.Client(),
        _storage = storage ?? const FlutterSecureStorage();

  final http.Client _client;
  final FlutterSecureStorage _storage;

  static const Duration _timeout = Duration(seconds: 12);

  /// Calcola il percorso dal mezzo [vehicleId] alla [destination].
  Future<RouteResult> computeRoute({
    required String vehicleId,
    required LatLng destination,
  }) async {
    final token = await _storage.read(key: kTokenKey);

    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse('$kBaseUrl/routes'),
            headers: {
              'Content-Type': 'application/json',
              if (token != null) 'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'vehicle_id': vehicleId,
              'dest_lat': destination.latitude,
              'dest_lng': destination.longitude,
            }),
          )
          .timeout(_timeout);
    } on http.ClientException {
      throw Exception('Impossibile connettersi al server');
    } on TimeoutException {
      throw Exception('Impossibile connettersi al server');
    }

    if (response.statusCode == 401) throw const SessionExpiredException();
    if (response.statusCode != 200) {
      throw Exception('Impossibile calcolare il percorso');
    }

    final body =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final geometry = body['geometry'] as Map<String, dynamic>?;
    final coords = (geometry?['coordinates'] as List<dynamic>?) ?? const [];
    final points = <LatLng>[];
    for (final c in coords) {
      final pair = c as List<dynamic>;
      // GeoJSON usa l'ordine [lon, lat].
      points.add(
        LatLng((pair[1] as num).toDouble(), (pair[0] as num).toDouble()),
      );
    }

    return RouteResult(
      points: points,
      distanceKm: (body['distance_km'] as num?)?.toDouble() ?? 0,
      durationMinutes: (body['duration_minutes'] as num?)?.toDouble() ?? 0,
      estimatedCost: (body['estimated_cost'] as num?)?.toDouble() ?? 0,
      fallback: body['fallback'] as bool? ?? false,
    );
  }
}
