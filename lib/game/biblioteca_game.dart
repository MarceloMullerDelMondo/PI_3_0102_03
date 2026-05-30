import 'dart:async' as async;
import 'dart:convert';
import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/experimental.dart' show Rectangle;
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/game_state.dart';
import '../services/firebase_service.dart';
import 'base_hud_component.dart';
import 'h15_game.dart' show InvisibleWall, PlayerComponent, SolidObstacle;

class BibliotecaGame extends FlameGame with HasCollisionDetection {
  BibliotecaGame({required this.playerName});

  final String playerName;

  static final Vector2 _kMapFallback = Vector2(870, 1024);
  static final Vector2 _kSpawnFallback = Vector2(435, 930);
  static final Vector2 _kCardFallback = Vector2(435, 700);
  static final Vector2 _kExitPosFallback = Vector2(300, 30);
  static final Vector2 _kExitSizeFallback = Vector2(220, 70);
  static final Vector2 _kPlayerSize = Vector2(48, 48);

  PlayerComponent? player;
  JoystickComponent? _joystick;
  Vector2 _mapSize = _kMapFallback.clone();
  final List<SolidObstacle> _walls = [];

  AccessCardComponent? _card;
  ExitDoorZone? _exitDoor;

  // ── Centralized HUD (camera-viewport fixed) ────────────────────────────
  // Initialized eagerly so biblioteca_level_screen.dart can read hud.*
  // notifiers from build() before onLoad() completes. The component is
  // registered with camera.viewport inside onLoad() as usual.
  final BaseHudComponent hud = BaseHudComponent(
    initialHealth: 100,
    maxHealth: 100,
    initialMission: 'Missão: Encontre o Cartão de Acesso.',
    countTimer: true,
  );

  // ── Phase-specific state ───────────────────────────────────────────────
  bool hasAccessCard = false;
  bool _transitioning = false;
  bool _showingExitOverlay = false;
  double _exitDeniedCooldown = 0;
  double _exitOverlayCooldown = 0;

  final ValueNotifier<bool> levelCompleted = ValueNotifier(false);
  final ValueNotifier<bool> hasAccessCardNotifier = ValueNotifier(false);

  @override
  Color backgroundColor() => Colors.black;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    camera.viewfinder.anchor = Anchor.center;

    // ── 1. Register the pre-built HUD component with the camera viewport ──
    // hud is created eagerly at field-declaration time so the screen's
    // build() can safely read hud.* before onLoad() completes.
    // camera.viewport.add() is what makes it fixed in screen-space.
    camera.viewport.add(hud);

    // ── 2. World setup ────────────────────────────────────────────────────
    final rawMap = await _loadTiledMap();
    await _loadBackground();
    _addBorderWalls();
    _spawnCard(rawMap);
    _spawnExitDoor(rawMap);

    // ── 3. Player ─────────────────────────────────────────────────────────
    final spawn = _readSpawn(rawMap);
    final playerImg = await images.load('player/player_sprite.jpg');
    final p = PlayerComponent.fromSpriteSheet(playerImg)
      ..position = spawn
      ..size = _kPlayerSize
      ..priority = 5;
    player = p;
    await world.add(p);

    // ── 4. Camera ─────────────────────────────────────────────────────────
    camera.viewfinder.position = spawn;
    final minZoom = math.max(size.x / _mapSize.x, size.y / _mapSize.y);
    camera.viewfinder.zoom = math.max(minZoom, 1.5);
    camera.setBounds(Rectangle.fromLTWH(0, 0, _mapSize.x, _mapSize.y));
    camera.follow(p, snap: true);

    // ── 5. Input + weapon ─────────────────────────────────────────────────
    _setupJoystick();
    _restoreWeapon();

