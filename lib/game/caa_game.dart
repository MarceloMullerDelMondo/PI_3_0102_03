import 'dart:async' as async;
import 'dart:convert';
import 'dart:math' as math;

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/experimental.dart' show Rectangle;
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/firebase_service.dart';
import 'h15_game.dart' show InvisibleWall, PlayerComponent, SolidObstacle;

// ─────────────────────────────────────────────────────────────────────────────
// State machine
// ─────────────────────────────────────────────────────────────────────────────
enum CAAPhase { waitingForVest, defendingHorde, readyToTalk, levelComplete }

enum CAAFinalChoice { rescueSignal, cureData }

// ─────────────────────────────────────────────────────────────────────────────
// CAALevel
// ─────────────────────────────────────────────────────────────────────────────
class CAALevel extends FlameGame with HasCollisionDetection {
  CAALevel({required this.playerName});

  final String playerName;

  static const int hordeTarget = 12;
  static final Vector2 _fallbackMapSize = Vector2(1269, 1041);
  static final Vector2 _fallbackSpawn = Vector2(730, 730);
  static final Vector2 _vestPosition = Vector2(220, 430);
  static final Vector2 _rochaPosition = Vector2(300, 90);
  static final Vector2 _playerSize = Vector2(58, 58);

  PlayerComponent? player;
  JoystickComponent? _joystick;
  SpriteComponent? _background;
  CaaRochaComponent? rocha;
  CaaVestComponent? _vest;

  final Vector2 _mapSize = _fallbackMapSize.clone();
  final List<SolidObstacle> _walls = [];
  final List<CaaZombieComponent> _zombies = [];
  final math.Random _rng = math.Random();

  // ── HUD state ──────────────────────────────────────────────────────────────
  final ValueNotifier<double> currentHealth = ValueNotifier(100);
  final ValueNotifier<double> maxHealth = ValueNotifier(100);
  final ValueNotifier<CAAPhase> phase = ValueNotifier(CAAPhase.waitingForVest);
  final ValueNotifier<String> missionText =
      ValueNotifier('Missao: encontre o Colete Balistico no CAA.');
  final ValueNotifier<String?> hudMessage = ValueNotifier(null);
  final ValueNotifier<bool> canInteract = ValueNotifier(false);
  final ValueNotifier<String> interactLabel = ValueNotifier('INTERAGIR');
  final ValueNotifier<bool> dialogOpen = ValueNotifier(false);
  final ValueNotifier<bool> attackEnabled = ValueNotifier(true);
  final ValueNotifier<int> zombiesKilled = ValueNotifier(0);
  final ValueNotifier<int> zombiesRemaining = ValueNotifier(0);
  final ValueNotifier<bool> hordeActive = ValueNotifier(false);
  final ValueNotifier<bool> levelCompleted = ValueNotifier(false);
  final ValueNotifier<bool> gameOver = ValueNotifier(false);

  bool _choiceSaved = false;
  int zombiesSpawned = 0;
  double _spawnCooldown = 0;

  @override
  bool get debugMode => false;

  @override
  Color backgroundColor() => Colors.black;

  // ── onLoad ─────────────────────────────────────────────────────────────────
  @override
  Future<void> onLoad() async {
    await super.onLoad();

    camera.viewfinder.anchor = Anchor.center;
    camera.viewfinder.position = _fallbackSpawn.clone();

    await _loadBackground();
    await _loadCaaCollisions();

    final playerImage = await images.load('player/player_sprite.jpg');
    final playerComponent = PlayerComponent.fromSpriteSheet(playerImage)
      ..position = _fallbackSpawn.clone()
      ..size = _playerSize
      ..priority = 6;
    player = playerComponent;
    await world.add(playerComponent);

    final minZoom = math.max(size.x / _mapSize.x, size.y / _mapSize.y);
    camera.viewfinder.zoom = math.max(minZoom, 1.35);
    camera.setBounds(Rectangle.fromLTWH(0, 0, _mapSize.x, _mapSize.y));
    camera.follow(playerComponent, snap: true);

    // Stage 1 — vest collectible
    _vest = CaaVestComponent(position: _vestPosition)..priority = 7;
    await world.add(_vest!);

    // Stage 3 — Rocha (inactive until readyToTalk)
    rocha = CaaRochaComponent(position: _rochaPosition)..priority = 8;
    await world.add(rocha!);

    _setupJoystick();
    _restoreWeapon();

    async.Timer(const Duration(milliseconds: 700), () {
      if (!isMounted || gameOver.value) return;
      showHudMessage('Colete o Colete Balistico antes de avancar.');
    });
  }

