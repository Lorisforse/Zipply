import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:ziply_app/constants.dart';
import 'package:ziply_app/data/models/subscription_model.dart';
import 'package:ziply_app/services/api_exceptions.dart';

typedef SubscriptionListResult = ({
  List<SubscriptionModel> subscriptions,
  List<VehicleTypeModel> vehicleTypes,
});

class SubscriptionService {
  SubscriptionService({http.Client? client, FlutterSecureStorage? storage})
      : _client = client ?? http.Client(),
        _storage = storage ?? const FlutterSecureStorage();

  final http.Client _client;
  final FlutterSecureStorage _storage;

  static const Duration _timeout = Duration(seconds: 10);

  Future<Map<String, String>> _authHeaders() async {
    final token = await _storage.read(key: kTokenKey);
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// Recupera gli abbonamenti dell'utente e tutte le tipologie di mezzo disponibili.
  Future<SubscriptionListResult> fetchAll() async {
    final http.Response response;
    try {
      response = await _client
          .get(
            Uri.parse('$kBaseUrl/subscriptions'),
            headers: await _authHeaders(),
          )
          .timeout(_timeout);
    } on http.ClientException {
      throw Exception('Impossibile connettersi al server');
    } on TimeoutException {
      throw Exception('Impossibile connettersi al server');
    }

    if (response.statusCode == 401) throw const SessionExpiredException();

    final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;

    if (response.statusCode == 200) {
      final rawSubs = body['subscriptions'] as List<dynamic>? ?? [];
      final rawTypes = body['vehicle_types'] as List<dynamic>? ?? [];
      return (
        subscriptions: rawSubs
            .map((e) => SubscriptionModel.fromJson(e as Map<String, dynamic>))
            .toList(),
        vehicleTypes: rawTypes
            .map((e) => VehicleTypeModel.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
    }

    final errorMsg = body['error'] as String?;
    throw Exception(errorMsg ?? 'Impossibile recuperare gli abbonamenti');
  }

  /// Sottoscrive un abbonamento per la tipologia e la durata indicate.
  Future<SubscriptionModel> subscribe({
    required String vehicleTypeId,
    required int durationMonths,
  }) async {
    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse('$kBaseUrl/subscriptions'),
            headers: await _authHeaders(),
            body: jsonEncode({
              'vehicle_type_id': vehicleTypeId,
              'duration_months': durationMonths,
            }),
          )
          .timeout(_timeout);
    } on http.ClientException {
      throw Exception('Impossibile connettersi al server');
    } on TimeoutException {
      throw Exception('Impossibile connettersi al server');
    }

    if (response.statusCode == 401) throw const SessionExpiredException();

    final body = response.body.isNotEmpty
        ? jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>?
        : null;

    if (response.statusCode == 201) {
      return SubscriptionModel.fromJson(body!);
    }

    final errorMsg = body?['error'] as String?;
    throw Exception(errorMsg ?? 'Impossibile sottoscrivere l\'abbonamento');
  }
}
