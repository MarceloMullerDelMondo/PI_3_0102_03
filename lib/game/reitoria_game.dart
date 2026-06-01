import 'dart:async' as async;
import 'dart:convert';
import 'dart:math' as math;

import 'package:flame/collisions.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flame/components.dart';
import 'package:flame/experimental.dart' show Rectangle;
import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../services/firebase_service.dart';
import 'h15_game.dart' show InvisibleWall, PlayerComponent, SolidObstacle;

// ─────────────────────────────────────────────────────────────────────────────
// ReitoriaLevel — Boss Fight: Paciente Zero
// ─────────────────────────────────────────────────────────────────────────────
class ReitoriaLevel extends FlameGame with HasCollisionDetection {
  ReitoriaLevel({required this.playerName});

  final String playerName;

  static final Vector2 _fallbackMapSize = Vector2(1402, 1122);
  static final Vector2 _playerSpawn = Vector2(701, 1020);
  static final Vector2 _bossSpawn = Vector2(701, 561);
  static final Vector2 _playerSize = Vector2(58, 58);
  static const double _minionSpawnInterval = 3.0;

  PlayerComponent? player;
  JoystickComponent? _joystick;
  FinalBossComponent? boss;

  Vector2 _mapSize = _fallbackMapSize.clone();
  final List<SolidObstacle> _walls = [];
  final List<ReitoriaZombieComponent> _zombies = [];
  final math.Random _rng = math.Random();

  // HUD state
  final ValueNotifier<double> currentHealth = ValueNotifier(100);
  final ValueNotifier<double> maxHealth = ValueNotifier(100);
  final ValueNotifier<int> bossCurrentHealth = ValueNotifier(FinalBossComponent.maxHp);
  final ValueNotifier<int> bossMaxHealth = ValueNotifier(FinalBossComponent.maxHp);
  final ValueNotifier<String> missionText = ValueNotifier('Missao final: derrote o Paciente Zero!');
  final ValueNotifier<String?> hudMessage = ValueNotifier(null);
  final ValueNotifier<bool> dialogOpen = ValueNotifier(false);
  final ValueNotifier<bool> attackEnabled = ValueNotifier(true);
  final ValueNotifier<bool> gameOver = ValueNotifier(false);
  final ValueNotifier<bool> levelCompleted = ValueNotifier(false);

  bool isBossDead = false;
  bool _endingOpen = false;
  double _spawnTimer = 0;

  @override
  bool get debugMode => false;

  @override
  Color backgroundColor() => Colors.black;

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    camera.viewfinder.anchor = Anchor.center;
    camera.viewfinder.position = _playerSpawn.clone();

    await _loadBackground();
    await _loadTiledCollisions();

    final playerImage = await images.load('player/player_sprite.jpg');
    final playerComp = PlayerComponent.fromSpriteSheet(playerImage)
      ..position = _playerSpawn.clone()
      ..size = _playerSize
      ..priority = 8;
    player = playerComp;
    await world.add(playerComp);

    final bossComp = FinalBossComponent(game: this)
      ..position = _bossSpawn.clone()
      ..priority = 7;
    boss = bossComp;
    await world.add(bossComp);

    final minZoom = math.max(size.x / _mapSize.x, size.y / _mapSize.y);
    camera.viewfinder.zoom = math.max(minZoom, 1.25);
    camera.setBounds(Rectangle.fromLTWH(0, 0, _mapSize.x, _mapSize.y));
    camera.follow(playerComp, snap: true);

    _setupJoystick();
    _restoreWeapon();

