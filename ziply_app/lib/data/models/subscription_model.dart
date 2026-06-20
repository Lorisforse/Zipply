// Modelli dati per abbonamenti (UT.22).
// Mappano la response di GET /subscriptions del backend Ziply.

class VehicleTypeModel {
  const VehicleTypeModel({required this.id, required this.nome});

  final String id;
  final String nome;

  factory VehicleTypeModel.fromJson(Map<String, dynamic> json) => VehicleTypeModel(
        id: json['id'] as String,
        nome: json['nome'] as String,
      );
}

class SubscriptionModel {
  const SubscriptionModel({
    required this.id,
    required this.userId,
    required this.vehicleTypeId,
    required this.vehicleTypeName,
    required this.startDate,
    required this.endDate,
    required this.status,
  });

  final String id;
  final String userId;
  final String vehicleTypeId;
  final String vehicleTypeName;
  final DateTime startDate;
  final DateTime endDate;
  final String status; // 'active' | 'expired' | 'cancelled'

  bool get isActive => status == 'active' && endDate.isAfter(DateTime.now());

  factory SubscriptionModel.fromJson(Map<String, dynamic> json) => SubscriptionModel(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        vehicleTypeId: json['vehicle_type_id'] as String,
        vehicleTypeName: json['vehicle_type_name'] as String? ?? '',
        startDate: DateTime.parse(json['start_date'] as String),
        endDate: DateTime.parse(json['end_date'] as String),
        status: json['status'] as String,
      );
}
