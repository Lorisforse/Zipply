import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:ziply_app/presentation/mobile/auth/login_screen.dart';
import 'package:ziply_app/presentation/mobile/map/map_screen.dart';
import 'package:ziply_app/services/auth_service.dart';

// Logica di piattaforma:
//   - Mobile (iOS / Android) → UI mobile per utenti finali
//   - Web                    → UI web per operatori e amministratori pubblici
//
// Per ora viene mostrata la UI mobile su entrambe le piattaforme;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ZiplyApp());
}

class ZiplyApp extends StatelessWidget {
  const ZiplyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ziply',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF1A1A1A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFF69659),
          surface: Color(0xFF252525),
        ),
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
      ),
      // TODO: sostituire con GoRouter quando sono pronte più schermate
      home: kIsWeb
          ? const Scaffold(
              body: Center(child: Text('Web UI — coming soon')),
            )
          : const AuthGate(),
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
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _tokenFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          // Schermo nero minimale durante il check del token.
          return const Scaffold(
            backgroundColor: Color(0xFF1A1A1A),
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
