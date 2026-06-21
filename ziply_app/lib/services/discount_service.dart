import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:ziply_app/services/api_client.dart';

/// Esito della validazione di un codice sconto (UT.09): codice normalizzato e
/// percentuale di sconto restituiti dal backend.
class DiscountValidation {
  const DiscountValidation({required this.code, required this.percentage});

  final String code;

  /// Percentuale di sconto (es. 10 = 10%).
  final double percentage;
}

/// Servizio per la validazione dei codici sconto (POST /discount-codes/validate)
/// tramite [ApiClient] (base URL, token JWT, 401 → sessione scaduta).
class DiscountService {
  DiscountService({http.Client? client, FlutterSecureStorage? storage})
      : _api = ApiClient(client: client, storage: storage);

  final ApiClient _api;

  /// Valida [code] lato backend. Restituisce la percentuale di sconto se il
  /// codice è utilizzabile; altrimenti una Exception con il messaggio del
  /// backend (404 inesistente, 422 scaduto/esaurito) pronto per la UI.
  Future<DiscountValidation> validate(String code) async {
    final res = await _api.post(
      '/discount-codes/validate',
      body: {'code': code.trim()},
    );

    if (res.statusCode == 200) {
      final body = res.map;
      return DiscountValidation(
        code: (body?['code'] as String?)?.trim().toUpperCase() ??
            code.trim().toUpperCase(),
        percentage: (body?['percentage'] as num?)?.toDouble() ?? 0,
      );
    }

    throw Exception(res.errorMessage ?? 'Codice sconto non valido');
  }
}
