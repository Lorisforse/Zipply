import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:ziply_app/core/theme/app_colors.dart';
import 'package:ziply_app/core/theme/app_theme.dart';
import 'package:ziply_app/core/utils/app_logger.dart';
import 'package:ziply_app/presentation/mobile/auth/login_screen.dart';
import 'package:ziply_app/presentation/mobile/map/map_screen.dart';
import 'package:ziply_app/presentation/web/auth/web_auth_gate.dart';
import 'package:ziply_app/services/auth_service.dart';

// Logica di piattaforma:
//   - Mobile (iOS / Android) → UI mobile per utenti finali
//   - Web                    → UI web per operatori e amministratori pubblici
//
// Per ora viene mostrata la UI mobile su entrambe le piattaforme;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  zlog('App avviata');
  runApp(const ZiplyApp());
}

class ZiplyApp extends StatelessWidget {
  const ZiplyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ziply',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      // Mobile (iOS/Android) → app utente; Web → dashboard operatore/amministrazione.
      // TODO: sostituire con GoRouter quando sono pronte più schermate
      home: kIsWeb ? const WebAuthGate() : const AuthGate(),
    );
  }
}

/// Decide la schermata iniziale in base alla presenza del token JWT salvato:
/// token presente → MapScreen, assente → LoginScreen.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final AuthService _authService = AuthService();
  late final Future<String?> _tokenFuture = _authService.getToken();

  @override
  void initState() {
    super.initState();
    _tokenFuture.then((token) {
      final loggedIn = token != null && token.isNotEmpty;
      zlog(
        loggedIn
            ? 'Sessione trovata: apro la mappa'
            : 'Nessuna sessione: apro il login',
        tag: 'Auth',
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _tokenFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          // Schermo nero minimale durante il check del token.
          return const Scaffold(
            backgroundColor: AppColors.bg,
            body: SizedBox.shrink(),
          );
        }
        final token = snapshot.data;
        final isLoggedIn = token != null && token.isNotEmpty;
        return isLoggedIn ? const MapScreen() : const LoginScreen();
      },
    );
  }
}
