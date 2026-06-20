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

  /// Schedula una notifica locale per la prenotazione.
  /// - Per prenotazioni immediate: avviso 3 min prima di [booking.expiresAt]
  ///   ("Prenotazione in scadenza").
  /// - Per prenotazioni anticipate (UT.19): avviso 3 min prima di
  ///   [booking.scheduledStart] ("È quasi ora di usare il mezzo!").
  Future<void> scheduleBookingExpiryNotification(
    BookingModel booking,
    String vehicleName,
  ) async {
    if (kIsWeb) return;
    await init();

    final now = DateTime.now();
    final String notifTitle;
    final String notifBody;
    final DateTime targetTime;

    if (booking.isScheduled && booking.scheduledStart != null) {
      // UT.19 — avvisa 3 min prima dell'orario programmato.
      targetTime = booking.scheduledStart!.toLocal();
      notifTitle = 'È quasi ora!';
      notifBody =
          'La tua $vehicleName prenotata è pronta tra pochi minuti.';
    } else {
      // Prenotazione immediata — avvisa 3 min prima della scadenza.
      targetTime = booking.expiresAt.toLocal();
      notifTitle = 'Prenotazione in scadenza';
      notifBody = 'La tua prenotazione sta scadendo.';
    }

    final alertTime = targetTime.subtract(const Duration(minutes: 3));

    // Se l'orario di avviso è già trascorso, non scheduliamo
    if (alertTime.isBefore(now)) {
      zlog(
        'Notifica scadenza saltata: mancano meno di 3 minuti a $targetTime',
        tag: 'Notifications',
      );
      return;
    }

    zlog(
      'Schedulo avviso per le $alertTime (riferimento: $targetTime) per veicolo $vehicleName',
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
        id: 100,
        title: notifTitle,
        body: notifBody,
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
