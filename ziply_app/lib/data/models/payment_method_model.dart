// Modello dati per il metodo di pagamento (UT.14).
// Mappa la response di GET/POST /payment-methods del backend Ziply: solo le
// ultime 4 cifre e la scadenza sono persistite (il PAN completo e il CVV non
// lasciano mai il client).

class PaymentMethodModel {
  const PaymentMethodModel({
    required this.id,
    required this.cardLastFour,
    required this.cardExpiry,
    required this.isDefault,
    required this.createdAt,
  });

  final String id;

  /// Ultime 4 cifre della carta (es. '4242').
  final String cardLastFour;

  /// Scadenza nel formato MM/YY (es. '12/28').
  final String cardExpiry;

  /// Indica se è la carta predefinita dell'utente.
  final bool isDefault;

  /// Istante di creazione (UTC).
  final DateTime createdAt;

  factory PaymentMethodModel.fromJson(Map<String, dynamic> json) {
    return PaymentMethodModel(
      id: json['id'] as String,
      cardLastFour: json['card_last_four'] as String,
      cardExpiry: json['card_expiry'] as String,
      isDefault: (json['is_default'] as bool?) ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