  // ── Update ─────────────────────────────────────────────────────────────────
  @override
  void update(double dt) {
    super.update(dt);
    if (dialogOpen.value || gameOver.value || levelCompleted.value) return;

    final p = player;
    final j = _joystick;
    if (p == null || j == null) return;

    p.move(j.relativeDelta, dt, _mapSize, _walls);
    _checkVestPickup(p);
    _tickSpawner(dt);
    _removeDeadZombies();
    _updateInteractionState(p);
  }

  // ── Stage 1: vest pickup ───────────────────────────────────────────────────
  void _checkVestPickup(PlayerComponent p) {
    final v = _vest;
    if (v == null || v.isRemoved || phase.value != CAAPhase.waitingForVest) return;
    if ((p.position - v.position).length > 60) return;

    v.removeFromParent();
    _vest = null;

    // Increase max HP pool AND heal — vest is an upgrade, not just a heal.
    maxHealth.value += 20;
    currentHealth.value = math.min(maxHealth.value, currentHealth.value + 20);
    showHudMessage('+20 HP MAX — Colete equipado!');

    // Transition → Stage 2
    phase.value = CAAPhase.defendingHorde;
    _startHorde();
  }

  // ── Stage 2: horde ─────────────────────────────────────────────────────────
  void _startHorde() {
    zombiesSpawned = 0;
    _spawnCooldown = 0; // spawn first zombie immediately
    hordeActive.value = true;
    missionText.value = 'Missao: elimine a horda do CAA! (0/$hordeTarget)';
    showHudMessage('Horda detectada! Defenda o CAA!');
  }

  // Called every frame from update(). Spawns one zombie per interval until cap.
  void _tickSpawner(double dt) {
    if (phase.value != CAAPhase.defendingHorde) return;
    if (zombiesSpawned >= hordeTarget) return; // hard cap — never exceed 12

    _spawnCooldown -= dt;
    if (_spawnCooldown > 0) return;
    _spawnCooldown = 0.8; // one zombie every 0.8 s

    _spawnZombie(_clampToMap(_zombieSpawnPoint(), CaaZombieComponent.visualSize));
  }

  // Zombie spawn area constrained to the bottom-right grass region of the map.
  Vector2 _zombieSpawnPoint() => Vector2(
        1160 + _rng.nextDouble() * 80,
        800 + _rng.nextDouble() * 80,
      );

  void _spawnZombie(Vector2 position) {
    final p = player;
    if (p == null) return;
    final zombie = CaaZombieComponent(game: this, target: p, position: position)
      ..priority = 9;
    _zombies.add(zombie);
    zombiesSpawned++;
    zombiesRemaining.value = _zombies.length;
    world.add(zombie);
  }

  void _transitionToReadyToTalk() {
    // Evict any zombie that spawned in the same frame the last kill happened.
    for (final z in List<CaaZombieComponent>.of(_zombies)) {
      z.removeFromParent();
    }
    // Also sweep world children to catch any component not in _zombies.
    world.children
        .whereType<CaaZombieComponent>()
        .toList()
        .forEach((z) => z.removeFromParent());
    _zombies.clear();
    zombiesRemaining.value = 0;

    hordeActive.value = false;
    phase.value = CAAPhase.readyToTalk;
    missionText.value = 'Missao: fale com Sargento Rocha.';
    showHudMessage('Horda eliminada! Converse com Rocha.');
  }

