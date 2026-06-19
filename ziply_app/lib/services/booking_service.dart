import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:ziply_app/constants.dart';
import 'package:ziply_app/data/models/booking_model.dart';
import 'package:ziply_app/services/api_exceptions.dart';

/// Servizio per la prenotazione dei mezzi: chiamate REST verso ziply_backend.
/// Allinea le convenzioni di [VehicleService] e [AuthService]: package http,
/// token JWT da flutter_secure_storage, Exception con messaggi pronti per la UI.
class BookingService {
  BookingService({http.Client? client, FlutterSecureStorage? storage})
      : _client = client ?? http.Client(),
        _storage = storage ?? const FlutterSecureStorage();

  final http.Client _client;
  final FlutterSecureStorage _storage;

  static const Duration _timeout = Duration(seconds: 10);

  /// Crea una prenotazione per [vehicleId] (POST /bookings).
  /// [discountCode] è opzionale (UT.09): se valorizzato viene inviato al backend
  /// che lo collega alla prenotazione per applicarlo al costo a fine corsa.
  /// In caso di errore lancia una Exception con un messaggio pronto per la UI;
  /// per il 409 viene propagato il messaggio del backend ("mezzo non
  /// disponibile" / "hai già una prenotazione attiva"), per il 422 quello sul
  /// codice sconto non valido.
  Future<BookingModel> createBooking(String vehicleId,
      {String? discountCode}) async {
    final token = await _storage.read(key: kTokenKey);

    final payload = <String, dynamic>{'vehicle_id': vehicleId};
    final code = discountCode?.trim();
    if (code != null && code.isNotEmpty) {
      payload['discount_code'] = code;
    }

    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse('$kBaseUrl/bookings'),
            headers: {
              'Content-Type': 'application/json',
              if (token != null) 'Authorization': 'Bearer $token',
            },
            body: jsonEncode(payload),
          )
          .timeout(_timeout);
    } on http.ClientException {
      throw Exception('Impossibile connettersi al server');
    } on TimeoutException {
      throw Exception('Impossibile connettersi al server');
    }

    final body = _decodeBody(response.bodyBytes);

    if (response.statusCode == 201) {
      final booking = body?['booking'];
      if (booking is Map<String, dynamic>) {
        return BookingModel.fromJson(booking);
      }
      throw Exception('Risposta del server non valida');
    }

    throw Exception(_errorMessageFor(response.statusCode, body));
  }

  /// Annulla la prenotazione [bookingId] (POST /bookings/{id}/cancel).
  /// Non restituisce nulla in caso di successo; lancia [SessionExpiredException]
  /// sul 401, altrimenti una Exception con messaggio pronto per la UI.
  Future<void> cancelBooking(String bookingId) async {
    final token = await _storage.read(key: kTokenKey);

    final http.Response response;
    try {
      response = await _client.post(
        Uri.parse('$kBaseUrl/bookings/$bookingId/cancel'),
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

    if (response.statusCode == 200) return;
    if (response.statusCode == 401) throw const SessionExpiredException();

    final body = _decodeBody(response.bodyBytes);
    final serverMessage = body?['error'];
    throw Exception(
      serverMessage is String && serverMessage.isNotEmpty
          ? serverMessage
          : 'Impossibile annullare la prenotazione',
    );
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
  /// messaggio del backend quando disponibile (409).
  String _errorMessageFor(int statusCode, Map<String, dynamic>? body) {
    final serverMessage = body?['error'];
    switch (statusCode) {
      case 409:
        return serverMessage is String && serverMessage.isNotEmpty
            ? serverMessage
            : 'Mezzo non più disponibile';
      case 422:
        // UT.09 — codice sconto inesistente o non più valido.
        return serverMessage is String && serverMessage.isNotEmpty
            ? serverMessage
            : 'Codice sconto non valido';
      case 401:
        return 'Sessione scaduta, effettua di nuovo l\'accesso';
      default:
        return 'Impossibile completare la prenotazione';
    }
  }
}
