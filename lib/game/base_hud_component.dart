import 'dart:async' as async;

import 'package:flame/components.dart';
import 'package:flutter/foundation.dart';

/// A PositionComponent that lives in [CameraComponent.viewport].
///
/// Because it is added to the viewport (not the world), it is always rendered
/// in screen-space — fixed to the screen edges regardless of camera movement.
///
/// Responsibilities:
/// - Owns the shared HUD [ValueNotifier]s (health, mission, flash message, timer).
/// - Increments [survivalSeconds] once per real second in [update].
///
/// The actual visual rendering is handled by [BaseGameHud] (a Flutter widget
/// in the screen layer) which reads these notifiers. This separation keeps
/// game logic in the Flame layer and rich UI in the Flutter layer.
///
/// Usage — inside any game's [onLoad]:
/// ```dart
/// hud = BaseHudComponent(
///   initialHealth: 100,
///   maxHealth: 100,
///   initialMission: 'Missão: ...',
/// );
/// camera.viewport.add(hud);
/// ```
class BaseHudComponent extends PositionComponent {
  BaseHudComponent({
    required double initialHealth,
    required this.maxHealth,
    required String initialMission,
    this.countTimer = true,
  })  : currentHealth = ValueNotifier(initialHealth),
        missionText = ValueNotifier(initialMission),
        survivalSeconds = ValueNotifier(0),
        hudMessage = ValueNotifier(null);

  // ── Public state ───────────────────────────────────────────────────────

  final double maxHealth;

  /// When true, [survivalSeconds] increments every second.
  /// Set to false for cut-scenes or dialog-paused states.
  bool countTimer;

  /// Set to true to pause the timer without disabling [countTimer] permanently.
  bool paused = false;

  final ValueNotifier<double> currentHealth;
  final ValueNotifier<String> missionText;
  final ValueNotifier<int> survivalSeconds;
  final ValueNotifier<String?> hudMessage;

  // ── Private ────────────────────────────────────────────────────────────

  double _elapsed = 0;
  async.Timer? _msgTimer;

  // ── API ────────────────────────────────────────────────────────────────

  void takeDamage(double amount) =>
      currentHealth.value = (currentHealth.value - amount).clamp(0, maxHealth);

  void heal(double amount) =>
      currentHealth.value = (currentHealth.value + amount).clamp(0, maxHealth);

  /// Shows [message] in the HUD flash area for [duration], then auto-clears.
  /// Calling again before the timer fires replaces the previous message.
  void showMessage(
    String message, {
    Duration duration = const Duration(seconds: 3),
  }) {
    hudMessage.value = message;
    _msgTimer?.cancel();
    _msgTimer = async.Timer(duration, () {
      if (hudMessage.value == message) hudMessage.value = null;
    });
  }

  // ── Flame lifecycle ────────────────────────────────────────────────────

  @override
  void update(double dt) {
    super.update(dt);
    if (paused || !countTimer) return;
    _elapsed += dt;
    if (_elapsed >= 1.0) {
      _elapsed -= 1.0;
      survivalSeconds.value++;
    }
  }

  @override
  void onRemove() {
    _msgTimer?.cancel();
    currentHealth.dispose();
    missionText.dispose();
    survivalSeconds.dispose();
    hudMessage.dispose();
    super.onRemove();
  }
}