  // Lightweight stale-reference cleanup — no kill counting, no state transitions.
  void _removeDeadZombies() {
    _zombies.removeWhere((z) => !z.isMounted || !z.isAlive);
    zombiesRemaining.value = _zombies.length;
  }

  // ── Stage 3: Rocha interaction ─────────────────────────────────────────────
  void _updateInteractionState(PlayerComponent p) {
    if (phase.value != CAAPhase.readyToTalk) {
      canInteract.value = false;
      return;
    }
    final r = rocha;
    if (r == null) {
      canInteract.value = false;
      return;
    }
    final near = (p.position - r.position).length <= 90;
    canInteract.value = near;
    interactLabel.value = near ? 'FALAR' : 'INTERAGIR';
  }

  void interact() {
    if (!canInteract.value || dialogOpen.value) return;
    if (phase.value == CAAPhase.readyToTalk) _openDilemmaMenu();
  }

  void _openDilemmaMenu() {
    missionText.value = 'Missao: escolha o destino do sinal.';
    dialogOpen.value = true;
    pauseEngine();
    overlays.add('DilemmaMenu');
  }

  Future<void> chooseFinalSignal(CAAFinalChoice choice) async {
    if (_choiceSaved) return;
    _choiceSaved = true;
    final value = switch (choice) {
      CAAFinalChoice.rescueSignal => 'rescue_signal',
      CAAFinalChoice.cureData => 'cure_data',
    };
    await FirebaseService.instance.completeArea4(playerName, finalChoice: value);
    overlays.remove('DilemmaMenu');
    dialogOpen.value = false;
    resumeEngine();
    phase.value = CAAPhase.levelComplete;
    showHudMessage('Sinal enviado. Reitoria desbloqueada.');
    await async.Future<void>.delayed(const Duration(milliseconds: 800));
    levelCompleted.value = true;
  }

  // ── Combat ─────────────────────────────────────────────────────────────────
  void attack() {
    if (!attackEnabled.value || gameOver.value || dialogOpen.value) return;
    final p = player;
    if (p == null) return;
    p.startAttack();
    final attackRect = p.weaponAttackRect(null);

    // Query the world component tree directly — immune to stale _zombies list state.
    final candidates = world.children.whereType<CaaZombieComponent>().toList();
    final defeated = <CaaZombieComponent>[];
    for (final z in candidates) {
      if (attackRect.overlaps(z.hitRect) && z.takeDamage(10)) {
        defeated.add(z);
      }
    }

    for (final z in defeated) {
      z.removeFromParent();
      _zombies.remove(z);
      zombiesKilled.value++;
      zombiesRemaining.value = _zombies.length;
      missionText.value =
          'Missao: elimine a horda! (${zombiesKilled.value}/$hordeTarget)';
      if (zombiesKilled.value >= hordeTarget) {
        _transitionToReadyToTalk();
        break; // transition clears everything — stop the loop
      }
    }
  }

  void damagePlayer(double amount) {
    if (gameOver.value) return;
    currentHealth.value =
        (currentHealth.value - amount).clamp(0, maxHealth.value).toDouble();
    if (currentHealth.value <= 0) {
      gameOver.value = true;
      showHudMessage('Voce caiu defendendo o CAA.');
    }
  }

