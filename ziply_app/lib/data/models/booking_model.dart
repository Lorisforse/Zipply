// Modello dati per la prenotazione di un veicolo (UT.02).
// Mappa la response di POST /bookings del backend Ziply.

class BookingModel {
  const BookingModel({
    required this.id,
    required this.vehicleId,
    required this.expiresAt,
  });

  final String id;
  final String vehicleId;

  /// Istante di scadenza della prenotazione (UTC). Usato come riferimento
  /// temporale dal countdown della schermata di conferma.
  final DateTime expiresAt;

  factory BookingModel.fromJson(Map<String, dynamic> json) {
    return BookingModel(
      id: json['id'] as String,
      vehicleId: json['vehicle_id'] as String,
      expiresAt: DateTime.parse(json['expires_at'] as String),
    );
  }
}
