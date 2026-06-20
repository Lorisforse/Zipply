// Modello dati per la prenotazione di un veicolo (UT.02 / UT.19).
// Mappa la response di POST /bookings e POST /bookings/scheduled.

class BookingModel {
  const BookingModel({
    required this.id,
    required this.vehicleId,
    required this.expiresAt,
    this.appliedPromotion,
    this.promotionPercentage,
    this.scheduledStart,
    this.preAuthAmount,
  });

  final String id;
  final String vehicleId;

  /// Istante di scadenza della prenotazione (UTC). Per le prenotazioni
  /// anticipate (UT.19) vale scheduledStart + 30 min.
  final DateTime expiresAt;

  /// Sconto automatico applicato dal sistema (UT.21).
  final String? appliedPromotion;
  final double? promotionPercentage;

  /// UT.19 — orario programmato per la prenotazione anticipata (null = immediata).
  final DateTime? scheduledStart;

  /// UT.19 — importo preautorizzato (mock) per la prenotazione anticipata.
  final double? preAuthAmount;

  bool get isScheduled => scheduledStart != null;

  factory BookingModel.fromJson(Map<String, dynamic> json) {
    final rawScheduled = json['scheduled_start'] as String?;
    return BookingModel(
      id: json['id'] as String,
      vehicleId: json['vehicle_id'] as String,
      expiresAt: DateTime.parse(json['expires_at'] as String),
      appliedPromotion: json['applied_promotion'] as String?,
      promotionPercentage: (json['promotion_percentage'] as num?)?.toDouble(),
      scheduledStart:
          rawScheduled != null ? DateTime.parse(rawScheduled) : null,
      preAuthAmount: (json['pre_auth_amount'] as num?)?.toDouble(),
    );
  }

  /// Costruisce un BookingModel dalla risposta annidata di POST /bookings/scheduled,
  /// che include il campo pre_auth_amount al livello superiore del JSON.
  factory BookingModel.fromScheduledJson(Map<String, dynamic> root) {
    final b = root['booking'] as Map<String, dynamic>;
    return BookingModel.fromJson({
      ...b,
      'pre_auth_amount': root['pre_auth_amount'],
    });
  }
}