    async.Timer(const Duration(milliseconds: 600), () {
      if (isMounted) hud.showMessage('Encontre o Cartão de Acesso na Biblioteca.');
    });
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_transitioning) return;

    final p = player;
    final j = _joystick;
    if (p != null && j != null && !_showingExitOverlay) {
      p.move(j.relativeDelta, dt, _mapSize, _walls);
    }

    if (_exitDeniedCooldown > 0) _exitDeniedCooldown -= dt;
    if (_exitOverlayCooldown > 0) _exitOverlayCooldown -= dt;

    _checkCardCollection();
    if (!_showingExitOverlay) _checkExitDoor();
  }

  // ── Gameplay Logic ────────────────────────────────────────────────────

  void _checkCardCollection() {
    final card = _card;
    final p = player;
    if (card == null || card.collected || p == null) return;
    if ((p.position - card.position).length <= 56) _collectCard();
  }

  void _collectCard() {
    _card!.collect();
    hasAccessCard = true;
    hasAccessCardNotifier.value = true;
    hud.missionText.value = 'Missão: Vá até a Porta de Saída.';
    hud.showMessage('Cartão de Acesso Coletado');
    FirebaseService.instance
        .addItem(playerName, 'cartao_acesso_funcionario')
        .catchError((_) {});
  }

  void _checkExitDoor() {
    if (_exitOverlayCooldown > 0) return;
    final door = _exitDoor;
    final p = player;
    if (door == null || p == null) return;

    final playerRect = Rect.fromCenter(
      center: Offset(p.position.x, p.position.y),
      width: p.size.x * 0.6,
      height: p.size.y * 0.6,
    );
    if (!door.rect.inflate(20).overlaps(playerRect)) return;

    if (!hasAccessCard) {
      if (_exitDeniedCooldown <= 0) {
        hud.showMessage('Trancado. Encontre o Cartão.');
        _exitDeniedCooldown = 3.0;
      }
      return;
    }

    _showingExitOverlay = true;
    hud.paused = true; // freeze timer while player decides
    overlays.add('ExitDoor');
  }

  // Called by the "Entrar" button in ExitDoorOverlay.
  void onExitConfirmed() {
    overlays.remove('ExitDoor');
    _transitioning = true;
    hud.paused = false;
    FirebaseService.instance.unlockNextPhase(playerName).then((_) {
      levelCompleted.value = true;
    }).catchError((_) {
      levelCompleted.value = true;
    });
  }

  // Called by the "Cancelar" button in ExitDoorOverlay.
  void onExitCancelled() {
    overlays.remove('ExitDoor');
    _showingExitOverlay = false;
    hud.paused = false;
    _exitOverlayCooldown = 2.0;
  }

  // ── Weapon Loading ────────────────────────────────────────────────────
  //
  // Pattern for ALL phase game files:
  // 1. Load weapon name from Firebase (source of truth).
  // 2. Update GameState so subsequent phases skip the Firebase call.
  // 3. Apply the sprite sheet to the player.
  // 4. On Firebase failure, fall back to whatever GameState already holds
  //    (populated by a previous phase's successful load).

  void _restoreWeapon() {
    FirebaseService.instance.loadWeapon().then((weapon) async {
      final selected = (weapon == null || weapon.isEmpty) ? 'Espada' : weapon;
      GameState.instance.setWeapon(selected); // persist across phases in-memory
      try {
        player?.useWeaponSpriteSheet(
          await images.load(GameState.instance.weaponAssetPath),
        );
      } catch (_) {}
    }).catchError((_) async {
      // Firebase unavailable — use whatever weapon the previous phase loaded.
      try {
        player?.useWeaponSpriteSheet(
          await images.load(GameState.instance.weaponAssetPath),
        );
      } catch (_) {}
    });
  }

  // ── Map Loading ───────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _loadTiledMap() async {
    try {
      final raw = await rootBundle.loadString('assets/tiles/biblioteca.json');
      final map = jsonDecode(raw) as Map<String, dynamic>;
      _mapSize = _readMapSize(map);
      return map;
    } catch (e) {
      debugPrint('BibliotecaGame: map load failed: $e');
      _mapSize = _kMapFallback.clone();
      return const {};
    }
  }

  Vector2 _readMapSize(Map<String, dynamic> map) {
    final w = (map['width'] as num? ?? 0).toDouble();
    final h = (map['height'] as num? ?? 0).toDouble();
    final tw = (map['tilewidth'] as num? ?? 16).toDouble();
    final th = (map['tileheight'] as num? ?? 16).toDouble();
    if (w > 0 && h > 0) return Vector2(w * tw, h * th);
    return _kMapFallback.clone();
  }

  Future<void> _loadBackground() async {
    try {
      world.add(SpriteComponent(
        sprite: await loadSprite('screens/biblioteca.png'),
        size: _mapSize,
        position: Vector2.zero(),
        priority: -10,
      ));
    } catch (_) {
      world.add(BibliotecaFallbackMap(mapSize: _mapSize)..priority = -10);
    }
  }

  void _addBorderWalls() {
    const t = 8.0;
    for (final s in [
      (Vector2.zero(), Vector2(_mapSize.x, t)),
      (Vector2(0, _mapSize.y - t), Vector2(_mapSize.x, t)),
      (Vector2.zero(), Vector2(t, _mapSize.y)),
      (Vector2(_mapSize.x - t, 0), Vector2(t, _mapSize.y)),
    ]) {
      final w = InvisibleWall(position: s.$1, size: s.$2, showDebug: false)
        ..priority = 1;
      _walls.add(w);
      world.add(w);
    }
  }

  void _spawnCard(Map<String, dynamic> map) {
    final obj = _findObject(map, (n) {
      final l = n.toLowerCase();
      return l.contains('cartao') || l.contains('card') || l.contains('acesso');
    });
    final pos = obj == null
        ? _kCardFallback.clone()
        : Vector2(
            (obj['x'] as num).toDouble() +
                (obj['width'] as num? ?? 0).toDouble() / 2,
            (obj['y'] as num).toDouble() +
                (obj['height'] as num? ?? 0).toDouble() / 2,
          );
    _card = AccessCardComponent(position: _clamp(pos, Vector2(42, 28)));
    world.add(_card!);
  }

  void _spawnExitDoor(Map<String, dynamic> map) {
    final obj = _findObject(map, (n) {
      final l = n.toLowerCase();
      return l.contains('saida') || l.contains('exit') || l.contains('porta');
    });
    final pos = obj == null
        ? _kExitPosFallback.clone()
        : Vector2(
            (obj['x'] as num).toDouble(),
            (obj['y'] as num).toDouble(),
          );
    final sz = obj == null
        ? _kExitSizeFallback.clone()
        : Vector2(
            math.max((obj['width'] as num? ?? 0).toDouble(), 60),
            math.max((obj['height'] as num? ?? 0).toDouble(), 60),
          );
    _exitDoor = ExitDoorZone(position: pos, size: sz);
    world.add(_exitDoor!);
  }

  Vector2 _readSpawn(Map<String, dynamic> map) {
    final obj = _findObject(map, (n) {
      final l = n.toLowerCase();
      return l.contains('spawn') || l.contains('player');
    });
    if (obj == null) return _clamp(_kSpawnFallback, _kPlayerSize);
    return _clamp(
      Vector2((obj['x'] as num).toDouble(), (obj['y'] as num).toDouble()),
      _kPlayerSize,
    );
  }

  void _setupJoystick() {
    _joystick = JoystickComponent(
      knob: CircleComponent(
        radius: 26,
        paint: Paint()..color = const Color(0xFFF5C842),
      ),
      background: CircleComponent(
        radius: 68,
        paint: Paint()..color = const Color(0xAAE5E7EB),
      ),
      margin: const EdgeInsets.only(left: 28, bottom: 28),
      priority: 1001,
    );
    camera.viewport.add(_joystick!);
  }

  // ── Helpers ───────────────────────────────────────────────────────────

  Vector2 _clamp(Vector2 center, Vector2 sz) => Vector2(
        center.x.clamp(sz.x / 2, _mapSize.x - sz.x / 2).toDouble(),
        center.y.clamp(sz.y / 2, _mapSize.y - sz.y / 2).toDouble(),
      );

  Map<String, dynamic>? _findObject(
    Map<String, dynamic> map,
    bool Function(String) test,
  ) {
    for (final layer
        in (map['layers'] as List? ?? []).whereType<Map<String, dynamic>>()) {
      for (final obj in (layer['objects'] as List? ?? [])
          .whereType<Map<String, dynamic>>()) {
        if (test(obj['name']?.toString() ?? '')) return obj;
      }
    }
    return null;
  }
}

