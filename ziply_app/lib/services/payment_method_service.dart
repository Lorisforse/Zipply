import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:ziply_app/data/models/payment_method_model.dart';
import 'package:ziply_app/services/api_client.dart';

/// Servizio per la gestione dei metodi di pagamento (UT.14): chiamate REST
/// verso ziply_backend tramite [ApiClient] (base URL, token JWT, 401 → sessione
/// scaduta).
class PaymentMethodService {
  PaymentMethodService({http.Client? client, FlutterSecureStorage? storage})
      : _api = ApiClient(client: client, storage: storage);

  final ApiClient _api;

  /// Recupera i metodi di pagamento salvati (GET /payment-methods).
  Future<List<PaymentMethodModel>> getPaymentMethods() async {
    final res = await _api.get('/payment-methods');

    if (res.statusCode == 200) {
      final list = res.list ?? const [];
      return list
          .map((e) => PaymentMethodModel.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw Exception('Impossibile caricare i metodi di pagamento');
  }

  /// Salva una nuova carta (POST /payment-methods). Riceve solo le ultime 4
  /// cifre e la scadenza MM/YY: il numero completo e il CVV restano sul client.
  Future<PaymentMethodModel> addPaymentMethod({
    required String cardLastFour,
    required String cardExpiry,
    required bool isDefault,
  }) async {
    final res = await _api.post('/payment-methods', body: {
      'card_last_four': cardLastFour,
      'card_expiry': cardExpiry,
      'is_default': isDefault,
    });

    if (res.statusCode == 201) {
      return PaymentMethodModel.fromJson(res.map!);
    }
    throw Exception('Impossibile salvare la carta');
  }

  /// Elimina la carta [id] (DELETE /payment-methods/{id}).
  Future<void> deletePaymentMethod(String id) async {
    final res = await _api.delete('/payment-methods/$id');

    if (res.statusCode == 204) return;
    if (res.statusCode == 404) {
      throw Exception('Carta non trovata');
    }
    throw Exception('Impossibile eliminare la carta');
  }
}
