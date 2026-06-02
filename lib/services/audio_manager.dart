import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Convenience alias — both names refer to the same singleton.
typedef MusicManager = AudioManager;

/// Global singleton that owns the menu BGM lifecycle.
///
/// Rules:
///   • playMenuBgm()  — called when the menu / map screen becomes active.
///   • stopMenuBgm()  — called just before entering a gameplay level.
///   • resumeMenuBgm()— called just after returning from a gameplay level.
///   • setMusicEnabled(bool) — called from the Options toggle; persisted to
///     SharedPreferences so the choice survives app restarts.
class AudioManager {
  AudioManager._();
  static final AudioManager instance = AudioManager._();

  // ── SharedPreferences key ────────────────────────────────────────────────
  static const _kMusicOn = 'music_on';

  // ── Actual asset file inside assets/audio/ ───────────────────────────────
  // Rename this constant if you rename the file on disk.
  static const menuBgmFile = 'MusicaRPGPucSurvival.mp3';

  // ── Internal state ────────────────────────────────────────────────────────
  bool _musicEnabled = true;

  /// true  → bgm.play() was called and has NOT been stopped yet.
  /// false → never started OR was stopped via stopMenuBgm().
  bool _bgmStarted = false;

  /// true → bgm.pause() was called while _bgmStarted == true.
  bool _bgmPaused = false;

  // ── Public getters ────────────────────────────────────────────────────────

  bool get musicEnabled => _musicEnabled;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  /// Call once in main() — reads the persisted ON/OFF preference.
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance()
          .timeout(const Duration(seconds: 3));
      _musicEnabled = prefs.getBool(_kMusicOn) ?? true;
    } catch (e) {
      debugPrint('[AudioManager] init error: $e');
    }
  }

  /// Start menu BGM looping.  No-op when music is disabled or already playing.
  Future<void> playMenuBgm() async {
    if (!_musicEnabled) return;
    // Already running — nothing to do.
    if (_bgmStarted && !_bgmPaused) return;
    try {
      await FlameAudio.bgm.play(menuBgmFile, volume: 0.65);
      _bgmStarted = true;
      _bgmPaused = false;
    } catch (e) {
      debugPrint('[AudioManager] playMenuBgm error: $e');
    }
  }

  /// Stop the BGM completely (use when entering a gameplay level).
  Future<void> stopMenuBgm() async {
    if (!_bgmStarted) return;
    try {
      await FlameAudio.bgm.stop();
    } catch (e) {
      debugPrint('[AudioManager] stopMenuBgm error: $e');
    } finally {
      _bgmStarted = false;
      _bgmPaused = false;
    }
  }

  /// Resume after returning from a level.  Equivalent to playMenuBgm() but
  /// kept as a separate entry-point for call-site clarity.
  Future<void> resumeMenuBgm() => playMenuBgm();

  // ── Options toggle ────────────────────────────────────────────────────────

  /// Toggle music on/off from the Options screen.
  /// Persists the choice and immediately starts/pauses the BGM.
  Future<void> setMusicEnabled(bool enabled) async {
    _musicEnabled = enabled;

    // Persist asynchronously — fire and forget is fine here.
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setBool(_kMusicOn, enabled))
        .catchError((Object e) {
          debugPrint('[AudioManager] persist error: $e');
          return false; // matches Future<bool> returned by setBool
        });

    if (enabled) {
      if (_bgmStarted && _bgmPaused) {
        // Was playing before the user toggled off — resume from same position.
        try {
          await FlameAudio.bgm.resume();
          _bgmPaused = false;
        } catch (e) {
          // resume() can throw if the player was disposed; fall back to play().
          await playMenuBgm();
        }
      } else {
        // Never started, or was stopped by a level exit — start fresh.
        await playMenuBgm();
      }
    } else {
      // Pause (not stop) so resume() restores position if toggled back quickly.
      if (_bgmStarted && !_bgmPaused) {
        try {
          await FlameAudio.bgm.pause();
          _bgmPaused = true;
        } catch (e) {
          debugPrint('[AudioManager] pause error: $e');
        }
      }
    }
  }
}
