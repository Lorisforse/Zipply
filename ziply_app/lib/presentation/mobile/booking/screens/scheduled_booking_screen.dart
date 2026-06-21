import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ziply_app/core/theme/app_colors.dart';
import 'package:ziply_app/data/models/booking_model.dart';
import 'package:ziply_app/data/models/vehicle_model.dart';
import 'package:ziply_app/services/booking_service.dart';
import 'package:ziply_app/services/api_exceptions.dart';

// ── Palette ─────────────────────────────────────────────────────────────────
const Color _kBg = AppColors.bg;
const Color _kSurface = AppColors.surface;
const Color _kBorder = AppColors.border;
const Color _kText = AppColors.text;
const Color _kDim = AppColors.dim;
const Color _kAccent = AppColors.accent;

/// UT.19 — Schermata di selezione data/ora e conferma della prenotazione
/// anticipata. Accessibile solo per bici e automobili elettriche.
/// Restituisce un [BookingModel] (con [BookingModel.isScheduled] == true)
/// quando la prenotazione è confermata, o null se l'utente annulla.
class ScheduledBookingScreen extends StatefulWidget {
  const ScheduledBookingScreen({super.key, required this.vehicle});

  final VehicleModel vehicle;

  @override
  State<ScheduledBookingScreen> createState() => _ScheduledBookingScreenState();
}

class _ScheduledBookingScreenState extends State<ScheduledBookingScreen> {
  final BookingService _bookingService = BookingService();

  DateTime? _selectedDateTime;
  bool _confirming = false;
  String? _error;

  // ── Vincoli temporali ─────────────────────────────────────────────────────

