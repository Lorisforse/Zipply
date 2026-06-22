/// Tipologia di mezzo lato operatore, derivata dal nome del tipo restituito dal
/// backend. Usata per scegliere icona e filtri nella dashboard flotta (OP.01).
enum OperatorVehicleType { bike, scooter, car, unknown }

OperatorVehicleType vehicleTypeFromNome(String nome) {
  switch (nome) {
    case 'Bicicletta':
      return OperatorVehicleType.bike;
    case 'Monopattino elettrico':
      return OperatorVehicleType.scooter;
    case 'Automobile elettrica':
      return OperatorVehicleType.car;
    default:
      return OperatorVehicleType.unknown;
  }
}

/// Mezzo della flotta dal punto di vista dell'operatore: include lo stato
/// operativo completo (disponibile, prenotato, in_uso, manutenzione) e il
/// livello di carica, mostrati sulla mappa flotta in tempo reale (OP.01).
class OperatorVehicleModel {
  final String id;
  final String type; // nome esatto (es. 'Bicicletta')
  final OperatorVehicleType kind;
  final String qrCode;
  final double latitude;
  final double longitude;
  final int batteryLevel;
  final double tariffaAlMinuto;
  final String status; // 'disponibile' | 'prenotato' | 'in_uso' | 'manutenzione'

  const OperatorVehicleModel({
    required this.id,
    required this.type,
    required this.kind,
    required this.qrCode,
    required this.latitude,
    required this.longitude,
    required this.batteryLevel,
    required this.tariffaAlMinuto,
    required this.status,
  });

  factory OperatorVehicleModel.fromJson(Map<String, dynamic> json) {
    final nome = (json['type'] as String?) ?? '';
    return OperatorVehicleModel(
      id: json['id'] as String,
      type: nome,
      kind: vehicleTypeFromNome(nome),
      qrCode: (json['qr_code'] as String?) ?? '',
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      batteryLevel: (json['battery_level'] as num).toInt(),
      tariffaAlMinuto: (json['tariffa_al_minuto'] as num).toDouble(),
      status: json['status'] as String? ?? 'disponibile',
    );
  }
}