  // ── Reset (called by Revive button) ────────────────────────────────────────
  void resetLevel() {
    // 1. Wipe every zombie — both from our list and the world tree.
    for (final z in List<CaaZombieComponent>.of(_zombies)) {
      if (z.isMounted) z.removeFromParent();
    }
    world.children
        .whereType<CaaZombieComponent>()
        .toList()
        .forEach((z) => z.removeFromParent());
    _zombies.clear();

    // 2. Reset all counters and flags.
    zombiesSpawned = 0;
    _spawnCooldown = 0;
    _choiceSaved = false;
    hordeActive.value = false;
    zombiesRemaining.value = 0;
    zombiesKilled.value = 0;

    // 3. Restore player.
    currentHealth.value = maxHealth.value;
    gameOver.value = false;
    player?.position = _fallbackSpawn.clone();

    // 4. Always respawn a fresh vest (remove the old one first if present).
    if (_vest != null && _vest!.isMounted) _vest!.removeFromParent();
    _vest = CaaVestComponent(position: _vestPosition)..priority = 7;
    world.add(_vest!);

    // 5. Back to Stage 1.
    phase.value = CAAPhase.waitingForVest;
    missionText.value = 'Missao: encontre o Colete Balistico no CAA.';
  }

  // Keep the old name as an alias so the screen file doesn't break before update.
  void reviveAtCheckpoint() => resetLevel();

  void showHudMessage(String message) {
    hudMessage.value = message;
    async.Timer(const Duration(seconds: 3), () {
      if (hudMessage.value == message) hudMessage.value = null;
    });
  }

  Future<void> _loadBackground() async {
    try {
      _background = SpriteComponent(
        sprite: await loadSprite('screens/caa_environment.jpg'),
        size: _mapSize,
        position: Vector2.zero(),
        priority: -10,
      );
      world.add(_background!);
    } catch (e) {
      debugPrint('CAA background failed: $e');
      world.add(CaaFallbackMap(size: _mapSize)..priority = -10);
    }
  }

  // Loads collision rectangles from caa_collisions.json.
  // The image layer has x:0, y:0 (no offset), so coordinates map directly.
  Future<void> _loadCaaCollisions() async {
    try {
      final raw = await rootBundle.loadString('assets/tiles/caa_collisions.json');
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final layers = (map['layers'] as List<dynamic>).whereType<Map<String, dynamic>>();

      for (final layer in layers) {
        if (layer['name'] != 'Colisoes') continue;
        final objects =
            (layer['objects'] as List<dynamic>? ?? []).whereType<Map<String, dynamic>>();
        for (final obj in objects) {
          final w = (obj['width'] as num).toDouble();
          final h = (obj['height'] as num).toDouble();
          if (w <= 0 || h <= 0) continue;
          final x = (obj['x'] as num).toDouble();
          final y = (obj['y'] as num).toDouble();
          final wall = CaaWall(position: Vector2(x, y), size: Vector2(w, h))
            ..priority = 1;
          _walls.add(wall);
          world.add(wall);
        }
        break;
      }
    } catch (e) {
      debugPrint('CAA collisions failed — using border walls: $e');
      _addBorderWalls();
    }
  }

  void _addBorderWalls() {
    const t = 10.0;
    for (final s in [
      (Vector2.zero(), Vector2(_mapSize.x, t)),
      (Vector2(0, _mapSize.y - t), Vector2(_mapSize.x, t)),
      (Vector2.zero(), Vector2(t, _mapSize.y)),
      (Vector2(_mapSize.x - t, 0), Vector2(t, _mapSize.y)),
    ]) {
      final w = InvisibleWall(position: s.$1, size: s.$2, showDebug: false)..priority = 1;
      _walls.add(w);
      world.add(w);
    }
  }

  void _setupJoystick() {
    _joystick = JoystickComponent(
      knob: CircleComponent(radius: 26, paint: Paint()..color = const Color(0xFFF5C842)),
      background: CircleComponent(radius: 68, paint: Paint()..color = const Color(0xAAE5E7EB)),
      margin: const EdgeInsets.only(left: 28, bottom: 28),
      priority: 1001,
    );
    camera.viewport.add(_joystick!);
  }

  void _restoreWeapon() {
    FirebaseService.instance.loadWeapon().then((weapon) async {
      final selected = (weapon == null || weapon.isEmpty) ? 'Espada' : weapon;
      final asset = selected == 'Duas Adagas'
          ? 'player/player_espada2mao.png'
          : 'player/player_espada1mao.png';
      try {
        player?.useWeaponSpriteSheet(await images.load(asset));
      } catch (e) {
        debugPrint('CAA weapon sprite failed: $e');
      }
    }).catchError((_) {});
  }

