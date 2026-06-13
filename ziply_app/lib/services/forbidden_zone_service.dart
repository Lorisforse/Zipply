import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:ziply_app/constants.dart';
import 'package:ziply_app/data/models/forbidden_zone_model.dart';

/// Servizio per il recupero delle zone vietate: chiamate REST verso
/// ziply_backend. Allinea le convenzioni di [VehicleService] (package http,
/// timeout, Exception con messaggi pronti per la UI). L'endpoint è pubblico,
/// quindi non richiede il token JWT.
class ForbiddenZoneService {
  ForbiddenZoneService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  static const Duration _timeout = Duration(seconds: 10);

  /// Recupera le zone vietate attive (is_active = true) dal backend.
  Future<List<ForbiddenZoneModel>> getForbiddenZones() async {
    final uri = Uri.parse('$kBaseUrl/forbidden-zones');

    final http.Response response;
    try {
      response = await _client.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      ).timeout(_timeout);
    } on http.ClientException {
      throw Exception('Impossibile connettersi al server');
    } on TimeoutException {
      throw Exception('Impossibile connettersi al server');
    }

    if (response.statusCode == 200) {
      final body = jsonDecode(utf8.decode(response.bodyBytes)) as List<dynamic>;
      return body
          .map((e) => ForbiddenZoneModel.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw Exception('Impossibile caricare le zone vietate');
  }
}
