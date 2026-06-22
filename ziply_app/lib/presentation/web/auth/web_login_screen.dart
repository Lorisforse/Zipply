import 'dart:math';

import 'package:flutter/material.dart';
import 'package:ziply_app/core/theme/app_colors.dart';
import 'package:ziply_app/core/theme/app_text_styles.dart';
import 'package:ziply_app/core/utils/app_logger.dart';
import 'package:ziply_app/presentation/web/auth/web_auth_gate.dart';
import 'package:ziply_app/services/auth_service.dart';

/// Variante più chiara dell'accento, usata solo per il feedback hover del
/// pulsante di accesso.
const Color _accentHover = Color(0xFFFFAE74);

/// Schermata di login della dashboard web. Accetta solo i ruoli operatore e
/// amministrazione: dopo il login decodifica il claim `ruolo` dal JWT e nega
/// l'accesso agli altri ruoli (OP.01 / autorizzazione per ruolo Sprint 2).
class WebLoginScreen extends StatefulWidget {
  const WebLoginScreen({super.key, this.errorMessage, this.authService});

  final String? errorMessage;
  final AuthService? authService;

  @override
  State<WebLoginScreen> createState() => _WebLoginScreenState();
}

class _WebLoginScreenState extends State<WebLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  late final AuthService _authService = widget.authService ?? AuthService();

  bool _isLoading = false;
  String? _error;
  bool _showPassword = false;
  bool _rememberMe = true;
  bool _isHoveredButton = false;

  @override
  void initState() {
    super.initState();
    _error = widget.errorMessage;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final email = _emailController.text.trim();
    final password = _passwordController.text;

    try {
      final response = await _authService.login(email, password);
      final token = response['token'] as String;

      final claims = decodeJwt(token);
      final ruolo = claims['ruolo'] as String?;

      if (ruolo == 'operatore' || ruolo == 'amministrazione') {
        await _authService.saveToken(token);
        zlog('Login operatore riuscito, reindirizzo...', tag: 'WebLogin');
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const WebAuthGate()),
          );
        }
      } else {
        setState(() {
          _error = 'Accesso negato: questa area è riservata agli operatori.';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 800;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Row(
        children: [
          // Pannello brand (solo su schermi grandi).
          if (isDesktop)
            Expanded(
              flex: 46,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF221913), AppColors.bg],
                  ),
                  border: Border(right: BorderSide(color: AppColors.border)),
                ),
                child: const Stack(
                  children: [
                    BrandMotif(),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 52, vertical: 48),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          LogoHeader(),
                          Spacer(),
                          BrandContent(),
                          Spacer(),
                          LocationFooter(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Pannello form (destra o a schermo intero).
          Expanded(
            flex: isDesktop ? 54 : 100,
            child: Container(
              color: AppColors.bg,
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(32),
                  child: SizedBox(
                    width: 380,
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'ACCEDI ALLA DASHBOARD',
                            style: appCond(size: 34, w: FontWeight.bold, ls: 0.5),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Inserisci le credenziali operatore per continuare.',
                            style: appBody(size: 14.5, c: AppColors.dim),
                          ),
                          const SizedBox(height: 28),

                          if (_error != null) ...[
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.red.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppColors.red),
                              ),
                              child: Text(
                                _error!,
                                style: appBody(size: 14, c: AppColors.red),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            const SizedBox(height: 20),
                          ],

                          const FieldLabel(label: 'Email operatore'),
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            style: appBody(c: AppColors.text),
                            decoration: const InputDecoration(
                              hintText: 'nome@ziply.it',
                              prefixIcon: Icon(Icons.person_outline_rounded, color: AppColors.dim),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Inserisci l\'email operatore';
                              } else if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.trim())) {
                                return 'Email non valida';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 18),

                          const FieldLabel(label: 'Password'),
                          TextFormField(
                            controller: _passwordController,
                            obscureText: !_showPassword,
                            style: appBody(c: AppColors.text),
                            decoration: InputDecoration(
                              hintText: 'La tua password',
                              prefixIcon: const Icon(Icons.lock_outline_rounded, color: AppColors.dim),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                  color: AppColors.dim,
                                ),
                                onPressed: () => setState(() => _showPassword = !_showPassword),
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Inserisci la password';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),

                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              GestureDetector(
                                onTap: () => setState(() => _rememberMe = !_rememberMe),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 20,
                                      height: 20,
                                      decoration: BoxDecoration(
                                        color: _rememberMe ? AppColors.accent : Colors.transparent,
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: _rememberMe ? AppColors.accent : AppColors.border,
                                          width: 1.5,
                                        ),
                                      ),
                                      child: _rememberMe
                                          ? const Icon(Icons.check, size: 14, color: AppColors.bg)
                                          : null,
                                    ),
                                    const SizedBox(width: 9),
                                    Text('Ricordami', style: appBody(size: 14, c: AppColors.text)),
                                  ],
                                ),
                              ),
                              Text(
                                'Problemi di accesso?',
                                style: appBody(size: 13.5, c: AppColors.accent),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),

                          MouseRegion(
                            onEnter: (_) => setState(() => _isHoveredButton = true),
                            onExit: (_) => setState(() => _isHoveredButton = false),
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _handleLogin,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _isHoveredButton ? _accentHover : AppColors.accent,
                                foregroundColor: AppColors.bg,
                                padding: const EdgeInsets.symmetric(vertical: 18),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                elevation: 0,
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<Color>(AppColors.bg),
                                      ),
                                    )
                                  : Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          'ACCEDI',
                                          style: appCond(size: 19, w: FontWeight.bold, c: AppColors.bg, ls: 1.2),
                                        ),
                                        const SizedBox(width: 9),
                                        const Icon(Icons.arrow_forward_rounded, size: 19),
                                      ],
                                    ),
                            ),
                          ),
                          const SizedBox(height: 26),

                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              border: Border.all(color: AppColors.border),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.lock_rounded, color: AppColors.green, size: 16),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Connessione protetta · accesso riservato al personale autorizzato',
                                    style: appBody(size: 12.5, c: AppColors.dim),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Etichetta in maiuscolo sopra un campo del form.
