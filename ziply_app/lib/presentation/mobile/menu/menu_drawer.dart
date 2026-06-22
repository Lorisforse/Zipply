import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:ziply_app/core/theme/app_colors.dart';
import 'package:ziply_app/core/theme/app_text_styles.dart';
import 'package:ziply_app/presentation/mobile/auth/login_screen.dart';
import 'package:ziply_app/presentation/mobile/chat/chat_screen.dart';
import 'package:ziply_app/presentation/mobile/payment/payment_methods_screen.dart';
import 'package:ziply_app/presentation/mobile/subscription/subscription_screen.dart';
import 'package:ziply_app/services/auth_service.dart';
import 'package:ziply_app/services/payment_link_service.dart';

// Palette (alias di AppColors).
const Color _kBg      = AppColors.bg;
const Color _kBorder  = AppColors.border;
const Color _kText    = AppColors.text;
const Color _kDim     = AppColors.dim;
const Color _kAccent  = AppColors.accent;
const Color _kGreen   = AppColors.green;

TextStyle _cond({double size = 14, FontWeight w = FontWeight.w700, Color c = _kText, double ls = 0}) =>
    appCond(size: size, w: w, c: c, ls: ls);

TextStyle _body({double size = 15, FontWeight w = FontWeight.w400, Color c = _kText}) =>
    appBody(size: size, w: w, c: c);

/// Identità ricavata dal JWT salvato per popolare l'header del menu.
class _Identity {
  const _Identity({required this.email, required this.ruolo});

  final String email;
  final String ruolo;

  /// Iniziali per l'avatar, derivate dalla parte locale dell'email
  /// (es. mario.rossi → "MR").
  String get initials {
    final local = email.split('@').first;
    final parts =
        local.split(RegExp(r'[._-]')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    final first = parts[0][0];
    final second = parts.length > 1 ? parts[1][0] : '';
    return (first + second).toUpperCase();
  }
}

/// [MOBILE] Menu (handoff `Grafica/menu-handoff`): drawer laterale destro con
/// header profilo e voci di navigazione. Da qui si raggiungono i metodi di
/// pagamento (UT.14); le altre voci sono ancora da implementare.
class MenuDrawer extends StatefulWidget {
  const MenuDrawer({super.key});

  @override
  State<MenuDrawer> createState() => _MenuDrawerState();
}

class _MenuDrawerState extends State<MenuDrawer> {
  final AuthService _authService = AuthService();
  _Identity? _identity;
  double _creditBalance = 0.0;

  @override
  void initState() {
    super.initState();
    _loadIdentity();
  }

  /// Decodifica localmente il payload del JWT per leggere email e ruolo, e carica il saldo crediti.
  Future<void> _loadIdentity() async {
    final token = await _authService.getToken();
    final identity = _decodeIdentity(token);
    double balance = 0.0;
    try {
      if (token != null && token.isNotEmpty) {
        balance = await PaymentLinkService().getCreditBalance();
      }
    } catch (_) {
      // Ignora se fallisce (es. offline)
    }
    if (!mounted) return;
    setState(() {
      _identity = identity;
      _creditBalance = balance;
    });
  }

  _Identity? _decodeIdentity(String? token) {
    if (token == null) return null;
    final parts = token.split('.');
    if (parts.length != 3) return null;
    try {
      final normalized = base64Url.normalize(parts[1]);
      final payload =
          jsonDecode(utf8.decode(base64Url.decode(normalized)))
              as Map<String, dynamic>;
      final email = payload['email'];
      if (email is! String || email.isEmpty) return null;
      return _Identity(
        email: email,
        ruolo: (payload['ruolo'] as String?) ?? 'utente',
      );
    } on FormatException {
      return null;
    }
  }

  /// Chiude il drawer e apre la schermata dei metodi di pagamento.
  void _openPaymentMethods() {
    final navigator = Navigator.of(context);
    Scaffold.of(context).closeEndDrawer();
    navigator.push(
      MaterialPageRoute(builder: (_) => const PaymentMethodsScreen()),
    );
  }

  /// Chiude il drawer e apre la schermata degli abbonamenti (UT.22).
  void _openSubscriptions() {
    Scaffold.of(context).closeEndDrawer();
    SubscriptionScreen.show(context);
  }

  /// Chiude il drawer e apre la chat di supporto (UT.10).
  void _openChat() {
    Scaffold.of(context).closeEndDrawer();
    ChatScreen.show(context);
  }



