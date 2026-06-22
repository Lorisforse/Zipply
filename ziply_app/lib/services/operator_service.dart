import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
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
}
