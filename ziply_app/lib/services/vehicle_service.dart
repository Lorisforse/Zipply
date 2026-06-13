import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:ziply_app/constants.dart';
import 'package:ziply_app/core/utils/app_logger.dart';
import 'package:ziply_app/data/models/vehicle_model.dart';
import 'package:ziply_app/services/api_exceptions.dart';

/// Servizio per il recupero dei mezzi: chiamate REST verso ziply_backend.
/// Allinea le convenzioni di [AuthService]: package http, token JWT da
/// flutter_secure_storage, Exception con messaggi pronti per la UI.
class VehicleService {
  VehicleService({http.Client? client, FlutterSecureStorage? storage})
      : _client = client ?? http.Client(),
        _storage = storage ?? const FlutterSecureStorage();

  final http.Client _client;
  final FlutterSecureStorage _storage;

  static const Duration _timeout = Duration(seconds: 10);

  /// Recupera i mezzi disponibili. Se [lat], [lng] e [radius] sono tutti
  /// presenti, il backend filtra i mezzi nel raggio indicato (km).
  Future<List<VehicleModel>> getAvailableVehicles({
    double? lat,
    double? lng,
    double? radius,
  }) async {
    final token = await _storage.read(key: kTokenKey);

    final query = <String, String>{};
    if (lat != null && lng != null && radius != null) {
      query['lat'] = '$lat';
      query['lng'] = '$lng';
      query['radius'] = '$radius';
    }
    final uri = Uri.parse('$kBaseUrl/vehicles')
        .replace(queryParameters: query.isEmpty ? null : query);

    final http.Response response;
    try {
      response = await _client.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      ).timeout(_timeout);
    } on http.ClientException {
      throw Exception('Impossibile connettersi al server');
    } on TimeoutException {
      throw Exception('Impossibile connettersi al server');
    }

    if (response.statusCode == 200) {
      final body =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final list = (body['vehicles'] as List<dynamic>?) ?? const [];
      final vehicles = list
          .map((e) => VehicleModel.fromJson(e as Map<String, dynamic>))
          .toList();
      zlog('${vehicles.length} mezzi disponibili dal server', tag: 'Mezzi');
      return vehicles;
    }
    // 401: token assente/scaduto/non valido → l'utente deve riautenticarsi.
    if (response.statusCode == 401) {
      throw const SessionExpiredException();
    }
    throw Exception('Impossibile caricare i mezzi disponibili');
  }
}
