import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:ziply_app/data/models/booking_model.dart';
import 'package:ziply_app/data/models/ride_model.dart';
import 'package:ziply_app/data/models/vehicle_model.dart';
import 'package:ziply_app/presentation/mobile/booking/screens/scheduled_booking_screen.dart';
import 'package:ziply_app/presentation/mobile/map/widgets/vehicle_widgets.dart';
import 'package:ziply_app/services/booking_service.dart';
import 'package:ziply_app/services/discount_service.dart';
import 'package:ziply_app/services/ride_service.dart';
import 'package:ziply_app/services/subscription_service.dart';

// ── Palette (da Grafica/mappa-handoff) ─────────────────────────────────────
const Color _kBg      = Color(0xFF1A1A1A);
const Color _kSurface = Color(0xFF252525);
const Color _kBorder  = Color(0xFF333333);
const Color _kText    = Color(0xFFF5F5F5);
const Color _kDim     = Color(0xFF777777);
const Color _kAccent  = Color(0xFFF69659);
const Color _kGreen   = Color(0xFF5DCAA5);
const Color _kRed     = Color(0xFFE57373);

// UT.13 — Sblocco per prossimità abilitato solo entro questa distanza (metri).
const double _kUnlockRadiusMeters = 50;

/// Esito delle azioni della scheda mezzo restituito da [VehicleBottomSheet.show]:
/// [booking] se è stata creata una prenotazione, [ride] se il mezzo è stato
/// sbloccato direttamente, [error] in caso di fallimento.
class VehicleBookingResult {
  const VehicleBookingResult.success(BookingModel this.booking)
      : ride = null,
        error = null;
  const VehicleBookingResult.unlocked(RideModel this.ride)
      : booking = null,
        error = null;
  const VehicleBookingResult.failure(String this.error)
      : booking = null,
        ride = null;

  final BookingModel? booking;
  final RideModel? ride;
  final String? error;

  bool get isSuccess => booking != null;
  bool get isUnlocked => ride != null;
}

/// [MOBILE] UT.05 + UT.02 — Scheda mezzo e avvio prenotazione.
/// Bottom sheet aperto al tap su un marker: mostra tipo, batteria, tariffa e
/// distanza dall'utente, e consente di prenotare il mezzo. La chiamata a
/// POST /bookings è gestita qui (con loading sul pulsante); l'esito viene
/// restituito al chiamante via [Navigator.pop] come [VehicleBookingResult].
class VehicleBottomSheet extends StatefulWidget {
  const VehicleBottomSheet({
    super.key,
    required this.vehicle,
    this.userPosition,
    this.unlockQrCode,
  });

  final VehicleModel vehicle;

  /// Posizione utente corrente (può essere null se la localizzazione non è
  /// disponibile → la distanza viene mostrata come «—»).
  final LatLng? userPosition;

  /// Quando la scheda è aperta dopo la scansione del QR del mezzo, contiene il
  /// codice letto: lo sblocco è sempre abilitato (la scansione prova che sei
  /// davanti al mezzo) e avviene via QR anziché per prossimità.
  final String? unlockQrCode;

  /// Apre la scheda come modal bottom sheet: si chiude con swipe verso il
  /// basso o tap fuori (comportamento di default di [showModalBottomSheet]).
  /// Restituisce l'esito (prenotazione o sblocco), o null se l'utente la chiude.
  static Future<VehicleBookingResult?> show(
    BuildContext context,
    VehicleModel vehicle,
    LatLng? userPosition, {
    String? unlockQrCode,
  }) {
    return showModalBottomSheet<VehicleBookingResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x8C000000), // rgba(0,0,0,0.55)
      builder: (_) => VehicleBottomSheet(
        vehicle: vehicle,
        userPosition: userPosition,
        unlockQrCode: unlockQrCode,
      ),
    );
  }

  @override
  State<VehicleBottomSheet> createState() => _VehicleBottomSheetState();
}

class _VehicleBottomSheetState extends State<VehicleBottomSheet> {
  final BookingService _bookingService = BookingService();
  final RideService _rideService = RideService();
  final DiscountService _discountService = DiscountService();
  bool _isBooking = false;
  bool _isUnlocking = false;

  // UT.09 — Codice sconto inserito in conferma prenotazione.
  final TextEditingController _discountController = TextEditingController();
  bool _validatingDiscount = false;
  DiscountValidation? _validDiscount;
  String? _discountError;
  bool _showDiscountInput = false;

  // UT.22 — abbonamento attivo per la tipologia di questo mezzo.
  bool _subscriptionActive = false;

