import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/home_screen.dart';
// import 'package:firebase_core/firebase_core.dart';
// import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Trava em portrait
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // Status bar transparente / ícones claros
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  // Descomente após rodar `flutterfire configure`:
  // await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

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

/// Paleta central do app — usada por todas as telas
abstract class AppColors {
  static const Color bg = Color(0xFF0A0A0A);
  static const Color surface = Color(0xFF1A1A1A);
  static const Color amber = Color(0xFFB8860B);
  static const Color red = Color(0xFF8B0000);
  static const Color paper = Color(0xFFD4C5A9);
  static const Color fade = Color(0xFF4A3F2F);
  static const Color green = Color(0xFF228B22);
}
