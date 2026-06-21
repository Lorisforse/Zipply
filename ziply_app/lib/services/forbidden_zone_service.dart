import 'package:http/http.dart' as http;
import 'package:ziply_app/data/models/forbidden_zone_model.dart';
import 'package:ziply_app/services/api_client.dart';

/// Servizio per il recupero delle zone vietate: chiamate REST verso
/// ziply_backend tramite [ApiClient]. L'endpoint è pubblico, quindi la chiamata
/// è non autenticata (nessun token, 401 non convertito in sessione scaduta).
class ForbiddenZoneService {
  ForbiddenZoneService({http.Client? client})
      : _api = ApiClient(client: client);

  final ApiClient _api;

  /// Recupera le zone vietate attive (is_active = true) dal backend.
  Future<List<ForbiddenZoneModel>> getForbiddenZones() async {
    final res = await _api.get('/forbidden-zones', authenticated: false);

    if (res.statusCode == 200) {
      final list = res.list ?? const [];
      return list
          .map((e) => ForbiddenZoneModel.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw Exception('Impossibile caricare le zone vietate');
  }
}
