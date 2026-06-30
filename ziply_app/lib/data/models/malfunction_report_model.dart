/// Segnalazione di malfunzionamento vista dall'operatore nella dashboard
/// (OP.03 / UC-26). Arricchita con i dati del mezzo coinvolto (QR, tipo,
/// posizione) restituiti dal backend.
class MalfunctionReportModel {
  final String id;
  final String vehicleId;
  final String vehicleQr;
  final String vehicleType;
  final double latitude;
  final double longitude;
  final String problemType;
  final String description;
  final String source; // 'utente' | 'sensore'
  final DateTime createdAt;
  final String status; // 'in_attesa' | 'preso_in_carico' | 'risolto'

  const MalfunctionReportModel({
    required this.id,
    required this.vehicleId,
    required this.vehicleQr,
    required this.vehicleType,
    required this.latitude,
    required this.longitude,
    required this.problemType,
    required this.description,
    required this.source,
    required this.createdAt,
    required this.status,
  });

  factory MalfunctionReportModel.fromJson(Map<String, dynamic> json) {
    return MalfunctionReportModel(
      id: json['id'] as String,
      vehicleId: (json['vehicle_id'] as String?) ?? '',
      vehicleQr: (json['vehicle_qr'] as String?) ?? '',
      vehicleType: (json['vehicle_type'] as String?) ?? '',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
      problemType: (json['problem_type'] as String?) ?? '',
      description: (json['description'] as String?) ?? '',
      source: (json['source'] as String?) ?? 'utente',
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '')?.toLocal() ??
              DateTime.now(),
      status: (json['status'] as String?) ?? 'in_attesa',
    );
  }
}
