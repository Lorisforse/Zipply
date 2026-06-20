// Modello dati per la corsa avviata allo sblocco del mezzo (UT.13).
// Mappa la response di POST /rides/unlock del backend Ziply.

class RideModel {
  const RideModel({
    required this.id,
    required this.vehicleId,
    required this.startedAt,
    this.status = 'attiva',
  });

  final String id;
  final String vehicleId;

  /// Istante di avvio della corsa (UTC). Riferimento temporale per il timer e
  /// il costo aggiornato in tempo reale nella schermata di noleggio attivo.
  final DateTime startedAt;

  final String status;

  factory RideModel.fromJson(Map<String, dynamic> json) {
    return RideModel(
      id: json['ride_id'] as String,
      vehicleId: json['vehicle_id'] as String,
      startedAt: DateTime.parse(json['started_at'] as String),
      status: json['status'] as String? ?? 'attiva',
    );
  }

  RideModel copyWith({
    String? id,
    String? vehicleId,
    DateTime? startedAt,
    String? status,
  }) {
    return RideModel(
      id: id ?? this.id,
      vehicleId: vehicleId ?? this.vehicleId,
      startedAt: startedAt ?? this.startedAt,
      status: status ?? this.status,
    );
  }
}

/// Riepilogo server-autoritativo restituito da POST /rides/{id}/end: durata,
/// costo (già al netto dello sconto), CO2 risparmiata e importo scontato (UT.09).
/// [subscriptionApplied] è true quando il costo è azzerato da un abbonamento (UT.22).
class RideEndSummary {
  const RideEndSummary({
    required this.durationMinutes,
    required this.totalCost,
    required this.co2SavedGrams,
    required this.appliedDiscount,
    this.subscriptionApplied = false,
  });

  final int durationMinutes;

  /// Costo addebitato, già al netto dell'eventuale sconto.
  final double totalCost;
  final double co2SavedGrams;

  /// Importo scontato (0 se nessuno sconto). Costo lordo = totalCost + questo.
  final double appliedDiscount;

  /// True se il costo è stato azzerato da un abbonamento attivo (UT.22).
  final bool subscriptionApplied;

  factory RideEndSummary.fromJson(Map<String, dynamic> json) {
    return RideEndSummary(
      durationMinutes: (json['duration_minutes'] as num?)?.toInt() ?? 0,
      totalCost: (json['total_cost'] as num?)?.toDouble() ?? 0,
      co2SavedGrams: (json['co2_saved'] as num?)?.toDouble() ?? 0,
      appliedDiscount: (json['applied_discount'] as num?)?.toDouble() ?? 0,
      subscriptionApplied: (json['subscription_applied'] as bool?) ?? false,
    );
  }
}
