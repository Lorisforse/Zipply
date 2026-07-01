// Modello dati per la segnalazione di malfunzionamento (UT.11).
// Mappa la response di POST /malfunction-reports del backend Ziply.

class MalfunctionReportModel {
  const MalfunctionReportModel({
    required this.id,
    required this.userId,
    required this.vehicleId,
    required this.rideId,
    required this.problemType,
    required this.description,
    required this.attachmentUrls,
    required this.createdAt,
    required this.status,
  });

  final String id;
  final String userId;
  final String vehicleId;
  final String rideId;
  final String problemType;
  final String description;
  final String attachmentUrls;
  final DateTime createdAt;
  final String status; // 'in_attesa' | 'preso_in_carico' | 'risolto'

  factory MalfunctionReportModel.fromJson(Map<String, dynamic> json) {
    return MalfunctionReportModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      vehicleId: json['vehicle_id'] as String,
      rideId: json['ride_id'] as String,
      problemType: json['problem_type'] as String,
      description: json['description'] as String? ?? '',
      attachmentUrls: json['attachment_urls'] as String? ?? '',
      createdAt: DateTime.parse(json['created_at'] as String),
      status: json['status'] as String,
    );
  }
}