  Vector2 _clampToMap(Vector2 center, Vector2 componentSize) => Vector2(
        center.x.clamp(componentSize.x / 2, _mapSize.x - componentSize.x / 2).toDouble(),
        center.y.clamp(componentSize.y / 2, _mapSize.y - componentSize.y / 2).toDouble(),
      );

}

// ─────────────────────────────────────────────────────────────────────────────
// CaaVestComponent — Stage 1 collectible
// ─────────────────────────────────────────────────────────────────────────────
class CaaVestComponent extends PositionComponent {
  // 56×34 — visible but flat ("dropped on floor" aspect ratio).
  CaaVestComponent({required super.position})
      : super(size: Vector2(56, 34), anchor: Anchor.center);

  Sprite? _sprite;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    final game = findGame() as CAALevel;
    try {
      _sprite = Sprite(await game.images.load('objects/colete.png'));
    } catch (e) {
      debugPrint('Vest sprite failed: $e');
    }
  }

  @override
  void render(Canvas canvas) {
    if (_sprite != null) {
      _sprite!.render(canvas, size: size);
    } else {
      // Fallback: flat rectangle in vest blue
      canvas.drawRect(
        size.toRect(),
        Paint()..color = const Color(0xFF1E64DC),
      );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CaaRochaComponent
// ─────────────────────────────────────────────────────────────────────────────
class CaaRochaComponent extends SpriteAnimationComponent {
  CaaRochaComponent({required super.position})
      : super(size: Vector2(40, 80), anchor: Anchor.center);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    final game = findGame() as CAALevel;
    try {
      final img = await game.images.load('npcs/sargento_rocha.png');
      // Full image as a single-frame looping animation.
      // textureSize = full image dimensions; amount = 1.
      animation = SpriteAnimation.fromFrameData(
        img,
        SpriteAnimationData.sequenced(
          amount: 1,
          stepTime: 1.0,
          textureSize: Vector2(img.width.toDouble(), img.height.toDouble()),
          texturePosition: Vector2.zero(),
        ),
      );
    } catch (e) {
      debugPrint('Sargento Rocha sprite failed: $e');
    }
  }

  @override
  void render(Canvas canvas) {
    // Ground shadow
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.x / 2, size.y + 3),
        width: size.x * .75,
        height: 8,
      ),
      Paint()..color = Colors.black.withValues(alpha: .35),
    );
    if (animation != null) {
      super.render(canvas);
    } else {
      // Fallback silhouette
      canvas.drawRRect(
        RRect.fromRectAndRadius(size.toRect(), const Radius.circular(4)),
        Paint()..color = const Color(0xFF374151),
      );
      canvas.drawCircle(
        Offset(size.x / 2, size.y * .25),
        14,
        Paint()..color = const Color(0xFFC49A6C),
      );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CaaZombieComponent
// ─────────────────────────────────────────────────────────────────────────────
class CaaZombieComponent extends SpriteAnimationComponent with CollisionCallbacks {
  CaaZombieComponent({
    required this.game,
    required this.target,
    required Vector2 position,
  }) : super(position: position, size: visualSize.clone(), anchor: Anchor.center);

  static final Vector2 visualSize = Vector2(52, 52); // close to player 58×58
  static const double _speed = 62;
  static const double _damageCooldown = 1.2;
  static const double _touchDamage = 7;

  final CAALevel game;
  final PlayerComponent target;
  int health = 20;
  double _hitCooldown = 0;
  double _hurtFlashTimer = 0; // H-15 fading-alpha flash
  Vector2 _prevPosition = Vector2.zero(); // wall collision rollback
  bool get isAlive => health > 0;

  Rect get hitRect => Rect.fromCenter(
        center: Offset(position.x, position.y),
        width: size.x * .70,
        height: size.y * .72,
      );

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    try {
      final img = await game.images.load('zumbis/zumbi_normal.png');
      // zumbi_normal.png: 592×421 — 4 cols × 3 rows
      const int amount = 4;
      final double frameH = (421 / 3).floorToDouble(); // 140
      animation = SpriteAnimation.fromFrameData(
        img,
        SpriteAnimationData.sequenced(
          amount: amount,
          stepTime: 0.15,
          textureSize: Vector2(592 / 4, frameH),
          texturePosition: Vector2(0, 2 * frameH), // row 2 — side-walk
        ),
      );
    } catch (e) {
      debugPrint('CAA zombie sprite failed: $e');
    }
    add(RectangleHitbox(collisionType: CollisionType.active));
  }

  @override
  void onCollision(Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollision(intersectionPoints, other);
    if (other is SolidObstacle) position = _prevPosition.clone();
  }

  // Returns true if the zombie died — caller handles removeFromParent + kill count.
  bool takeDamage(int dmg) {
    health -= dmg;
    _hurtFlashTimer = 0.20; // 200 ms fading red flash (H-15 pattern)
    return health <= 0;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!isAlive) return;
    if (_hitCooldown > 0) _hitCooldown -= dt;
    if (_hurtFlashTimer > 0) {
      _hurtFlashTimer -= dt;
      if (_hurtFlashTimer <= 0) setOpacity(1.0);
    }

    _prevPosition = position.clone(); // snapshot before movement for wall rollback

    var dir = target.position - position;
    if (dir.length2 > 4) {
      position += dir.normalized() * _speed * dt;
      position = Vector2(
        position.x.clamp(size.x / 2, game._mapSize.x - size.x / 2).toDouble(),
        position.y.clamp(size.y / 2, game._mapSize.y - size.y / 2).toDouble(),
      );
    }

    if (_hitCooldown <= 0 && hitRect.overlaps(target.feetRect.inflate(16))) {
      _hitCooldown = _damageCooldown;
      game.damagePlayer(_touchDamage);
    }
  }

  @override
  void render(Canvas canvas) {
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.x / 2, size.y + 3),
        width: size.x * .8,
        height: 7,
      ),
      Paint()..color = Colors.black.withValues(alpha: .35),
    );
    if (animation != null) {
      super.render(canvas);
    } else {
      canvas.drawCircle(
        Offset(size.x / 2, size.y / 2),
        size.x * .36,
        Paint()..color = const Color(0xFF3F6212),
      );
    }
    if (_hurtFlashTimer > 0) {
      final t = (_hurtFlashTimer / 0.20).clamp(0.0, 1.0);
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.x, size.y),
        Paint()..color = Colors.red.withValues(alpha: t * 0.55),
      );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CaaWall — passive hitbox so zombie (active) receives onCollision callbacks
// ─────────────────────────────────────────────────────────────────────────────
class CaaWall extends SolidObstacle {
  CaaWall({required Vector2 position, required Vector2 size})
      : super(position: position, size: size);

  @override
  bool overlapsRect(Rect rect) =>
      Rect.fromLTWH(position.x, position.y, size.x, size.y).overlaps(rect);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    add(RectangleHitbox(collisionType: CollisionType.passive));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CaaFallbackMap
// ─────────────────────────────────────────────────────────────────────────────
class CaaFallbackMap extends PositionComponent {
  CaaFallbackMap({required Vector2 size}) : super(size: size);

  @override
  void render(Canvas canvas) {
    canvas.drawRect(size.toRect(), Paint()..color = const Color(0xFF20242A));
    final grid = Paint()
      ..color = const Color(0x2238BDF8)
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.x; x += 64) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.y), grid);
    }
    for (var y = 0.0; y < size.y; y += 64) {
      canvas.drawLine(Offset(0, y), Offset(size.x, y), grid);
    }
  }
}