  // (Le voci senza use case sono state rimosse: niente azione "non disponibile".)

  /// Logout: azione distruttiva, quindi prima chiede conferma; solo se
  /// confermata pulisce il token e torna al login svuotando lo stack.
  Future<void> _logout() async {
    final confirmed = await _confirmLogout();
    if (confirmed != true || !mounted) return;
    final navigator = Navigator.of(context);
    await _authService.logout();
    if (!mounted) return;
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  /// Dialog di conferma prima del logout (stesso stile di [_confirmCancel]
  /// della mappa).
  Future<bool?> _confirmLogout() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: Text(
          'Vuoi uscire?',
          style: _cond(size: 22, c: _kText),
        ),
        content: Text(
          'Dovrai accedere di nuovo la prossima volta che apri Ziply.',
          style: _body(size: 14, c: _kDim),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'ANNULLA',
              style: _cond(size: 16, c: _kDim, ls: 0.5),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'ESCI',
              style: _cond(size: 16, c: _kAccent, ls: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width * 0.82;

    return Drawer(
      width: width,
      backgroundColor: _kBg,
      shape: const Border(left: BorderSide(color: _kBorder)),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Chiusura.
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                onPressed: () => Scaffold.of(context).closeEndDrawer(),
                icon: const Icon(Icons.close, color: _kDim, size: 22),
                splashRadius: 22,
              ),
            ),
            _ProfileHeader(identity: _identity, creditBalance: _creditBalance),
            const SizedBox(height: 6),
            Container(height: 1, color: _kBorder, margin: const EdgeInsets.symmetric(horizontal: 20)),
            const SizedBox(height: 6),

            // Voci di navigazione.
            _MenuItem(
              icon: Icons.map_outlined,
              label: 'Mappa',
              active: true,
              onTap: () => Scaffold.of(context).closeEndDrawer(),
            ),
            _MenuItem(
              icon: Icons.workspace_premium_outlined,
              label: 'Abbonamenti',
              onTap: _openSubscriptions,
            ),
            _MenuItem(
              icon: Icons.credit_card,
              label: 'Metodi di pagamento',
              onTap: _openPaymentMethods,
            ),
            _MenuItem(
              icon: Icons.support_agent_outlined,
              label: 'Supporto',
              onTap: _openChat,
            ),

            const Spacer(),
            Container(height: 1, color: _kBorder, margin: const EdgeInsets.symmetric(horizontal: 20)),
            // Logout.
            InkWell(
              onTap: _logout,
              child: Container(
                constraints: const BoxConstraints(minHeight: 52),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    const Icon(Icons.logout, color: _kAccent, size: 22),
                    const SizedBox(width: 15),
                    Text('Esci',
                        style: _cond(size: 18, w: FontWeight.w700, c: _kAccent, ls: 0.4)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

// ── Header profilo (avatar iniziali + email + badge ruolo) ───────────────────
class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.identity, required this.creditBalance});

  final _Identity? identity;
  final double creditBalance;

  @override
  Widget build(BuildContext context) {
    final id = identity;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(color: _kAccent, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text(
              id?.initials ?? '?',
              style: _cond(size: 21, c: _kBg, ls: 0.5),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  id?.email ?? 'Account Ziply',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _cond(size: 18, c: _kText, ls: 0.3),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (id != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _kAccent.withValues(alpha: 0.10),
                          border: Border.all(color: _kAccent),
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: Text(
                          id.ruolo.toUpperCase(),
                          style: _cond(size: 10, w: FontWeight.w700, c: _kAccent, ls: 0.5),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      'Credito: € ${creditBalance.toStringAsFixed(2).replaceAll('.', ',')}',
                      style: _cond(size: 12, c: _kGreen, w: FontWeight.w600),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Voce di menu ─────────────────────────────────────────────────────────────
class _MenuItem extends StatelessWidget {
  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: active ? _kAccent : Colors.transparent,
              width: 3,
            ),
          ),
          color: active ? _kAccent.withValues(alpha: 0.10) : Colors.transparent,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            Icon(icon, color: active ? _kAccent : _kDim, size: 22),
            const SizedBox(width: 15),
            Expanded(
              child: Text(label,
                  style: _cond(size: 18, w: FontWeight.w600, c: _kText, ls: 0.3)),
            ),
            const Icon(Icons.chevron_right, color: _kBorder, size: 18),
          ],
        ),
      ),
    );
  }
}
