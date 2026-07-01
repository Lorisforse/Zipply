import 'package:latlong2/latlong.dart';

/// Centro di una zona parcheggio: coordinata + raggio in metri (OP.04 / UC-27).
class ParkingZoneCenter {
  final double lat;
  final double lng;
  final double radius;

  const ParkingZoneCenter({
    required this.lat,
    required this.lng,
    required this.radius,
  });

  factory ParkingZoneCenter.fromJson(Map<String, dynamic> json) {
    return ParkingZoneCenter(
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      radius: (json['radius'] as num).toDouble(),
    );
  }

  LatLng get latLng => LatLng(lat, lng);
}

/// Zona parcheggio designata (OP.04 / UC-27): cerchio con bonus credito.
class ParkingZoneModel {
  final String id;
  final String name;
  final ParkingZoneCenter center;
  final double bonusCredit;
  final bool isActive;

  const ParkingZoneModel({
    required this.id,
    required this.name,
    required this.center,
    required this.bonusCredit,
    required this.isActive,
  });

  factory ParkingZoneModel.fromJson(Map<String, dynamic> json) {
    return ParkingZoneModel(
      id: json['id'] as String,
      name: json['name'] as String,
      center: ParkingZoneCenter.fromJson(json['center'] as Map<String, dynamic>),
      bonusCredit: (json['bonus_credit'] as num).toDouble(),
      isActive: json['is_active'] as bool? ?? true,
    );
  }
}
