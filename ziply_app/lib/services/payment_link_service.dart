import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:ziply_app/data/models/payment_link_model.dart';
import 'package:ziply_app/services/api_client.dart';

/// Servizio per i link di pagamento e il credito (UT.23): chiamate REST verso
/// ziply_backend tramite [ApiClient] (base URL, token JWT, 401 → sessione
/// scaduta).
class PaymentLinkService {
  PaymentLinkService({http.Client? client, FlutterSecureStorage? storage})
      : _api = ApiClient(client: client, storage: storage);

  final ApiClient _api;

  /// Genera un link di pagamento per la corsa multipla [rideId].
  Future<PaymentLinkModel> generatePaymentLink(String rideId) async {
    final res = await _api.post('/rides/$rideId/payment-link');

    if (res.statusCode == 201) {
      return PaymentLinkModel.fromJson(res.map!);
    }
    throw Exception(
      res.errorMessage ?? 'Impossibile generare il link di pagamento',
    );
  }

  /// Recupera i dettagli del link di pagamento [linkId].
  Future<PaymentLinkModel> getPaymentLink(String linkId) async {
    final res = await _api.get('/payment-links/$linkId');

    if (res.statusCode == 200) {
      return PaymentLinkModel.fromJson(res.map!);
    }
    throw Exception(
      res.errorMessage ?? 'Impossibile recuperare il link di pagamento',
    );
  }

  /// Paga la quota del link di pagamento [linkId].
  Future<void> payPaymentLink(String linkId) async {
    final res = await _api.post('/payment-links/$linkId/pay');

    if (res.statusCode == 200) return;
    throw Exception(res.errorMessage ?? 'Pagamento della quota fallito');
  }

  /// Recupera il saldo crediti dell'utente.
  Future<double> getCreditBalance() async {
    final res = await _api.get('/users/credit-balance');

    if (res.statusCode == 200) {
      return (res.map!['credit_balance'] as num).toDouble();
    }
    throw Exception('Impossibile recuperare il saldo crediti');
  }
}
