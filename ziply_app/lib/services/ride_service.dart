import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:ziply_app/data/models/ride_model.dart';
import 'package:ziply_app/services/api_client.dart';

/// Servizio per lo sblocco e la gestione della corsa (UT.13/UT.15/UT.16):
/// chiamate REST verso ziply_backend tramite [ApiClient]. Il 401 (sessione
/// scaduta) è gestito in modo uniforme da [ApiClient]; qui resta la mappatura
/// dei messaggi di dominio.
class RideService {
  RideService({http.Client? client, FlutterSecureStorage? storage})
      : _api = ApiClient(client: client, storage: storage);

  final ApiClient _api;

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
  /// importo scontato, UT.09).
  Future<RideEndSummary> endRide(String rideId) async {
    final res = await _api.post('/rides/$rideId/end');

    if (res.statusCode == 200) {
      return RideEndSummary.fromJson(res.map ?? const {});
    }
    throw Exception(res.errorMessage ?? 'Impossibile terminare il noleggio');
  }

  /// Mette in pausa la corsa [rideId] (POST /rides/{id}/pause).
  /// Restituisce lo stato aggiornato (dovrebbe essere 'paused').
  Future<String> pauseRide(String rideId) async {
    final res = await _api.post('/rides/$rideId/pause');

    if (res.statusCode == 200) {
      return res.map?['status'] as String? ?? 'paused';
    }
    throw Exception(
      res.errorMessage ?? 'Impossibile mettere in pausa il noleggio',
    );
  }

  /// Riprende la corsa [rideId] (POST /rides/{id}/resume).
  /// Restituisce lo stato aggiornato (dovrebbe essere 'attiva').
  Future<String> resumeRide(String rideId) async {
    final res = await _api.post('/rides/$rideId/resume');

    if (res.statusCode == 200) {
      return res.map?['status'] as String? ?? 'attiva';
    }
    throw Exception(
      res.errorMessage ?? 'Impossibile riprendere il noleggio',
    );
  }

  /// UT.16: Sblocca simultaneamente tutte le corse di un gruppo
  /// (POST /rides/group/{id}/unlock). Restituisce le corse avviate.
  Future<List<RideModel>> unlockGroup(String groupId) async {
    final res = await _api.post('/rides/group/$groupId/unlock');

    if (res.statusCode == 201) {
      final list = (res.map?['rides'] as List?) ?? const [];
      return list
          .whereType<Map<String, dynamic>>()
          .map(RideModel.fromJson)
          .toList(growable: false);
    }
    throw Exception(res.errorMessage ?? 'Impossibile sbloccare il gruppo');
  }

  /// UT.16: Termina tutte le corse di un gruppo (POST /rides/group/{id}/end) e
  /// restituisce il riepilogo aggregato (durata, costo, CO2, sconto sommati).
  Future<RideEndSummary> endGroup(String groupId) async {
    final res = await _api.post('/rides/group/$groupId/end');

    if (res.statusCode == 200) {
      return RideEndSummary.fromJson(res.map ?? const {});
    }
    throw Exception(
      res.errorMessage ?? 'Impossibile terminare il noleggio di gruppo',
    );
  }

  /// Esegue la POST /rides/unlock con il body indicato. Per 404/409 propaga il
  /// messaggio del backend ("veicolo non trovato", "prenotazione scaduta", ...).
  Future<RideModel> _unlock(Map<String, String> body) async {
    final res = await _api.post('/rides/unlock', body: body);

    if (res.statusCode == 201) {
      final decoded = res.map;
      if (decoded != null) {
        return RideModel.fromJson(decoded);
      }
      throw Exception('Risposta del server non valida');
    }

    throw Exception(_errorMessageFor(res.statusCode, res.map));
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
