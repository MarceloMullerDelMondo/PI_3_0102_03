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
  final String playerName;
  final bool devMode;
  const H15LevelScreen({super.key, required this.playerName, this.devMode = false});

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
    _game = H15Game(playerName: widget.playerName);
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
            loadingBuilder: (_) => const _H15LoadingScreen(),
            overlayBuilderMap: {
              'QuestDialog': (context, game) => QuestOverlay(game: game),
              'ServerDialog': (context, game) => ServerOverlay(game: game),
              'GameOver': (context, game) => GameOverOverlay(game: game),
              'Quest2Dialog': (context, game) => Quest2DialogOverlay(game: game),
              'ColorGame': (context, game) => ColorGameOverlay(game: game),
              'LightSwitch': (context, game) => LightSwitchOverlay(game: game),
              'LevelComplete': (context, game) => LevelCompleteOverlay(game: game),
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
                  devMode: widget.devMode,
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
// _H15LoadingScreen — exibida enquanto o onLoad do H15Game está em andamento
// ─────────────────────────────────────────────────────────────────────────────
class _H15LoadingScreen extends StatelessWidget {
  const _H15LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(
                color: Color(0xFFD4860A),
                strokeWidth: 3,
              ),
            ),
            SizedBox(height: 20),
            Text(
              'CARREGANDO...',
              style: TextStyle(
                color: Color(0xFFD4860A),
                fontSize: 12,
                fontFamily: 'monospace',
                letterSpacing: 2,
              ),
            ),
          ],
        ),
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
  final bool devMode;

  const GameHudOverlay({
    super.key,
    required this.game,
    required this.onBack,
    this.devMode = false,
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

          // ── DIREITA CENTRO: INTERAGIR COM GERADOR (Quest 3) ─────────────
          Positioned(
            right: 140,
            bottom: 80,
            child: ValueListenableBuilder<bool>(
              valueListenable: game.canInteractGenerator,
              builder: (_, canInteract, __) => AnimatedOpacity(
                opacity: canInteract ? 1 : 0,
                duration: const Duration(milliseconds: 140),
                child: IgnorePointer(
                  ignoring: !canInteract,
                  child: _PixelHudButton(
                    label: 'INTERAGIR',
                    onTap: game.interactGenerator,
                  ),
                ),
              ),
            ),
          ),

          // ── DIREITA CENTRO: FALAR COM NPC (Quest 2) ──────────────────────
          Positioned(
            right: 140,
            bottom: 80,
            child: ValueListenableBuilder<bool>(
              valueListenable: game.canTalkToNpc2,
              builder: (_, canTalk, __) => AnimatedOpacity(
                opacity: canTalk ? 1 : 0,
                duration: const Duration(milliseconds: 140),
                child: IgnorePointer(
                  ignoring: !canTalk,
                  child: _PixelHudButton(
                    label: 'FALAR (E)',
                    onTap: game.talkToNpc2,
                  ),
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

          // ── DEV: Botão pular missão ───────────────────────────────────────
          if (devMode)
            Positioned(
              top: 10,
              left: 0,
              right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: game.devSkipMission,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xDD001400),
                      border: Border.all(color: const Color(0xFF00FF00), width: 1.5),
                    ),
                    child: Text(
                      '[DEV] PULAR MISSÃO',
                      style: GoogleFonts.pressStart2p(
                        fontSize: 7,
                        color: const Color(0xFF00FF00),
                      ),
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

// ─────────────────────────────────────────────────────────────────────────────
// Quest2DialogOverlay — NPC dialogue before the colour mini-game
// ─────────────────────────────────────────────────────────────────────────────
class Quest2DialogOverlay extends StatefulWidget {
  final H15Game game;
  const Quest2DialogOverlay({super.key, required this.game});

  @override
  State<Quest2DialogOverlay> createState() => _Quest2DialogOverlayState();
}

class _Quest2DialogOverlayState extends State<Quest2DialogOverlay> {
  static const _fullText =
      'Pare aí mesmo! Como posso saber que\n'
      'você não é um deles? Prove que você\n'
      'é humano. Repita as cores que eu mostrar.';

  Timer? _timer;
  int _visibleChars = 0;

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
    final text = _fullText.substring(0, _visibleChars.clamp(0, _fullText.length));
    return Container(
      color: Colors.black.withValues(alpha: 0.75),
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760, minWidth: 520),
            child: Container(
              margin: const EdgeInsets.all(18),
              padding: const EdgeInsets.all(26),
              decoration: BoxDecoration(
                color: const Color(0xF2181210),
                border: Border.all(color: const Color(0xFFF59E0B), width: 3),
                boxShadow: const [
                  BoxShadow(color: Color(0xCC000000), offset: Offset(5, 5)),
                  BoxShadow(
                      color: Color(0x77FFD700), blurRadius: 26, spreadRadius: 2),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    _SurvivorAvatar(),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Professora Beatriz Mendonça',
                        style: GoogleFonts.pressStart2p(
                          fontSize: 13,
                          color: const Color(0xFFF4A261),
                          height: 1.5,
                          shadows: const [
                            Shadow(
                                color: Colors.black,
                                offset: Offset(2, 2),
                                blurRadius: 3)
                          ],
                        ),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  Container(
                      height: 1, color: Colors.amber.withValues(alpha: 0.4)),
                  const SizedBox(height: 12),
                  Text(
                    text,
                    style: GoogleFonts.pressStart2p(
                      fontSize: 11,
                      color: const Color(0xFFFFF7D6),
                      height: 2.0,
                      shadows: const [
                        Shadow(
                            color: Colors.black,
                            offset: Offset(1.5, 1.5),
                            blurRadius: 3)
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  Align(
                    alignment: Alignment.centerRight,
                    child: _PixelHudButton(
                      label: 'PROSSEGUIR',
                      onTap: widget.game.quest2Manager.closeDialogue,
                    ),
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

class _SurvivorAvatar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0x66F4A261),
        border: Border.all(color: const Color(0xFFF4A261), width: 2),
        boxShadow: const [
          BoxShadow(color: Color(0x88F4A261), blurRadius: 14, spreadRadius: 1)
        ],
      ),
      child: const Icon(Icons.person, color: Color(0xFFFFF7D6), size: 30),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ColorGameOverlay — 3-round colour-sequence memory mini-game
//
// Round 1: 3 colours  |  Round 2: 4 colours  |  Round 3: 5 colours
//
// All round management (advance, retry) is internal — the manager is only
// called once, on final victory or if the overlay is somehow dismissed early.
// ─────────────────────────────────────────────────────────────────────────────
class ColorGameOverlay extends StatefulWidget {
  final H15Game game;
  const ColorGameOverlay({super.key, required this.game});

  @override
  State<ColorGameOverlay> createState() => _ColorGameOverlayState();
}

class _ColorGameOverlayState extends State<ColorGameOverlay> {
  static const _flashDuration = Duration(milliseconds: 750);
  static const _pauseDuration = Duration(milliseconds: 300);

  // Reads from the manager so sequences are stable across rebuilds.
  List<List<GameColor>> get _allRounds =>
      widget.game.quest2Manager.rounds;

  int _roundIndex = 0;
  List<GameColor> get _sequence => _allRounds[_roundIndex];

  // Phases: 'showing' | 'input' | 'roundResult' | 'allDone'
  String _phase = 'showing';
  int _showIndex = -1;
  final List<GameColor> _playerInput = [];
  bool? _roundSuccess;

  @override
  void initState() {
    super.initState();
    _runSequence();
  }

  // Resets visual state then plays the current round's sequence.
  Future<void> _runSequence() async {
    if (!mounted) return;
    setState(() {
      _phase = 'showing';
      _showIndex = -1;
      _playerInput.clear();
      _roundSuccess = null;
    });
    await Future<void>.delayed(const Duration(milliseconds: 500));
    for (var i = 0; i < _sequence.length; i++) {
      if (!mounted) return;
      setState(() => _showIndex = i);
      await Future<void>.delayed(_flashDuration);
      if (!mounted) return;
      setState(() => _showIndex = -1);
      await Future<void>.delayed(_pauseDuration);
    }
    if (!mounted) return;
    setState(() => _phase = 'input');
  }

  void _onColorTap(GameColor color) {
    if (_phase != 'input') return;
    final expected = _sequence[_playerInput.length];

    setState(() {
      _playerInput.add(color); // always inside setState so counter re-renders

      if (color != expected) {
        _roundSuccess = false;
        _phase = 'roundResult';
      } else if (_playerInput.length == _sequence.length) {
        if (_roundIndex >= 2) {
          _phase = 'allDone';
        } else {
          _roundSuccess = true;
          _phase = 'roundResult';
        }
      }
      // Correct tap not yet completing the round: phase stays 'input',
      // counter increments and rebuilds on this same setState call.
    });
  }

  // Called by "PRÓXIMA RODADA" and "TENTAR NOVAMENTE" buttons.
  void _onContinueRound() {
    if (_roundSuccess == true) {
      setState(() => _roundIndex++);
    }
    // On failure _roundIndex is unchanged — retry same round.
    _runSequence();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.88),
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Container(
              margin: const EdgeInsets.all(20),
              padding: const EdgeInsets.all(26),
              decoration: BoxDecoration(
                color: const Color(0xF20C0C1A),
                border: Border.all(color: const Color(0xFFF59E0B), width: 3),
                boxShadow: const [
                  BoxShadow(color: Color(0xCC000000), offset: Offset(5, 5)),
                  BoxShadow(
                      color: Color(0x66FFD700), blurRadius: 24, spreadRadius: 1),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'TESTE DE CONTAMINAÇÃO',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.pressStart2p(
                      fontSize: 13,
                      color: const Color(0xFFFFF3B0),
                      height: 1.6,
                      shadows: const [
                        Shadow(
                            color: Colors.black,
                            offset: Offset(2, 2),
                            blurRadius: 3),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'RODADA ${_roundIndex + 1} / 3',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.pressStart2p(
                      fontSize: 9,
                      color: const Color(0xFFCBD5E1),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (_phase == 'showing') _buildShowPhase(),
                  if (_phase == 'input') _buildInputPhase(),
                  if (_phase == 'roundResult') _buildRoundResultPhase(),
                  if (_phase == 'allDone') _buildAllDonePhase(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildShowPhase() {
    final active = _showIndex >= 0 ? _sequence[_showIndex] : null;
    return Column(
      children: [
        Text(
          'Memorize a sequência:',
          style: GoogleFonts.pressStart2p(
              fontSize: 10, color: const Color(0xFFCBD5E1), height: 1.7),
        ),
        const SizedBox(height: 20),
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 90,
          height: 90,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color:
                active != null ? _colorValue(active) : const Color(0xFF1E293B),
            boxShadow: active != null
                ? [
                    BoxShadow(
                        color: _colorValue(active).withValues(alpha: 0.7),
                        blurRadius: 24,
                        spreadRadius: 4),
                  ]
                : [],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          active != null ? _colorLabel(active) : '...',
          style: GoogleFonts.pressStart2p(
            fontSize: 11,
            color: active != null
                ? _colorValue(active)
                : const Color(0xFF64748B),
          ),
        ),
      ],
    );
  }

  Widget _buildInputPhase() {
    return Column(
      children: [
        Text(
          'Repita a sequência!\n${_playerInput.length} / ${_sequence.length}',
          textAlign: TextAlign.center,
          style: GoogleFonts.pressStart2p(
              fontSize: 10, color: const Color(0xFFCBD5E1), height: 1.8),
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: GameColor.values
              .map((c) => _ColorButton(color: c, onTap: () => _onColorTap(c)))
              .toList(),
        ),
      ],
    );
  }

  Widget _buildRoundResultPhase() {
    final ok = _roundSuccess == true;
    return Column(
      children: [
        Text(
          ok
              ? 'Rodada ${_roundIndex + 1} concluída!'
              : 'Erro! Tente novamente.',
          textAlign: TextAlign.center,
          style: GoogleFonts.pressStart2p(
            fontSize: 11,
            color: ok ? const Color(0xFF4ADE80) : const Color(0xFFEF4444),
            height: 1.8,
            shadows: const [
              Shadow(
                  color: Colors.black,
                  offset: Offset(1.5, 1.5),
                  blurRadius: 3),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _PixelHudButton(
          label: ok ? 'PRÓXIMA RODADA' : 'TENTAR NOVAMENTE',
          onTap: _onContinueRound,
        ),
      ],
    );
  }

  Widget _buildAllDonePhase() {
    return Column(
      children: [
        Text(
          'Ufa! Certo, você não foi\ncontaminado. Vá para o\ngerador e ligue a energia.',
          textAlign: TextAlign.center,
          style: GoogleFonts.pressStart2p(
            fontSize: 10,
            color: const Color(0xFF4ADE80),
            height: 1.9,
            shadows: const [
              Shadow(
                  color: Colors.black,
                  offset: Offset(1.5, 1.5),
                  blurRadius: 3),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _PixelHudButton(
          label: 'CONTINUAR',
          onTap: () =>
              widget.game.quest2Manager.completeColorGame(success: true),
        ),
      ],
    );
  }

  Color _colorValue(GameColor c) => switch (c) {
        GameColor.red => const Color(0xFFEF4444),
        GameColor.blue => const Color(0xFF3B82F6),
        GameColor.green => const Color(0xFF22C55E),
      };

  String _colorLabel(GameColor c) => switch (c) {
        GameColor.red => 'VERMELHO',
        GameColor.blue => 'AZUL',
        GameColor.green => 'VERDE',
      };
}

class _ColorButton extends StatelessWidget {
  final GameColor color;
  final VoidCallback onTap;
  const _ColorButton({required this.color, required this.onTap});

  Color get _fill => switch (color) {
        GameColor.red => const Color(0xFFDC2626),
        GameColor.blue => const Color(0xFF2563EB),
        GameColor.green => const Color(0xFF16A34A),
      };

  String get _label => switch (color) {
        GameColor.red => 'VERM.',
        GameColor.blue => 'AZUL',
        GameColor.green => 'VERDE',
      };

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _fill,
          border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 2),
          boxShadow: [
            BoxShadow(
                color: _fill.withValues(alpha: 0.65),
                blurRadius: 14,
                spreadRadius: 2)
          ],
        ),
        child: Center(
          child: Text(
            _label,
            textAlign: TextAlign.center,
            style: GoogleFonts.pressStart2p(
              fontSize: 8,
              color: Colors.white,
              shadows: const [
                Shadow(color: Colors.black, offset: Offset(1, 1), blurRadius: 2)
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LightSwitchOverlay — retro mechanical switch panel for the generator.
// Tapping the switch flips OFF → ON, then calls game.activateGenerator()
// after a brief energising delay, removing the darkness and resetting zoom.
// ─────────────────────────────────────────────────────────────────────────────
class LightSwitchOverlay extends StatefulWidget {
  final H15Game game;
  const LightSwitchOverlay({super.key, required this.game});

  @override
  State<LightSwitchOverlay> createState() => _LightSwitchOverlayState();
}

class _LightSwitchOverlayState extends State<LightSwitchOverlay> {
  bool _isOn = false;
  bool _activating = false;

  void _flip() {
    if (_isOn || _activating) return;
    setState(() {
      _isOn = true;
      _activating = true;
    });
    Future<void>.delayed(const Duration(milliseconds: 1200), () {
      widget.game.activateGenerator();
      // overlay is removed inside activateGenerator()
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.90),
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 500),
              margin: const EdgeInsets.all(24),
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: _isOn
                    ? const Color(0xF20D1A0D)
                    : const Color(0xF20D0D1A),
                border: Border.all(
                  color: _isOn
                      ? const Color(0xFF22C55E)
                      : const Color(0xFF4B5563),
                  width: 3,
                ),
                boxShadow: [
                  const BoxShadow(
                      color: Color(0xCC000000), offset: Offset(5, 5)),
                  if (_isOn)
                    const BoxShadow(
                      color: Color(0x9916A34A),
                      blurRadius: 36,
                      spreadRadius: 6,
                    ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'GERADOR DE ENERGIA',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.pressStart2p(
                      fontSize: 12,
                      color: _isOn
                          ? const Color(0xFF86EFAC)
                          : const Color(0xFFFFF3B0),
                      height: 1.5,
                      shadows: const [
                        Shadow(
                            color: Colors.black,
                            offset: Offset(2, 2),
                            blurRadius: 3),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'PAINEL DE CONTROLE',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.pressStart2p(
                      fontSize: 8,
                      color: const Color(0xFF6B7280),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 30),

                  // ── Physical retro switch ─────────────────────────────────
                  GestureDetector(
                    onTap: _flip,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.easeInOut,
                      width: 88,
                      height: 148,
                      decoration: BoxDecoration(
                        color: _isOn
                            ? const Color(0xFF14532D)
                            : const Color(0xFF1C1C2E),
                        border: Border.all(
                          color: _isOn
                              ? const Color(0xFF22C55E)
                              : const Color(0xFF374151),
                          width: 3,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: _isOn
                                ? const Color(0xCC22C55E)
                                : const Color(0xAA000000),
                            blurRadius: _isOn ? 28 : 8,
                            spreadRadius: _isOn ? 6 : 0,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          Text(
                            'I',
                            style: GoogleFonts.pressStart2p(
                              fontSize: 20,
                              color: _isOn
                                  ? const Color(0xFF4ADE80)
                                  : const Color(0xFF374151),
                            ),
                          ),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 500),
                            curve: Curves.easeInOut,
                            width: 44,
                            height: 48,
                            decoration: BoxDecoration(
                              color: _isOn
                                  ? const Color(0xFF22C55E)
                                  : const Color(0xFFDC2626),
                              borderRadius: BorderRadius.circular(6),
                              boxShadow: const [
                                BoxShadow(
                                    color: Colors.black38,
                                    offset: Offset(0, 4),
                                    blurRadius: 4),
                              ],
                            ),
                            child: Center(
                              child: Text(
                                _isOn ? 'ON' : 'OFF',
                                style: GoogleFonts.pressStart2p(
                                  fontSize: 9,
                                  color: Colors.white,
                                  shadows: const [
                                    Shadow(
                                        color: Colors.black,
                                        offset: Offset(1, 1)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Text(
                            'O',
                            style: GoogleFonts.pressStart2p(
                              fontSize: 20,
                              color: !_isOn
                                  ? const Color(0xFFEF4444)
                                  : const Color(0xFF374151),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 22),
                  Text(
                    _activating ? 'ENERGIZANDO...' : 'Toque para ligar',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.pressStart2p(
                      fontSize: 9,
                      color: _activating
                          ? const Color(0xFF4ADE80)
                          : const Color(0xFF6B7280),
                      height: 1.8,
                      shadows: _activating
                          ? const [
                              Shadow(
                                  color: Color(0x8822C55E),
                                  blurRadius: 8,
                                  offset: Offset(0, 0)),
                            ]
                          : null,
                    ),
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

// ─────────────────────────────────────────────────────────────────────────────
// LevelCompleteOverlay — shown after the generator is activated (end of Fase 1)
// ─────────────────────────────────────────────────────────────────────────────
class LevelCompleteOverlay extends StatelessWidget {
  final H15Game game;
  const LevelCompleteOverlay({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.85),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 560),
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 36),
          decoration: BoxDecoration(
            color: const Color(0xF20A1A0A),
            border: Border.all(color: const Color(0xFF22C55E), width: 3),
            boxShadow: const [
              BoxShadow(color: Color(0xAA000000), offset: Offset(5, 5)),
              BoxShadow(
                color: Color(0x8816A34A),
                blurRadius: 36,
                spreadRadius: 6,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'FASE 1 CONCLUÍDA!',
                textAlign: TextAlign.center,
                style: GoogleFonts.pressStart2p(
                  fontSize: 20,
                  color: const Color(0xFF4ADE80),
                  height: 1.4,
                  shadows: const [
                    Shadow(color: Color(0xFF052E16), offset: Offset(3, 3)),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Vá para a próxima fase!',
                textAlign: TextAlign.center,
                style: GoogleFonts.pressStart2p(
                  fontSize: 11,
                  color: const Color(0xFFFFF3B0),
                  height: 1.9,
                  shadows: const [
                    Shadow(color: Colors.black, offset: Offset(2, 2), blurRadius: 3),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).pop(true),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF052E16),
                    border: Border.all(color: const Color(0xFF22C55E), width: 2.5),
                    boxShadow: const [
                      BoxShadow(color: Color(0x8816A34A), blurRadius: 14),
                    ],
                  ),
                  child: Text(
                    'PRÓXIMO NÍVEL',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.pressStart2p(
                      fontSize: 12,
                      color: const Color(0xFF86EFAC),
                      height: 1.5,
                      shadows: const [
                        Shadow(color: Colors.black, offset: Offset(2, 2), blurRadius: 3),
                      ],
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
