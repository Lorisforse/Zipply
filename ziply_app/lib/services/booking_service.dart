import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:ziply_app/constants.dart';
import 'package:ziply_app/data/models/booking_model.dart';

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
  /// In caso di errore lancia una Exception con un messaggio pronto per la UI;
  /// per il 409 viene propagato il messaggio del backend ("mezzo non
  /// disponibile" / "hai già una prenotazione attiva").
  Future<BookingModel> createBooking(String vehicleId) async {
    final token = await _storage.read(key: kTokenKey);

    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse('$kBaseUrl/bookings'),
            headers: {
              'Content-Type': 'application/json',
              if (token != null) 'Authorization': 'Bearer $token',
            },
            body: jsonEncode({'vehicle_id': vehicleId}),
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
      case 401:
        return 'Sessione scaduta, effettua di nuovo l\'accesso';
      default:
        return 'Impossibile completare la prenotazione';
    }
  }
}
