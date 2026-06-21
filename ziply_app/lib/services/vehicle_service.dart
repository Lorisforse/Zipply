import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:ziply_app/core/utils/app_logger.dart';
import 'package:ziply_app/data/models/vehicle_model.dart';
import 'package:ziply_app/services/api_client.dart';

/// Servizio per il recupero dei mezzi: chiamate REST verso ziply_backend
/// tramite [ApiClient] (base URL, token JWT, 401 → sessione scaduta).
class VehicleService {
  VehicleService({http.Client? client, FlutterSecureStorage? storage})
      : _api = ApiClient(client: client, storage: storage);

  final ApiClient _api;

  /// Recupera i mezzi disponibili. Se [lat], [lng] e [radius] sono tutti
  /// presenti, il backend filtra i mezzi nel raggio indicato (km).
  Future<List<VehicleModel>> getAvailableVehicles({
    double? lat,
    double? lng,
    double? radius,
  }) async {
    final query = <String, String>{};
    if (lat != null && lng != null && radius != null) {
      query['lat'] = '$lat';
      query['lng'] = '$lng';
      query['radius'] = '$radius';
    }

    final res = await _api.get('/vehicles', query: query);

    if (res.statusCode == 200) {
      final list = (res.map?['vehicles'] as List<dynamic>?) ?? const [];
      final vehicles = list
          .map((e) => VehicleModel.fromJson(e as Map<String, dynamic>))
          .toList();
      zlog('${vehicles.length} mezzi disponibili dal server', tag: 'Mezzi');
      return vehicles;
    }
    throw Exception('Impossibile caricare i mezzi disponibili');
  }
}
