import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ziply_app/core/theme/app_colors.dart';
import 'package:ziply_app/core/theme/app_text_styles.dart';
import 'package:ziply_app/data/models/payment_method_model.dart';
import 'package:ziply_app/presentation/mobile/auth/login_screen.dart';
import 'package:ziply_app/services/api_exceptions.dart';
import 'package:ziply_app/services/auth_service.dart';
import 'package:ziply_app/services/payment_method_service.dart';

// Palette (alias di AppColors).
const Color _kBg      = AppColors.bg;
const Color _kSurface = AppColors.surface;
const Color _kBorder  = AppColors.border;
const Color _kText    = AppColors.text;
const Color _kDim     = AppColors.dim;
const Color _kAccent  = AppColors.accent;

// Stili di testo (wrapper sugli helper condivisi).
TextStyle _cond({double size = 14, FontWeight w = FontWeight.w700, Color c = _kText, double ls = 0}) =>
    appCond(size: size, w: w, c: c, ls: ls);

TextStyle _body({double size = 15, FontWeight w = FontWeight.w400, Color c = _kText}) =>
    appBody(size: size, w: w, c: c);

/// Stato della vista lista, allineato a [_ViewState] della MapScreen.
enum _ViewState { loading, error, success }

/// [MOBILE] UT.14 — Metodi di pagamento.
/// Mostra le carte salvate (GET /payment-methods), consente di aggiungerne una
/// (POST /payment-methods) e di eliminarle (DELETE /payment-methods/{id}).
class PaymentMethodsScreen extends StatefulWidget {
  const PaymentMethodsScreen({super.key});

  @override
  State<PaymentMethodsScreen> createState() => _PaymentMethodsScreenState();
}

class _PaymentMethodsScreenState extends State<PaymentMethodsScreen> {
  final PaymentMethodService _service = PaymentMethodService();
  final AuthService _authService = AuthService();

  _ViewState _state = _ViewState.loading;
  String _errorMessage = '';
  List<PaymentMethodModel> _methods = const [];
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Carica le carte salvate, gestendo loading, errore e sessione scaduta.
  Future<void> _load() async {
    setState(() => _state = _ViewState.loading);
    try {
      final methods = await _service.getPaymentMethods();
      if (!mounted) return;
      setState(() {
        _methods = methods;
        _state = _ViewState.success;
      });
    } on SessionExpiredException {
      await _handleSessionExpired();
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
        _state = _ViewState.error;
      });
    }
  }

  /// Apre il form di aggiunta carta; se va a buon fine ricarica la lista.
  Future<void> _onAddCard() async {
    final result = await _AddCardSheet.show(context);
    if (result == null || !mounted) return;

    if (result.isSuccess) {
      await _load();
    } else {
      _showMessage(result.error!);
    }
  }

  /// Elimina la carta dopo conferma, poi ricarica la lista.
  Future<void> _onDeleteCard(PaymentMethodModel method) async {
    if (_deleting) return;
    final confirmed = await _confirmDelete(method);
    if (confirmed != true || !mounted) return;

    _deleting = true;
    try {
      await _service.deletePaymentMethod(method.id);
      if (!mounted) return;
      await _load();
    } on SessionExpiredException {
      await _handleSessionExpired();
    } on Exception catch (e) {
      if (!mounted) return;
      _showMessage(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      _deleting = false;
    }
  }

  /// Dialog di conferma prima di eliminare una carta.
  Future<bool?> _confirmDelete(PaymentMethodModel method) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: Text(
          'Eliminare la carta?',
          style: _cond(size: 22, c: _kText),
        ),
        content: Text(
          'La carta •••• ${method.cardLastFour} verrà rimossa dai tuoi metodi di pagamento.',
          style: _body(size: 14, c: _kDim),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('ANNULLA',
                style: _cond(size: 16, w: FontWeight.w700, c: _kDim, ls: 0.5)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('SÌ, ELIMINA',
                style: _cond(size: 16, w: FontWeight.w700, c: _kAccent, ls: 0.5)),
          ),
        ],
      ),
    );
  }

  /// Token assente/scaduto (401): pulisce il token, avvisa e torna al login.
  Future<void> _handleSessionExpired() async {
    await _authService.logout();
    if (!mounted) return;
    _showMessage('Sessione scaduta, effettua di nuovo l\'accesso');
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: _kSurface,
        content: Text(message, style: _body(size: 14, c: _kText)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: SafeArea(
        child: Column(
          children: [
            _Header(onBack: () => Navigator.of(context).maybePop()),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
      bottomNavigationBar: _state == _ViewState.success
          ? SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _onAddCard,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kAccent,
                      foregroundColor: _kBg,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4)),
                    ),
                    child: Text('AGGIUNGI CARTA',
                        style: _cond(size: 19, ls: 1.5, c: _kBg)),
                  ),
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case _ViewState.loading:
        return const Center(
          child: CircularProgressIndicator(color: _kAccent, strokeWidth: 2.5),
        );
      case _ViewState.error:
        return _ErrorView(message: _errorMessage, onRetry: _load);
      case _ViewState.success:
        if (_methods.isEmpty) return const _EmptyView();
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
          itemCount: _methods.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, i) => _CardTile(
            method: _methods[i],
            onDelete: () => _onDeleteCard(_methods[i]),
          ),
        );
    }
  }
}

