import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:ziply_app/core/theme/app_colors.dart';
import 'package:ziply_app/core/utils/app_logger.dart';
import 'package:ziply_app/presentation/web/auth/web_login_screen.dart';
import 'package:ziply_app/presentation/web/dashboard/dashboard_screen.dart';
import 'package:ziply_app/services/auth_service.dart';

/// Decodifica il payload di un token JWT senza dipendenze esterne. Usata lato
/// web per leggere il claim `ruolo` e differenziare l'accesso (operatore /
/// amministrazione) come previsto dall'autorizzazione per ruolo dello Sprint 2.
Map<String, dynamic> decodeJwt(String token) {
  final parts = token.split('.');
  if (parts.length != 3) {
    throw Exception('Token JWT malformato');
  }
  final normalized = base64Url.normalize(parts[1]);
  final decoded = utf8.decode(base64Url.decode(normalized));
  return jsonDecode(decoded) as Map<String, dynamic>;
}

/// Gate della dashboard web: verifica la sessione e il ruolo. Token assente o
/// ruolo non autorizzato → schermata di login; ruolo operatore/amministrazione
/// → dashboard.
class WebAuthGate extends StatefulWidget {
  const WebAuthGate({super.key});

  @override
  State<WebAuthGate> createState() => _WebAuthGateState();
}

class _WebAuthGateState extends State<WebAuthGate> {
  final AuthService _authService = AuthService();
  late final Future<String?> _tokenFuture = _authService.getToken();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _tokenFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            backgroundColor: AppColors.bg,
            body: Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent),
              ),
            ),
          );
        }

        final token = snapshot.data;
        if (token == null || token.isEmpty) {
          zlog('Nessuna sessione web trovata: reindirizzo al login', tag: 'WebAuth');
          return const WebLoginScreen();
        }

        try {
          final claims = decodeJwt(token);
          final ruolo = claims['ruolo'] as String?;
          zlog('Sessione web trovata per ruolo: $ruolo', tag: 'WebAuth');

          if (ruolo == 'operatore' || ruolo == 'amministrazione') {
            return const DashboardScreen();
          }
          zlog('Accesso negato: ruolo $ruolo non autorizzato', tag: 'WebAuth');
          return const WebLoginScreen(
            errorMessage: 'Accesso negato: questa area è riservata agli operatori.',
          );
        } catch (e) {
          zlog('Errore decodifica token: $e. Reindirizzo al login.', tag: 'WebAuth');
          return const WebLoginScreen();
        }
      },
    );
  }
}