  @override
  void initState() {
    super.initState();
    _checkSubscription();
  }

  Future<void> _checkSubscription() async {
    try {
      final result = await SubscriptionService().fetchAll();
      if (!mounted) return;
      final hasActive = result.subscriptions.any(
        (s) => s.vehicleTypeName == widget.vehicle.type && s.isActive,
      );
      setState(() => _subscriptionActive = hasActive);
    } catch (_) {
      // Non bloccante: se fallisce si mostra la tariffa normale.
    }
  }

  @override
  void dispose() {
    _discountController.dispose();
    super.dispose();
  }

  /// Verifica lato backend il codice sconto inserito (UT.09), mostrando il
  /// feedback di validità/errore. La percentuale verificata viene poi inviata
  /// con la prenotazione.
  Future<void> _verifyDiscount() async {
    final code = _discountController.text.trim();
    if (code.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _validatingDiscount = true;
      _discountError = null;
      _validDiscount = null;
    });
    try {
      final validation = await _discountService.validate(code);
      if (!mounted) return;
      setState(() => _validDiscount = validation);
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() =>
          _discountError = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _validatingDiscount = false);
    }
  }

  /// True quando lo sblocco è possibile. Se la scheda è aperta da scansione QR
  /// è sempre possibile (la scansione prova la presenza davanti al mezzo);
  /// altrimenti serve essere entro 50 m (sblocco per prossimità).
  bool get _canUnlock {
    if (widget.unlockQrCode != null) return true;
    final from = widget.userPosition;
    if (from == null) return false;
    final meters = Geolocator.distanceBetween(
      from.latitude,
      from.longitude,
      widget.vehicle.latitude,
      widget.vehicle.longitude,
    );
    return meters <= _kUnlockRadiusMeters;
  }

  /// Avvia la prenotazione mostrando il loading sul pulsante, poi chiude la
  /// scheda restituendone l'esito al chiamante (la mappa).
  Future<void> _book() async {
    setState(() => _isBooking = true);
    final navigator = Navigator.of(context);

    // UT.09 — usa il codice verificato; in mancanza, il testo grezzo (il
    // backend rivalida e respinge i codici non validi con un messaggio chiaro).
    final discountCode =
        _validDiscount?.code ?? _discountController.text.trim();

    VehicleBookingResult result;
    try {
      final booking = await _bookingService.createBooking(
        widget.vehicle.id,
        discountCode: discountCode,
      );
      result = VehicleBookingResult.success(booking);
    } on Exception catch (e) {
      result = VehicleBookingResult.failure(
        e.toString().replaceFirst('Exception: ', ''),
      );
    }

    if (!mounted) return; // scheda già chiusa dall'utente durante la chiamata
    navigator.pop(result);
  }

  /// UT.19 — Apre la schermata di prenotazione anticipata e, al ritorno con
  /// una prenotazione confermata, chiude la scheda restituendo il risultato.
  Future<void> _bookScheduled() async {
    final navigator = Navigator.of(context);
    final booking = await Navigator.push<BookingModel>(
      context,
      MaterialPageRoute<BookingModel>(
        builder: (_) => ScheduledBookingScreen(vehicle: widget.vehicle),
      ),
    );
    if (booking == null || !mounted) return;
    navigator.pop(VehicleBookingResult.success(booking));
  }

  /// UT.13 — Sblocca direttamente il mezzo (senza prenotare): via QR se la
  /// scheda è stata aperta da scansione, altrimenti per prossimità. Poi chiude
  /// la scheda restituendo la corsa avviata al chiamante (la mappa).
  Future<void> _unlock() async {
    setState(() => _isUnlocking = true);
    final navigator = Navigator.of(context);

    final qrCode = widget.unlockQrCode;
    VehicleBookingResult result;
    try {
      final ride = qrCode != null
          ? await _rideService.unlockByQr(qrCode)
          : await _rideService.unlockByProximity(widget.vehicle.id);
      result = VehicleBookingResult.unlocked(ride);
    } on Exception catch (e) {
      result = VehicleBookingResult.failure(
        e.toString().replaceFirst('Exception: ', ''),
      );
    }

    if (!mounted) return;
    navigator.pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final vehicle = widget.vehicle;
    final busy = _isBooking || _isUnlocking;
    final title = vehicle.type.isEmpty ? 'Mezzo' : vehicle.type;
    final rateText =
        '${(vehicle.hourlyRate / 60).toStringAsFixed(2).replaceAll('.', ',')} €';
    final (distValue, distSecondary) =
        walkingLabels(widget.userPosition, vehicle.latitude, vehicle.longitude);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
        color: _kBg,
        border: Border(top: BorderSide(color: _kBorder)),
        boxShadow: [
          BoxShadow(
            color: Color(0x73000000), // rgba(0,0,0,0.45)
            blurRadius: 30,
            offset: Offset(0, -12),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle trascinabile (da handoff: 38×4, raggio 2).
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: _kBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Header: tile-glifo + tipo mezzo + badge batteria.
              Row(
                children: [
                  VehicleGlyphTile(kind: vehicle.kind),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Text(
                      title,
                      style: GoogleFonts.barlowCondensed(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: _kText,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  BatteryBadge(pct: vehicle.batteryLevel),
                ],
              ),
              const SizedBox(height: 18),
              Container(height: 1, color: _kBorder),
              const SizedBox(height: 18),
              // Metriche: tariffa e distanza.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _Metric(
                      label: 'TARIFFA',
                      value: _subscriptionActive ? 'GRATUITA' : rateText,
                      secondary: _subscriptionActive ? 'abbonamento attivo' : 'al minuto',
                      valueColor: _subscriptionActive ? _kGreen : null,
                    ),
                  ),
                  Expanded(
                    child: _Metric(
                      label: 'DISTANZA',
                      value: distValue,
                      secondary: distSecondary,
                    ),
                  ),
                ],
              ),
              // UT.22 — banner abbonamento attivo.
              if (_subscriptionActive) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: _kGreen.withOpacity(0.08),
                    border: Border.all(color: _kGreen.withOpacity(0.5)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.workspace_premium_outlined, size: 16, color: _kGreen),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Hai un abbonamento attivo per questa tipologia — il noleggio sarà gratuito.',
                          style: GoogleFonts.barlow(fontSize: 12.5, color: _kGreen, height: 1.3),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              // UT.13 — Sblocco + quadratino sconto affiancati.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: (_canUnlock && !busy) ? _unlock : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kAccent,
                          foregroundColor: _kBg,
                          disabledBackgroundColor: _kSurface,
                          disabledForegroundColor: _kDim,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                            side: _canUnlock
                                ? BorderSide.none
                                : const BorderSide(color: _kBorder),
                          ),
                        ),
                        child: _isUnlocking
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: _kBg,
                                ),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.lock_open_rounded,
                                    size: 20,
                                    color: _canUnlock ? _kBg : _kDim,
                                  ),
                                  const SizedBox(width: 9),
                                  Text(
                                    'SBLOCCA MEZZO',
                                    style: GoogleFonts.barlowCondensed(
                                      fontSize: 19,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1.2,
                                      color: _canUnlock ? _kBg : _kDim,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Quadratino sconto: apre il campo codice sconto (UT.09).
                  _IconSquare(
                    icon: Icons.local_offer_outlined,
                    size: 52,
                    enabled: !busy &&
                        !_showDiscountInput &&
                        _validDiscount == null,
                    onTap: () => setState(() => _showDiscountInput = true),
                  ),
                ],
              ),
              if (!_canUnlock) ...[
                const SizedBox(height: 6),
                Text(
                  'Avvicinati al mezzo (entro 50 m) per sbloccarlo, oppure usa «Scansiona QR» sulla mappa.',
                  style: GoogleFonts.barlow(
                    fontSize: 12.5,
                    height: 1.3,
                    color: _kDim,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              // UT.09 — Campo codice sconto (si espande al tap del quadratino).
              _DiscountField(
                controller: _discountController,
                validating: _validatingDiscount,
                valid: _validDiscount,
                error: _discountError,
                enabled: !busy,
                showInput: _showDiscountInput,
                onShowInput: () => setState(() => _showDiscountInput = true),
                onVerify: _verifyDiscount,
                onRemove: () {
                  setState(() {
                    _validDiscount = null;
                    _discountError = null;
                    _discountController.clear();
                    _showDiscountInput = false;
                  });
                },
                onChanged: () {
                  if (_validDiscount != null || _discountError != null) {
                    setState(() {
                      _validDiscount = null;
                      _discountError = null;
                    });
                  }
                },
              ),
              const SizedBox(height: 12),
              // UT.02 + UT.19 — Prenota + quadratino calendario affiancati.
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: OutlinedButton(
                        onPressed: busy ? null : _book,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _kAccent,
                          side: const BorderSide(color: _kAccent),
                          disabledForegroundColor: _kDim,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        child: _isBooking
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: _kAccent,
                                ),
                              )
                            : Text(
                                'PRENOTA',
                                style: GoogleFonts.barlowCondensed(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.5,
                                  color: _kAccent,
                                ),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Quadratino calendario: apre la prenotazione anticipata (UT.19).
                  // Abilitato solo per bici e auto; disabilitato per monopattini.
                  _IconSquare(
                    icon: Icons.calendar_month_outlined,
                    size: 46,
                    enabled: !busy &&
                        (widget.vehicle.kind == VehicleType.bike ||
                            widget.vehicle.kind == VehicleType.car),
                    onTap: _bookScheduled,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
}

// ── Blocco metrica: etichetta + valore + secondario ────────────────────────
class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, this.secondary, this.valueColor});

  final String label;
  final String value;
  final String? secondary;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.barlowCondensed(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 1,
            color: _kDim,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: GoogleFonts.barlowCondensed(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: valueColor ?? _kText,
          ),
        ),
        if (secondary != null) ...[
          const SizedBox(height: 4),
          Text(
            secondary!,
            style: GoogleFonts.barlow(fontSize: 12.5, color: _kDim),
          ),
        ],
      ],
    );
  }
}

