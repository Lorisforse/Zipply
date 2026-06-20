import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:ziply_app/constants.dart';
import 'package:ziply_app/data/models/payment_link_model.dart';
import 'package:ziply_app/services/api_exceptions.dart';

class PaymentLinkService {
  PaymentLinkService({http.Client? client, FlutterSecureStorage? storage})
      : _client = client ?? http.Client(),
        _storage = storage ?? const FlutterSecureStorage();

  final http.Client _client;
  final FlutterSecureStorage _storage;

  static const Duration _timeout = Duration(seconds: 10);

  /// Genera un link di pagamento per la corsa multipla [rideId].
  Future<PaymentLinkModel> generatePaymentLink(String rideId) async {
    final token = await _storage.read(key: kTokenKey);

    final http.Response response;
    try {
      response = await _client.post(
        Uri.parse('$kBaseUrl/rides/$rideId/payment-link'),
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

    final body = response.body.isNotEmpty ? jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>? : null;

    if (response.statusCode == 201) {
      return PaymentLinkModel.fromJson(body!);
    }
    if (response.statusCode == 401) {
      throw const SessionExpiredException();
    }
    final errorMsg = body?['error'] as String?;
    throw Exception(errorMsg ?? 'Impossibile generare il link di pagamento');
  }

  /// Recupera i dettagli del link di pagamento [linkId].
  Future<PaymentLinkModel> getPaymentLink(String linkId) async {
    final token = await _storage.read(key: kTokenKey);

    final http.Response response;
    try {
      response = await _client.get(
        Uri.parse('$kBaseUrl/payment-links/$linkId'),
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

    final body = response.body.isNotEmpty ? jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>? : null;

    if (response.statusCode == 200) {
      return PaymentLinkModel.fromJson(body!);
    }
    if (response.statusCode == 401) {
      throw const SessionExpiredException();
    }
    final errorMsg = body?['error'] as String?;
    throw Exception(errorMsg ?? 'Impossibile recuperare il link di pagamento');
  }

  /// Paga la quota del link di pagamento [linkId].
  Future<void> payPaymentLink(String linkId) async {
    final token = await _storage.read(key: kTokenKey);

    final http.Response response;
    try {
      response = await _client.post(
        Uri.parse('$kBaseUrl/payment-links/$linkId/pay'),
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

    final body = response.body.isNotEmpty ? jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>? : null;

    if (response.statusCode == 200) {
      return;
    }
    if (response.statusCode == 401) {
      throw const SessionExpiredException();
    }
    final errorMsg = body?['error'] as String?;
    throw Exception(errorMsg ?? 'Pagamento della quota fallito');
  }

  /// Recupera il saldo crediti dell'utente.
  Future<double> getCreditBalance() async {
    final token = await _storage.read(key: kTokenKey);

    final http.Response response;
    try {
      response = await _client.get(
        Uri.parse('$kBaseUrl/users/credit-balance'),
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

    final body = response.body.isNotEmpty ? jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>? : null;

    if (response.statusCode == 200) {
      return (body!['credit_balance'] as num).toDouble();
    }
    if (response.statusCode == 401) {
      throw const SessionExpiredException();
    }
    throw Exception('Impossibile recuperare il saldo crediti');
  }
}
