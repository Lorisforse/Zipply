import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ziply_app/data/models/payment_link_model.dart';
import 'package:ziply_app/services/api_exceptions.dart';
import 'package:ziply_app/services/payment_link_service.dart';
import 'package:ziply_app/services/payment_method_service.dart';

const Color _kBg = Color(0xFF1A1A1A);
const Color _kSurface = Color(0xFF252525);
const Color _kBorder = Color(0xFF333333);
const Color _kText = Color(0xFFF5F5F5);
const Color _kDim = Color(0xFF777777);
const Color _kAccent = Color(0xFFF69659);
const Color _kGreen = Color(0xFF5DCAA5);

enum _ViewState { loading, success, expired, error }

class PaymentShareScreen extends StatefulWidget {
  const PaymentShareScreen({super.key, required this.linkId});

  final String linkId;

  static Future<void> show(BuildContext context, String linkId) {
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PaymentShareScreen(linkId: linkId)),
    );
  }

  @override
  State<PaymentShareScreen> createState() => _PaymentShareScreenState();
}

class _PaymentShareScreenState extends State<PaymentShareScreen> {
  final PaymentLinkService _linkService = PaymentLinkService();
  final PaymentMethodService _methodService = PaymentMethodService();

  _ViewState _viewState = _ViewState.loading;
  PaymentLinkModel? _paymentLink;
  String? _cardLastFour;
  String _errorMessage = '';
  bool _paying = false;

