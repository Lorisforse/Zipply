// Modello dati per la corsa avviata allo sblocco del mezzo (UT.13).
// Mappa la response di POST /rides/unlock del backend Ziply.

class RideModel {
  const RideModel({
    required this.id,
    required this.vehicleId,
    required this.startedAt,
  });

  final String id;
  final String vehicleId;

  /// Istante di avvio della corsa (UTC). Riferimento temporale per il timer e
  /// il costo aggiornato in tempo reale nella schermata di noleggio attivo.
  final DateTime startedAt;

  factory RideModel.fromJson(Map<String, dynamic> json) {
    return RideModel(
      id: json['ride_id'] as String,
      vehicleId: json['vehicle_id'] as String,
      startedAt: DateTime.parse(json['started_at'] as String),
    );
  }
}
