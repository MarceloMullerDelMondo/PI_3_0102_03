import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../game/caa_game.dart';

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
              'FinalChoice': (_, game) => CaaFinalChoiceOverlay(game: game),
            },
          ),
          ValueListenableBuilder<bool>(
            valueListenable: _game.dialogOpen,
            builder: (_, dialogOpen, __) => ValueListenableBuilder<bool>(
              valueListenable: _game.gameOver,
              builder: (_, gameOver, __) {
                if (dialogOpen) return const SizedBox.shrink();
                return CaaHud(
                  game: _game,
                  onBack: () => Navigator.of(context).pop(false),
                  devMode: widget.devMode,
                  showGameOver: gameOver,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class CaaHud extends StatelessWidget {
  const CaaHud({
    super.key,
    required this.game,
    required this.onBack,
    required this.showGameOver,
    this.devMode = false,
  });

  final CAALevel game;
  final VoidCallback onBack;
  final bool showGameOver;
  final bool devMode;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            left: 12,
            top: 10,
            child: _HudPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: onBack,
                    child: Text('< MAPA',
                        style: _font(8, const Color(0xFFF5C842))),
                  ),
                  const SizedBox(height: 12),
                  ValueListenableBuilder<double>(
                    valueListenable: game.currentHealth,
                    builder: (_, hp, __) => ValueListenableBuilder<double>(
                      valueListenable: game.maxHealth,
                      builder: (_, max, __) => Text(
                        'VIDA ${hp.round()}/${max.round()}',
                        style: _font(8, Colors.white),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ValueListenableBuilder<int>(
                    valueListenable: game.zombiesKilled,
                    builder: (_, kills, __) => ValueListenableBuilder<int>(
                      valueListenable: game.zombiesRemaining,
                      builder: (_, left, __) => Text(
                        'HORDA $kills/${CAALevel.hordeTarget}  RESTAM $left',
                        style: _font(7, const Color(0xFFFFD166)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 10,
            right: 12,
            child: _HudPanel(
              child: SizedBox(
                width: 370,
                child: ValueListenableBuilder<String>(
                  valueListenable: game.missionText,
                  builder: (_, text, __) => Text(
                    text,
                    textAlign: TextAlign.right,
                    style: _font(8, const Color(0xFFFDE68A), height: 1.7),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 145,
            bottom: 24,
            child: ValueListenableBuilder<bool>(
              valueListenable: game.canInteract,
              builder: (_, can, __) => AnimatedOpacity(
                opacity: can ? 1 : 0,
                duration: const Duration(milliseconds: 140),
                child: IgnorePointer(
                  ignoring: !can,
                  child: ValueListenableBuilder<String>(
                    valueListenable: game.interactLabel,
                    builder: (_, label, __) =>
                        _PixelButton(label: label, onTap: game.interact),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 24,
            bottom: 20,
            child: ValueListenableBuilder<bool>(
              valueListenable: game.attackEnabled,
              builder: (_, enabled, __) =>
                  _AttackButton(enabled: enabled, onTap: game.attack),
            ),
          ),
          Positioned(
            top: 78,
            left: 0,
            right: 0,
            child: ValueListenableBuilder<String?>(
              valueListenable: game.hudMessage,
              builder: (_, message, __) => AnimatedOpacity(
                opacity: message == null ? 0 : 1,
                duration: const Duration(milliseconds: 160),
                child: IgnorePointer(
                  child: Center(
                    child: _HudPanel(
                      child: Text(
                        message ?? '',
                        textAlign: TextAlign.center,
                        style: _font(8, const Color(0xFFF5C842), height: 1.6),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (showGameOver)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: .82),
                child: Center(
                  child: _HudPanel(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('VOCE CAIU',
                            style: _font(16, const Color(0xFFFF6666))),
                        const SizedBox(height: 18),
                        _PixelButton(
                          label: 'REVIVER',
                          onTap: game.reviveAtCheckpoint,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (devMode)
            Positioned(
              bottom: 24,
              left: 140,
              child: _HudPanel(
                child: Text('DEV', style: _font(7, const Color(0xFF00FF00))),
              ),
            ),
        ],
      ),
    );
  }
}

class CaaFinalChoiceOverlay extends StatelessWidget {
  const CaaFinalChoiceOverlay({super.key, required this.game});

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
                'TERMINAL DO CAA',
                textAlign: TextAlign.center,
                style: _font(16, const Color(0xFFF5C842)),
              ),
              const SizedBox(height: 16),
              Text(
                'A horda foi contida. O transmissor so aguenta um envio. Escolha o sinal que a Reitoria recebera.',
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
                    title: 'SINAL DE RESGATE',
                    subtitle: 'Prioriza evacuar sobreviventes.',
                    onTap: () =>
                        game.chooseFinalSignal(CAAFinalChoice.rescueSignal),
                  ),
                  _ChoiceButton(
                    title: 'SINAL DE TRANSMISSAO DE DADOS',
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
