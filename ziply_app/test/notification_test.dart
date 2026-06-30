import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:ziply_app/data/models/booking_model.dart';
import 'package:ziply_app/services/notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel =
      MethodChannel('dexterous.com/flutter/local_notifications');

  final List<MethodCall> log = <MethodCall>[];

  setUp(() {
    log.clear();

    // Inizializza l'istanza platform per evitare il LateInitializationError nei test unitari su desktop
    FlutterLocalNotificationsPlatform.instance =
        AndroidFlutterLocalNotificationsPlugin();

    // Intercetta le chiamate al canale nativo di flutter_local_notifications
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      log.add(methodCall);
      if (methodCall.method == 'initialize') {
        return true;
      }
      if (methodCall.method == 'zonedSchedule') {
        return null;
      }
      if (methodCall.method == 'cancel') {
        return null;
      }
      return null;
    });
  });

  group('NotificationService Tests', () {
    test('scheduleBookingExpiryNotification schedules at expiresAt - 3 min',
        () async {
      final now = DateTime.now();
      // Prenotazione con scadenza tra 15 minuti
      final expiresAt = now.add(const Duration(minutes: 15));
      final booking = BookingModel(
        id: 'b-123',
        vehicleId: 'v-456',
        expiresAt: expiresAt,
      );

      // Inizializza fusi orari
      tz.initializeTimeZones();

      await NotificationService.instance.init();
      await NotificationService.instance.scheduleBookingExpiryNotification(
        booking,
        'Bici elettrica',
      );

      // Verifica che la notifica sia stata schedulata
      final zonedScheduleCalls =
          log.where((call) => call.method == 'zonedSchedule').toList();
      expect(zonedScheduleCalls.length, 1);

      final Map<dynamic, dynamic> args =
          zonedScheduleCalls.first.arguments as Map<dynamic, dynamic>;

      expect(args['id'], 100);
      expect(args['title'], 'Prenotazione in scadenza');
      expect(args['body'], 'La tua prenotazione sta scadendo.');
      expect(args['payload'], 'b-123');
    });

    test(
        'scheduleBookingExpiryNotification does not schedule if expiresAt is too close',
        () async {
      final now = DateTime.now();
      // Scadenza tra solo 2 minuti (tempo inferiore ai 3 minuti di preavviso)
      final expiresAt = now.add(const Duration(minutes: 2));
      final booking = BookingModel(
        id: 'b-123',
        vehicleId: 'v-456',
        expiresAt: expiresAt,
      );

      tz.initializeTimeZones();
      await NotificationService.instance.init();
      await NotificationService.instance.scheduleBookingExpiryNotification(
        booking,
        'Bici elettrica',
      );

      // Nessuna notifica deve essere schedulata
      final zonedScheduleCalls =
          log.where((call) => call.method == 'zonedSchedule').toList();
      expect(zonedScheduleCalls.isEmpty, true);
    });

    test('cancelNotification calls channel to cancel with correct ID',
        () async {
      tz.initializeTimeZones();
      await NotificationService.instance.init();
      await NotificationService.instance.cancelNotification(100);

      final cancelCalls = log.where((call) => call.method == 'cancel').toList();
      expect(cancelCalls.length, 1);

      final arg = cancelCalls.first.arguments;
      if (arg is Map) {
        expect(arg['id'], 100);
      } else {
        expect(arg, 100);
      }
    });
  });
}
