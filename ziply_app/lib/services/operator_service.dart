import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:ziply_app/data/models/malfunction_report_model.dart';
import 'package:ziply_app/data/models/operator_vehicle_model.dart';
import 'package:ziply_app/services/api_client.dart';

/// Servizio dell'area operatore: chiamate REST verso ziply_backend per il
/// monitoraggio della flotta (OP.01). Usa [ApiClient] per token, timeout e
/// gestione uniforme degli errori di rete e del 401.
class OperatorService {
  OperatorService({http.Client? client, FlutterSecureStorage? storage})
      : _api = ApiClient(client: client, storage: storage);

  final ApiClient _api;

  /// Recupera tutti i mezzi della flotta (qualsiasi stato) per la mappa
  /// operatore. L'endpoint è riservato ai ruoli operatore/amministrazione.
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
  Future<List<MalfunctionReportModel>> getMalfunctionReports({String? status}) async {
    final query = (status != null && status.isNotEmpty) ? {'status': status} : null;
    final res = await _api.get('/operator/malfunction-reports', query: query);
    if (res.statusCode == 200) {
      final list = res.list ?? const <dynamic>[];
      return list
          .map((e) => MalfunctionReportModel.fromJson(e as Map<String, dynamic>))
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
}
