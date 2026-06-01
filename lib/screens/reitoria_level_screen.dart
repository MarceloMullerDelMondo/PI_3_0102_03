import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../game/reitoria_game.dart';
import 'base_game_hud.dart';

class ReitoriaLevelScreen extends StatefulWidget {
  const ReitoriaLevelScreen({
    super.key,
    required this.playerName,
    this.devMode = false,
  });

  final String playerName;
  final bool devMode;

  @override
  State<ReitoriaLevelScreen> createState() => _ReitoriaLevelScreenState();
}

class _ReitoriaLevelScreenState extends State<ReitoriaLevelScreen>
    with WidgetsBindingObserver {
  late final ReitoriaLevel _game;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _game = ReitoriaLevel(playerName: widget.playerName);
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
    Navigator.of(context).pop(true);
  }

  Future<void> _setLandscape() => SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);

  Future<void> _setPortrait() =>
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          GameWidget<ReitoriaLevel>(
            game: _game,
            loadingBuilder: (_) => const Center(
              child: CircularProgressIndicator(color: Color(0xFFF5C842)),
            ),
            overlayBuilderMap: {
              'BossIntroDialog': (_, game) => BossIntroDialogOverlay(game: game),
              'BossVictory': (_, game) => BossVictoryOverlay(game: game),
            },
          ),
          // ── Boss HP bar — completely independent layer, top-centre ────────────
          ValueListenableBuilder<bool>(
            valueListenable: _game.dialogOpen,
            builder: (_, dialogOpen, __) {
              if (dialogOpen) return const SizedBox.shrink();
              return Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _BossHealthBar(game: _game),
                ),
              );
            },
          ),
          // ── Player HUD — left panel, attack button, game-over ───────────────
          ValueListenableBuilder<bool>(
            valueListenable: _game.dialogOpen,
            builder: (_, dialogOpen, __) {
              if (dialogOpen) return const SizedBox.shrink();
              return BaseGameHud(
                currentHealth: _game.currentHealth,
                maxHealth: 100,
                missionText: _game.missionText,
                hudMessage: _game.hudMessage,
                onBack: () => Navigator.of(context).pop(false),
                extraStack: [
                  // Attack button — bottom right
                  Positioned(
                    right: 24,
                    bottom: 20,
                    child: ValueListenableBuilder<bool>(
                      valueListenable: _game.attackEnabled,
                      builder: (_, enabled, __) =>
                          _AttackButton(enabled: enabled, onTap: _game.attack),
                    ),
                  ),
                  // Game-over overlay
                  Positioned.fill(
                    child: ValueListenableBuilder<bool>(
                      valueListenable: _game.gameOver,
                      builder: (_, over, __) {
                        if (!over) return const IgnorePointer(child: SizedBox.expand());
                        return ColoredBox(
                          color: Colors.black.withValues(alpha: .84),
                          child: Center(
                            child: _HudPanel(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'DERROTA',
                                    style: _font(16, const Color(0xFFFF6666)),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    'O Paciente Zero nao foi derrotado.',
                                    textAlign: TextAlign.center,
                                    style: _font(7, const Color(0xFFE5E7EB), height: 1.8),
                                  ),
                                  const SizedBox(height: 18),
                                  _PixelButton(
                                    label: 'TENTAR DE NOVO',
                                    onTap: _game.reviveAtCheckpoint,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  // Dev badge
                  if (widget.devMode)
                    Positioned(
                      bottom: 24,
                      left: 140,
                      child: _HudPanel(
                        child: Text('DEV', style: _font(7, const Color(0xFF00FF00))),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Boss Health Bar — brutalist, centred, occupies 58% of screen width
// ─────────────────────────────────────────────────────────────────────────────
class _BossHealthBar extends StatelessWidget {
  const _BossHealthBar({required this.game});

  final ReitoriaLevel game;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: 0.58,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xF0100000),
          border: Border.all(color: const Color(0xFFCC0000), width: 3),
          boxShadow: const [
            BoxShadow(color: Color(0xAAFF0000), blurRadius: 14, spreadRadius: 1),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'PACIENTE ZERO',
              style: _font(9, const Color(0xFFFF4444)),
            ),
            const SizedBox(height: 8),
            ValueListenableBuilder<int>(
              valueListenable: game.bossCurrentHealth,
              builder: (_, hp, __) {
                final fraction = (hp / FinalBossComponent.maxHp).clamp(0.0, 1.0);
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Bar — LayoutBuilder gives explicit pixel width so the
                    // fill Container never collapses to zero.
                    LayoutBuilder(
                      builder: (_, constraints) => Container(
                        width: constraints.maxWidth,
                        height: 20,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A0000),
                          border: Border.all(color: const Color(0xFF880000), width: 2),
                        ),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            width: constraints.maxWidth * fraction,
                            height: 20,
                            color: const Color(0xFFCC0000),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 5),
                    // HP numbers
                    Text(
                      '$hp  /  ${FinalBossComponent.maxHp}',
                      style: _font(7, const Color(0xFFFF9999)),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Overlays
// ─────────────────────────────────────────────────────────────────────────────
class BossIntroDialogOverlay extends StatelessWidget {
  const BossIntroDialogOverlay({super.key, required this.game});

  final ReitoriaLevel game;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: .9),
      child: Center(
        child: _DialogBox(
          title: 'PACIENTE ZERO',
          body:
              'Este e o inicio do fim.\nO Paciente Zero criou a infeccao.\nDerrote-o e a cura estara a salvo.',
          actionLabel: 'ENFRENTAR',
          onTap: game.closeBossIntroDialog,
        ),
      ),
    );
  }
}

class BossVictoryOverlay extends StatelessWidget {
  const BossVictoryOverlay({super.key, required this.game});

  final ReitoriaLevel game;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: .93),
      child: Center(
        child: _DialogBox(
          title: 'VITORIA',
          body:
              'O Paciente Zero foi derrotado.\nA cura esta a salvo.\nO campus foi libertado.',
          actionLabel: 'ENCERRAR',
          onTap: game.finishFinale,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared widgets
// ─────────────────────────────────────────────────────────────────────────────
class _DialogBox extends StatelessWidget {
  const _DialogBox({
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onTap,
  });

  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 760),
      margin: const EdgeInsets.all(24),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xF20A0A0A),
        border: Border.all(color: const Color(0xFFF5C842), width: 3),
        boxShadow: const [BoxShadow(color: Colors.black, offset: Offset(5, 5))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title,
              textAlign: TextAlign.center, style: _font(16, const Color(0xFFF5C842))),
          const SizedBox(height: 18),
          Text(
            body,
            textAlign: TextAlign.center,
            style: _font(9, const Color(0xFFE5E7EB), height: 1.9),
          ),
          const SizedBox(height: 24),
          _PixelButton(label: actionLabel, onTap: onTap),
        ],
      ),
    );
  }
}

class _HudPanel extends StatelessWidget {
  const _HudPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .72),
        border: Border.all(color: const Color(0xFFB87A18), width: 1.5),
      ),
      child: child,
    );
  }
}

class _PixelButton extends StatelessWidget {
  const _PixelButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: enabled ? const Color(0xFF2E1E06) : const Color(0xFF1F2937),
          border: Border.all(
            color: enabled ? const Color(0xFFF5C842) : const Color(0xFF4B5563),
            width: 2,
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: _font(8, enabled ? const Color(0xFFFDE68A) : const Color(0xFF9CA3AF),
              height: 1.5),
        ),
      ),
    );
  }
}

class _AttackButton extends StatefulWidget {
  const _AttackButton({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_AttackButton> createState() => _AttackButtonState();
}

class _AttackButtonState extends State<_AttackButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) {
        setState(() => _pressed = false);
        if (widget.enabled) widget.onTap();
      },
      child: AnimatedScale(
        duration: const Duration(milliseconds: 70),
        scale: _pressed ? 0.88 : 1.0,
        child: Container(
          width: 90,
          height: 90,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.enabled ? const Color(0xDD2A0505) : const Color(0x884A4A4A),
            border: Border.all(
              color: widget.enabled ? Colors.redAccent : const Color(0xFF777777),
              width: 3.5,
            ),
          ),
          child: Center(
            child: Text(
              'ATK',
              style: _font(11, widget.enabled ? Colors.redAccent : const Color(0xFFB0B0B0)),
            ),
          ),
        ),
      ),
    );
  }
}

TextStyle _font(double size, Color color, {double height = 1.2}) {
  return GoogleFonts.pressStart2p(
    fontSize: size,
    color: color,
    height: height,
    shadows: const [Shadow(color: Colors.black, offset: Offset(2, 2))],
  );
}
