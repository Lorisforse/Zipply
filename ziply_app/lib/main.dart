import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:ziply_app/presentation/mobile/auth/login_screen.dart';

// Logica di piattaforma:
//   - Mobile (iOS / Android) → UI mobile per utenti finali
//   - Web                    → UI web per operatori e amministratori pubblici
//
// Per ora viene mostrata la LoginScreen mobile su entrambe le piattaforme;
// il routing condizionale verrà implementato quando sarà pronta la UI web.

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
        colorScheme: ColorScheme.dark(
          primary: const Color(0xFFF69659),
          surface: const Color(0xFF252525),
        ),
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
      ),
      // TODO: sostituire con GoRouter quando sono pronte più schermate
      home: kIsWeb
          ? const Scaffold(
              body: Center(child: Text('Web UI — coming soon')),
            )
          : const LoginScreen(),
    );
  }
}
