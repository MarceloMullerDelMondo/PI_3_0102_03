import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../game/caa_game.dart';
import 'base_game_hud.dart';

class CaaLevelScreen extends StatefulWidget {
  const CaaLevelScreen({
    super.key,
    required this.playerName,
    this.devMode = false,
  });

  final String playerName;
  final bool devMode;

  @override
  State<CaaLevelScreen> createState() => _CaaLevelScreenState();
}

class _CaaLevelScreenState extends State<CaaLevelScreen>
    with WidgetsBindingObserver {
  late final CAALevel _game;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _game = CAALevel(playerName: widget.playerName);
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
          GameWidget<CAALevel>(
            game: _game,
            loadingBuilder: (_) => const Center(
              child: CircularProgressIndicator(color: Color(0xFFF5C842)),
            ),
            overlayBuilderMap: {
              'DilemmaMenu': (_, game) => CaaDilemmaMenuOverlay(game: game),
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
                // Horde kills shown in extraTopLeft; no separate stats row needed.
                onBack: () => Navigator.of(context).pop(false),
                extraTopLeft: ValueListenableBuilder<CAAPhase>(
                  valueListenable: _game.phase,
                  builder: (_, ph, __) => Visibility(
                    visible: ph == CAAPhase.defendingHorde,
                    child: _HordeCounter(game: _game),
                  ),
                ),
                extraStack: [
                  // Interact button (centre-right)
                  Positioned(
                    right: 145,
                    bottom: 24,
                    child: ValueListenableBuilder<bool>(
                      valueListenable: _game.canInteract,
                      builder: (_, can, __) => AnimatedOpacity(
                        opacity: can ? 1 : 0,
                        duration: const Duration(milliseconds: 140),
                        child: IgnorePointer(
                          ignoring: !can,
                          child: ValueListenableBuilder<String>(
                            valueListenable: _game.interactLabel,
                            builder: (_, label, __) => _PixelButton(
                              label: label,
                              onTap: _game.interact,
                            ),
                          ),
                        ),
                      ),
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
                  // Game-over overlay (full-screen, behind nothing)
                  Positioned.fill(
                    child: ValueListenableBuilder<bool>(
                      valueListenable: _game.gameOver,
                      builder: (_, gameOver, __) {
                        if (!gameOver) {
                          return const IgnorePointer(child: SizedBox.expand());
                        }
                        return ColoredBox(
                          color: Colors.black.withValues(alpha: .82),
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 20,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: .72),
                                border: Border.all(
                                  color: const Color(0xFFB87A18),
                                  width: 1.5,
                                ),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'VOCE CAIU',
                                    style: _font(16, const Color(0xFFFF6666)),
                                  ),
                                  const SizedBox(height: 18),
                                  _PixelButton(
                                    label: 'REVIVER',
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
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: .72),
                          border: Border.all(
                            color: const Color(0xFFB87A18),
                            width: 1.5,
                          ),
                        ),
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

/// Injected into [BaseGameHud.extraTopLeft] for Phase 4.
/// Shows the live horde kill count and zombies remaining.
class _HordeCounter extends StatelessWidget {
  const _HordeCounter({required this.game});

  final CAALevel game;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xE607070B),
        border: Border.all(color: const Color(0xFFF59E0B), width: 1.5),
      ),
      child: ValueListenableBuilder<int>(
        valueListenable: game.zombiesKilled,
        builder: (_, kills, __) {
          final restam = (CAALevel.hordeTarget - kills).clamp(0, CAALevel.hordeTarget);
          return Text(
            'HORDA $kills/${CAALevel.hordeTarget}  RESTAM $restam',
            style: _font(7, const Color(0xFFFFD166)),
          );
        },
      ),
    );
  }
}

class CaaDilemmaMenuOverlay extends StatelessWidget {
  const CaaDilemmaMenuOverlay({super.key, required this.game});

  final CAALevel game;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: .90),
      child: Center(
        child: Container(
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
              Text(
                'DILEMA — SARGENTO ROCHA',
                textAlign: TextAlign.center,
                style: _font(14, const Color(0xFFF5C842)),
              ),
              const SizedBox(height: 16),
              Text(
                'A horda foi contida. O transmissor so aguenta um envio.\nEscolha o destino do sinal.',
                textAlign: TextAlign.center,
                style: _font(9, const Color(0xFFE5E7EB), height: 1.9),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 14,
                runSpacing: 14,
                alignment: WrapAlignment.center,
                children: [
                  _ChoiceButton(
                    title: 'SINAL DE RESGATE\n(PORTAO 1)',
                    subtitle: 'Prioriza evacuar os sobreviventes do campus.',
                    onTap: () => game.chooseFinalSignal(CAAFinalChoice.rescueSignal),
                  ),
                  _ChoiceButton(
                    title: 'SINAL DE TRANSMISSAO\nDE DADOS (REITORIA)',
                    subtitle: 'Envia os dados da cura para a Reitoria.',
                    onTap: () => game.chooseFinalSignal(CAAFinalChoice.cureData),
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

class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 320,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF2E1E06),
          border: Border.all(color: const Color(0xFFF5C842), width: 2),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: _font(8, const Color(0xFFFDE68A), height: 1.6),
            ),
            const SizedBox(height: 10),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: _font(7, const Color(0xFFE5E7EB), height: 1.7),
            ),
          ],
        ),
      ),
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
