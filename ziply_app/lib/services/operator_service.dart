import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:ziply_app/data/models/operator_malfunction_report_model.dart';
import 'package:ziply_app/data/models/operator_vehicle_model.dart';
import 'package:ziply_app/data/models/parking_zone_model.dart';
import 'package:ziply_app/services/api_client.dart';

/// Servizio dell'area operatore: chiamate REST verso ziply_backend per il
/// monitoraggio della flotta (OP.01), gestione segnalazioni (OP.03),
/// blocco remoto mezzi (OP.11) e zone parcheggio (OP.04).
class OperatorService {
  OperatorService({http.Client? client, FlutterSecureStorage? storage})
      : _api = ApiClient(client: client, storage: storage);

  final ApiClient _api;

  /// Recupera tutti i mezzi della flotta (qualsiasi stato) per la mappa
  /// operatore. L'endpoint e' riservato ai ruoli operatore/amministrazione.
  Future<List<OperatorVehicleModel>> getVehicles() async {
    final res = await _api.get('/operator/vehicles');
    if (res.statusCode == 200) {
      final list = res.list ?? const <dynamic>[];
      return list
          .map((e) => OperatorVehicleModel.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw Exception('Impossibile caricare i veicoli dell\'operatore');
  }

  /// Recupera le segnalazioni di malfunzionamento per la dashboard (OP.03 /
  /// UC-26). [status] opzionale filtra per stato di lavorazione.
  Future<List<OperatorMalfunctionReportModel>> getMalfunctionReports({String? status}) async {
    final query = (status != null && status.isNotEmpty) ? {'status': status} : null;
    final res = await _api.get('/operator/malfunction-reports', query: query);
    if (res.statusCode == 200) {
      final list = res.list ?? const <dynamic>[];
      return list
          .map((e) => OperatorMalfunctionReportModel.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw Exception('Impossibile caricare le segnalazioni');
  }

  /// Aggiorna lo stato di una segnalazione a 'preso_in_carico' o 'risolto'
  /// (OP.03 / UC-26). Su 'risolto' il backend rimette il mezzo disponibile.
  Future<void> updateMalfunctionStatus(String reportId, String status) async {
    final res = await _api.patch(
      '/operator/malfunction-reports/$reportId',
      body: {'status': status},
    );
    if (res.statusCode == 200) return;
    throw Exception(res.errorMessage ?? 'Aggiornamento stato non riuscito');
  }

  /// Forza il blocco remoto di un mezzo (OP.11 / UC-32).
  Future<void> blockVehicle(String vehicleId) async {
    final res = await _api.patch('/operator/vehicles/$vehicleId/block');
    if (res.statusCode == 200) return;
    if (res.statusCode == 404) throw Exception('Mezzo non trovato');
    throw Exception(res.errorMessage ?? 'Blocco non riuscito');
  }

  /// Sblocca un mezzo precedentemente bloccato (OP.11 / UC-32). Lo status
  /// finale ('disponibile' o 'manutenzione') e' deciso dal backend in base
  /// alle segnalazioni aperte.
  Future<void> unblockVehicle(String vehicleId) async {
    final res = await _api.patch('/operator/vehicles/$vehicleId/unblock');
    if (res.statusCode == 200) return;
    if (res.statusCode == 404) throw Exception('Mezzo non trovato o non bloccato');
    throw Exception(res.errorMessage ?? 'Sblocco non riuscito');
  }

  /// Recupera le zone parcheggio attive (OP.04 / UC-27).
  Future<List<ParkingZoneModel>> getParkingZones() async {
    final res = await _api.get('/operator/parking-zones');
    if (res.statusCode == 200) {
      final list = res.list ?? const <dynamic>[];
      return list
          .map((e) => ParkingZoneModel.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw Exception('Impossibile caricare le zone parcheggio');
  }

  /// Crea una nuova zona parcheggio (OP.04 / UC-27).
  Future<ParkingZoneModel> createParkingZone({
    required String name,
    required double lat,
    required double lng,
    required double radiusMeters,
    double bonusCredit = 0,
  }) async {
    final res = await _api.post('/operator/parking-zones', body: {
      'name': name,
      'lat': lat,
      'lng': lng,
      'radius_meters': radiusMeters,
      'bonus_credit': bonusCredit,
    });
    if (res.statusCode == 201) {
      return ParkingZoneModel.fromJson(res.map!);
    }
    throw Exception(res.errorMessage ?? 'Creazione zona non riuscita');
  }

  /// Elimina (disattiva) una zona parcheggio (OP.04 / UC-27).
  Future<void> deleteParkingZone(String zoneId) async {
    final res = await _api.delete('/operator/parking-zones/$zoneId');
    if (res.statusCode == 204) return;
    if (res.statusCode == 404) throw Exception('Zona non trovata');
    throw Exception(res.errorMessage ?? 'Eliminazione zona non riuscita');
  }
}
