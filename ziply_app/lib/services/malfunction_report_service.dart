import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:ziply_app/constants.dart';
import 'package:ziply_app/data/models/malfunction_report_model.dart';
import 'package:ziply_app/services/api_exceptions.dart';

class MalfunctionReportService {
  MalfunctionReportService({http.Client? client, FlutterSecureStorage? storage})
      : _client = client ?? http.Client(),
        _storage = storage ?? const FlutterSecureStorage();

  final http.Client _client;
  final FlutterSecureStorage _storage;

  static const Duration _timeout = Duration(seconds: 10);

  /// Invia una segnalazione di malfunzionamento.
  Future<MalfunctionReportModel> submitReport({
    required String rideId,
    required String problemType,
    required String description,
    required List<String> attachmentUrls,
  }) async {
    final token = await _storage.read(key: kTokenKey);

    final http.Response response;
    try {
      response = await _client.post(
        Uri.parse('$kBaseUrl/malfunction-reports'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'ride_id': rideId,
          'problem_type': problemType,
          'description': description,
          'attachment_urls': attachmentUrls,
        }),
      ).timeout(_timeout);
    } on http.ClientException {
      throw Exception('Impossibile connettersi al server');
    } on TimeoutException {
      throw Exception('Impossibile connettersi al server');
    }

    final body = response.body.isNotEmpty ? jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>? : null;

    if (response.statusCode == 201) {
      return MalfunctionReportModel.fromJson(body!);
    }
    if (response.statusCode == 401) {
      throw const SessionExpiredException();
    }
    final errorMsg = body?['error'] as String?;
    throw Exception(errorMsg ?? 'Impossibile inviare la segnalazione');
  }
}
