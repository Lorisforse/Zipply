import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:ziply_app/constants.dart';
import 'package:ziply_app/data/models/vehicle_model.dart';

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
      return list
          .map((e) => VehicleModel.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw Exception(_errorMessageFor(response.statusCode));
  }

  /// Mappa uno status code di errore del backend in un messaggio per la UI.
  String _errorMessageFor(int statusCode) {
    switch (statusCode) {
      case 401:
        return 'Sessione scaduta, effettua di nuovo l\'accesso';
      default:
        return 'Impossibile caricare i mezzi disponibili';
    }
  }
}
