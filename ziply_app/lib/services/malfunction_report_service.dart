import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:ziply_app/data/models/malfunction_report_model.dart';
import 'package:ziply_app/services/api_client.dart';

/// Servizio per la segnalazione di malfunzionamento (UT.11): chiamate REST verso
/// ziply_backend tramite [ApiClient] (base URL, token JWT, 401 → sessione scaduta).
class MalfunctionReportService {
  MalfunctionReportService({http.Client? client, FlutterSecureStorage? storage})
      : _api = ApiClient(client: client, storage: storage);

  final ApiClient _api;

  /// Invia una segnalazione di malfunzionamento.
  Future<MalfunctionReportModel> submitReport({
    required String rideId,
    required String problemType,
    required String description,
    required List<String> attachmentUrls,
  }) async {
    final res = await _api.post('/malfunction-reports', body: {
      'ride_id': rideId,
      'problem_type': problemType,
      'description': description,
      'attachment_urls': attachmentUrls,
    });

    if (res.statusCode == 201) {
      return MalfunctionReportModel.fromJson(res.map!);
    }
    throw Exception(res.errorMessage ?? 'Impossibile inviare la segnalazione');
  }
}
