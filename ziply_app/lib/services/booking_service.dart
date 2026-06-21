import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:ziply_app/data/models/booking_model.dart';
import 'package:ziply_app/data/models/multi_booking_model.dart';
import 'package:ziply_app/services/api_client.dart';

/// Servizio per la prenotazione dei mezzi: chiamate REST verso ziply_backend
/// tramite [ApiClient]. Il 401 (sessione scaduta) è gestito in modo uniforme da
/// [ApiClient] (→ SessionExpiredException); qui resta la mappatura dei messaggi
/// di dominio (409 mezzo non disponibile / prenotazione attiva, 422 codice
/// sconto, vincoli prenotazione di gruppo/anticipata).
class BookingService {
  BookingService({http.Client? client, FlutterSecureStorage? storage})
      : _api = ApiClient(client: client, storage: storage);

  final ApiClient _api;

  /// Crea una prenotazione per [vehicleId] (POST /bookings).
  /// [discountCode] è opzionale (UT.09): se valorizzato viene inviato al backend
  /// che lo collega alla prenotazione per applicarlo al costo a fine corsa.
  /// In caso di errore lancia una Exception con un messaggio pronto per la UI;
  /// per il 409 viene propagato il messaggio del backend ("mezzo non
  /// disponibile" / "hai già una prenotazione attiva"), per il 422 quello sul
  /// codice sconto non valido.
  Future<BookingModel> createBooking(String vehicleId,
      {String? discountCode}) async {
    final payload = <String, dynamic>{'vehicle_id': vehicleId};
    final code = discountCode?.trim();
    if (code != null && code.isNotEmpty) {
      payload['discount_code'] = code;
    }

    final res = await _api.post('/bookings', body: payload);

    if (res.statusCode == 201) {
      final booking = res.map?['booking'];
      if (booking is Map<String, dynamic>) {
        return BookingModel.fromJson(booking);
      }
      throw Exception('Risposta del server non valida');
    }

    throw Exception(_errorMessageFor(res.statusCode, res.map));
  }

  /// UT.16: Prenotazione multipla (POST /bookings/multi): riserva insieme i
  /// mezzi [vehicleIds] sotto un group_id condiviso. Per 409/422 propaga il
  /// messaggio del backend (vincoli non rispettati, mezzo non disponibile, ecc.).
  Future<MultiBookingModel> createMultiBooking(List<String> vehicleIds) async {
    final res = await _api.post('/bookings/multi', body: {'vehicle_ids': vehicleIds});

    if (res.statusCode == 201) {
      final body = res.map;
      if (body != null) return MultiBookingModel.fromJson(body);
      throw Exception('Risposta del server non valida');
    }

    throw Exception(
      res.errorMessage ?? 'Impossibile completare la prenotazione di gruppo',
    );
  }

  /// UT.19: Prenotazione anticipata (POST /bookings/scheduled): riserva il
  /// mezzo [vehicleId] per l'orario [scheduledStart] (solo bici/auto, tra 15 min
  /// e fine del giorno successivo). Restituisce il BookingModel con
  /// scheduledStart e preAuthAmount valorizzati. Per 409/422 propaga il
  /// messaggio del backend.
  Future<BookingModel> createScheduledBooking(
    String vehicleId,
    DateTime scheduledStart,
  ) async {
    final res = await _api.post('/bookings/scheduled', body: {
      'vehicle_id': vehicleId,
      'scheduled_start': scheduledStart.toUtc().toIso8601String(),
    });

    if (res.statusCode == 201) {
      final body = res.map;
      if (body != null) return BookingModel.fromScheduledJson(body);
      throw Exception('Risposta del server non valida');
    }

    throw Exception(
      res.errorMessage ?? 'Impossibile completare la prenotazione anticipata',
    );
  }

  /// Annulla la prenotazione [bookingId] (POST /bookings/{id}/cancel).
  /// Non restituisce nulla in caso di successo.
  Future<void> cancelBooking(String bookingId) async {
    final res = await _api.post('/bookings/$bookingId/cancel');

    if (res.statusCode == 200) return;

    throw Exception(
      res.errorMessage ?? 'Impossibile annullare la prenotazione',
    );
  }

  /// Mappa uno status code di errore in un messaggio per la UI, preferendo il
  /// messaggio del backend quando disponibile (409/422).
  String _errorMessageFor(int statusCode, Map<String, dynamic>? body) {
    final serverMessage = body?['error'];
    switch (statusCode) {
      case 409:
        return serverMessage is String && serverMessage.isNotEmpty
            ? serverMessage
            : 'Mezzo non più disponibile';
      case 422:
        // UT.09: codice sconto inesistente o non più valido.
        return serverMessage is String && serverMessage.isNotEmpty
            ? serverMessage
            : 'Codice sconto non valido';
      default:
        return 'Impossibile completare la prenotazione';
    }
  }
}
