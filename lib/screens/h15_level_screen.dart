import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../game/h15_game.dart';

class H15LevelScreen extends StatefulWidget {
  const H15LevelScreen({super.key});

  @override
  State<H15LevelScreen> createState() => _H15LevelScreenState();
}

class _H15LevelScreenState extends State<H15LevelScreen> {
  late final H15Game _game;

  @override
  void initState() {
    super.initState();
    _game = H15Game();
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
            },
          ),
          ValueListenableBuilder<bool>(
            valueListenable: _game.questDialogOpen,
            builder: (_, questOpen, __) {
              if (questOpen) return const SizedBox.shrink();

              return SafeArea(
                child: Stack(
                  children: [
                    Positioned(
                      top: 12,
                      left: 12,
                      child: _PixelHudButton(
                        label: 'VOLTAR',
                        onTap: () => Navigator.of(context).pop(false),
                      ),
                    ),
                    Positioned(
                      right: 24,
                      bottom: 128,
                      child: ValueListenableBuilder<bool>(
                        valueListenable: _game.canInteract,
                        builder: (_, canInteract, __) {
                          return AnimatedOpacity(
                            opacity: canInteract ? 1 : 0,
                            duration: const Duration(milliseconds: 140),
                            child: IgnorePointer(
                              ignoring: !canInteract,
                              child: _PixelHudButton(
                                label: 'INTERAGIR',
                                onTap: _game.interact,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    Positioned(
                      right: 24,
                      bottom: 24,
                      child: ValueListenableBuilder<bool>(
                        valueListenable: _game.attackEnabled,
                        builder: (_, enabled, __) => _AttackButton(
                          enabled: enabled,
                          onTap: _game.attack,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class QuestOverlay extends StatefulWidget {
  final H15Game game;

  const QuestOverlay({
    super.key,
    required this.game,
  });

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
    _timer = Timer.periodic(const Duration(milliseconds: 24), (timer) {
      if (!mounted) return;
      if (_visibleChars >= _fullText.length) {
        timer.cancel();
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
    final text = _fullText.substring(
      0,
      _visibleChars.clamp(0, _fullText.length),
    );

    return Container(
      color: Colors.black.withValues(alpha: 0.72),
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Container(
              margin: const EdgeInsets.all(22),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xEE090B12),
                border: Border.all(
                  color: const Color(0xFFF5C842),
                  width: 2,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x8838BDF8),
                    blurRadius: 24,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const _HologramAvatar(),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          'Prof. Álvaro (Holograma)',
                          style: GoogleFonts.pressStart2p(
                            fontSize: 11,
                            color: const Color(0xFF7DD3FC),
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    height: 1,
                    color: const Color(0xFFF5C842).withValues(alpha: 0.55),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    text,
                    style: GoogleFonts.pressStart2p(
                      fontSize: 9,
                      color: const Color(0xFFDFF8FF),
                      height: 1.9,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Align(
                    alignment: Alignment.centerRight,
                    child: _PixelHudButton(
                      label: 'ACEITAR',
                      onTap: widget.game.closeQuestDialog,
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

class _HologramAvatar extends StatelessWidget {
  const _HologramAvatar();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 74,
      height: 74,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0x6638BDF8),
        border: Border.all(color: const Color(0xFF7DD3FC), width: 2),
        boxShadow: const [
          BoxShadow(
            color: Color(0xAA38BDF8),
            blurRadius: 18,
            spreadRadius: 2,
          ),
        ],
      ),
      child: const Icon(
        Icons.person_4,
        color: Color(0xFFDFF8FF),
        size: 40,
      ),
    );
  }
}

class ServerOverlay extends StatelessWidget {
  final H15Game game;

  const ServerOverlay({
    super.key,
    required this.game,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.76),
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Container(
              margin: const EdgeInsets.all(24),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xEE001307),
                border: Border.all(
                  color: const Color(0xFF22C55E),
                  width: 2,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0xAA16A34A),
                    blurRadius: 22,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'TERMINAL DE SEGURANÇA',
                    style: GoogleFonts.pressStart2p(
                      fontSize: 11,
                      color: const Color(0xFF86EFAC),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    '[SISTEMA]\nReiniciando Servidores...\nEnergia Restaurada!',
                    style: GoogleFonts.pressStart2p(
                      fontSize: 10,
                      color: const Color(0xFFBBF7D0),
                      height: 2.0,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Align(
                    alignment: Alignment.centerRight,
                    child: _PixelHudButton(
                      label: 'OK',
                      onTap: game.restorePowerAndCloseServerDialog,
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

class _PixelHudButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _PixelHudButton({
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0xCC0A0600),
          border: Border.all(color: const Color(0xFFD4860A), width: 1.5),
        ),
        child: Text(
          label,
          style: GoogleFonts.pressStart2p(
            fontSize: 8,
            color: const Color(0xFFF5C842),
          ),
        ),
      ),
    );
  }
}

class _AttackButton extends StatefulWidget {
  final bool enabled;
  final VoidCallback onTap;

  const _AttackButton({
    required this.enabled,
    required this.onTap,
  });

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
        duration: const Duration(milliseconds: 80),
        scale: _pressed ? 0.94 : 1,
        child: Container(
          width: 92,
          height: 92,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.enabled
                ? const Color(0xCC8B0000)
                : const Color(0x774A4A4A),
            border: Border.all(
              color: widget.enabled
                  ? const Color(0xFFFF7777)
                  : const Color(0xFF777777),
              width: 2,
            ),
            boxShadow: widget.enabled
                ? const [
              BoxShadow(
                color: Color(0xAAFF3333),
                blurRadius: 18,
                spreadRadius: 1,
              ),
              BoxShadow(
                color: Color(0xAA0A0600),
                offset: Offset(0, 5),
                blurRadius: 0,
              ),
            ]
                : const [
                    BoxShadow(
                      color: Color(0xAA0A0600),
                      offset: Offset(0, 5),
                      blurRadius: 0,
                    ),
                  ],
          ),
          child: Center(
            child: Text(
              'ATAQUE',
              textAlign: TextAlign.center,
              style: GoogleFonts.pressStart2p(
                fontSize: 10,
                color: widget.enabled
                    ? const Color(0xFFFFDDDD)
                    : const Color(0xFFB0B0B0),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