  Timer? _countdownTimer;
  int _secondsLeft = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _viewState = _ViewState.loading);
    try {
      final pl = await _linkService.getPaymentLink(widget.linkId);
      final cards = await _methodService.getPaymentMethods();

      String? lastFour;
      if (cards.isNotEmpty) {
        final card = cards.firstWhere((c) => c.isDefault, orElse: () => cards.first);
        lastFour = card.cardLastFour;
      }

      if (!mounted) return;

      _paymentLink = pl;
      _cardLastFour = lastFour;

      final now = DateTime.now();
      if (pl.status == 'expired' || now.isAfter(pl.validUntil)) {
        setState(() => _viewState = _ViewState.expired);
      } else {
        _secondsLeft = pl.validUntil.difference(now).inSeconds;
        _startTimer();
        setState(() => _viewState = _ViewState.success);
      }
    } on SessionExpiredException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: _kSurface,
          content: Text('Sessione scaduta. Effettua di nuovo il login.',
              style: GoogleFonts.barlow(color: _kText)),
        ),
      );
      Navigator.of(context).pop();
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
        _viewState = _ViewState.error;
      });
    }
  }

  void _startTimer() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_secondsLeft <= 0) {
        timer.cancel();
        setState(() => _viewState = _ViewState.expired);
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  String _formatDuration(int totalSecs) {
    final m = totalSecs ~/ 60;
    final s = totalSecs % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _onPay() async {
    if (_paying || _paymentLink == null) return;
    setState(() => _paying = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _linkService.payPaymentLink(widget.linkId);
      if (!mounted) return;
      setState(() => _paying = false);

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return AlertDialog(
            backgroundColor: _kSurface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            title: Text(
              'PAGAMENTO COMPLETATO',
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                color: _kGreen,
                fontSize: 22,
              ),
            ),
            content: Text(
              'Hai pagato con successo la tua quota di € ${_paymentLink!.amountPerHead.toStringAsFixed(2).replaceAll('.', ',')}.',
              style: GoogleFonts.barlow(fontSize: 14.5, color: _kText),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(); // dialog
                },
                child: Text(
                  'OK',
                  style: GoogleFonts.barlowCondensed(
                    color: _kAccent,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          );
        },
      );
      if (!mounted) return;
      Navigator.of(context).pop(); // torna indietro
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _paying = false);
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
      appBar: AppBar(
        backgroundColor: _kBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _kText),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'ZIPLY',
          style: GoogleFonts.barlowCondensed(
            fontSize: 23,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
            color: _kAccent,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    switch (_viewState) {
      case _ViewState.loading:
        return const Center(
          child: CircularProgressIndicator(color: _kAccent),
        );
      case _ViewState.expired:
        return _buildExpiredState();
      case _ViewState.error:
        return _buildErrorState();
      case _ViewState.success:
        return _buildSuccessState();
    }
  }

  Widget _buildExpiredState() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.timer_off_outlined, color: _kDim, size: 72),
          const SizedBox(height: 20),
          Text(
            'LINK DI PAGAMENTO SCADUTO',
            style: GoogleFonts.barlowCondensed(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: _kText,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'I link di pagamento hanno una validità di 10 minuti. Chiedi al prenotante della corsa di generare un nuovo codice.',
            textAlign: TextAlign.center,
            style: GoogleFonts.barlow(fontSize: 14.5, color: _kDim, height: 1.4),
          ),
          const SizedBox(height: 32),
          SizedBox(
            height: 50,
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: _kBorder),
                foregroundColor: _kText,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              ),
              child: Text(
                'TORNA ALLA MAPPA',
                style: GoogleFonts.barlowCondensed(
                  fontSize: 17.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: _kAccent, size: 72),
          const SizedBox(height: 20),
          Text(
            'ERRORE',
            style: GoogleFonts.barlowCondensed(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: _kText,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _errorMessage,
            textAlign: TextAlign.center,
            style: GoogleFonts.barlow(fontSize: 14.5, color: _kDim, height: 1.4),
          ),
          const SizedBox(height: 32),
          SizedBox(
            height: 50,
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _load,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kAccent,
                foregroundColor: _kBg,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              ),
              child: Text(
                'RIPROVA',
                style: GoogleFonts.barlowCondensed(
                  fontSize: 17.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessState() {
    final pl = _paymentLink!;
    final cardSaved = _cardLastFour != null;
    final String paymentMethodText = cardSaved ? '•••• $_cardLastFour' : 'Nessun metodo di pagamento salvato';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 24),
          Container(
            width: 72,
            height: 72,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _kSurface,
              shape: BoxShape.circle,
              border: Border.all(color: _kBorder),
            ),
            child: const Icon(Icons.payment, color: _kAccent, size: 30),
          ),
          const SizedBox(height: 20),
          Text(
            'PAGAMENTO QUOTA CORSA',
            style: GoogleFonts.barlowCondensed(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: _kText,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Dividi la spesa del viaggio con i tuoi amici',
            style: GoogleFonts.barlow(fontSize: 14.5, color: _kDim),
          ),
          const SizedBox(height: 32),
          Container(
            decoration: BoxDecoration(
              color: _kSurface,
              border: Border.all(color: _kBorder),
              borderRadius: BorderRadius.circular(6),
            ),
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                _DetailRow(label: 'Corsa di', value: pl.prenotanteName ?? '—'),
                const SizedBox(height: 12),
                _DetailRow(label: 'Partecipanti', value: '${pl.participants}'),
                const SizedBox(height: 12),
                _DetailRow(
                  label: 'Scade tra',
                  value: _formatDuration(_secondsLeft),
                  valueColor: _secondsLeft < 120 ? _kAccent : _kText,
                ),
                const SizedBox(height: 18),
                Container(height: 1, color: _kBorder),
                const SizedBox(height: 18),
                _DetailRow(label: 'Metodo di pagamento', value: paymentMethodText),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Quota da pagare',
                        style: GoogleFonts.barlow(fontSize: 14, color: _kDim)),
                    Text(
                      '€ ${pl.amountPerHead.toStringAsFixed(2).replaceAll('.', ',')}',
                      style: GoogleFonts.barlowCondensed(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: _kAccent,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Spacer(),
          SizedBox(
            height: 54,
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (!cardSaved || _paying) ? null : _onPay,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kAccent,
                foregroundColor: _kBg,
                disabledBackgroundColor: _kAccent.withOpacity(0.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                elevation: 0,
              ),
              child: _paying
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: _kBg),
                    )
                  : Text(
                      cardSaved
                          ? 'PAGA ORA € ${pl.amountPerHead.toStringAsFixed(2).replaceAll('.', ',')}'
                          : 'INSERISCI CARTA IN IMPOSTAZIONI',
                      style: GoogleFonts.barlowCondensed(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 18),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value, this.valueColor = _kText});
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
            fontSize: 15.5,
            fontWeight: FontWeight.w600,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}
