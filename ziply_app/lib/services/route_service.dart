import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:ziply_app/services/api_client.dart';

/// Percorso calcolato dal backend (UT.07): punti da disegnare sulla mappa più
/// distanza e durata stimate.
class RouteResult {
  const RouteResult({
    required this.points,
    required this.distanceKm,
    required this.durationMinutes,
    required this.estimatedCost,
    required this.suggestion,
    required this.fallback,
  });

  final List<LatLng> points;
  final double distanceKm;
  final double durationMinutes;

  /// UT.03: stima costo (€) del tragitto per il mezzo selezionato.
  final double estimatedCost;

  /// UT.08: tipologia consigliata per il tragitto, calcolata dal backend in
  /// base alla distanza del percorso.
  final SuggestedCategory suggestion;

  /// true quando il backend ha usato una linea diretta perché OpenRouteService
  /// non era disponibile.
  final bool fallback;
}

/// UT.08: categoria di mezzo consigliata per il tragitto, inclusa nella
/// risposta del calcolo percorso (POST /routes).
enum SuggestedCategory { auto, biciScooter, unknown }

/// Calcolo del percorso mezzo→destinazione tramite il backend (POST /routes),
/// che a sua volta interroga OpenRouteService. Usa [ApiClient] (base URL, token
/// JWT, 401 → sessione scaduta).
class RouteService {
  RouteService({http.Client? client, FlutterSecureStorage? storage})
      : _api = ApiClient(client: client, storage: storage);

  final ApiClient _api;

  static const Duration _timeout = Duration(seconds: 12);

  /// Calcola il percorso dal mezzo [vehicleId] alla [destination].
  Future<RouteResult> computeRoute({
    required String vehicleId,
    required LatLng destination,
  }) async {
    final res = await _api.post(
      '/routes',
      body: {
        'vehicle_id': vehicleId,
        'dest_lat': destination.latitude,
        'dest_lng': destination.longitude,
      },
      timeout: _timeout,
    );

    if (res.statusCode != 200) {
      throw Exception('Impossibile calcolare il percorso');
    }

    final body = res.map ?? const <String, dynamic>{};
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

    final st = body['suggested_type'] as String?;
    final suggestion = switch (st) {
      'auto' => SuggestedCategory.auto,
      'bici_scooter' => SuggestedCategory.biciScooter,
      _ => SuggestedCategory.unknown,
    };

    return RouteResult(
      points: points,
      distanceKm: (body['distance_km'] as num?)?.toDouble() ?? 0,
      durationMinutes: (body['duration_minutes'] as num?)?.toDouble() ?? 0,
      estimatedCost: (body['estimated_cost'] as num?)?.toDouble() ?? 0,
      suggestion: suggestion,
      fallback: body['fallback'] as bool? ?? false,
    );
  }
}
