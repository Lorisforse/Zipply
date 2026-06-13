import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:ziply_app/constants.dart';
import 'package:ziply_app/data/models/payment_method_model.dart';
import 'package:ziply_app/services/api_exceptions.dart';

/// Servizio per la gestione dei metodi di pagamento (UT.14): chiamate REST
/// verso ziply_backend. Allinea le convenzioni di [BookingService] e
/// [VehicleService]: package http, token JWT da flutter_secure_storage,
/// Exception con messaggi pronti per la UI, [SessionExpiredException] sul 401.
class PaymentMethodService {
  PaymentMethodService({http.Client? client, FlutterSecureStorage? storage})
      : _client = client ?? http.Client(),
        _storage = storage ?? const FlutterSecureStorage();

  final http.Client _client;
  final FlutterSecureStorage _storage;

  static const Duration _timeout = Duration(seconds: 10);

  /// Recupera i metodi di pagamento salvati (GET /payment-methods).
  Future<List<PaymentMethodModel>> getPaymentMethods() async {
    final token = await _storage.read(key: kTokenKey);

    final http.Response response;
    try {
      response = await _client.get(
        Uri.parse('$kBaseUrl/payment-methods'),
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
      final list = jsonDecode(utf8.decode(response.bodyBytes)) as List<dynamic>;
      return list
          .map((e) => PaymentMethodModel.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    if (response.statusCode == 401) {
      throw const SessionExpiredException();
    }
    throw Exception('Impossibile caricare i metodi di pagamento');
  }

  /// Salva una nuova carta (POST /payment-methods). Riceve solo le ultime 4
  /// cifre e la scadenza MM/YY: il numero completo e il CVV restano sul client.
  Future<PaymentMethodModel> addPaymentMethod({
    required String cardLastFour,
    required String cardExpiry,
    required bool isDefault,
  }) async {
    final token = await _storage.read(key: kTokenKey);

    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse('$kBaseUrl/payment-methods'),
            headers: {
              'Content-Type': 'application/json',
              if (token != null) 'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'card_last_four': cardLastFour,
              'card_expiry': cardExpiry,
              'is_default': isDefault,
            }),
          )
          .timeout(_timeout);
    } on http.ClientException {
      throw Exception('Impossibile connettersi al server');
    } on TimeoutException {
      throw Exception('Impossibile connettersi al server');
    }

    if (response.statusCode == 201) {
      final body =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      return PaymentMethodModel.fromJson(body);
    }
    if (response.statusCode == 401) {
      throw const SessionExpiredException();
    }
    throw Exception('Impossibile salvare la carta');
  }

  /// Elimina la carta [id] (DELETE /payment-methods/{id}).
  Future<void> deletePaymentMethod(String id) async {
    final token = await _storage.read(key: kTokenKey);

    final http.Response response;
    try {
      response = await _client.delete(
        Uri.parse('$kBaseUrl/payment-methods/$id'),
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

    if (response.statusCode == 204) return;
    if (response.statusCode == 401) throw const SessionExpiredException();
    if (response.statusCode == 404) {
      throw Exception('Carta non trovata');
    }
    throw Exception('Impossibile eliminare la carta');
  }
}