    async.Timer(const Duration(milliseconds: 600), () {
      if (!isMounted) return;
      dialogOpen.value = true;
      pauseEngine();
      overlays.add('BossIntroDialog');
    });
  }

  Future<void> _loadBackground() async {
    try {
      final image = await images.load('screens/reitoria_screen.jpeg');
      _mapSize = Vector2(image.width.toDouble(), image.height.toDouble());
      world.add(SpriteComponent(
        sprite: Sprite(image),
        size: _mapSize,
        position: Vector2.zero(),
        priority: -10,
      ));
    } catch (e) {
      debugPrint('Reitoria background: $e');
      world.add(ReitoriaFallbackMap(size: _mapSize)..priority = -10);
    }
  }

  // Loads collision rectangles from reitoria_collisions.json.
  // The Tiled image layer has offsetx = -403.03 and offsety = 266.667, so
  // every object coordinate must be shifted to align with the game background
  // rendered at (0, 0): game_x = tiled_x + 403.03, game_y = tiled_y - 266.667.
  Future<void> _loadTiledCollisions() async {
    const double imgOffsetX = 403.03;
    const double imgOffsetY = 266.667;
    try {
      final raw = await rootBundle.loadString('assets/tiles/reitoria_collisions.json');
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
          final x = (obj['x'] as num).toDouble() + imgOffsetX;
          final y = (obj['y'] as num).toDouble() - imgOffsetY;
          final wall = InvisibleWall(
            position: Vector2(x, y),
            size: Vector2(w, h),
            showDebug: false,
          )..priority = 1;
          _walls.add(wall);
          world.add(wall);
        }
        break;
      }
    } catch (e) {
      debugPrint('Reitoria collisions failed — falling back to border walls: $e');
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
      } catch (_) {}
    }).catchError((_) {});
  }

  void closeBossIntroDialog() {
    overlays.remove('BossIntroDialog');
    dialogOpen.value = false;
    resumeEngine();
    showHudMessage('Elimine o Paciente Zero!');
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (dialogOpen.value || gameOver.value || levelCompleted.value) return;

    final p = player;
    final j = _joystick;
    if (p == null || j == null) return;

    p.move(j.relativeDelta, dt, _mapSize, _walls);
    _removeDeadZombies();

    if (!isBossDead) {
      _spawnTimer -= dt;
      if (_spawnTimer <= 0) {
        _spawnTimer = _minionSpawnInterval;
        _spawnMinionNearBoss();
      }
    }
  }

  void _spawnMinionNearBoss() {
    final b = boss;
    final p = player;
    if (b == null || b.isRemoved || p == null) return;

    final angle = _rng.nextDouble() * math.pi * 2;
    final radius = 120 + _rng.nextDouble() * 80;
    final spawn = Vector2(
      (b.position.x + math.cos(angle) * radius).clamp(80, _mapSize.x - 80).toDouble(),
      (b.position.y + math.sin(angle) * radius).clamp(80, _mapSize.y - 80).toDouble(),
    );

    final zombie = ReitoriaZombieComponent(game: this, player: p, position: spawn)..priority = 6;
    _zombies.add(zombie);
    world.add(zombie);
  }

  void _removeDeadZombies() {
    _zombies.removeWhere((z) => z.isRemoved || !z.isAlive);
  }

  void attack() {
    if (dialogOpen.value || gameOver.value || levelCompleted.value) return;
    final p = player;
    if (p == null) return;
    p.startAttack();
    final rect = p.weaponAttackRect(null);

    for (final z in List<ReitoriaZombieComponent>.of(_zombies)) {
      if (z.isAlive && rect.overlaps(z.hitRect)) z.takeDamage(10);
    }

    final b = boss;
    if (b != null && !b.isRemoved && b.isAlive && rect.overlaps(b.hitRect)) {
      b.takeDamage(15);
    }
  }

  void damagePlayer(double amount) {
    if (gameOver.value || levelCompleted.value) return;
    currentHealth.value = math.max(0, currentHealth.value - amount);
    if (currentHealth.value <= 0) {
      gameOver.value = true;
      missionText.value = 'Voce foi derrotado pelo Paciente Zero.';
    }
  }

  void onBossDefeated() {
    if (_endingOpen) return;
    isBossDead = true;
    _endingOpen = true;
    bossCurrentHealth.value = 0;

    for (final z in List<ReitoriaZombieComponent>.of(_zombies)) {
      z.removeFromParent();
    }
    _zombies.clear();

    async.Timer(const Duration(milliseconds: 1200), () {
      if (!isMounted) return;
      pauseEngine();
      dialogOpen.value = true;
      overlays.add('BossVictory');
    });
  }

  Future<void> finishFinale() async {
    if (levelCompleted.value) return;
    try {
      await FirebaseService.instance.completeArea5(playerName, ending: 'boss_defeated');
    } catch (_) {}
    overlays.remove('BossVictory');
    dialogOpen.value = false;
    levelCompleted.value = true;
  }

  void reviveAtCheckpoint() {
    for (final z in List<ReitoriaZombieComponent>.of(_zombies)) {
      z.removeFromParent();
    }
    _zombies.clear();
    currentHealth.value = maxHealth.value;
    _spawnTimer = 0;
    isBossDead = false;
    _endingOpen = false;
    gameOver.value = false;
    player?.position = _playerSpawn.clone();

    if (boss == null || boss!.isRemoved) {
      final b = FinalBossComponent(game: this)
        ..position = _bossSpawn.clone()
        ..priority = 7;
      boss = b;
      world.add(b);
    } else {
      boss!.resetHealth();
    }
    bossCurrentHealth.value = FinalBossComponent.maxHp;
    missionText.value = 'Missao final: derrote o Paciente Zero!';
  }

  void showHudMessage(String message) {
    hudMessage.value = message;
    async.Timer(const Duration(seconds: 3), () {
      if (hudMessage.value == message) hudMessage.value = null;
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FinalBossComponent — Paciente Zero
// ─────────────────────────────────────────────────────────────────────────────
class FinalBossComponent extends SpriteComponent {
  static const int maxHp = 500;
  static const double _speed = 38;
  static const double _touchDamage = 15;
  static const double _touchCooldown = 1.5;

  // Size is derived from the sprite frame in onLoad to avoid any squish/clip.
  FinalBossComponent({required this.game}) : super(anchor: Anchor.center);

  final ReitoriaLevel game;
  int health = maxHp;
  double _hitCooldown = 0;
  double _flash = 0;

  bool get isAlive => health > 0;

  Rect get hitRect => Rect.fromCenter(
        center: Offset(position.x, position.y),
        width: size.x * .65,
        height: size.y * .65,
      );

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    try {
      final img = await game.images.load('zumbis/final_boss.png');
      // Static first frame only — avoids all fractional-pixel bleeding issues.
      sprite = Sprite(
        img,
        srcPosition: Vector2(0, 0),
        srcSize: Vector2(125, 139),
      );
      size = Vector2(125 * 1.3, 139 * 1.3);
    } catch (e) {
      debugPrint('FinalBoss sprite failed: $e');
      size = Vector2(125 * 1.3, 139 * 1.3); // fallback keeps hitRect non-zero
    }
    add(RectangleHitbox(collisionType: CollisionType.passive));
  }

  void takeDamage(int amount) {
    if (!isAlive) return;
    health = (health - amount).clamp(0, maxHp);
    _flash = 0.2;
    game.bossCurrentHealth.value = health;
    if (health <= 0) {
      removeFromParent();
      game.onBossDefeated();
    }
  }

  void resetHealth() {
    health = maxHp;
    _hitCooldown = 0;
    _flash = 0;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!isAlive) return;
    if (_hitCooldown > 0) _hitCooldown -= dt;
    if (_flash > 0) _flash -= dt;

    final p = game.player;
    if (p == null) return;

    final dir = p.position - position;
    if (dir.length2 > 1) {
      position += dir.normalized() * _speed * dt;
      position = Vector2(
        position.x.clamp(size.x / 2, game._mapSize.x - size.x / 2).toDouble(),
        position.y.clamp(size.y / 2, game._mapSize.y - size.y / 2).toDouble(),
      );
    }

    if (_hitCooldown > 0) return;
    if (hitRect.overlaps(p.feetRect.inflate(20))) {
      _hitCooldown = _touchCooldown;
      game.damagePlayer(_touchDamage);
    }
  }

  @override
  void render(Canvas canvas) {
    // Shadow
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.x / 2, size.y + 5),
        width: size.x * .85,
        height: 12,
      ),
      Paint()..color = Colors.black.withValues(alpha: .4),
    );
    super.render(canvas);
    // Hit flash
    if (_flash > 0) {
      canvas.drawRect(size.toRect(), Paint()..color = Colors.red.withValues(alpha: .5));
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ReitoriaZombieComponent — minion lackey spawned around the boss
// ─────────────────────────────────────────────────────────────────────────────
class ReitoriaZombieComponent extends SpriteAnimationComponent {
  static final Vector2 visualSize = Vector2(62, 62);
  static const double _speed = 68;
  static const double _touchDamage = 7;
  static const double _cooldownDuration = 1.0;

  ReitoriaZombieComponent({
    required this.game,
    required this.player,
    required Vector2 position,
  }) : super(position: position, size: visualSize.clone(), anchor: Anchor.center);

  final ReitoriaLevel game;
  final PlayerComponent player;
  int health = 22;
  double _cooldown = 0;
  double _flash = 0;
  bool get isAlive => health > 0;

  Rect get hitRect => Rect.fromCenter(
        center: Offset(position.x, position.y),
        width: size.x * .72,
        height: size.y * .72,
      );

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    try {
      final img = await game.images.load('zumbis/zumbi_normal.png');
      // zumbi_normal.png: 592×421 — 4 cols × 3 rows
      const int cols = 4;
      const int rows = 3;
      const int amount = 4; // row 2: 4 frames side-walk
      final frameH = (421 / rows).floorToDouble(); // 140 px (floor evita sangramento)
      animation = SpriteAnimation.fromFrameData(
        img,
        SpriteAnimationData.sequenced(
          amount: amount,
          stepTime: 0.15,
          textureSize: Vector2(592 / cols, frameH),
          texturePosition: Vector2(0, 2 * frameH), // row 2
        ),
      );
    } catch (_) {}
    add(RectangleHitbox(collisionType: CollisionType.passive));
  }

  void takeDamage(int amount) {
    if (!isAlive) return;
    health -= amount;
    _flash = 0.18;
    if (health <= 0) removeFromParent();
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!isAlive) return;
    if (_cooldown > 0) _cooldown -= dt;
    if (_flash > 0) _flash -= dt;

    final dir = player.position - position;
    if (dir.length2 > 4) {
      position += dir.normalized() * _speed * dt;
      position = Vector2(
        position.x.clamp(size.x / 2, game._mapSize.x - size.x / 2).toDouble(),
        position.y.clamp(size.y / 2, game._mapSize.y - size.y / 2).toDouble(),
      );
    }

    if (_cooldown > 0) return;
    if (hitRect.overlaps(player.feetRect.inflate(16))) {
      _cooldown = _cooldownDuration;
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
    if (_flash > 0) {
      canvas.drawRect(size.toRect(), Paint()..color = Colors.red.withValues(alpha: .45));
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ReitoriaFallbackMap — rendered when background image fails to load
// ─────────────────────────────────────────────────────────────────────────────
class ReitoriaFallbackMap extends PositionComponent {
  ReitoriaFallbackMap({required Vector2 size}) : super(size: size);

  @override
  void render(Canvas canvas) {
    canvas.drawRect(size.toRect(), Paint()..color = const Color(0xFF1A0A0A));
    final grid = Paint()
      ..color = const Color(0x22FF3333)
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.x; x += 64) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.y), grid);
    }
    for (var y = 0.0; y < size.y; y += 64) {
      canvas.drawLine(Offset(0, y), Offset(size.x, y), grid);
    }
  }
}