class FieldLabel extends StatelessWidget {
  final String label;
  const FieldLabel({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Text(
        label.toUpperCase(),
        style: appCond(size: 13, w: FontWeight.w600, c: AppColors.dim, ls: 1.2),
      ),
    );
  }
}

/// Logo Ziply del pannello brand.
class LogoHeader extends StatelessWidget {
  const LogoHeader({super.key});

  @override
  Widget build(BuildContext context) {
    // Stesso wordmark dell'app (header mappa): 'ZIPLY' arancione + 'ZOOTROPOLIS'.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text('ZIPLY', style: appCond(size: 27, w: FontWeight.w700, c: AppColors.accent, ls: 1)),
        const SizedBox(width: 9),
        Text('ZOOTROPOLIS', style: appCond(size: 12, w: FontWeight.w600, c: AppColors.dim, ls: 1.5)),
      ],
    );
  }
}

/// Testo descrittivo del pannello brand.
class BrandContent extends StatelessWidget {
  const BrandContent({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 380),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'CENTRO OPERATIVO',
            style: appCond(size: 14, w: FontWeight.w600, c: AppColors.accent, ls: 3.0),
          ),
          const SizedBox(height: 14),
          Text(
            'GESTISCI LA TUA FLOTTA IN TEMPO REALE',
            style: appCond(size: 52, w: FontWeight.bold, c: Colors.white, ls: 0.5).copyWith(height: 1.02),
          ),
          const SizedBox(height: 18),
          Text(
            'Monitora veicoli, stati e manutenzioni da un\'unica dashboard. Accesso riservato agli operatori autorizzati.',
            style: appBody(size: 15.5, c: Colors.white.withValues(alpha: 0.62)).copyWith(height: 1.55),
          ),
        ],
      ),
    );
  }
}

/// Footer con la localizzazione del centro operativo.
class LocationFooter extends StatelessWidget {
  const LocationFooter({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.location_on_outlined, color: AppColors.dim, size: 15),
        const SizedBox(width: 8),
        Text(
          'Zootropolis HQ · Centro operativo flotta',
          style: appBody(size: 13, c: AppColors.dim),
        ),
      ],
    );
  }
}

/// Motivo decorativo (strade + puntini pulsanti) del pannello brand.
class BrandMotif extends StatelessWidget {
  const BrandMotif({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          left: -100,
          right: -100,
          top: 250,
          child: Transform.rotate(
            angle: -8 * pi / 180,
            child: Container(height: 2, color: Colors.white.withValues(alpha: 0.05)),
          ),
        ),
        Positioned(
          left: -100,
          right: -100,
          top: 480,
          child: Transform.rotate(
            angle: -8 * pi / 180,
            child: Container(height: 2, color: Colors.white.withValues(alpha: 0.05)),
          ),
        ),
        Positioned(
          left: 280,
          top: -100,
          bottom: -100,
          child: Transform.rotate(
            angle: 7 * pi / 180,
            child: Container(width: 2, color: Colors.white.withValues(alpha: 0.05)),
          ),
        ),

        // Puntini di flotta colorati per stato.
        const Positioned(left: 100, top: 150, child: PulsingDot(color: AppColors.green)),
        const Positioned(left: 310, top: 100, child: PulsingDot(color: AppColors.accent)),
        const Positioned(left: 410, top: 250, child: PulsingDot(color: AppColors.red)),
        const Positioned(left: 200, top: 300, child: PulsingDot(color: AppColors.green)),
        const Positioned(left: 110, top: 400, child: PulsingDot(color: AppColors.dim)),
        const Positioned(left: 350, top: 430, child: PulsingDot(color: AppColors.accent)),
        const Positioned(left: 440, top: 460, child: PulsingDot(color: AppColors.green)),
        const Positioned(left: 250, top: 500, child: PulsingDot(color: AppColors.red)),
        const Positioned(left: 60, top: 280, child: PulsingDot(color: AppColors.green)),
        const Positioned(left: 170, top: 90, child: PulsingDot(color: AppColors.accent)),
      ],
    );
  }
}

/// Puntino di flotta con alone pulsante.
class PulsingDot extends StatefulWidget {
  final Color color;
  const PulsingDot({super.key, required this.color});

  @override
  State<PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<PulsingDot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final glowSize = 4.0 + 8.0 * _controller.value;
        return Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: widget.color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.16 + 0.20 * _controller.value),
                blurRadius: glowSize,
                spreadRadius: glowSize / 2,
              ),
            ],
          ),
        );
      },
    );
  }
}
