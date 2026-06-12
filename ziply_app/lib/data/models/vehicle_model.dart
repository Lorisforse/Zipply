// Modello dati per il veicolo (bici, monopattino, auto elettrica).
// Mappa la response di GET /vehicles del backend Ziply.

/// Tipo di mezzo, derivato dal nome italiano restituito dal backend
/// (vehicle_types.nome). Usato per differenziare i marker sulla mappa.
enum VehicleType { bike, scooter, car, unknown }

VehicleType _vehicleTypeFromNome(String nome) {
  switch (nome) {
    case 'Bicicletta':
      return VehicleType.bike;
    case 'Monopattino elettrico':
      return VehicleType.scooter;
    case 'Automobile elettrica':
      return VehicleType.car;
    default:
      return VehicleType.unknown;
  }
}

class VehicleModel {
  const VehicleModel({
    required this.id,
    required this.type,
    required this.kind,
    required this.latitude,
    required this.longitude,
    required this.batteryLevel,
    required this.hourlyRate,
  });

  final String id;
  final String type; // nome esatto dal DB (es. 'Bicicletta')
  final VehicleType kind;
  final double latitude;
  final double longitude;
  final int batteryLevel;
  final double hourlyRate;

  factory VehicleModel.fromJson(Map<String, dynamic> json) {
    final nome = (json['type'] as String?) ?? '';
    return VehicleModel(
      id: json['id'] as String,
      type: nome,
      kind: _vehicleTypeFromNome(nome),
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      batteryLevel: (json['battery_level'] as num).toInt(),
      hourlyRate: (json['hourly_rate'] as num).toDouble(),
    );
  }
}
