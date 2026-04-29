import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Orientação bloqueada em portrait
  try {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]).timeout(const Duration(seconds: 3));
  } catch (e, st) {
    debugPrint('SystemChrome.setPreferredOrientations falhou: $e');
    debugPrintStack(stackTrace: st);
  }

  // Status bar transparente
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  // ── Firebase ──────────────────────────────────────────────────────────────
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(const Duration(seconds: 8));
  } catch (e, st) {
    debugPrint(
      'Firebase.initializeApp falhou${kIsWeb ? ' no Web' : ''}: $e',
    );
    debugPrintStack(stackTrace: st);
  }

  runApp(const RpgPucSurvivalApp());
}

class RpgPucSurvivalApp extends StatelessWidget {
  const RpgPucSurvivalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PUC Survival',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      home: const HomeScreen(),
    );
  }

  ThemeData _buildTheme() {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.bg,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.amber,
        secondary: AppColors.red,
        surface: AppColors.surface,
        onPrimary: AppColors.bg,
        onSecondary: Colors.white,
        onSurface: AppColors.paper,
      ),
    );
  }
}

/// Paleta central — usada por todas as telas
abstract class AppColors {
  static const Color bg = Color(0xFF0A0A0A);
  static const Color surface = Color(0xFF1A1A1A);
  static const Color amber = Color(0xFFB8860B);
  static const Color red = Color(0xFF8B0000);
  static const Color paper = Color(0xFFD4C5A9);
  static const Color fade = Color(0xFF4A3F2F);
  static const Color green = Color(0xFF228B22);
}
