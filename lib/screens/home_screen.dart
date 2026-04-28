import 'dart:math';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../main.dart';
import '../models/environment.dart';
import '../services/location_service.dart';
import 'game_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Estado da tela
// ─────────────────────────────────────────────────────────────────────────────
sealed class ScanState {}

class ScanIdle extends ScanState {}

class ScanRunning extends ScanState {}

class ScanDone extends ScanState {
  final Position position;
  final double distance;
  final bool unlocked;
  ScanDone({
    required this.position,
    required this.distance,
    required this.unlocked,
  });
}

class ScanError extends ScanState {
  final String message;
  ScanError(this.message);
}

// ─────────────────────────────────────────────────────────────────────────────
// HomeScreen
// ─────────────────────────────────────────────────────────────────────────────
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  late final AnimationController _flickerCtrl;
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulse;

  ScanState _scanState = ScanIdle();

  @override
  void initState() {
    super.initState();

    _flickerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3500),
    )..repeat(reverse: true);

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _pulse = Tween<double>(begin: 0.55, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _flickerCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  // ── Lógica GPS ─────────────────────────────────────────────────────────────

  Future<void> _scan() async {
    setState(() => _scanState = ScanRunning());

    final result = await LocationService.instance.getCurrentPosition();

    if (!mounted) return;

    switch (result) {
      case LocationFailure(:final message):
        setState(() => _scanState = ScanError(message));

      case LocationSuccess(:final position):
        final distance = EnvironmentRegistry.blocoH15.distanceTo(position);
        final unlocked = EnvironmentRegistry.blocoH15.isUnlockedBy(position);
        setState(() {
          _scanState = ScanDone(
            position: position,
            distance: distance,
            unlocked: unlocked,
          );
        });
        if (unlocked) _showH15Dialog(distance);
    }
  }

  void _showH15Dialog(double distance) {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      builder: (_) => _H15Dialog(
        environment: EnvironmentRegistry.blocoH15,
        distance: distance,
        onEnterGame: () {
          Navigator.of(context).pop();
          Navigator.of(context).push(
            PageRouteBuilder(
              pageBuilder: (_, anim, __) => const GameScreen(),
              transitionsBuilder: (_, anim, __, child) =>
                  FadeTransition(opacity: anim, child: child),
              transitionDuration: const Duration(milliseconds: 800),
            ),
          );
        },
      ),
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _NoisyBackground(),
          SafeArea(
            child: Column(
              children: [
                const Spacer(flex: 2),
                _TitleWidget(flickerCtrl: _flickerCtrl),
                const SizedBox(height: 8),
                _SubtitleWidget(),
                const Spacer(flex: 3),
                _StatusPanel(state: _scanState, pulse: _pulse),
                const SizedBox(height: 32),
                _ActionButton(
                  state: _scanState,
                  pulse: _pulse,
                  onTap: _scan,
                ),
                const SizedBox(height: 16),
                _HintText('GPS necessário · Ambiente externo recomendado'),
                const Spacer(flex: 1),
                _HintText(
                  'PUC-CAMPINAS  ·  CAMPUS I  ·  DIA 0',
                  size: 9,
                  opacity: 0.5,
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widgets privados
// ─────────────────────────────────────────────────────────────────────────────

class _TitleWidget extends StatelessWidget {
  final AnimationController flickerCtrl;
  const _TitleWidget({required this.flickerCtrl});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: flickerCtrl,
      builder: (_, __) {
        final opacity =
            (0.82 + 0.18 * sin(flickerCtrl.value * pi * 7)).clamp(0.0, 1.0);
        return Opacity(
          opacity: opacity,
          child: Column(
            children: [
              Text(
                'PUC',
                style: TextStyle(
                  fontSize: 14,
                  letterSpacing: 12,
                  color: AppColors.amber.withValues(alpha: 0.7),
                  fontWeight: FontWeight.w300,
                ),
              ),
              const SizedBox(height: 4),
              ShaderMask(
                shaderCallback: (b) => const LinearGradient(
                  colors: [AppColors.paper, AppColors.amber],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ).createShader(b),
                child: const Text(
                  'SURVIVAL',
                  style: TextStyle(
                    fontSize: 52,
                    letterSpacing: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    height: 1.0,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SubtitleWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Text(
      '— Campus I está perdido. Você não está. —',
      style: TextStyle(fontSize: 11, color: AppColors.fade, letterSpacing: 1.5),
      textAlign: TextAlign.center,
    );
  }
}

class _StatusPanel extends StatelessWidget {
  final ScanState state;
  final Animation<double> pulse;
  const _StatusPanel({required this.state, required this.pulse});

  Color get _borderColor => switch (state) {
        ScanIdle() => AppColors.fade,
        ScanRunning() => AppColors.amber,
        ScanDone d => d.unlocked ? AppColors.red : AppColors.amber,
        ScanError() => AppColors.red,
      };

  String get _label => switch (state) {
        ScanIdle() => 'AGUARDANDO',
        ScanRunning() => 'ESCANEANDO',
        ScanDone() => 'SINAL ADQUIRIDO',
        ScanError() => 'FALHA NO SISTEMA',
      };

  String get _message => switch (state) {
        ScanIdle() => 'Sistema offline. Aguardando sinal...',
        ScanRunning() => 'Rastreando sinal de GPS...',
        ScanDone d => d.unlocked
            ? '⚠ ÁREA CONTAMINADA DETECTADA\nAcesso ao Bloco H-15 liberado.'
            : 'Sinal adquirido. Nenhuma zona de risco próxima.',
        ScanError e => e.message,
      };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: AnimatedBuilder(
        animation: pulse,
        builder: (_, child) => Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(
              color: _borderColor.withValues(
                alpha: state is ScanRunning ? pulse.value : 0.5,
              ),
            ),
            color: AppColors.bg,
          ),
          child: child,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _Dot(color: _borderColor),
                const SizedBox(width: 10),
                Text(
                  _label,
                  style: TextStyle(
                    fontSize: 10,
                    color: _borderColor,
                    letterSpacing: 3,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _message,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.paper,
                height: 1.7,
              ),
            ),
            if (state case ScanDone d) ...[
              const SizedBox(height: 12),
              _GpsReadout(position: d.position),
              const SizedBox(height: 8),
              _DistanceRow(distance: d.distance),
            ],
          ],
        ),
      ),
    );
  }
}

class _GpsReadout extends StatelessWidget {
  final Position position;
  const _GpsReadout({required this.position});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DataRow('LAT', position.latitude.toStringAsFixed(5)),
        _DataRow('LON', position.longitude.toStringAsFixed(5)),
        _DataRow('PREC', '±${position.accuracy.toStringAsFixed(1)}m'),
      ],
    );
  }
}

class _DistanceRow extends StatelessWidget {
  final double distance;
  const _DistanceRow({required this.distance});

  @override
  Widget build(BuildContext context) {
    final color = distance <= 50 ? AppColors.red : AppColors.amber;
    return Row(
      children: [
        const Text(
          'H-15 ▸ ',
          style:
              TextStyle(fontSize: 11, color: AppColors.fade, letterSpacing: 1),
        ),
        Text(
          '${distance.toStringAsFixed(1)} m',
          style: TextStyle(
              fontSize: 13, color: color, fontWeight: FontWeight.bold),
        ),
        if (distance <= 50) ...[
          const SizedBox(width: 8),
          const Text(
            '[ ZONA DE RISCO ]',
            style:
                TextStyle(fontSize: 10, color: AppColors.red, letterSpacing: 2),
          ),
        ],
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final ScanState state;
  final Animation<double> pulse;
  final VoidCallback onTap;
  const _ActionButton(
      {required this.state, required this.pulse, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isScanning = state is ScanRunning;
    final label = switch (state) {
      ScanIdle() => 'INICIAR EXPLORAÇÃO',
      ScanRunning() => 'RASTREANDO...',
      ScanDone() => 'RASTREAR NOVAMENTE',
      ScanError() => 'TENTAR NOVAMENTE',
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: GestureDetector(
        onTap: isScanning ? null : onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            color: isScanning ? AppColors.bg : AppColors.amber,
            border: Border.all(color: AppColors.amber, width: 1.5),
          ),
          child: isScanning
              ? AnimatedBuilder(
                  animation: pulse,
                  builder: (_, __) => Opacity(
                    opacity: pulse.value,
                    child: Text(
                      label,
                      style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.amber,
                          letterSpacing: 4),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.bg,
                    letterSpacing: 4,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
        ),
      ),
    );
  }
}

class _HintText extends StatelessWidget {
  final String text;
  final double size;
  final double opacity;
  const _HintText(this.text, {this.size = 10, this.opacity = 0.7});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: size,
        color: AppColors.fade.withValues(alpha: opacity),
        letterSpacing: 1.5,
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final Color color;
  const _Dot({required this.color});

  @override
  Widget build(BuildContext context) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

class _DataRow extends StatelessWidget {
  final String label;
  final String value;
  const _DataRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 10, color: AppColors.fade, letterSpacing: 2)),
          ),
          const Text('▸ ',
              style: TextStyle(fontSize: 10, color: AppColors.fade)),
          Text(value,
              style: const TextStyle(
                  fontSize: 11, color: AppColors.paper, letterSpacing: 1)),
        ],
      ),
    );
  }
}

class _NoisyBackground extends StatelessWidget {
  const _NoisyBackground();

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _NoisePainter());
}

class _NoisePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFF1C1C1C);
    final rng = Random(42);
    for (var i = 0; i < 900; i++) {
      canvas.drawCircle(
        Offset(rng.nextDouble() * size.width, rng.nextDouble() * size.height),
        0.7,
        paint,
      );
    }
    final vignette = Paint()
      ..shader = RadialGradient(
        colors: [Colors.transparent, const Color(0xDD000000)],
        stops: const [0.45, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), vignette);
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// Dialog do Bloco H-15
// ─────────────────────────────────────────────────────────────────────────────
class _H15Dialog extends StatelessWidget {
  final Environment environment;
  final double distance;
  final VoidCallback onEnterGame;

