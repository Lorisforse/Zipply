import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:ziply_app/core/utils/app_logger.dart';
import 'package:ziply_app/data/models/booking_model.dart';

/// Servizio per la gestione delle notifiche locali di scadenza della prenotazione (UT.20).
class NotificationService {
  NotificationService._internal();

  /// Istanza singleton globale.
  static final NotificationService instance = NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// Inizializza il plugin delle notifiche e carica i fusi orari.
  Future<void> init() async {
    if (_initialized || kIsWeb) return;

    // Inizializza i fusi orari necessari alla schedulazione temporale
    tz.initializeTimeZones();

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsDarwin,
    );

    await _notificationsPlugin.initialize(settings: initializationSettings);

    // Su Android 13+ richiede esplicitamente i permessi di notifica
    if (Platform.isAndroid) {
      final androidImpl =
          _notificationsPlugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidImpl?.requestNotificationsPermission();
      // Su Android 13+ (targetSdk 33+) SCHEDULE_EXACT_ALARM è negato di
      // default: senza questa richiesta zonedSchedule in modalità esatta
      // lancerebbe "exact_alarms_not_permitted" e la notifica non partirebbe.
      await androidImpl?.requestExactAlarmsPermission();
    }

    _initialized = true;
    zlog('NotificationService inizializzato con successo',
        tag: 'Notifications');
  }

  /// Schedula una notifica locale che avvisa della scadenza della prenotazione.
  /// La notifica viene schedulata a 3 minuti prima di [booking.expiresAt].
  /// Se mancano meno di 3 minuti alla scadenza, la schedulazione viene saltata.
  Future<void> scheduleBookingExpiryNotification(
    BookingModel booking,
    String vehicleName,
  ) async {
    if (kIsWeb) return;
    await init();

    // Normalizziamo expiresAt in orario locale per un confronto corretto con
    // DateTime.now() (che è sempre locale). Il backend può restituire un
    // timestamp UTC (es. "2026-06-20T10:10:00Z") e senza .toLocal() il
    // confronto potrebbe saltare la schedulazione.
    final expiresLocal = booking.expiresAt.toLocal();
    final now = DateTime.now();
    final alertTime = expiresLocal.subtract(const Duration(minutes: 3));

    // Se l'orario di avviso è già trascorso, non scheduliamo
    if (alertTime.isBefore(now)) {
      zlog(
        'Notifica scadenza saltata: mancano meno di 3 minuti a $expiresLocal',
        tag: 'Notifications',
      );
      return;
    }

    zlog(
      'Schedulo avviso scadenza per le $alertTime (scadenza: $expiresLocal) per veicolo $vehicleName',
      tag: 'Notifications',
    );

    // Rimuoviamo eventuali notifiche residue per evitare duplicazioni
    await cancelNotification(100);

    final tzAlertTime = tz.TZDateTime.from(alertTime, tz.local);

    // Se gli allarmi esatti non sono concessi (Android 13+ li nega di
    // default), ripieghiamo su una schedulazione inesatta: per un avviso a
    // 3 minuti dalla scadenza una piccola tolleranza è accettabile ed evita
    // l'eccezione "exact_alarms_not_permitted".
    final canExact = await _notificationsPlugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.canScheduleExactNotifications() ??
        true;
    final scheduleMode = canExact
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'booking_expiry_channel',
      'Scadenza Prenotazione',
      channelDescription: 'Avvisi prima della scadenza della prenotazione',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
      presentBadge: true,
    );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    try {
      await _notificationsPlugin.zonedSchedule(
        id: 100, // ID fisso per notifica prenotazione
        title: 'Prenotazione in scadenza',
        body: 'La tua prenotazione sta scadendo.',
        scheduledDate: tzAlertTime,
        notificationDetails: details,
        androidScheduleMode: scheduleMode,
        payload: booking.id,
      );
    } catch (e) {
      // Un fallimento qui non deve restare silenzioso: la chiamata dal
      // chiamante è fire-and-forget, quindi senza log non sapremmo perché
      // la notifica non parte.
      zlog(
        'Schedulazione notifica scadenza fallita: $e',
        tag: 'Notifications',
      );
    }
  }

  /// Annulla una notifica schedulata (es. in caso di sblocco anticipato o cancellazione).
  Future<void> cancelNotification(int id) async {
    if (kIsWeb) return;
    await _notificationsPlugin.cancel(id: id);
    zlog('Notifica con ID $id cancellata', tag: 'Notifications');
  }
}
