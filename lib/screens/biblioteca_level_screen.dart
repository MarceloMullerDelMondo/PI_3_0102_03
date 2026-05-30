import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../game/biblioteca_game.dart';
import 'base_game_hud.dart';
import 'caa_level_screen.dart';

class BibliotecaLevelScreen extends StatefulWidget {
  const BibliotecaLevelScreen({
    super.key,
    required this.playerName,
    this.devMode = false,
  });

  final String playerName;
  final bool devMode;

  @override
  State<BibliotecaLevelScreen> createState() => _BibliotecaLevelScreenState();
}

class _BibliotecaLevelScreenState extends State<BibliotecaLevelScreen>
    with WidgetsBindingObserver {
  late final BibliotecaGame _game;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _game = BibliotecaGame(playerName: widget.playerName);
    _game.levelCompleted.addListener(_onLevelCompleted);
    _setLandscape();
  }

  @override
  void dispose() {
    _game.levelCompleted.removeListener(_onLevelCompleted);
    WidgetsBinding.instance.removeObserver(this);
    _setPortrait();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _setLandscape();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _setPortrait();
    }
  }

  void _onLevelCompleted() {
    if (!_game.levelCompleted.value || !mounted) return;
    // Bypass the map screen — transition seamlessly to Phase 4.
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => CaaLevelScreen(playerName: widget.playerName),
      ),
    );
  }

  Future<void> _setLandscape() => SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);

  Future<void> _setPortrait() => SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Flame game ────────────────────────────────────────────────
          GameWidget<BibliotecaGame>(
            game: _game,
            loadingBuilder: (_) => const Center(
              child: CircularProgressIndicator(color: Color(0xFFF5C842)),
            ),
            overlayBuilderMap: {
              'ExitDoor': (_, game) => _ExitDoorOverlay(game: game),
            },
          ),

          // ── Base HUD (health · timer · mission) + card counter ────────
          //
          // BaseGameHud renders the Phase 1 layout.
          // BibliotecaGame uses BaseHudComponent, so notifiers are at hud.*.
          // The "CARTÃO: 0/1" counter is injected via [extraTopLeft].
          BaseGameHud(
            currentHealth: _game.hud.currentHealth,
            maxHealth: _game.hud.maxHealth,
            missionText: _game.hud.missionText,
            hudMessage: _game.hud.hudMessage,
            survivalSeconds: _game.hud.survivalSeconds,
            onBack: () => Navigator.of(context).pop(false),
            extraTopLeft: _CardCounter(game: _game),
          ),
        ],
      ),
    );
  }
}

// ── Phase-specific: Card Counter ──────────────────────────────────────────
//
// Injected into BaseGameHud.extraTopLeft.
// Shows "CARTÃO: 0/1" before collection and "CARTÃO: 1/1" after.

class _CardCounter extends StatelessWidget {
  const _CardCounter({required this.game});

  final BibliotecaGame game;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: game.hasAccessCardNotifier,
      builder: (_, hasCard, __) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xE607070B),
          border: Border.all(
            color: hasCard
                ? const Color(0xFF86EFAC) // green when collected
                : const Color(0xFFF59E0B), // amber while missing
            width: 1.5,
          ),
        ),
        child: Text(
          'CARTÃO: ${hasCard ? '1/1' : '0/1'}',
          style: GoogleFonts.pressStart2p(
            fontSize: 7,
            color: hasCard
                ? const Color(0xFF86EFAC)
                : const Color(0xFFFCA5A5),
            shadows: const [
              Shadow(color: Colors.black, offset: Offset(1, 1)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Phase-specific: Exit Door Overlay ─────────────────────────────────────

class _ExitDoorOverlay extends StatelessWidget {
  const _ExitDoorOverlay({required this.game});

  final BibliotecaGame game;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.82),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 480),
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
          decoration: BoxDecoration(
            color: const Color(0xFF050D18),
            border: Border.all(color: const Color(0xFF38BDF8), width: 2.5),
            boxShadow: const [
              BoxShadow(
                color: Color(0x5538BDF8),
                blurRadius: 32,
                spreadRadius: -4,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('PORTA DE SAÍDA', style: _font(13, const Color(0xFF7DD3FC))),
              const SizedBox(height: 16),
              Text(
                'Rota para o CAA desbloqueada.\nDeseja prosseguir?',
                textAlign: TextAlign.center,
                style: _font(8, const Color(0xFFE5E7EB), height: 1.9),
              ),
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _OverlayButton(
                    label: 'CANCELAR',
                    color: const Color(0xFF1F2937),
                    borderColor: const Color(0xFF4B5563),
                    textColor: const Color(0xFF9CA3AF),
                    onTap: game.onExitCancelled,
                  ),
                  const SizedBox(width: 16),
                  _OverlayButton(
                    label: 'ENTRAR',
                    color: const Color(0xFF061827),
                    borderColor: const Color(0xFF38BDF8),
                    textColor: const Color(0xFFE0F2FE),
                    onTap: game.onExitConfirmed,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OverlayButton extends StatelessWidget {
  const _OverlayButton({
    required this.label,
    required this.color,
    required this.borderColor,
    required this.textColor,
    required this.onTap,
  });

  final String label;
  final Color color;
  final Color borderColor;
  final Color textColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: color,
          border: Border.all(color: borderColor, width: 2),
        ),
        child: Text(label, style: _font(8, textColor, height: 1.5)),
      ),
    );
  }
}

TextStyle _font(double size, Color color, {double height = 1.2}) =>
    GoogleFonts.pressStart2p(
      fontSize: size,
      color: color,
      height: height,
      shadows: const [Shadow(color: Colors.black, offset: Offset(2, 2))],
    );
