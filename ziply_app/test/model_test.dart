import 'package:flutter_test/flutter_test.dart';
import 'package:ziply_app/data/models/multi_booking_model.dart';
import 'package:ziply_app/data/models/ride_model.dart';
import 'package:ziply_app/data/models/vehicle_model.dart';
import 'package:ziply_app/data/models/malfunction_report_model.dart';

void main() {
  group('Model Tests', () {
    test('RideModel fromJson test', () {
      final json = {
        'ride_id': 'r-123',
        'vehicle_id': 'v-456',
        'started_at': '2026-06-19T12:00:00Z',
        'status': 'attiva',
      };

      final model = RideModel.fromJson(json);

      expect(model.id, 'r-123');
      expect(model.vehicleId, 'v-456');
      expect(model.startedAt, DateTime.parse('2026-06-19T12:00:00Z'));
      expect(model.status, 'attiva');
    });

    test('VehicleModel fromJson test', () {
      final json = {
        'id': 'v-456',
        'type': 'Monopattino elettrico',
        'qr_code': 'ZP-SCOOT-001',
        'latitude': 45.4648,
        'longitude': 9.1850,
        'battery_level': 85,
        'hourly_rate': 12.0,
      };

      final model = VehicleModel.fromJson(json);

      expect(model.id, 'v-456');
      expect(model.type, 'Monopattino elettrico');
      expect(model.kind, VehicleType.scooter);
      expect(model.qrCode, 'ZP-SCOOT-001');
      expect(model.latitude, 45.4648);
      expect(model.longitude, 9.1850);
      expect(model.batteryLevel, 85);
      expect(model.hourlyRate, 12.0);
    });

    // UT.16 — prenotazione multipla
    test('MultiBookingModel fromJson test', () {
      final json = {
        'group_id': 'g-789',
        'bookings': [
          {
            'id': 'b-1',
            'vehicle_id': 'v-1',
            'expires_at': '2026-06-19T12:15:00Z',
          },
          {
            'id': 'b-2',
            'vehicle_id': 'v-2',
            'expires_at': '2026-06-19T12:15:00Z',
          },
        ],
      };

      final model = MultiBookingModel.fromJson(json);

      expect(model.groupId, 'g-789');
      expect(model.bookings.length, 2);
      expect(model.bookings.first.id, 'b-1');
      expect(model.bookings.first.vehicleId, 'v-1');
      expect(model.expiresAt, DateTime.parse('2026-06-19T12:15:00Z'));
    });

    test('MalfunctionReportModel fromJson test', () {
      final json = {
        'id': 'rep-123',
        'user_id': 'usr-456',
        'vehicle_id': 'veh-789',
        'ride_id': 'ride-abc',
        'problem_type': 'freni',
        'description': 'I freni fischiano',
        'attachment_urls': 'img1.png,img2.png',
        'created_at': '2026-06-20T10:00:00Z',
        'status': 'in_attesa',
      };

      final model = MalfunctionReportModel.fromJson(json);

      expect(model.id, 'rep-123');
      expect(model.userId, 'usr-456');
      expect(model.vehicleId, 'veh-789');
      expect(model.rideId, 'ride-abc');
      expect(model.problemType, 'freni');
      expect(model.description, 'I freni fischiano');
      expect(model.attachmentUrls, 'img1.png,img2.png');
      expect(model.createdAt, DateTime.parse('2026-06-20T10:00:00Z'));
      expect(model.status, 'in_attesa');
    });
  });
}