// ── AccessCardComponent ───────────────────────────────────────────────────

class AccessCardComponent extends PositionComponent {
  AccessCardComponent({required super.position})
      : super(size: Vector2(42, 28), anchor: Anchor.center, priority: 4);

  bool collected = false;
  double _pulse = 0;

  void collect() {
    collected = true;
    removeFromParent();
  }

  @override
  void update(double dt) => _pulse += dt;

  @override
  void render(Canvas canvas) {
    if (collected) return;
    final glow = 0.55 + math.sin(_pulse * 5) * 0.18;
    final rect = Rect.fromLTWH(0, 0, size.x, size.y);

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.x / 2, size.y + 4),
        width: size.x * 0.85,
        height: 7,
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.35),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(3)),
      Paint()..color = const Color(0xFFE5E7EB),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.deflate(3), const Radius.circular(2)),
      Paint()..color = const Color(0xFF1D4ED8),
    );
    canvas.drawRect(
      Rect.fromLTWH(size.x * .12, size.y * .18, size.x * .76, size.y * .16),
      Paint()..color = const Color(0xFFFACC15),
    );
    canvas.drawCircle(
      Offset(size.x * .75, size.y * .68),
      4,
      Paint()..color = const Color(0xFF86EFAC),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.inflate(3), const Radius.circular(4)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFFFACC15).withValues(alpha: glow),
    );
  }
}

// ── ExitDoorZone ──────────────────────────────────────────────────────────

class ExitDoorZone extends PositionComponent {
  ExitDoorZone({required super.position, required super.size})
      : super(priority: 2);

  Rect get rect => Rect.fromLTWH(position.x, position.y, size.x, size.y);

  @override
  void render(Canvas canvas) {
    canvas.drawRect(
      size.toRect(),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFF38BDF8).withValues(alpha: 0.45),
    );
    final tp = TextPainter(
      text: const TextSpan(
        text: 'SAÍDA →',
        style: TextStyle(
          color: Color(0xFF38BDF8),
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset((size.x - tp.width) / 2, (size.y - tp.height) / 2),
    );
  }
}

// ── BibliotecaFallbackMap ─────────────────────────────────────────────────

class BibliotecaFallbackMap extends PositionComponent {
  BibliotecaFallbackMap({required Vector2 mapSize})
      : super(size: mapSize, position: Vector2.zero());

  @override
  void render(Canvas canvas) {
    canvas.drawRect(size.toRect(), Paint()..color = const Color(0xFF2F2A24));
    final grid = Paint()
      ..color = const Color(0x224A5568)
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.x; x += 48) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.y), grid);
    }
    for (var y = 0.0; y < size.y; y += 48) {
      canvas.drawLine(Offset(0, y), Offset(size.x, y), grid);
    }
  }
}
