import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../game/biblioteca_game.dart';
import '../models/game_state.dart';
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
              'CardSwipe': (_, game) => CardSwipeOverlay(game: game),
            },
          ),

          // ── Base HUD (health · timer · mission) + card counter ────────
          BaseGameHud(
            currentHealth: _game.hud.currentHealth,
            maxHealth: _game.hud.maxHealth,
            missionText: _game.hud.missionText,
            hudMessage: _game.hud.hudMessage,
            survivalSeconds: _game.hud.survivalSeconds,
            onBack: () => Navigator.of(context).pop(false),
            extraTopLeft: _CardCounter(game: _game),
            mapNotifier: GameState.instance.hasMapaNotifier,
            extraStack: [
              // "USAR CARTÃO" button — appears only when player is at the door
              // with both items collected. Bottom-right, above joystick area.
              Positioned(
                right: 24,
                bottom: 80,
                child: ValueListenableBuilder<bool>(
                  valueListenable: _game.showCardReaderPrompt,
                  builder: (_, show, __) => AnimatedOpacity(
                    opacity: show ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 180),
                    child: IgnorePointer(
                      ignoring: !show,
                      child: GestureDetector(
                        onTap: _game.openCardSwipe,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF050D18),
                            border: Border.all(
                                color: const Color(0xFF86EFAC), width: 2.5),
                            boxShadow: const [
                              BoxShadow(
                                  color: Color(0x6686EFAC), blurRadius: 18),
                            ],
                          ),
                          child: Text(
                            'USAR CARTÃO',
                            style: _font(8, const Color(0xFF86EFAC)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
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

// ── Card Swipe Mini-game Overlay ──────────────────────────────────────────

class CardSwipeOverlay extends StatefulWidget {
  const CardSwipeOverlay({required this.game, super.key});

  final BibliotecaGame game;

  @override
  State<CardSwipeOverlay> createState() => _CardSwipeOverlayState();
}

class _CardSwipeOverlayState extends State<CardSwipeOverlay> {
  // Track is 260 px wide; card is 72 px wide → max travel = 188 px.
  // Threshold at 170 px (~90 % of max) to feel satisfying but not too strict.
  static const double _trackW = 260;
  static const double _cardW = 72;
  static const double _cardH = 46;
  static const double _threshold = 170;

  double _cardX = 0; // 0 = leftmost start
  bool _done = false;
  bool _success = false;

  double get _maxX => _trackW - _cardW;

  void _onDragUpdate(DragUpdateDetails d) {
    if (_done) return;
    setState(() => _cardX = (_cardX + d.delta.dx).clamp(0, _maxX));
  }

  void _onDragEnd(DragEndDetails _) {
    if (_done) return;
    if (_cardX >= _threshold) {
      setState(() {
        _done = true;
        _success = true;
        _cardX = _maxX;
      });
      // Brief success pause so the player sees the green state.
      Future.delayed(const Duration(milliseconds: 700), () {
        if (mounted) widget.game.onCardSwipeSuccess();
      });
    } else {
      // Snap back — try again.
      setState(() => _cardX = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final borderColor =
        _success ? const Color(0xFF86EFAC) : const Color(0xFFF59E0B);
    final glowColor =
        _success ? const Color(0x6686EFAC) : const Color(0x55F59E0B);

    return Material(
      color: Colors.black.withValues(alpha: 0.88),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
          decoration: BoxDecoration(
            color: const Color(0xFF050D18),
            border: Border.all(color: borderColor, width: 2.5),
            boxShadow: [
              BoxShadow(color: glowColor, blurRadius: 28, spreadRadius: -4),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Title
              Text('LEITOR DE CARTÃO',
                  style: _font(10, const Color(0xFFF59E0B))),
              const SizedBox(height: 10),
              // Status line
              Text(
                _success ? 'ACESSO CONCEDIDO ✓' : 'Deslize o cartão →',
                style: _font(
                  8,
                  _success
                      ? const Color(0xFF86EFAC)
                      : const Color(0xFFD1D5DB),
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 22),

              // Swipe track
              _SwipeTrack(
                trackW: _trackW,
                cardW: _cardW,
                cardH: _cardH,
                cardX: _cardX,
                success: _success,
                onDragUpdate: _onDragUpdate,
                onDragEnd: _onDragEnd,
              ),

              // Arrow hint
              if (!_success) ...[
                const SizedBox(height: 8),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.arrow_forward,
                        color: Color(0xFF4B5563), size: 14),
                    Icon(Icons.arrow_forward,
                        color: Color(0xFF6B7280), size: 14),
                    Icon(Icons.arrow_forward,
                        color: Color(0xFF9CA3AF), size: 14),
                  ],
                ),
              ],

              const SizedBox(height: 22),

              // Cancel — hidden after success
              if (!_success)
                _OverlayButton(
                  label: 'CANCELAR',
                  color: const Color(0xFF1F2937),
                  borderColor: const Color(0xFF4B5563),
                  textColor: const Color(0xFF9CA3AF),
                  onTap: widget.game.dismissCardSwipe,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// Horizontal swipe track with a draggable access-card widget.
class _SwipeTrack extends StatelessWidget {
  const _SwipeTrack({
    required this.trackW,
    required this.cardW,
    required this.cardH,
    required this.cardX,
    required this.success,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final double trackW, cardW, cardH, cardX;
  final bool success;
  final void Function(DragUpdateDetails) onDragUpdate;
  final void Function(DragEndDetails) onDragEnd;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: trackW,
      height: cardH + 16,
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        border: Border.all(
          color: success ? const Color(0xFF86EFAC) : const Color(0xFF374151),
          width: 1.5,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Stack(
        children: [
          // Slot line
          Positioned(
            left: 10,
            right: 10,
            top: (cardH + 16) / 2 - 1,
            height: 2,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: success
                    ? const Color(0xFF86EFAC)
                    : const Color(0xFF1F2937),
              ),
            ),
          ),
          // Card — the only draggable surface
          Positioned(
            left: 8 + cardX,
            top: 8,
            child: GestureDetector(
              onHorizontalDragUpdate: onDragUpdate,
              onHorizontalDragEnd: onDragEnd,
              child: Container(
                width: cardW,
                height: cardH,
                decoration: BoxDecoration(
                  color: success
                      ? const Color(0xFF86EFAC)
                      : const Color(0xFF1D4ED8),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                    color: success
                        ? const Color(0xFF4ADE80)
                        : const Color(0xFF60A5FA),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: success
                          ? const Color(0x8086EFAC)
                          : const Color(0x6038BDF8),
                      blurRadius: 10,
                    ),
                  ],
                ),
                // Card face: gold stripe + chip
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      height: 6,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFACC15),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      height: 3,
                      color: Colors.white.withValues(alpha: 0.25),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
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
