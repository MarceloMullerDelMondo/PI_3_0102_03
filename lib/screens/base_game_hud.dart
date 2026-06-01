import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ── Map viewer ────────────────────────────────────────────────────────────────

void _showMapOverlay(BuildContext context) {
  showDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.92),
    builder: (_) => const MapViewerOverlay(),
  );
}

/// Full-screen modal that shows mapaaberto.png with pinch-to-zoom support.
/// Dismiss by tapping the barrier or the FECHAR button.
class MapViewerOverlay extends StatelessWidget {
  const MapViewerOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 4,
                child: Image.asset(
                  'assets/images/objects/mapaaberto.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF07070B),
                    border:
                        Border.all(color: const Color(0xFFF59E0B), width: 2),
                    boxShadow: const [
                      BoxShadow(
                          color: Color(0xAA000000), offset: Offset(2, 2)),
                    ],
                  ),
                  child: Text('FECHAR', style: _font(8, const Color(0xFFFFF3B0))),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Reusable Flutter HUD that replicates the Phase 1 (H15) layout:
///
///   [VOLTAR] [♥ 100/100 ██████]      [Missão texto →]
///   [MM:SS]  [☠ N]
///   [extraTopLeft]
///                  ← centro: flash messages →
///   ...extraStack (Positioned widgets)
///
/// Accepts individual [ValueNotifier]s so it works with any game class —
/// those that use [BaseHudComponent] (e.g. BibliotecaGame) pass `hud.*`
/// fields; games with their own notifiers (Cafeteria, CAA, Reitoria) pass
/// the game notifiers directly.
///
/// Phase-specific content is injected via:
/// - [extraTopLeft] — widget rendered below the stats row in the left panel.
/// - [extraStack]   — [Positioned] widgets overlaid on the full HUD Stack.
class BaseGameHud extends StatelessWidget {
  const BaseGameHud({
    super.key,
    required this.currentHealth,
    required this.maxHealth,
    required this.missionText,
    required this.hudMessage,
    required this.onBack,
    this.survivalSeconds,
    this.showKills = false,
    this.killsNotifier,
    this.extraTopLeft,
    this.extraStack = const [],
    this.mapNotifier,
  });

  // ── Required notifiers ──────────────────────────────────────────────────
  final ValueNotifier<double> currentHealth;

  /// Pass `hud.maxHealth` (a plain double) or `game.maxHealth.value` (100.0).
  final double maxHealth;
  final ValueNotifier<String> missionText;
  final ValueNotifier<String?> hudMessage;
  final VoidCallback onBack;

  // ── Optional stats-row ──────────────────────────────────────────────────
  /// When non-null, the MM:SS survival timer is shown in the stats row.
  final ValueNotifier<int>? survivalSeconds;

  /// When true (and [killsNotifier] is provided), "☠ N" is shown in the
  /// stats row.
  final bool showKills;
  final ValueNotifier<int>? killsNotifier;

  // ── Injection points ────────────────────────────────────────────────────
  /// Rendered below the stats row inside the left panel.
  final Widget? extraTopLeft;

  /// Arbitrary [Positioned] widgets overlaid on the full HUD Stack.
  final List<Widget> extraStack;

  /// When provided, a "MAPA" button appears bottom-left whenever its value
  /// is true. Tapping it opens [MapViewerOverlay]. Pass
  /// [GameState.instance.hasMapaNotifier] to make it persist across levels.
  final ValueNotifier<bool>? mapNotifier;

