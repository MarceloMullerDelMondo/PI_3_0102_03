/// In-memory singleton that persists the player's equipped weapon across
/// phase transitions within a single app session.
/// Firebase remains the source of truth for cross-session persistence;
/// this class prevents a redundant async Firebase call on every phase load
/// once the weapon has already been fetched.
class GameState {
  GameState._();
  static final GameState instance = GameState._();

  String _weapon = 'Espada';

  String get equippedWeapon => _weapon;

  /// Returns the Flame asset path for the current weapon's sprite sheet.
  String get weaponAssetPath => _weapon == 'Duas Adagas'
      ? 'player/player_espada2mao.png'
      : 'player/player_espada1mao.png';

  /// Call this after a successful Firebase weapon load so subsequent phases
  /// can resolve the sprite path without a network round-trip.
  void setWeapon(String weapon) => _weapon = weapon;
}
