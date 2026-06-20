// Modello dati per la prenotazione multipla (UT.16): più prenotazioni create
// insieme sotto un identificativo di gruppo condiviso.
// Mappa la response di POST /bookings/multi del backend Ziply.

import 'package:ziply_app/data/models/booking_model.dart';

class MultiBookingModel {
  const MultiBookingModel({required this.groupId, required this.bookings});

  final String groupId;
  final List<BookingModel> bookings;

  /// Scadenza comune del gruppo (tutte le prenotazioni nascono insieme con la
  /// stessa scadenza di 15 minuti).
  DateTime? get expiresAt => bookings.isEmpty ? null : bookings.first.expiresAt;

  factory MultiBookingModel.fromJson(Map<String, dynamic> json) {
    final list = (json['bookings'] as List?) ?? const [];
    return MultiBookingModel(
      groupId: json['group_id'] as String,
      bookings: list
          .whereType<Map<String, dynamic>>()
          .map(BookingModel.fromJson)
          .toList(growable: false),
    );
  }
}
