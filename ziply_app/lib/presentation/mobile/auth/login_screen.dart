import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:ziply_app/core/theme/app_colors.dart';
import 'package:ziply_app/core/theme/app_text_styles.dart';
import 'package:ziply_app/presentation/mobile/map/map_screen.dart';
import 'package:ziply_app/services/auth_service.dart';

// Palette (alias di AppColors).
const Color _kBg = AppColors.bg;
const Color _kSurface = AppColors.surface;
const Color _kBorder = AppColors.border;
const Color _kText = AppColors.text;
const Color _kDim = AppColors.dim;
const Color _kAccent = AppColors.accent;

// Stili di testo (wrapper sugli helper condivisi).
TextStyle _cond({double size = 14, FontWeight w = FontWeight.w700, Color c = _kText, double ls = 0}) =>
    appCond(size: size, w: w, c: c, ls: ls);

TextStyle _body({double size = 15, FontWeight w = FontWeight.w400, Color c = _kText}) =>
    appBody(size: size, w: w, c: c);

// ─────────────────────────────────────────────────────────────────────────────
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLogin = true;
  bool _showPass = false;
  bool _showPassConf = false; // fix #4 – toggle conferma password

  final _nome = TextEditingController();
  final _cognome = TextEditingController();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _passConf = TextEditingController(); // fix #4 – conferma password

  final AuthService _authService = AuthService();
  bool _isLoading = false;
  String? _apiError;

  Map<String, String?> _errors = {};

  @override
  void dispose() {
    _nome.dispose();
    _cognome.dispose();
    _email.dispose();
    _pass.dispose();
    _passConf.dispose();
    super.dispose();
  }

  void _switchMode(bool login) {
    if (_isLogin == login || _isLoading) return;
    setState(() {
      _isLogin = login;
      _errors = {};
      _apiError = null;
      _showPass = false;
      _showPassConf = false;
    });
  }

  bool _emailValid(String s) =>
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(s);

  Future<void> _submit() async {
    final e = <String, String?>{};
    if (!_isLogin) {
      if (_nome.text.trim().isEmpty) e['nome'] = '!';
      if (_cognome.text.trim().isEmpty) e['cognome'] = '!';
    }
    if (_email.text.trim().isEmpty) {
      e['email'] = 'Inserisci la tua email';
    } else if (!_emailValid(_email.text)) {
      e['email'] = 'Email non valida';
    }

    if (_pass.text.isEmpty) {
      e['pass'] = 'Inserisci la password';
    } else if (_pass.text.length < 8) {
      e['pass'] = 'Almeno 8 caratteri';
    }

    // fix #4 – validazione conferma password
    if (!_isLogin) {
      if (_passConf.text.isEmpty) {
        e['passConf'] = 'Conferma la password';
      } else if (_passConf.text != _pass.text) {
        e['passConf'] = 'Le password non coincidono';
      }
    }

    setState(() {
      _errors = e;
      _apiError = null;
    });
    if (e.isNotEmpty) return;

    setState(() => _isLoading = true);
    try {
      final data = _isLogin
          ? await _authService.login(_email.text.trim(), _pass.text)
          : await _authService.register(
              _nome.text.trim(),
              _cognome.text.trim(),
              _email.text.trim(),
              _pass.text,
            );
      await _authService.saveToken(data['token'] as String);
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MapScreen()),
        (route) => false,
      );
    } on Exception catch (err) {
      debugPrint('auth failed: $err');
      if (!mounted) return;
      setState(
          () => _apiError = err.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _clearError(String key) {
    if (_errors.containsKey(key))
      setState(() => _errors = {..._errors, key: null});
  }

  // ── eye button helper ─────────────────────────────────────────────────────
  Widget _eyeBtn(bool visible, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 0, 4),
          child: Icon(
            visible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
            size: 20,
            color: _kDim,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    // fix #1 – hero proporzionale all'altezza schermo
    final screenH = MediaQuery.of(context).size.height;
    // fix 4b – con la tastiera aperta l'hero si ritrae per non coprire i campi.
    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    final fullHeroHeight = screenH * 0.37;
    final heroHeight = keyboardOpen ? screenH * 0.12 : fullHeroHeight;

    return Scaffold(
      backgroundColor: _kBg,
      // fix #2 – ridimensiona lo scaffold quando appare la tastiera
      resizeToAvoidBottomInset: true,
      body: Column(
        children: [
          // ── HERO (fix 4b – si ritrae con la tastiera aperta) ─────────────
          // L'hero è sempre dimensionato a piena altezza ma viene clippato dal
          // contenitore che si restringe (ancorato in alto): così niente
          // overflow del RenderFlex e l'illustrazione scompare gradualmente
          // mentre il wordmark resta visibile.
          ClipRect(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              height: heroHeight,
              child: OverflowBox(
                minHeight: 0,
                maxHeight: fullHeroHeight,
                alignment: Alignment.topCenter,
                child: SizedBox(
                  height: fullHeroHeight,
                  child: const _FullHero(),
                ),
              ),
            ),
          ),

          // ── TAB BAR (fix #3 – fuori dallo scroll, sempre visibile) ───────
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
            child: Row(
              children: [
                _Tab(
                    label: 'Accedi',
                    active: _isLogin,
                    onTap: () => _switchMode(true)),
                _Tab(
                    label: 'Registrati',
                    active: !_isLogin,
                    onTap: () => _switchMode(false)),
              ],
            ),
          ),

          // ── FORM (fix #2 – l'Expanded + SingleChildScrollView gestisce
          //          la tastiera: il contenuto scrolla invece di comprimersi) ──
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // fix #5 – spaziatura tra TabBar e primo campo
                  const SizedBox(height: 16),

                  // nome + cognome (solo registrazione)
                  if (!_isLogin) ...[
                    Row(
                      children: [
                        Expanded(
                          child: _Field(
                            label: 'Nome',
                            controller: _nome,
                            placeholder: 'Mario',
                            error: _errors['nome'],
                            onChanged: (_) => _clearError('nome'),
                            autoComplete: 'given-name',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _Field(
                            label: 'Cognome',
                            controller: _cognome,
                            placeholder: 'Rossi',
                            error: _errors['cognome'],
                            onChanged: (_) => _clearError('cognome'),
                            autoComplete: 'family-name',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                  ],

                  // email
                  _Field(
                    label: 'Email',
                    controller: _email,
                    placeholder: 'nome@email.it',
                    keyboardType: TextInputType.emailAddress,
                    autoComplete: 'email',
                    error: _errors['email'],
                    onChanged: (_) => _clearError('email'),
                  ),
                  const SizedBox(height: 14),

                  // password
                  _Field(
                    label: 'Password',
                    controller: _pass,
                    placeholder:
                        _isLogin ? 'La tua password' : 'Almeno 8 caratteri',
                    obscure: !_showPass,
                    autoComplete:
                        _isLogin ? 'current-password' : 'new-password',
                    error: _errors['pass'],
                    onChanged: (_) => _clearError('pass'),
                    trailing: _eyeBtn(_showPass,
                        () => setState(() => _showPass = !_showPass)),
                  ),

                  // fix #4 – campo conferma password (solo registrazione)
                  if (!_isLogin) ...[
                    const SizedBox(height: 14),
                    _Field(
                      label: 'Conferma password',
                      controller: _passConf,
                      placeholder: 'Ripeti la password',
                      obscure: !_showPassConf,
                      autoComplete: 'new-password',
                      error: _errors['passConf'],
                      onChanged: (_) => _clearError('passConf'),
                      trailing: _eyeBtn(
                        _showPassConf,
                        () => setState(() => _showPassConf = !_showPassConf),
                      ),
                    ),
                  ],

                  // password dimenticata (solo login)
                  if (_isLogin) ...[
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: GestureDetector(
                        onTap: () {
                          // TODO: navigare al flusso di recupero password
                        },
                        child: Text('Password dimenticata?',
                            style: _body(size: 13, c: _kAccent)),
                      ),
                    ),
                  ],

                  SizedBox(height: _isLogin ? 16 : 20),

                  // CTA button
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kAccent,
                        foregroundColor: _kBg,
                        disabledBackgroundColor: _kAccent,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4)),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: _kBg,
                              ),
                            )
                          : Text(
                              _isLogin ? 'ACCEDI' : 'CREA ACCOUNT',
                              style: _cond(size: 19, ls: 1.5, c: _kBg),
                            ),
                    ),
                  ),

                  // errore API sotto il pulsante principale
                  if (_apiError != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _apiError!,
                      textAlign: TextAlign.center,
                      style: _body(size: 13, c: _kAccent),
                    ),
                  ],
                  const SizedBox(height: 18),

                  // divider "oppure"
                  Row(
                    children: [
                      const Expanded(
                          child: Divider(
                              color: _kBorder, thickness: 1, height: 1)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text('OPPURE',
                            style: _cond(
                                size: 13,
                                w: FontWeight.w600,
                                c: _kDim,
                                ls: 1.5)),
                      ),
                      const Expanded(
                          child: Divider(
                              color: _kBorder, thickness: 1, height: 1)),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // Google button
                  SizedBox(
                    height: 50,
                    child: OutlinedButton(
                      onPressed: () {
                        // TODO: avviare il flusso OAuth Google
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _kText,
                        side: const BorderSide(color: _kBorder),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const _GoogleGIcon(size: 19),
                          const SizedBox(width: 10),
                          Text('CONTINUA CON GOOGLE',
                              style: _cond(
                                  size: 16,
                                  w: FontWeight.w600,
                                  c: _kText,
                                  ls: 0.6)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Hero esteso (logo + tagline + illustrazione) ───────────────────────────
class _FullHero extends StatelessWidget {
  const _FullHero();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(child: ColoredBox(color: _kBg)),
        // glow overlay 225° (topRight → bottomLeft)
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                stops: const [0, 0.28, 0.58, 0.84],
                colors: [
                  _kAccent.withValues(alpha: 0.45),
                  _kAccent.withValues(alpha: 0.26),
                  _kAccent.withValues(alpha: 0.08),
                  _kAccent.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                const SizedBox(height: 32),
                Text('ZIPLY', style: _cond(size: 36, ls: 3.0)),
                const SizedBox(height: 4),
                Text(
                  'Muoviti. Ovunque.',
                  style:
                      _body(size: 13, c: Colors.white.withValues(alpha: 0.65)),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: SvgPicture.asset(
                      'assets/images/scooter.svg',
                      fit: BoxFit.contain,
                      alignment: Alignment.center,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Tab switcher item ─────────────────────────────────────────────────────────
class _Tab extends StatelessWidget {
  const _Tab({required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                label.toUpperCase(),
                textAlign: TextAlign.center,
                style: _cond(size: 20, ls: 1.0, c: active ? _kText : _kDim),
              ),
            ),
            Container(height: 2, color: active ? _kAccent : _kBorder),
          ],
        ),
      ),
    );
  }
}

// ── Labeled text field ────────────────────────────────────────────────────────
class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.placeholder,
    this.obscure = false,
    this.keyboardType,
    this.autoComplete,
    this.error,
    this.onChanged,
    this.trailing,
  });

  final String label;
  final TextEditingController controller;
  final String? placeholder;
  final bool obscure;
  final TextInputType? keyboardType;
  final String? autoComplete;
  final String? error;
  final ValueChanged<String>? onChanged;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final hasErr = error != null && error!.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: _cond(
              size: 13,
              w: FontWeight.w600,
              c: hasErr ? _kAccent : _kDim,
              ls: 1.2),
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
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  obscureText: obscure,
                  keyboardType: keyboardType,
                  autofillHints: autoComplete != null ? [autoComplete!] : null,
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
              if (trailing != null) trailing!,
            ],
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

// ── Google "G" multicolor icon ────────────────────────────────────────────────
class _GoogleGIcon extends StatelessWidget {
  const _GoogleGIcon({this.size = 18});
  final double size;

  static const String _svg = '''
<svg width="48" height="48" viewBox="0 0 48 48" xmlns="http://www.w3.org/2000/svg">
  <path fill="#FFC107" d="M43.6 20.5H42V20H24v8h11.3c-1.6 4.7-6.1 8-11.3 8a12 12 0 010-24c3 0 5.8 1.1 7.9 3l5.7-5.7A20 20 0 1024 44c11 0 20-9 20-20 0-1.3-.1-2.3-.4-3.5z"/>
  <path fill="#FF3D00" d="M6.3 14.7l6.6 4.8A12 12 0 0124 16c3 0 5.8 1.1 7.9 3l5.7-5.7A20 20 0 006.3 14.7z"/>
  <path fill="#4CAF50" d="M24 44c5.2 0 9.9-2 13.5-5.2l-6.2-5.3A12 12 0 0124 36c-5.2 0-9.6-3.3-11.3-7.9l-6.5 5C9.5 39.6 16.2 44 24 44z"/>
  <path fill="#1976D2" d="M43.6 20.5H42V20H24v8h11.3a12 12 0 01-4.1 5.6l6.2 5.3C36.9 36.7 44 31 44 24c0-1.3-.1-2.3-.4-3.5z"/>
</svg>''';

  @override
  Widget build(BuildContext context) =>
      SvgPicture.string(_svg, width: size, height: size);
}