  DateTime get _minTime => DateTime.now().add(const Duration(minutes: 15));
  DateTime get _maxTime {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    return DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 23, 59);
  }

  // ── Pre-auth progressiva (formula client-side = server-side) ──────────────

  double _preAuthFor(DateTime scheduledStart) {
    final advanceHours =
        scheduledStart.difference(DateTime.now()).inMinutes / 60.0;
    final amount = widget.vehicle.hourlyRate * 0.5 * (1 + advanceHours / 24);
    return (amount * 100).roundToDouble() / 100;
  }

  // ── Selezione data e ora in sequenza ─────────────────────────────────────

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final firstDate = now;
    final tomorrow = now.add(const Duration(days: 1));
    final lastDate = DateTime(tomorrow.year, tomorrow.month, tomorrow.day);

    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDateTime ?? _minTime,
      firstDate: firstDate,
      lastDate: lastDate,
      builder: (ctx, child) => _themeWrapper(ctx, child),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selectedDateTime ?? _minTime),
      builder: (ctx, child) => _themeWrapper(ctx, child),
    );
    if (time == null || !mounted) return;

    final picked = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );

    setState(() {
      _error = null;
      if (picked.isBefore(_minTime)) {
        _error = 'Scegli un orario almeno 15 minuti nel futuro.';
        _selectedDateTime = null;
      } else if (picked.isAfter(_maxTime)) {
        _error = 'Non è possibile prenotare oltre la fine di domani (23:59).';
        _selectedDateTime = null;
      } else {
        _selectedDateTime = picked;
      }
    });
  }

  Widget _themeWrapper(BuildContext ctx, Widget? child) {
    return Theme(
      data: ThemeData.dark().copyWith(
        colorScheme: const ColorScheme.dark(
          primary: _kAccent,
          onPrimary: _kBg,
          surface: _kSurface,
          onSurface: _kText,
        ),
        dialogBackgroundColor: _kBg,
      ),
      child: child!,
    );
  }

  // ── Conferma prenotazione ─────────────────────────────────────────────────

  Future<void> _confirm() async {
    final dt = _selectedDateTime;
    if (dt == null) return;

    setState(() {
      _confirming = true;
      _error = null;
    });

    try {
      final booking = await _bookingService.createScheduledBooking(
        widget.vehicle.id,
        dt,
      );
      if (!mounted) return;
      Navigator.of(context).pop(booking);
    } on SessionExpiredException {
      if (!mounted) return;
      setState(() {
        _confirming = false;
        _error = 'Sessione scaduta, effettua di nuovo l\'accesso.';
      });
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _confirming = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final vehicle = widget.vehicle;
    final dt = _selectedDateTime;
    final preAuth = dt != null ? _preAuthFor(dt) : null;
    final rateText =
        '${(vehicle.hourlyRate / 60).toStringAsFixed(2).replaceAll('.', ',')} €/min';

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _kText),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Prenota in anticipo',
          style: GoogleFonts.barlowCondensed(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            color: _kText,
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Info mezzo
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _kSurface,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _kBorder),
                ),
                child: Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'MEZZO',
                          style: GoogleFonts.barlowCondensed(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.1,
                            color: _kDim,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          vehicle.type.isEmpty ? 'Mezzo' : vehicle.type,
                          style: GoogleFonts.barlowCondensed(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: _kText,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      rateText,
                      style: GoogleFonts.barlowCondensed(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: _kDim,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              Text(
                'ORARIO DI UTILIZZO',
                style: GoogleFonts.barlowCondensed(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.1,
                  color: _kDim,
                ),
              ),
              const SizedBox(height: 8),
              // Selettore data/ora
              GestureDetector(
                onTap: _confirming ? null : _pickDateTime,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                  decoration: BoxDecoration(
                    color: _kSurface,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: dt != null ? _kAccent : _kBorder,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.schedule_rounded,
                        size: 20,
                        color: dt != null ? _kAccent : _kDim,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        dt != null
                            ? _formatDateTime(dt)
                            : 'Seleziona data e ora',
                        style: GoogleFonts.barlowCondensed(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                          color: dt != null ? _kText : _kDim,
                        ),
                      ),
                      const Spacer(),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: _kDim,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Disponibile da oggi (tra 15 min) fino alla fine di domani (23:59).',
                style: GoogleFonts.barlow(fontSize: 12.5, color: _kDim),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.error_outline,
                        size: 15, color: AppColors.red),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _error!,
                        style: GoogleFonts.barlow(
                          fontSize: 13,
                          color: AppColors.red,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 28),
              // Box preautorizzazione (visibile solo quando la data è scelta)
              if (preAuth != null) ...[
                _PreAuthBox(preAuth: preAuth),
                const SizedBox(height: 28),
              ],
              const Spacer(),
              // Bottone conferma
              SizedBox(
                height: 52,
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (dt != null && !_confirming) ? _confirm : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kAccent,
                    foregroundColor: _kBg,
                    disabledBackgroundColor: _kSurface,
                    disabledForegroundColor: _kDim,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                      side: dt != null
                          ? BorderSide.none
                          : const BorderSide(color: _kBorder),
                    ),
                  ),
                  child: _confirming
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: _kBg,
                          ),
                        )
                      : Text(
                          'CONFERMA PRENOTAZIONE',
                          style: GoogleFonts.barlowCondensed(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    final local = dt.toLocal();
    final now = DateTime.now();
    final isToday = local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    final tomorrow = now.add(const Duration(days: 1));
    final isTomorrow = local.year == tomorrow.year &&
        local.month == tomorrow.month &&
        local.day == tomorrow.day;

    final timeStr =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    if (isToday) return 'Oggi alle $timeStr';
    if (isTomorrow) return 'Domani alle $timeStr';
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')} alle $timeStr';
  }
}

// ── Box preautorizzazione ────────────────────────────────────────────────────
class _PreAuthBox extends StatelessWidget {
  const _PreAuthBox({required this.preAuth});

  final double preAuth;

  @override
  Widget build(BuildContext context) {
    final amountStr = preAuth.toStringAsFixed(2).replaceAll('.', ',');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PREAUTORIZZAZIONE',
            style: GoogleFonts.barlowCondensed(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.1,
              color: _kDim,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '€ $amountStr',
                style: GoogleFonts.barlowCondensed(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: _kAccent,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '(mock — non addebitato)',
                style: GoogleFonts.barlow(fontSize: 12, color: _kDim),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Importo calcolato in base all\'anticipo. Verrà liberato al momento dell\'utilizzo.',
            style:
                GoogleFonts.barlow(fontSize: 12.5, height: 1.4, color: _kDim),
          ),
        ],
      ),
    );
  }
}