  const _H15Dialog({
    required this.environment,
    required this.distance,
    required this.onEnterGame,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF0D0D0D),
      shape: const RoundedRectangleBorder(),
      child: SingleChildScrollView(
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.amber.withValues(alpha: 0.4)),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('⚠ ZONA CONTAMINADA',
                  style: TextStyle(
                      fontSize: 10, color: AppColors.red, letterSpacing: 3)),
              const SizedBox(height: 8),
              Text(
                environment.name,
                style: const TextStyle(
                    fontSize: 22,
                    color: AppColors.amber,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 3),
              ),
              Text(
                environment.description,
                style: TextStyle(
                    fontSize: 10,
                    color: AppColors.amber.withValues(alpha: 0.6),
                    letterSpacing: 2),
              ),
              const SizedBox(height: 12),
              Text(
                'Você está a ${distance.toStringAsFixed(1)}m daqui.',
                style: const TextStyle(fontSize: 11, color: AppColors.red),
              ),
              const Divider(color: Color(0xFF2A2A2A), height: 24),
              Text(
                environment.lore,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.paper, height: 1.8),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border:
                      Border.all(color: AppColors.amber.withValues(alpha: 0.2)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('👤 ', style: TextStyle(fontSize: 18)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            environment.npcName.toUpperCase(),
                            style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.amber,
                                letterSpacing: 2,
                                fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            environment.npcDescription,
                            style: TextStyle(
                                fontSize: 11,
                                color: AppColors.paper.withValues(alpha: 0.75),
                                height: 1.6),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _DialogButton(
                label: '[ ENTRAR NO LABORATÓRIO ]',
                color: AppColors.amber,
                filled: true,
                onTap: onEnterGame,
              ),
              const SizedBox(height: 10),
              _DialogButton(
                label: '[ VOLTAR AO MAPA ]',
                color: AppColors.fade,
                filled: false,
                onTap: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DialogButton extends StatelessWidget {
  final String label;
  final Color color;
  final bool filled;
  final VoidCallback onTap;

  const _DialogButton({
    required this.label,
    required this.color,
    required this.filled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: filled ? color : Colors.transparent,
          border: Border.all(color: color),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: filled ? AppColors.bg : color,
            letterSpacing: 2,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
