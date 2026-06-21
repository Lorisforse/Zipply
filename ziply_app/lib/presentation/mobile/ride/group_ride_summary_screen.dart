// [MOBILE] UT.16 — Schermata "Riepilogo fine noleggio di gruppo".
// Mirroring di [RideSummaryScreen]: stesso stile, layout e palette, ma per la
// corsa di gruppo (più mezzi, costo/CO2 aggregati, durata condivisa).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:ziply_app/core/theme/app_colors.dart';
import 'package:ziply_app/data/models/vehicle_model.dart';
import 'package:ziply_app/presentation/mobile/map/widgets/vehicle_widgets.dart';
import 'package:ziply_app/services/payment_method_service.dart';
import 'package:ziply_app/services/payment_link_service.dart';

const Color _kBg = AppColors.bg;
const Color _kSurface = AppColors.surface;
const Color _kSurface2 = AppColors.surface2;
const Color _kBorder = AppColors.border;
const Color _kText = AppColors.text;
const Color _kDim = AppColors.dim;
const Color _kAccent = AppColors.accent;
const Color _kGreen = AppColors.green;

/// [MOBILE] UT.16 — Riepilogo fine noleggio di gruppo.
class GroupRideSummaryScreen extends StatefulWidget {
  const GroupRideSummaryScreen({
    super.key,
    required this.groupId,
    required this.vehicles,
    required this.durationMinutes,
    required this.cost,
    required this.co2Grams,
    required this.rideIds,
    this.appliedDiscount = 0,
  });

  final String groupId;
  final List<VehicleModel> vehicles;
  final int durationMinutes;
  final double cost;
  final double co2Grams;
  final double appliedDiscount;
  final List<String> rideIds;

  /// Apre la schermata sostituendo la rotta corrente (come [RideSummaryScreen]),
  /// con la stessa transizione dissolvenza + scorrimento.
  static Future<void> show(
    BuildContext context, {
    required String groupId,
    required List<VehicleModel> vehicles,
    required int durationMinutes,
    required double cost,
    required double co2Grams,
    required List<String> rideIds,
    double appliedDiscount = 0,
  }) {
    return Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 420),
        reverseTransitionDuration: const Duration(milliseconds: 280),
        pageBuilder: (_, __, ___) => GroupRideSummaryScreen(
          groupId: groupId,
          vehicles: vehicles,
          durationMinutes: durationMinutes,
          cost: cost,
          co2Grams: co2Grams,
          rideIds: rideIds,
          appliedDiscount: appliedDiscount,
        ),
        transitionsBuilder: (context, animation, _, child) {
          final curved =
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.06),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  State<GroupRideSummaryScreen> createState() => _GroupRideSummaryScreenState();
}

class _GroupRideSummaryScreenState extends State<GroupRideSummaryScreen> {
  final PaymentMethodService _paymentService = PaymentMethodService();
  String? _cardLastFour;
  bool _generating = false;

  @override
  void initState() {
    super.initState();
    _loadPaymentMethod();
  }

  Future<void> _loadPaymentMethod() async {
    try {
      final methods = await _paymentService.getPaymentMethods();
      if (!mounted || methods.isEmpty) return;
      final card = methods.firstWhere(
        (m) => m.isDefault,
        orElse: () => methods.first,
      );
      setState(() => _cardLastFour = card.cardLastFour);
    } on Exception {
      // Dettaglio non essenziale: lasciamo "—".
    }
  }