// ── Header con back + titolo ─────────────────────────────────────────────────
class _Header extends StatelessWidget {
  const _Header({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: _kBg,
      padding: const EdgeInsets.fromLTRB(8, 8, 18, 12),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back, color: _kText, size: 22),
            splashRadius: 22,
          ),
          const SizedBox(width: 2),
          Text(
            'METODI DI PAGAMENTO',
            style: _cond(size: 22, ls: 1, c: _kText),
          ),
        ],
      ),
    );
  }
}

// ── Tile di una carta salvata ────────────────────────────────────────────────
class _CardTile extends StatelessWidget {
  const _CardTile({required this.method, required this.onDelete});

  final PaymentMethodModel method;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _kBorder),
      ),
      child: Row(
        children: [
          const Icon(Icons.credit_card, color: _kAccent, size: 26),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('•••• ${method.cardLastFour}',
                        style: _cond(size: 20, ls: 1, c: _kText)),
                    if (method.isDefault) ...[
                      const SizedBox(width: 10),
                      Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: _kAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text('PREDEFINITA',
                            style: _cond(
                                size: 11, w: FontWeight.w600, c: _kAccent, ls: 0.8)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text('Scade ${method.cardExpiry}',
                    style: _body(size: 13, c: _kDim)),
              ],
            ),
          ),
          IconButton(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline, color: _kDim, size: 22),
            splashRadius: 22,
          ),
        ],
      ),
    );
  }
}

// ── Stato vuoto ──────────────────────────────────────────────────────────────
class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.credit_card_off_outlined, color: _kDim, size: 48),
          const SizedBox(height: 14),
          Text('Nessuna carta salvata',
              style: _cond(size: 20, c: _kText)),
          const SizedBox(height: 6),
          Text('Aggiungi una carta per pagare le tue corse',
              textAlign: TextAlign.center,
              style: _body(size: 14, c: _kDim)),
        ],
      ),
    );
  }
}

// ── Vista errore con retry ───────────────────────────────────────────────────
class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: _kDim, size: 48),
            const SizedBox(height: 14),
            Text(message.isEmpty ? 'Qualcosa è andato storto' : message,
                textAlign: TextAlign.center, style: _body(size: 15, c: _kText)),
            const SizedBox(height: 18),
            OutlinedButton(
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(
                foregroundColor: _kAccent,
                side: const BorderSide(color: _kBorder),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4)),
              ),
              child: Text('RIPROVA',
                  style: _cond(size: 16, w: FontWeight.w600, c: _kAccent, ls: 0.6)),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Form di aggiunta carta (modal bottom sheet).
// ─────────────────────────────────────────────────────────────────────────────

/// Esito dell'aggiunta carta restituito da [_AddCardSheet.show]:
/// [success] true se la POST è andata a buon fine, altrimenti [error]
/// contiene il messaggio pronto per la UI.
class _AddCardResult {
  const _AddCardResult.success() : error = null;
  const _AddCardResult.failure(String this.error);

  final String? error;

  bool get isSuccess => error == null;
}

class _AddCardSheet extends StatefulWidget {
  const _AddCardSheet();

  /// Apre il form come modal bottom sheet. Restituisce l'esito, o null se
  /// l'utente lo chiude senza confermare.
  static Future<_AddCardResult?> show(BuildContext context) {
    return showModalBottomSheet<_AddCardResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x8C000000),
      builder: (_) => const _AddCardSheet(),
    );
  }

  @override
  State<_AddCardSheet> createState() => _AddCardSheetState();
}

class _AddCardSheetState extends State<_AddCardSheet> {
  final PaymentMethodService _service = PaymentMethodService();

  final _number = TextEditingController();
  final _expiry = TextEditingController();
  final _cvv = TextEditingController();
  bool _isDefault = false;

  bool _saving = false;
  Map<String, String?> _errors = {};

  @override
  void dispose() {
    _number.dispose();
    _expiry.dispose();
    _cvv.dispose();
    super.dispose();
  }

  void _clearError(String key) {
    if (_errors.containsKey(key)) {
      setState(() => _errors = {..._errors, key: null});
    }
  }

