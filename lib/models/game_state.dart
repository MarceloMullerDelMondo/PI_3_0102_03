import 'package:flutter/foundation.dart';

/// In-memory singleton that persists player inventory and equipment across
/// phase transitions within a single app session.
/// Firebase remains the source of truth for cross-session persistence.
class GameState {
  GameState._();
  static final GameState instance = GameState._();

  // ── Weapon ──────────────────────────────────────────────────────────────
  String _weapon = 'Espada';

  String get equippedWeapon => _weapon;

  String get weaponAssetPath => _weapon == 'Duas Adagas'
      ? 'player/player_espada2mao.png'
      : 'player/player_espada1mao.png';

  void setWeapon(String weapon) => _weapon = weapon;

  // ── Map item (Fase 3 → persists into CAA, Reitoria) ─────────────────────
  // ValueNotifier so any HUD listening to it refreshes instantly on pickup.
  final ValueNotifier<bool> hasMapaNotifier = ValueNotifier(false);

  bool get hasMapa => hasMapaNotifier.value;

  void setHasMapa({bool value = true}) => hasMapaNotifier.value = value;

  // ── Max-health bonus — accumulates across phase transitions ───────────────
  // Sources: +20 from Refeitório armário (Fase 2), +20 from CAA vest (Fase 4).
  // Firebase is the cross-session source of truth; this field keeps the value
  // alive within a single app session so new game instances don't reset to 100.
  int _maxHealthBonus = 0;

  int get maxHealthBonus => _maxHealthBonus;

  /// Adds [delta] HP to the persistent bonus (idempotent-safe: never subtract).
  void addMaxHealthBonus(int delta) {
    if (delta > 0) _maxHealthBonus += delta;
  }

  /// Called when Firebase loads a stored bonus that exceeds the in-memory value.
  void syncMaxHealthBonus(int storedBonus) {
    if (storedBonus > _maxHealthBonus) _maxHealthBonus = storedBonus;
  }
}
