import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:ziply_app/data/models/subscription_model.dart';
import 'package:ziply_app/services/api_client.dart';

typedef SubscriptionListResult = ({
  List<SubscriptionModel> subscriptions,
  List<VehicleTypeModel> vehicleTypes,
});

/// Servizio per gli abbonamenti (UT.22): chiamate REST verso ziply_backend
/// tramite [ApiClient] (base URL, token JWT, 401 → sessione scaduta).
class SubscriptionService {
  SubscriptionService({http.Client? client, FlutterSecureStorage? storage})
      : _api = ApiClient(client: client, storage: storage);

  final ApiClient _api;

  /// Recupera gli abbonamenti dell'utente e tutte le tipologie di mezzo disponibili.
  Future<SubscriptionListResult> fetchAll() async {
    final res = await _api.get('/subscriptions');

    if (res.statusCode == 200) {
      final body = res.map ?? const <String, dynamic>{};
      final rawSubs = body['subscriptions'] as List<dynamic>? ?? [];
      final rawTypes = body['vehicle_types'] as List<dynamic>? ?? [];
      return (
        subscriptions: rawSubs
            .map((e) => SubscriptionModel.fromJson(e as Map<String, dynamic>))
            .toList(),
        vehicleTypes: rawTypes
            .map((e) => VehicleTypeModel.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
    }

    throw Exception(res.errorMessage ?? 'Impossibile recuperare gli abbonamenti');
  }

  /// Sottoscrive un abbonamento per la tipologia e la durata indicate.
  Future<SubscriptionModel> subscribe({
    required String vehicleTypeId,
    required int durationMonths,
  }) async {
    final res = await _api.post('/subscriptions', body: {
      'vehicle_type_id': vehicleTypeId,
      'duration_months': durationMonths,
    });

    if (res.statusCode == 201) {
      return SubscriptionModel.fromJson(res.map!);
    }

    throw Exception(
      res.errorMessage ?? 'Impossibile sottoscrivere l\'abbonamento',
    );
  }
}