  bool get _showStatsRow =>
      survivalSeconds != null || (showKills && killsNotifier != null);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ── Top-left: back · health · stats · phase extras ─────────────
          Positioned(
            top: 10,
            left: 12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    _HudButton(label: 'VOLTAR', onTap: onBack),
                    const SizedBox(width: 8),
                    ValueListenableBuilder<double>(
                      valueListenable: currentHealth,
                      builder: (_, hp, __) =>
                          _HealthBar(current: hp, max: maxHealth),
                    ),
                  ],
                ),
                if (_showStatsRow) ...[
                  const SizedBox(height: 5),
                  _StatsRow(
                    survivalSeconds: survivalSeconds,
                    showKills: showKills,
                    killsNotifier: killsNotifier,
                  ),
                ],
                if (extraTopLeft != null) ...[
                  const SizedBox(height: 5),
                  extraTopLeft!,
                ],
              ],
            ),
          ),
          // ── Top-right: mission tracker ──────────────────────────────────
          Positioned(
            top: 10,
            right: 12,
            child: ValueListenableBuilder<String>(
              valueListenable: missionText,
              builder: (_, text, __) => _MissionTracker(text: text),
            ),
          ),
          // ── Centre-top: transient flash message ─────────────────────────
          Positioned(
            top: 72,
            left: 0,
            right: 0,
            child: ValueListenableBuilder<String?>(
              valueListenable: hudMessage,
              builder: (_, msg, __) => AnimatedOpacity(
                opacity: msg == null ? 0 : 1,
                duration: const Duration(milliseconds: 160),
                child: IgnorePointer(
                  child: Center(
                    child: _MsgPanel(
                      child: Text(
                        msg ?? '',
                        textAlign: TextAlign.center,
                        style: _font(9, const Color(0xFFF5C842), height: 1.6),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // ── Persistent map button — bottom-right, visible when collected ──
          if (mapNotifier != null)
            Positioned(
              right: 12,
              bottom: 20,
              child: ValueListenableBuilder<bool>(
                valueListenable: mapNotifier!,
                builder: (ctx, hasMapa, __) => hasMapa
                    ? _HudButton(
                        label: 'MAPA',
                        onTap: () => _showMapOverlay(ctx),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          // ── Phase-specific overlay widgets ──────────────────────────────
          ...extraStack,
        ],
      ),
    );
  }
}

// ── Internal Widgets ──────────────────────────────────────────────────────
// Exact visual match to the h15_level_screen.dart Phase 1 design.

class _HealthBar extends StatelessWidget {
  const _HealthBar({required this.current, required this.max});

  final double current;
  final double max;

  @override
  Widget build(BuildContext context) {
    final progress = max > 0 ? (current / max).clamp(0.0, 1.0) : 0.0;
    return Container(
      width: 180,
      height: 32,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xF207070B),
        border: Border.all(color: Colors.amber.shade900, width: 2),
        boxShadow: const [BoxShadow(color: Color(0xAA000000), offset: Offset(2, 2))],
      ),
      child: Row(
        children: [
          const Text(
            '♥',
            style: TextStyle(fontSize: 14, color: Color(0xFFEF4444), height: 1),
          ),
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
                          Shadow(color: Colors.black, offset: Offset(1.5, 1.5), blurRadius: 3),
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

class _StatsRow extends StatelessWidget {
  const _StatsRow({
    required this.survivalSeconds,
    required this.showKills,
    required this.killsNotifier,
  });

  final ValueNotifier<int>? survivalSeconds;
  final bool showKills;
  final ValueNotifier<int>? killsNotifier;

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
          if (survivalSeconds != null)
            ValueListenableBuilder<int>(
              valueListenable: survivalSeconds!,
              builder: (_, s, __) => Text(
                _fmtTime(s),
                style: GoogleFonts.pressStart2p(
                  fontSize: 11,
                  color: Colors.white,
                  shadows: const [
                    Shadow(color: Colors.black, offset: Offset(1.5, 1.5), blurRadius: 3),
                  ],
                ),
              ),
            ),
          if (survivalSeconds != null && showKills && killsNotifier != null)
            const SizedBox(width: 18),
          if (showKills && killsNotifier != null)
            ValueListenableBuilder<int>(
              valueListenable: killsNotifier!,
              builder: (_, k, __) => Text(
                '☠ $k',
                style: GoogleFonts.pressStart2p(
                  fontSize: 14,
                  color: const Color(0xFFFFF3B0),
                  shadows: const [
                    Shadow(color: Colors.black, offset: Offset(1.5, 1.5), blurRadius: 3),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _fmtTime(int s) =>
      '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
}

class _MissionTracker extends StatelessWidget {
  const _MissionTracker({required this.text});

  final String text;

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
              Shadow(color: Colors.black, offset: Offset(1.5, 1.5), blurRadius: 3),
            ],
          ),
        ),
      ),
    );
  }
}

class _MsgPanel extends StatelessWidget {
  const _MsgPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        border: Border.all(color: const Color(0xFF38BDF8), width: 1.5),
      ),
      child: child,
    );
  }
}

class _HudButton extends StatelessWidget {
  const _HudButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF07070B),
          border: Border.all(color: const Color(0xFFF59E0B), width: 2),
          boxShadow: const [BoxShadow(color: Color(0xAA000000), offset: Offset(2, 2))],
        ),
        child: Text(label, style: _font(8, const Color(0xFFFFF3B0))),
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
