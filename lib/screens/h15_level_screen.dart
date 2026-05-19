import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../game/h15_game.dart';

// ─────────────────────────────────────────────────────────────────────────────
// H15LevelScreen — forçar landscape ao entrar, portrait ao sair
// ─────────────────────────────────────────────────────────────────────────────
class H15LevelScreen extends StatefulWidget {
  const H15LevelScreen({super.key});

  @override
  State<H15LevelScreen> createState() => _H15LevelScreenState();
}

class _H15LevelScreenState extends State<H15LevelScreen>
    with WidgetsBindingObserver {
  late final H15Game _game;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _game = H15Game();
    _setLandscape();
  }

  @override
  void dispose() {
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
          GameWidget<H15Game>(
            game: _game,
            overlayBuilderMap: {
              'QuestDialog': (context, game) => QuestOverlay(game: game),
              'ServerDialog': (context, game) => ServerOverlay(game: game),
              'GameOver': (context, game) => GameOverOverlay(game: game),
            },
          ),
          ValueListenableBuilder<bool>(
            valueListenable: _game.questDialogOpen,
            builder: (_, questOpen, __) => ValueListenableBuilder<bool>(
              valueListenable: _game.gameOver,
              builder: (_, isGameOver, __) {
                if (questOpen || isGameOver) return const SizedBox.shrink();
                return GameHudOverlay(
                  game: _game,
                  onBack: () => Navigator.of(context).pop(false),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GameHudOverlay — layout landscape com SafeArea
// Joystick está na camera.viewport (Flame); só o ATK fica aqui no Flutter
// ─────────────────────────────────────────────────────────────────────────────
class GameHudOverlay extends StatelessWidget {
  final H15Game game;
  final VoidCallback onBack;

  const GameHudOverlay({
    super.key,
    required this.game,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Stack(
        children: [
          // ── TOPO ESQUERDO: Voltar + Vida + Stats ──────────────────────────
          Positioned(
            top: 10,
            left: 12,
            child: _LeftHudPanel(game: game, onBack: onBack),
          ),

          // ── TOPO DIREITO: Rastreador de Missão ────────────────────────────
          Positioned(
            top: 10,
            right: 12,
            child: ValueListenableBuilder<String>(
              valueListenable: game.missionText,
              builder: (_, mission, __) => _MissionTracker(text: mission),
            ),
          ),

          // ── CENTRO: Toast de mensagem HUD ─────────────────────────────────
          Positioned(
            top: 80,
            left: 0,
            right: 0,
            child: ValueListenableBuilder<String?>(
              valueListenable: game.hudMessage,
              builder: (_, message, __) => AnimatedOpacity(
                opacity: message == null ? 0 : 1,
                duration: const Duration(milliseconds: 160),
                child: IgnorePointer(
                  child: Center(child: _HudToast(message: message ?? '')),
                ),
              ),
            ),
          ),

          // ── DIREITA CENTRO: LER PAPEL ─────────────────────────────────────
          Positioned(
            right: 140,
            bottom: 24,
            child: ValueListenableBuilder<bool>(
              valueListenable: game.canReadPaper,
              builder: (_, canRead, __) => AnimatedOpacity(
                opacity: canRead ? 1 : 0,
                duration: const Duration(milliseconds: 140),
                child: IgnorePointer(
                  ignoring: !canRead,
                  child: _PixelHudButton(
                    label: 'LER PAPEL',
                    onTap: () => _showWeaponChoiceDialog(context),
                  ),
                ),
              ),
            ),
          ),

          // ── DIREITA CENTRO: INTERAGIR ─────────────────────────────────────
          Positioned(
            right: 140,
            bottom: 24,
            child: ValueListenableBuilder<bool>(
              valueListenable: game.canInteract,
              builder: (_, canInteract, __) => AnimatedOpacity(
                opacity: canInteract ? 1 : 0,
                duration: const Duration(milliseconds: 140),
                child: IgnorePointer(
                  ignoring: !canInteract,
                  child: _PixelHudButton(
                    label: 'INTERAGIR',
                    onTap: game.interact,
                  ),
                ),
              ),
            ),
          ),

          // ── CANTO INFERIOR DIREITO EXTREMO: Botão ATK ────────────────────
          // Joystick está no viewport Flame — canto inferior esquerdo extremo
          Positioned(
            right: 20,
            bottom: 20,
            child: ValueListenableBuilder<bool>(
              valueListenable: game.attackEnabled,
              builder: (_, enabled, __) =>
                  _AttackButton(enabled: enabled, onTap: game.attack),
            ),
          ),

          // ── CENTRO: Popup missão concluída ────────────────────────────────
          Center(
            child: ValueListenableBuilder<bool>(
              valueListenable: game.missionCompletedPopup,
              builder: (_, visible, __) => AnimatedOpacity(
                opacity: visible ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                child: IgnorePointer(
                  ignoring: !visible,
                  child: _MissionCompletePopup(
                    onClose: game.closeMissionCompletedPopup,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showWeaponChoiceDialog(BuildContext context) async {
    game.pauseEngine();
    final weapon = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _WeaponChoiceDialog(),
    );
    if (weapon != null) await game.equipWeapon(weapon);
    game.resumeEngine();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GameOverOverlay
// ─────────────────────────────────────────────────────────────────────────────
class GameOverOverlay extends StatelessWidget {
  final H15Game game;

  const GameOverOverlay({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.78),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 620),
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 30),
          decoration: BoxDecoration(
            color: const Color(0xE607070B),
            border: Border.all(color: const Color(0xFFB91C1C), width: 3),
            boxShadow: const [
              BoxShadow(color: Color(0xAA7F1D1D), blurRadius: 28),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'VOCÊ MORREU',
                textAlign: TextAlign.center,
                style: GoogleFonts.pressStart2p(
                  fontSize: 26,
                  color: const Color(0xFFEF4444),
                  height: 1.3,
                  shadows: const [
                    Shadow(
                      color: Color(0xFF450A0A),
                      offset: Offset(3, 3),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: game.reviveAtCheckpoint,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111827),
                    border: Border.all(
                        color: const Color(0xFFFBBF24), width: 2.5),
                    boxShadow: const [
                      BoxShadow(color: Color(0x887F1D1D), blurRadius: 14),
                    ],
                  ),
                  child: Text(
                    'Reviver no Ponto de Controle',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.pressStart2p(
                      fontSize: 10,
                      color: const Color(0xFFFDE68A),
                      height: 1.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _LeftHudPanel — Voltar + barra de vida + stats
// ─────────────────────────────────────────────────────────────────────────────
class _LeftHudPanel extends StatelessWidget {
  final H15Game game;
  final VoidCallback onBack;

  const _LeftHudPanel({required this.game, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            _PixelHudButton(label: 'VOLTAR', onTap: onBack),
            const SizedBox(width: 8),
            ValueListenableBuilder<double>(
              valueListenable: game.currentHealth,
              builder: (_, health, __) => _HealthBar(
                current: health,
                max: game.maxHealth,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        _SurvivalStats(game: game),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _HealthBar
// ─────────────────────────────────────────────────────────────────────────────
class _HealthBar extends StatelessWidget {
  final double current;
  final double max;
  const _HealthBar({required this.current, required this.max});

  @override
  Widget build(BuildContext context) {
    final progress = (current / max).clamp(0.0, 1.0);
    return Container(
      width: 180,
      height: 32,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xF207070B),
        border: Border.all(color: Colors.amber.shade900, width: 2),
        boxShadow: const [
          BoxShadow(color: Color(0xAA000000), offset: Offset(2, 2))
        ],
      ),
      child: Row(
        children: [
          const Text('♥',
              style:
                  TextStyle(fontSize: 14, color: Color(0xFFEF4444), height: 1)),
          const SizedBox(width: 5),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(color: const Color(0xFF3F3F46)),
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: progress,
                  child: Container(
                    color: progress > 0.35
                        ? const Color(0xFF22C55E)
                        : const Color(0xFFEF4444),
                  ),
                ),
                Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '${current.round()}/${max.round()}',
                      style: GoogleFonts.pressStart2p(
                        fontSize: 9,
                        color: Colors.white,
                        shadows: const [
                          Shadow(
                              color: Colors.black,
                              offset: Offset(1.5, 1.5),
                              blurRadius: 3)
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _SurvivalStats
// ─────────────────────────────────────────────────────────────────────────────
class _SurvivalStats extends StatelessWidget {
  final H15Game game;
  const _SurvivalStats({required this.game});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xE607070B),
        border: Border.all(color: const Color(0xFFF59E0B), width: 2),
        boxShadow: const [
          BoxShadow(color: Color(0xCC000000), offset: Offset(3, 3)),
          BoxShadow(color: Color(0x55F59E0B), blurRadius: 10),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ValueListenableBuilder<int>(
            valueListenable: game.survivalSeconds,
            builder: (_, s, __) => Text(
              _fmt(s),
              style: GoogleFonts.pressStart2p(
                fontSize: 11,
                color: Colors.white,
                shadows: const [
                  Shadow(
                      color: Colors.black,
                      offset: Offset(1.5, 1.5),
                      blurRadius: 3),
                ],
              ),
            ),
          ),
          const SizedBox(width: 18),
          ValueListenableBuilder<int>(
            valueListenable: game.zombiesKilled,
            builder: (_, k, __) => Text(
              '☠ $k',
              style: GoogleFonts.pressStart2p(
                fontSize: 14,
                color: const Color(0xFFFFF3B0),
                shadows: const [
                  Shadow(
                      color: Colors.black,
                      offset: Offset(1.5, 1.5),
                      blurRadius: 3),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(int s) =>
      '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
}

// ─────────────────────────────────────────────────────────────────────────────
// _MissionTracker — topo direito, maxWidth fixo para landscape
// ─────────────────────────────────────────────────────────────────────────────
class _MissionTracker extends StatelessWidget {
  final String text;
  const _MissionTracker({required this.text});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xE607070B),
          border: Border.all(color: const Color(0xFFF59E0B), width: 2.5),
          boxShadow: const [
            BoxShadow(color: Color(0xCC000000), offset: Offset(3, 3)),
            BoxShadow(color: Color(0x44F59E0B), blurRadius: 12),
          ],
        ),
        child: Text(
          text,
          textAlign: TextAlign.right,
          style: GoogleFonts.pressStart2p(
            fontSize: 10,
            color: const Color(0xFFFFF3B0),
            height: 1.6,
            shadows: const [
              Shadow(
                  color: Colors.black, offset: Offset(1.5, 1.5), blurRadius: 3),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _MissionCompletePopup
// ─────────────────────────────────────────────────────────────────────────────
class _MissionCompletePopup extends StatelessWidget {
  final VoidCallback onClose;
  const _MissionCompletePopup({required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(24),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xF20F1A10),
        border: Border.all(color: const Color(0xFFF59E0B), width: 3),
        boxShadow: const [
          BoxShadow(color: Color(0xAA000000), offset: Offset(4, 4)),
          BoxShadow(color: Color(0x88FFD700), blurRadius: 24, spreadRadius: 2),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'MISSÃO CONCLUÍDA!',
            textAlign: TextAlign.center,
            style: GoogleFonts.pressStart2p(
              fontSize: 18,
              color: const Color(0xFFFFF3B0),
              height: 1.5,
              shadows: const [
                Shadow(color: Colors.black, offset: Offset(2, 2), blurRadius: 3)
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Saguão limpo. Aguarde instruções.',
            textAlign: TextAlign.center,
            style: GoogleFonts.pressStart2p(
                fontSize: 10, color: const Color(0xFFFFF7D6), height: 1.8),
          ),
          const SizedBox(height: 16),
          _PixelHudButton(label: 'OK', onTap: onClose),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _HudToast
// ─────────────────────────────────────────────────────────────────────────────
class _HudToast extends StatelessWidget {
  final String message;
  const _HudToast({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xDD0A0600),
        border: Border.all(color: Colors.amber, width: 2),
      ),
      child: Text(
        message,
        style: GoogleFonts.pressStart2p(
          fontSize: 10,
          color: const Color(0xFFFDE68A),
          height: 1.5,
          shadows: const [
            Shadow(color: Colors.black, offset: Offset(1.5, 1.5), blurRadius: 3)
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _WeaponChoiceDialog
// ─────────────────────────────────────────────────────────────────────────────
class _WeaponChoiceDialog extends StatelessWidget {
  const _WeaponChoiceDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xF21B0F0A),
            border: Border.all(color: const Color(0xFFF59E0B), width: 3),
            boxShadow: const [
              BoxShadow(color: Color(0xCC000000), offset: Offset(5, 5)),
              BoxShadow(color: Color(0xAA7F1D1D), blurRadius: 26),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SALA B — NOTA MANCHADA',
                style: GoogleFonts.pressStart2p(
                  fontSize: 14,
                  color: const Color(0xFFFFF3B0),
                  height: 1.6,
                  shadows: const [
                    Shadow(color: Colors.black, offset: Offset(2, 2), blurRadius: 3)
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                "Uma nota manchada: 'Eles estão vindo. Pegue o que puder e sobreviva.'",
                style: GoogleFonts.pressStart2p(
                  fontSize: 11,
                  color: const Color(0xFFFFF7D6),
                  height: 1.9,
                  shadows: const [
                    Shadow(
                        color: Colors.black,
                        offset: Offset(1.5, 1.5),
                        blurRadius: 3)
                  ],
                ),
              ),
              const SizedBox(height: 18),
              _WeaponOptionButton(
                title: 'ESPADA DE UMA MÃO',
                subtitle: 'Dano alto · Alcance médio',
                onTap: () => Navigator.of(context).pop('Espada'),
              ),
              const SizedBox(height: 10),
              _WeaponOptionButton(
                title: 'DUAS ADAGAS',
                subtitle: 'Velocidade · Multi-alvo',
                onTap: () => Navigator.of(context).pop('Duas Adagas'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WeaponOptionButton extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _WeaponOptionButton(
      {required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xDD1F0808),
          border: Border.all(color: const Color(0xFFF59E0B), width: 2),
          boxShadow: const [
            BoxShadow(color: Color(0xAA000000), offset: Offset(3, 3)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: GoogleFonts.pressStart2p(
                    fontSize: 11, color: const Color(0xFFFFF3B0), height: 1.5)),
            const SizedBox(height: 6),
            Text(subtitle,
                style: GoogleFonts.pressStart2p(
                    fontSize: 9, color: const Color(0xFFFFD4D4))),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _PixelHudButton
// ─────────────────────────────────────────────────────────────────────────────
class _PixelHudButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _PixelHudButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xCC0A0600),
          border: Border.all(color: Colors.amber, width: 2),
          boxShadow: const [BoxShadow(color: Color(0x66FFD700), blurRadius: 6)],
        ),
        child: Text(
          label,
          style: GoogleFonts.pressStart2p(
            fontSize: 10,
            color: const Color(0xFFFFF3B0),
            shadows: const [
              Shadow(color: Colors.black, offset: Offset(1.5, 1.5), blurRadius: 3)
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _AttackButton — canto inferior direito extremo para o polegar
// ─────────────────────────────────────────────────────────────────────────────
class _AttackButton extends StatefulWidget {
  final bool enabled;
  final VoidCallback onTap;
  const _AttackButton({required this.enabled, required this.onTap});

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
        scale: _pressed ? 0.91 : 1.0,
        child: Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.enabled
                ? const Color(0xDD2A0505)
                : const Color(0x884A4A4A),
            border: Border.all(
              color:
                  widget.enabled ? Colors.redAccent : const Color(0xFF777777),
              width: 3.5,
            ),
            boxShadow: widget.enabled
                ? const [
                    BoxShadow(
                        color: Color(0xCCFF3333),
                        blurRadius: 20,
                        spreadRadius: 2),
                    BoxShadow(color: Color(0xAA0A0600), offset: Offset(0, 4)),
                  ]
                : const [
                    BoxShadow(color: Color(0xAA0A0600), offset: Offset(0, 4))
                  ],
          ),
          child: Center(
            child: Text(
              'ATK',
              style: GoogleFonts.pressStart2p(
                fontSize: 12,
                color:
                    widget.enabled ? Colors.redAccent : const Color(0xFFB0B0B0),
                shadows: const [
                  Shadow(color: Colors.black, offset: Offset(2, 2))
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// QuestOverlay
// ─────────────────────────────────────────────────────────────────────────────
class QuestOverlay extends StatefulWidget {
  final H15Game game;
  const QuestOverlay({super.key, required this.game});

  @override
  State<QuestOverlay> createState() => _QuestOverlayState();
}

class _QuestOverlayState extends State<QuestOverlay> {
  Timer? _timer;
  int _visibleChars = 0;

  String get _fullText => widget.game.questDialogText;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 24), (t) {
      if (!mounted) return;
      if (_visibleChars >= _fullText.length) {
        t.cancel();
        return;
      }
      setState(() => _visibleChars += 2);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text =
        _fullText.substring(0, _visibleChars.clamp(0, _fullText.length));

    return Container(
      color: Colors.black.withValues(alpha: 0.72),
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760, minWidth: 520),
            child: Container(
              margin: const EdgeInsets.all(18),
              padding: const EdgeInsets.all(26),
              decoration: BoxDecoration(
                color: const Color(0xF2162115),
                border: Border.all(color: const Color(0xFFF59E0B), width: 3),
                boxShadow: const [
                  BoxShadow(color: Color(0xCC000000), offset: Offset(5, 5)),
                  BoxShadow(
                      color: Color(0x77FFD700), blurRadius: 26, spreadRadius: 2)
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _HologramAvatar(),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Prof. Álvaro (Holograma)',
                          style: GoogleFonts.pressStart2p(
                            fontSize: 13,
                            color: const Color(0xFFBAE6FD),
                            height: 1.5,
                            shadows: const [
                              Shadow(
                                  color: Colors.black,
                                  offset: Offset(2, 2),
                                  blurRadius: 3),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                      height: 1, color: Colors.amber.withValues(alpha: 0.4)),
                  const SizedBox(height: 12),
                  Text(
                    text,
                    style: GoogleFonts.pressStart2p(
                      fontSize: 12,
                      color: const Color(0xFFFFF7D6),
                      height: 2.0,
                      shadows: const [
                        Shadow(
                            color: Colors.black,
                            offset: Offset(1.5, 1.5),
                            blurRadius: 3),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  Align(
                    alignment: Alignment.centerRight,
                    child: _PixelHudButton(
                        label: 'ACEITAR', onTap: widget.game.closeQuestDialog),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HologramAvatar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0x6638BDF8),
        border: Border.all(color: const Color(0xFF7DD3FC), width: 2),
        boxShadow: const [
          BoxShadow(color: Color(0xAA38BDF8), blurRadius: 18, spreadRadius: 2)
        ],
      ),
      child: const Icon(Icons.person_4, color: Color(0xFFDFF8FF), size: 30),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ServerOverlay
// ─────────────────────────────────────────────────────────────────────────────
class ServerOverlay extends StatelessWidget {
  final H15Game game;
  const ServerOverlay({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.76),
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700, minWidth: 480),
            child: Container(
              margin: const EdgeInsets.all(22),
              padding: const EdgeInsets.all(26),
              decoration: BoxDecoration(
                color: const Color(0xF20C1B10),
                border: Border.all(color: const Color(0xFF22C55E), width: 3),
                boxShadow: const [
                  BoxShadow(color: Color(0xCC000000), offset: Offset(5, 5)),
                  BoxShadow(
                      color: Color(0xAA16A34A), blurRadius: 22, spreadRadius: 1)
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('TERMINAL DE SEGURANÇA',
                      style: GoogleFonts.pressStart2p(
                        fontSize: 16,
                        color: const Color(0xFFBBF7D0),
                        height: 1.5,
                        shadows: const [
                          Shadow(
                              color: Colors.black,
                              offset: Offset(2, 2),
                              blurRadius: 3),
                        ],
                      )),
                  const SizedBox(height: 14),
                  Text(
                      '[SISTEMA]\nReiniciando Servidores...\nEnergia Restaurada!',
                      style: GoogleFonts.pressStart2p(
                        fontSize: 12,
                        color: const Color(0xFFF0FDF4),
                        height: 2.0,
                        shadows: const [
                          Shadow(
                              color: Colors.black,
                              offset: Offset(1.5, 1.5),
                              blurRadius: 3),
                        ],
                      )),
                  const SizedBox(height: 22),
                  Align(
                    alignment: Alignment.centerRight,
                    child: _PixelHudButton(
                        label: 'OK',
                        onTap: game.restorePowerAndCloseServerDialog),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