  Future<void> _onGeneratePaymentLink() async {
    if (_generating) return;
    setState(() => _generating = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final plService = PaymentLinkService();
      final pl = await plService.generatePaymentLink(widget.rideIds.first);
      if (!mounted) return;
      setState(() => _generating = false);
      
      showDialog(
        context: context,
        builder: (context) {
          final shareUrl = pl.link ?? '';
          return AlertDialog(
            backgroundColor: _kSurface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            title: Text(
              'DIVIDI COSTO CORSA',
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                color: _kAccent,
                fontSize: 22,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Condividi questo link con i partecipanti per dividere il costo in parti uguali:',
                  style: GoogleFonts.barlow(fontSize: 14.5, color: _kText),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: _kSurface2,
                    border: Border.all(color: _kBorder),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          shareUrl,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.barlow(
                            fontSize: 14,
                            color: _kText,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.copy, color: _kAccent, size: 20),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: shareUrl));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: _kSurface2,
                              content: Text(
                                'Link copiato negli appunti!',
                                style: GoogleFonts.barlow(color: _kText),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _DialogDetailRow(label: 'Quota a testa', value: '€ ${pl.amountPerHead.toStringAsFixed(2).replaceAll('.', ',')}'),
                const SizedBox(height: 8),
                _DialogDetailRow(label: 'Partecipanti', value: '${pl.participants}'),
                const SizedBox(height: 8),
                const _DialogDetailRow(label: 'Scadenza link', value: '10 minuti'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  SharePlus.instance.share(
                    ShareParams(
                      text: 'Ciao! Puoi pagare la tua quota del noleggio di gruppo Ziply usando questo link: $shareUrl',
                    ),
                  );
                },
                child: Text(
                  'CONDIVIDI',
                  style: GoogleFonts.barlowCondensed(
                    color: _kAccent,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  'CHIUDI',
                  style: GoogleFonts.barlowCondensed(
                    color: _kDim,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _generating = false);
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: _kSurface,
          content: Text(
            e.toString().replaceFirst('Exception: ', ''),
            style: GoogleFonts.barlow(color: _kText),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 8, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'ZIPLY',
                    style: GoogleFonts.barlowCondensed(
                      fontSize: 23,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: _kAccent,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close, color: _kDim),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Column(
                  children: [
                    const SizedBox(height: 24),
                    const _SuccessBadge(),
                    const SizedBox(height: 26),
                    Text(
                      'NOLEGGIO DI GRUPPO COMPLETATO',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.barlowCondensed(
                        fontSize: 31,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        height: 1,
                        color: _kText,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Grazie per aver viaggiato con Ziply. Ecco il riepilogo del noleggio di gruppo.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.barlow(
                        fontSize: 14.5,
                        height: 1.5,
                        color: _kDim,
                      ),
                    ),
                    const SizedBox(height: 26),
                    _SummaryCard(
                      groupId: widget.groupId,
                      vehicles: widget.vehicles,
                      durationMinutes: widget.durationMinutes,
                      cost: widget.cost,
                      co2Grams: widget.co2Grams,
                      appliedDiscount: widget.appliedDiscount,
                      cardLastFour: _cardLastFour,
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
            Container(
              decoration: const BoxDecoration(
                color: _kBg,
                border: Border(top: BorderSide(color: _kBorder)),
              ),
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 50,
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _generating ? null : _onGeneratePaymentLink,
                      icon: _generating
                          ? const SizedBox(
                              width: 19,
                              height: 19,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: _kBg,
                              ),
                            )
                          : const Icon(Icons.groups_2, size: 19, color: _kBg),
                      label: Text(
                        'DIVIDI COSTO CORSA',
                        style: GoogleFonts.barlowCondensed(
                          fontSize: 17.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                          color: _kBg,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kAccent,
                        foregroundColor: _kBg,
                        disabledBackgroundColor: _kAccent.withOpacity(0.6),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 50,
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.map_outlined, size: 19, color: _kText),
                      label: Text(
                        'TORNA ALLA MAPPA',
                        style: GoogleFonts.barlowCondensed(
                          fontSize: 17.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                          color: _kText,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: _kBorder),
                        foregroundColor: _kText,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Badge ✓ (doppio anello, verde successo) ────────────────────────────────
class _SuccessBadge extends StatelessWidget {
  const _SuccessBadge();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 96,
      height: 96,
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _kSurface,
                border: Border.all(color: _kBorder),
              ),
            ),
          ),
          Positioned.fill(
            child: Container(
              margin: const EdgeInsets.all(13),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _kGreen.withOpacity(0.08),
                border: Border.all(
                  color: _kGreen.withOpacity(0.9),
                  width: 2,
                ),
              ),
              child: const Icon(Icons.check, color: _kGreen, size: 34),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Card riepilogo noleggio di gruppo ──────────────────────────────────────
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.groupId,
    required this.vehicles,
    required this.durationMinutes,
    required this.cost,
    required this.co2Grams,
    required this.appliedDiscount,
    required this.cardLastFour,
  });

  final String groupId;
  final List<VehicleModel> vehicles;
  final int durationMinutes;
  final double cost;
  final double co2Grams;
  final double appliedDiscount;
  final String? cardLastFour;

  String _shortCode() {
    final id = groupId.replaceAll('-', '');
    final head = id.length >= 8 ? id.substring(0, 8) : id;
    return 'ZP-${head.toUpperCase()}';
  }

  String _euro(double value) =>
      '€ ${value.toStringAsFixed(2).replaceAll('.', ',')}';

  @override
  Widget build(BuildContext context) {
    final n = vehicles.length;
    final payment = cardLastFour == null ? '—' : '•••• $cardLastFour';

    return Container(
      decoration: BoxDecoration(
        color: _kSurface,
        border: Border.all(color: _kBorder),
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
      child: Column(
        children: [
          // Riga intestazione gruppo.
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _kSurface2,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: _kBorder, width: 0.5),
                ),
                child: const Icon(Icons.groups_2, color: _kAccent, size: 24),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Noleggio di gruppo',
                      style: GoogleFonts.barlowCondensed(
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                        color: _kText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$n ${n == 1 ? 'mezzo' : 'mezzi'} · concluso',
                      style: GoogleFonts.barlow(fontSize: 12.5, color: _kDim),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const _StatusBadge(),
            ],
          ),
          const SizedBox(height: 14),
          // Glifi dei mezzi del gruppo.
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final v in vehicles)
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _kSurface2,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: _kBorder, width: 0.5),
                    ),
                    child: vehicleGlyph(v.kind, size: 19),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(height: 1, color: _kBorder),
          const SizedBox(height: 14),
          _DetailRow(label: 'Codice gruppo', value: _shortCode()),
          const SizedBox(height: 10),
          _DetailRow(label: 'Mezzi', value: '$n'),
          const SizedBox(height: 10),
          _DetailRow(label: 'Durata', value: '$durationMinutes min'),
          const SizedBox(height: 10),
          _DetailRow(
            label: 'CO₂ risparmiata',
            value: '${co2Grams.toStringAsFixed(0)} g',
            valueColor: _kGreen,
          ),
          const SizedBox(height: 10),
          _DetailRow(label: 'Metodo di pagamento', value: payment),
          const SizedBox(height: 14),
          Container(height: 1, color: _kBorder),
          const SizedBox(height: 14),
          if (appliedDiscount > 0) ...[
            _DetailRow(label: 'Subtotale', value: _euro(cost + appliedDiscount)),
            const SizedBox(height: 10),
            _DetailRow(
              label: 'Sconto',
              value: '− ${_euro(appliedDiscount)}',
              valueColor: _kGreen,
            ),
            const SizedBox(height: 10),
          ],
          _DetailRow(
            label: 'Costo totale',
            value: _euro(cost),
            valueColor: _kAccent,
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(7, 4, 7, 3),
      decoration: BoxDecoration(
        color: _kGreen.withOpacity(0.10),
        border: Border.all(color: _kGreen.withOpacity(0.55)),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(
        'COMPLETATA',
        style: GoogleFonts.barlowCondensed(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
          height: 1,
          color: _kGreen,
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.valueColor = _kText,
  });

  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: GoogleFonts.barlow(fontSize: 13.5, color: _kDim)),
        Text(
          value,
          style: GoogleFonts.barlowCondensed(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

class _DialogDetailRow extends StatelessWidget {
  const _DialogDetailRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: GoogleFonts.barlow(fontSize: 13, color: _kDim)),
        Text(
          value,
          style: GoogleFonts.barlowCondensed(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: _kText,
          ),
        ),
      ],
    );
  }
}
