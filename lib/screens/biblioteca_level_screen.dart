import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../game/biblioteca_game.dart';

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
          GameWidget<BibliotecaGame>(
            game: _game,
            loadingBuilder: (_) => const Center(
              child: CircularProgressIndicator(color: Color(0xFFF5C842)),
            ),
            overlayBuilderMap: {
              'Lore': (_, game) => BibliotecaLoreOverlay(game: game),
            },
          ),
          ValueListenableBuilder<bool>(
            valueListenable: _game.dialogOpen,
            builder: (_, dialogOpen, __) {
              if (dialogOpen) return const SizedBox.shrink();
              return BibliotecaHud(
                game: _game,
                onBack: () => Navigator.of(context).pop(false),
                devMode: widget.devMode,
              );
            },
          ),
        ],
      ),
    );
  }
}

class BibliotecaHud extends StatelessWidget {
  const BibliotecaHud({
    super.key,
    required this.game,
    required this.onBack,
    this.devMode = false,
  });

  final BibliotecaGame game;
  final VoidCallback onBack;
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
                    child: Text('< MAPA', style: _font(8, const Color(0xFFF5C842))),
                  ),
                  const SizedBox(height: 12),
                  ValueListenableBuilder<bool>(
                    valueListenable: game.hasAccessCardNotifier,
                    builder: (_, hasCard, __) => Text(
                      hasCard ? 'CARTAO OK' : 'SEM CARTAO',
                      style: _font(
                        8,
                        hasCard ? const Color(0xFF86EFAC) : const Color(0xFFFCA5A5),
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
                width: 360,
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
            right: 24,
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
                    builder: (_, label, __) => _PixelButton(
                      label: label,
                      onTap: game.interact,
                    ),
                  ),
                ),
              ),
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

class BibliotecaLoreOverlay extends StatelessWidget {
  const BibliotecaLoreOverlay({super.key, required this.game});

  final BibliotecaGame game;

  @override
  Widget build(BuildContext context) {
    final lore = game.activeLore.value;
    return Material(
      color: Colors.black.withValues(alpha: .88),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 680),
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xF20A0A0A),
            border: Border.all(color: const Color(0xFF38BDF8), width: 2.5),
            boxShadow: const [BoxShadow(color: Colors.black, offset: Offset(5, 5))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                lore?.title ?? 'ARQUIVO',
                textAlign: TextAlign.center,
                style: _font(14, const Color(0xFF7DD3FC)),
              ),
              const SizedBox(height: 18),
              Text(
                lore?.body ?? '',
                textAlign: TextAlign.center,
                style: _font(9, const Color(0xFFE5E7EB), height: 1.9),
              ),
              const SizedBox(height: 22),
              _PixelButton(label: 'FECHAR', onTap: game.closeLore),
            ],
          ),
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
        border: Border.all(color: const Color(0xFF38BDF8), width: 1.5),
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
          color: enabled ? const Color(0xFF061827) : const Color(0xFF1F2937),
          border: Border.all(
            color: enabled ? const Color(0xFF38BDF8) : const Color(0xFF4B5563),
            width: 2,
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: _font(
            8,
            enabled ? const Color(0xFFE0F2FE) : const Color(0xFF9CA3AF),
            height: 1.5,
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