// ── Campo codice sconto (UT.09) ────────────────────────────────────────────
// Invasivo al minimo: mostra solo un link "Aggiungi codice sconto" che,
// quando cliccato, si espande per mostrare l'input, per poi richiudersi
// in una singola riga di testo verde in caso di validazione positiva.
class _DiscountField extends StatelessWidget {
  const _DiscountField({
    required this.controller,
    required this.validating,
    required this.valid,
    required this.error,
    required this.enabled,
    required this.showInput,
    required this.onShowInput,
    required this.onVerify,
    required this.onRemove,
    required this.onChanged,
  });

  final TextEditingController controller;
  final bool validating;
  final DiscountValidation? valid;
  final String? error;
  final bool enabled;
  final bool showInput;
  final VoidCallback onShowInput;
  final VoidCallback onVerify;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  String _formatPercent(double p) {
    final s = p.toStringAsFixed(p.truncateToDouble() == p ? 0 : 1);
    return s.replaceAll('.', ',');
  }

  @override
  Widget build(BuildContext context) {
    final hasValid = valid != null;

    // 1. Stato: Codice sconto applicato con successo (Singola riga verde compatta)
    if (hasValid) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            const Icon(Icons.check_circle, size: 15, color: _kGreen),
            const SizedBox(width: 6),
            Text(
              'Sconto del ${_formatPercent(valid!.percentage)}% applicato (${valid!.code})',
              style: GoogleFonts.barlow(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _kGreen,
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: enabled ? onRemove : null,
              child: Text(
                'Rimuovi',
                style: GoogleFonts.barlow(
                  fontSize: 13,
                  color: _kRed,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // 2. Stato: Campo aperto per l'inserimento
    if (showInput) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: TextField(
                    controller: controller,
                    enabled: enabled,
                    onChanged: (_) => onChanged(),
                    onSubmitted: (_) => onVerify(),
                    textCapitalization: TextCapitalization.characters,
                    textInputAction: TextInputAction.done,
                    style: GoogleFonts.barlowCondensed(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                      color: _kText,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Codice sconto (es. ZIPLY10)',
                      hintStyle: GoogleFonts.barlow(fontSize: 12.5, color: _kDim),
                      filled: true,
                      fillColor: _kSurface,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 10),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: const BorderSide(color: _kBorder),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: const BorderSide(color: _kAccent),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 38,
                child: OutlinedButton(
                  onPressed: (enabled && !validating) ? onVerify : null,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _kAccent,
                    side: const BorderSide(color: _kBorder),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  child: validating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _kAccent,
                          ),
                        )
                      : Text(
                          'VERIFICA',
                          style: GoogleFonts.barlowCondensed(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: _kAccent,
                          ),
                        ),
                ),
              ),
            ],
          ),
          if (error != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.error_outline, size: 15, color: _kRed),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    error!,
                    style: GoogleFonts.barlow(fontSize: 12.5, color: _kRed),
                  ),
                ),
              ],
            ),
          ],
        ],
      );
    }

    // Stato di default: l'ingresso è il quadratino icona affiancato a SBLOCCA.
    return const SizedBox.shrink();
  }
}

// ── Quadratino icona (bottone compatto, affiancato ai pulsanti principali) ───
class _IconSquare extends StatelessWidget {
  const _IconSquare({
    required this.icon,
    required this.size,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final double size;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: _kSurface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: _kBorder),
        ),
        child: Icon(
          icon,
          size: 20,
          color: enabled ? _kDim : _kBorder,
        ),
      ),
    );
  }
}
