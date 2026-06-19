import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:ziply_app/constants.dart';
import 'package:ziply_app/services/api_exceptions.dart';

/// Esito della validazione di un codice sconto (UT.09): codice normalizzato e
/// percentuale di sconto restituiti dal backend.
class DiscountValidation {
  const DiscountValidation({required this.code, required this.percentage});

  final String code;

  /// Percentuale di sconto (es. 10 = 10%).
  final double percentage;
}

/// Servizio per la validazione dei codici sconto (POST /discount-codes/validate).
/// Allinea le convenzioni degli altri service: package http, token JWT da
/// flutter_secure_storage, Exception con messaggi pronti per la UI.
class DiscountService {
  DiscountService({http.Client? client, FlutterSecureStorage? storage})
      : _client = client ?? http.Client(),
        _storage = storage ?? const FlutterSecureStorage();

  final http.Client _client;
  final FlutterSecureStorage _storage;

  static const Duration _timeout = Duration(seconds: 10);

  /// Valida [code] lato backend. Restituisce la percentuale di sconto se il
  /// codice è utilizzabile; lancia [SessionExpiredException] sul 401, altrimenti
  /// una Exception con il messaggio del backend (404 inesistente, 422 scaduto/
  /// esaurito) pronto per la UI.
  Future<DiscountValidation> validate(String code) async {
    final token = await _storage.read(key: kTokenKey);

    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse('$kBaseUrl/discount-codes/validate'),
            headers: {
              'Content-Type': 'application/json',
              if (token != null) 'Authorization': 'Bearer $token',
            },
            body: jsonEncode({'code': code.trim()}),
          )
          .timeout(_timeout);
    } on http.ClientException {
      throw Exception('Impossibile connettersi al server');
    } on TimeoutException {
      throw Exception('Impossibile connettersi al server');
    }

    final body = _decodeBody(response.bodyBytes);

    if (response.statusCode == 200) {
      return DiscountValidation(
        code: (body?['code'] as String?)?.trim().toUpperCase() ??
            code.trim().toUpperCase(),
        percentage: (body?['percentage'] as num?)?.toDouble() ?? 0,
      );
    }

    if (response.statusCode == 401) throw const SessionExpiredException();

    final serverMessage = body?['error'];
    throw Exception(
      serverMessage is String && serverMessage.isNotEmpty
          ? serverMessage
          : 'Codice sconto non valido',
    );
  }

  Map<String, dynamic>? _decodeBody(List<int> bytes) {
    if (bytes.isEmpty) return null;
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }
}
