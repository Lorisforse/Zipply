import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:ziply_app/constants.dart';
import 'package:ziply_app/data/models/ride_model.dart';
import 'package:ziply_app/services/api_exceptions.dart';

/// Servizio per lo sblocco del mezzo (UT.13): chiamate REST verso ziply_backend.
/// Allinea le convenzioni di [BookingService] e [VehicleService]: package http,
/// token JWT da flutter_secure_storage, Exception con messaggi pronti per la UI.
class RideService {
  RideService({http.Client? client, FlutterSecureStorage? storage})
      : _client = client ?? http.Client(),
        _storage = storage ?? const FlutterSecureStorage();

  final http.Client _client;
  final FlutterSecureStorage _storage;

  static const Duration _timeout = Duration(seconds: 10);

  /// Sblocca per prossimità il mezzo [vehicleId] (POST /rides/unlock,
  /// unlock_method "proximity").
  Future<RideModel> unlockByProximity(String vehicleId) {
    return _unlock({'vehicle_id': vehicleId, 'unlock_method': 'proximity'});
  }

  /// Sblocca tramite il QR fisico del mezzo (POST /rides/unlock,
  /// unlock_method "qr").
  Future<RideModel> unlockByQr(String qrCode) {
    return _unlock({'qr_code': qrCode, 'unlock_method': 'qr'});
  }

  /// Termina la corsa [rideId] (POST /rides/{id}/end): la corsa diventa
  /// 'completata' e il mezzo torna disponibile. Restituisce il riepilogo
  /// server-autoritativo (durata, costo già al netto dello sconto, CO2 e
  /// importo scontato, UT.09); lancia [SessionExpiredException] sul 401,
  /// altrimenti una Exception con messaggio pronto per la UI.
  Future<RideEndSummary> endRide(String rideId) async {
    final token = await _storage.read(key: kTokenKey);

    final http.Response response;
    try {
      response = await _client.post(
        Uri.parse('$kBaseUrl/rides/$rideId/end'),
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

    final body = _decodeBody(response.bodyBytes);

    if (response.statusCode == 200) {
      return RideEndSummary.fromJson(body ?? const {});
    }
    if (response.statusCode == 401) throw const SessionExpiredException();

    final serverMessage = body?['error'];
    throw Exception(
      serverMessage is String && serverMessage.isNotEmpty
          ? serverMessage
          : 'Impossibile terminare il noleggio',
    );
  }

  /// Esegue la POST /rides/unlock con il body indicato. In caso di errore
  /// lancia una Exception con un messaggio pronto per la UI; per 404/409
  /// propaga il messaggio del backend ("veicolo non trovato", "prenotazione
  /// scaduta", ...). Sul 401 lancia [SessionExpiredException].
  Future<RideModel> _unlock(Map<String, String> body) async {
    final token = await _storage.read(key: kTokenKey);

    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse('$kBaseUrl/rides/unlock'),
            headers: {
              'Content-Type': 'application/json',
              if (token != null) 'Authorization': 'Bearer $token',
            },
            body: jsonEncode(body),
          )
          .timeout(_timeout);
    } on http.ClientException {
      throw Exception('Impossibile connettersi al server');
    } on TimeoutException {
      throw Exception('Impossibile connettersi al server');
    }

    final decoded = _decodeBody(response.bodyBytes);

    if (response.statusCode == 201) {
      if (decoded != null) {
        return RideModel.fromJson(decoded);
      }
      throw Exception('Risposta del server non valida');
    }

    if (response.statusCode == 401) throw const SessionExpiredException();

    throw Exception(_errorMessageFor(response.statusCode, decoded));
  }

  /// Decodifica il body JSON in modo difensivo, restituendo null se assente o
  /// non valido.
  Map<String, dynamic>? _decodeBody(List<int> bytes) {
    if (bytes.isEmpty) return null;
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  /// Mappa uno status code di errore in un messaggio per la UI, preferendo il
  /// messaggio del backend quando disponibile (404 veicolo non trovato, 409
  /// nessuna prenotazione valida / prenotazione scaduta).
  String _errorMessageFor(int statusCode, Map<String, dynamic>? body) {
    final serverMessage = body?['error'];
    if (serverMessage is String && serverMessage.isNotEmpty) {
      return serverMessage;
    }
    switch (statusCode) {
      case 404:
        return 'Mezzo non trovato';
      case 409:
        return 'Impossibile sbloccare il mezzo';
      default:
        return 'Impossibile sbloccare il mezzo';
    }
  }
}
