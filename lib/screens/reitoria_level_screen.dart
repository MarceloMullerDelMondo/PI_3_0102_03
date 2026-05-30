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

  Future<void> _setLandscape() {
    return SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  Future<void> _setPortrait() {
    return SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }

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
              'MarianaDialog': (_, game) => MarianaDialogOverlay(game: game),
              'FinalEnding': (_, game) => FinalEndingOverlay(game: game),
            },
          ),
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
                // Phase-specific: nightfall status badge below health bar.
                extraTopLeft: _NightfallBadge(game: _game),
                extraStack: [
                  // Upload progress OR rescue countdown (centre of top bar).
                  Positioned(
                    left: 140,
                    top: 10,
                    right: 460,
                    child: ValueListenableBuilder<ReitoriaRoute>(
                      valueListenable: _game.route,
                      builder: (_, route, __) => route == ReitoriaRoute.cure
                          ? _UploadStatus(game: _game)
                          : _CountdownStatus(game: _game),
                    ),
                  ),
                  // Attack button (far right)
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
                      builder: (_, gameOver, __) {
                        if (!gameOver) {
                          return const IgnorePointer(child: SizedBox.expand());
                        }
                        return ColoredBox(
                          color: Colors.black.withValues(alpha: .84),
                          child: Center(
                            child: _HudPanel(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'FIM DA LINHA',
                                    style: _font(16, const Color(0xFFFF6666)),
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
                  // Dev indicator
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

/// Injected into [BaseGameHud.extraTopLeft] for Phase 5.
/// Reflects the nightfall / lighting state below the health bar.
class _NightfallBadge extends StatelessWidget {
  const _NightfallBadge({required this.game});

  final ReitoriaLevel game;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: game.nightfallActive,
      builder: (_, night, __) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xE607070B),
          border: Border.all(
            color: night ? const Color(0xFF93C5FD) : const Color(0xFFF59E0B),
            width: 1.5,
          ),
        ),
        child: Text(
          night ? 'NOITE: LANTERNA ATIVA' : 'LUZ: INSTAVEL',
          style: _font(
            7,
            night ? const Color(0xFF93C5FD) : const Color(0xFFFDE68A),
          ),
        ),
      ),
    );
  }
}

class _UploadStatus extends StatelessWidget {
  const _UploadStatus({required this.game});

  final ReitoriaLevel game;

  @override
  Widget build(BuildContext context) {
    return _HudPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ValueListenableBuilder<double>(
            valueListenable: game.uploadProgress,
            builder: (_, progress, __) => Text(
              'UPLOAD ${(progress * 100).clamp(0, 100).round()}%',
              style: _font(8, const Color(0xFF67E8F9)),
            ),
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<double>(
            valueListenable: game.uploadProgress,
            builder: (_, progress, __) => _Bar(
              value: progress,
              color: const Color(0xFF22D3EE),
            ),
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<double>(
            valueListenable: game.serverIntegrity,
            builder: (_, integrity, __) => Text(
              'SERVIDOR ${integrity.round()}%',
              style: _font(7, integrity > 35 ? Colors.white : Colors.redAccent),
            ),
          ),
        ],
      ),
    );
  }
}

class _CountdownStatus extends StatelessWidget {
  const _CountdownStatus({required this.game});

  final ReitoriaLevel game;

  @override
  Widget build(BuildContext context) {
    return _HudPanel(
      child: ValueListenableBuilder<int>(
        valueListenable: game.countdownSeconds,
        builder: (_, seconds, __) {
          final m = (seconds ~/ 60).toString().padLeft(2, '0');
          final s = (seconds % 60).toString().padLeft(2, '0');
          return Text(
            'RESGATE $m:$s',
            style: _font(
              10,
              seconds <= 25 ? const Color(0xFFFF7777) : const Color(0xFFFDE68A),
            ),
          );
        },
      ),
    );
  }
}

class MarianaDialogOverlay extends StatelessWidget {
  const MarianaDialogOverlay({super.key, required this.game});

  final ReitoriaLevel game;

  @override
  Widget build(BuildContext context) {
    final isCure = game.route.value == ReitoriaRoute.cure;
    return Material(
      color: Colors.black.withValues(alpha: .88),
      child: Center(
        child: _DialogBox(
          title: 'MARIANA',
          body: isCure
              ? 'Voce trouxe os dados da cura. Eu seguro a porta. Voce segura o servidor.'
              : 'O resgate respondeu. O portao principal e nossa unica janela.',
          actionLabel: 'COMEÇAR',
          onTap: game.closeIntroDialog,
        ),
      ),
    );
  }
}

class FinalEndingOverlay extends StatelessWidget {
  const FinalEndingOverlay({super.key, required this.game});

  final ReitoriaLevel game;

  @override
  Widget build(BuildContext context) {
    final isCure = game.route.value == ReitoriaRoute.cure;
    return Material(
      color: Colors.black.withValues(alpha: .93),
      child: Center(
        child: _DialogBox(
          title: isCure ? 'ROTA CURA' : 'ROTA RESGATE',
          body: isCure
              ? 'A humanidade nao acabou... so precisava de alguem disposto a ficar.'
              : 'Sobreviver tambem e resistir.',
          actionLabel: 'ENCERRAR',
          onTap: game.finishFinale,
        ),
      ),
    );
  }
}

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
          Text(title, textAlign: TextAlign.center, style: _font(16, const Color(0xFFF5C842))),
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

class _Bar extends StatelessWidget {
  const _Bar({required this.value, required this.color});

  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 300,
      height: 15,
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        border: Border.all(color: const Color(0xFF4B5563), width: 1.5),
      ),
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: value.clamp(0, 1),
        child: ColoredBox(color: color),
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
          style: _font(
            8,
            enabled ? const Color(0xFFFDE68A) : const Color(0xFF9CA3AF),
            height: 1.5,
          ),
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
            color: widget.enabled
                ? const Color(0xDD2A0505)
                : const Color(0x884A4A4A),
            border: Border.all(
              color: widget.enabled ? Colors.redAccent : const Color(0xFF777777),
              width: 3.5,
            ),
          ),
          child: Center(
            child: Text(
              'ATK',
              style: _font(
                11,
                widget.enabled ? Colors.redAccent : const Color(0xFFB0B0B0),
              ),
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
