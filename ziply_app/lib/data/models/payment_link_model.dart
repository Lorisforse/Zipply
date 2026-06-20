// Modello dati per il link di pagamento (UT.23).
// Mappa la response di GET/POST /payment-links del backend Ziply.

class PaymentLinkModel {
  const PaymentLinkModel({
    required this.id,
    required this.rideId,
    required this.totalAmount,
    required this.participants,
    required this.amountPerHead,
    required this.validUntil,
    required this.status,
    this.link,
    this.prenotanteName,
  });

  final String id;
  final String rideId;
  final double totalAmount;
  final int participants;
  final double amountPerHead;
  final DateTime validUntil;
  final String status; // 'active' | 'expired' | 'paid'
  final String? link; // Il link condivisibile (es. ziply://payment-links/{id})
  final String? prenotanteName; // Nome del prenotante (es. 'Mario Rossi')

  factory PaymentLinkModel.fromJson(Map<String, dynamic> json) {
    return PaymentLinkModel(
      id: json['id'] as String,
      rideId: json['ride_id'] as String,
      totalAmount: (json['total_amount'] as num).toDouble(),
      participants: (json['participants'] as num).toInt(),
      amountPerHead: (json['amount_per_head'] as num).toDouble(),
      validUntil: DateTime.parse(json['valid_until'] as String),
      status: json['status'] as String,
      link: json['link'] as String?,
      prenotanteName: json['prenotante_name'] as String?,
    );
  }
}
