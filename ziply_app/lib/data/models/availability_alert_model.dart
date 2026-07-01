/// Avviso di anomalia mostrato nel pannello operatore (OP.02 / OP.07):
/// batteria scarica, movimento illecito o scarsita' mezzi in un'area di
/// servizio. Restituito da GET /operator/availability-alerts, e' un log di
/// sola lettura (nessuno stato di risoluzione, UC-25).
class AvailabilityAlertModel {
  final String id;
  final String type; // 'scarsita' | 'batteria' | 'movimento'
  final String? serviceAreaId;
  final String? vehicleId;
  final int? availableCount;
  final String message;
  final DateTime createdAt;

  const AvailabilityAlertModel({
    required this.id,
    required this.type,
    this.serviceAreaId,
    this.vehicleId,
    this.availableCount,
    required this.message,
    required this.createdAt,
  });

  factory AvailabilityAlertModel.fromJson(Map<String, dynamic> json) {
    return AvailabilityAlertModel(
      id: json['id'] as String,
      type: (json['type'] as String?) ?? 'scarsita',
      serviceAreaId: json['service_area_id'] as String?,
      vehicleId: json['vehicle_id'] as String?,
      availableCount: (json['available_count'] as num?)?.toInt(),
      message: (json['message'] as String?) ?? '',
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '')?.toLocal() ??
              DateTime.now(),
    );
  }
}