  /// Valida i campi lato client: il numero deve avere 16 cifre, la scadenza
  /// deve essere MM/YY valida e non passata, il CVV 3-4 cifre. Solo le ultime
  /// 4 cifre e la scadenza vengono inviate al backend.
  Future<void> _submit() async {
    final digits = _number.text.replaceAll(RegExp(r'\s'), '');
    final e = <String, String?>{};

    if (digits.length != 16) {
      e['number'] = 'Inserisci le 16 cifre della carta';
    }
    if (!_expiryValid(_expiry.text)) {
      e['expiry'] = 'Scadenza non valida (MM/YY)';
    }
    if (!RegExp(r'^[0-9]{3,4}$').hasMatch(_cvv.text)) {
      e['cvv'] = 'CVV non valido';
    }

    setState(() => _errors = e);
    if (e.isNotEmpty) return;

    setState(() => _saving = true);
    final navigator = Navigator.of(context);

    _AddCardResult result;
    try {
      await _service.addPaymentMethod(
        cardLastFour: digits.substring(12),
        cardExpiry: _expiry.text,
        isDefault: _isDefault,
      );
      result = const _AddCardResult.success();
    } on Exception catch (err) {
      result = _AddCardResult.failure(
        err.toString().replaceFirst('Exception: ', ''),
      );
    }

    if (!mounted) return;
    navigator.pop(result);
  }

  /// MM/YY con mese 01-12 e scadenza non antecedente al mese corrente.
  bool _expiryValid(String s) {
    final m = RegExp(r'^(0[1-9]|1[0-2])/([0-9]{2})$').firstMatch(s);
    if (m == null) return false;
    final month = int.parse(m.group(1)!);
    final year = 2000 + int.parse(m.group(2)!);
    final now = DateTime.now();
    final lastDay = DateTime(year, month + 1, 0);
    return !lastDay.isBefore(DateTime(now.year, now.month, 1));
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: _kBg,
        border: Border(top: BorderSide(color: _kBorder)),
        boxShadow: [
          BoxShadow(
            color: Color(0x73000000),
            blurRadius: 30,
            offset: Offset(0, -12),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(18, 8, 18, 24 + bottomInset),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: _kBorder,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text('NUOVA CARTA', style: _cond(size: 22, ls: 0.5, c: _kText)),
                const SizedBox(height: 18),

                _Field(
                  label: 'Numero carta',
                  controller: _number,
                  placeholder: '1234 5678 9012 3456',
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(16),
                    _CardNumberFormatter(),
                  ],
                  error: _errors['number'],
                  onChanged: (_) => _clearError('number'),
                ),
                const SizedBox(height: 14),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _Field(
                        label: 'Scadenza',
                        controller: _expiry,
                        placeholder: 'MM/YY',
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9/]')),
                          LengthLimitingTextInputFormatter(5),
                          _ExpiryFormatter(),
                        ],
                        error: _errors['expiry'],
                        onChanged: (_) => _clearError('expiry'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _Field(
                        label: 'CVV',
                        controller: _cvv,
                        placeholder: '123',
                        obscure: true,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(4),
                        ],
                        error: _errors['cvv'],
                        onChanged: (_) => _clearError('cvv'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Carta predefinita.
                InkWell(
                  onTap: () => setState(() => _isDefault = !_isDefault),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 22,
                          height: 22,
                          child: Checkbox(
                            value: _isDefault,
                            onChanged: (v) =>
                                setState(() => _isDefault = v ?? false),
                            activeColor: _kAccent,
                            checkColor: _kBg,
                            side: const BorderSide(color: _kDim),
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text('Imposta come predefinita',
                            style: _body(size: 14, c: _kText)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kAccent,
                      foregroundColor: _kBg,
                      disabledBackgroundColor: _kAccent,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4)),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5, color: _kBg),
                          )
                        : Text('SALVA CARTA',
                            style: _cond(size: 19, ls: 1.5, c: _kBg)),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Il CVV viene usato solo per la verifica e non viene salvato.',
                  textAlign: TextAlign.center,
                  style: _body(size: 12, c: _kDim),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Campo di testo etichettato (allineato a quello di LoginScreen) ───────────
class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.placeholder,
    this.obscure = false,
    this.keyboardType,
    this.inputFormatters,
    this.error,
    this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final String? placeholder;
  final bool obscure;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final String? error;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final hasErr = error != null && error!.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: _cond(
              size: 13, w: FontWeight.w600, c: hasErr ? _kAccent : _kDim, ls: 1.2),
        ),
        const SizedBox(height: 6),
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: _kSurface,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: hasErr ? _kAccent : Colors.transparent),
          ),
          child: Center(
            child: TextField(
              controller: controller,
              obscureText: obscure,
              keyboardType: keyboardType,
              inputFormatters: inputFormatters,
              onChanged: onChanged,
              style: _body(size: 15, c: _kText),
              cursorColor: _kAccent,
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: placeholder,
                hintStyle: _body(size: 15, c: _kDim),
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ),
        if (hasErr) ...[
          const SizedBox(height: 5),
          Text(error!, style: _body(size: 12, c: _kAccent)),
        ],
      ],
    );
  }
}

// ── Formatter: raggruppa il numero carta in blocchi da 4 cifre ───────────────
class _CardNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'\s'), '');
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && i % 4 == 0) buffer.write(' ');
      buffer.write(digits[i]);
    }
    final text = buffer.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

// ── Formatter: inserisce automaticamente la barra in MM/YY ───────────────────
class _ExpiryFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    final text = digits.length >= 3
        ? '${digits.substring(0, 2)}/${digits.substring(2)}'
        : digits;
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
