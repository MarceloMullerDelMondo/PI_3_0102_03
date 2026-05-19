import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/experimental.dart' show Rectangle;
import 'package:flame/game.dart';
import 'package:flame_tiled/flame_tiled.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class H15Game extends FlameGame with HasCollisionDetection {
  static const bool showDebugWalls = false;
  static const bool _enableLegacyIsoCollision = false;
  static const bool _enableLegacyQuestZones = false;
  static final Vector2 _fallbackMapSize = Vector2(2466, 1568);
  static const int totalQuestZombies = 15;
  static const int _hordeTargetKills = totalQuestZombies;
  static const int _spawnAttemptLimit = 40;
  static const double _spawnZombieBuffer = 18;
  static final Vector2 _zombieSpawnHitbox = Vector2(96 * .72, 96 * .76);

  // ── Estado público ──────────────────────────────────────────────────────────
  PlayerComponent? player;
  JoystickComponent? _joystick;
  DarknessOverlay? _darkness;
  SpriteComponent? _background;
  Vector2 _mapSize = _fallbackMapSize.clone();
  final List<SolidObstacle> _walls = [];
  final List<InteractableZone> _interactables = [];
  final List<ZombieComponent> _zombies = [];
  final List<Vector2> _safeZombieSpawns = [];
  final math.Random _random = math.Random();

  final double maxHealth = 100;
  final ValueNotifier<double> currentHealth = ValueNotifier(100);
  final ValueNotifier<int> survivalSeconds = ValueNotifier(0);
  final ValueNotifier<int> zombiesKilled = ValueNotifier(0);
  final ValueNotifier<String> missionText =
      ValueNotifier('Missão: Ache a nota manchada na Sala B');
  final ValueNotifier<bool> canInteract = ValueNotifier(false);
  final ValueNotifier<bool> canReadPaper = ValueNotifier(false);
  final ValueNotifier<bool> questDialogOpen = ValueNotifier(false);
  final ValueNotifier<bool> attackEnabled = ValueNotifier(false);
  final ValueNotifier<bool> missionCompletedPopup = ValueNotifier(false);
  final ValueNotifier<bool> gameOver = ValueNotifier(false);
  final ValueNotifier<String?> equippedWeapon = ValueNotifier(null);
  final ValueNotifier<String?> hudMessage = ValueNotifier(null);

  String? activeZoneId;
  int questState = 0;
  late Vector2 lastCheckpoint;

  // ── Horda ───────────────────────────────────────────────────────────────────
  bool _hordeActive = false;
  bool _hordeCompleted = false;
  int zombiesSpawned = 0;
  TimerComponent? _hordeTimer;

  // ── Acumuladores ────────────────────────────────────────────────────────────
  double _survivalAccumulator = 0;

  @override
  Color backgroundColor() => Colors.black;

  // ── onLoad ──────────────────────────────────────────────────────────────────
  @override
  Future<void> onLoad() async {
    await super.onLoad();

    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    _mapSize = await _loadTiledCollisions();

    camera.viewfinder.anchor = Anchor.center;
    camera.viewfinder.position = _centralLobbySpawn(_mapSize);

    // Background
    final bgSprite = await loadSprite('h15_lab.jpg');
    _background = SpriteComponent(
      sprite: bgSprite,
      size: _mapSize,
      position: Vector2.zero(),
      priority: -10,
    );
    world.add(_background!);

    if (_enableLegacyIsoCollision) _setupWalls(size);
    if (_enableLegacyQuestZones) _setupInteractables(size);
    _setupNarrativeZones();

    // Player
    final playerImage = await images.load('player_sprite.jpg');
    lastCheckpoint = _centralLobbySpawn(_mapSize);
    final playerComponent = PlayerComponent.fromSpriteSheet(playerImage)
      ..position = lastCheckpoint.clone()
      ..priority = 5;
    player = playerComponent;
    await world.add(playerComponent);

    camera.viewfinder.zoom = 1.2;
    camera.setBounds(Rectangle.fromLTWH(0, 0, 2466, 1568));
    camera.follow(playerComponent, snap: true);

    // Escuridão
    _darkness = DarknessOverlay(radius: 220)..priority = 1000;
    camera.viewport.add(_darkness!);

    // ── Joystick na viewport — margem para landscape (polegar esquerdo) ────────
    final joystickComponent = JoystickComponent(
      knob: CircleComponent(
          radius: 26, paint: Paint()..color = const Color(0xFFF5C842)),
      background: CircleComponent(
          radius: 68, paint: Paint()..color = const Color(0xAAE5E7EB)),
      // Esquerda extrema para o polegar em landscape
      margin: const EdgeInsets.only(left: 28, bottom: 28),
      priority: 200,
    );
    _joystick = joystickComponent;
    camera.viewport.add(joystickComponent);
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (_enableLegacyIsoCollision && _walls.isNotEmpty) {
      for (final w in _walls) w.removeFromParent();
      _walls.clear();
      _setupWalls(size);
    }
    if (_enableLegacyQuestZones && _interactables.isNotEmpty) {
      for (final z in _interactables) z.removeFromParent();
      _interactables.clear();
      _setupInteractables(size);
    }
  }

  Vector2 _centralLobbySpawn(Vector2 mapSize) =>
      Vector2(mapSize.x * 0.50, mapSize.y * 0.58);

  // ── Update ──────────────────────────────────────────────────────────────────
  @override
  void update(double dt) {
    super.update(dt);
    _updateSurvivalTimer(dt);

    final p = player;
    final j = _joystick;
    if (p == null || j == null) return;
    p.move(j.relativeDelta, dt, _mapSize, _walls);
  }

  // ── Tiled ───────────────────────────────────────────────────────────────────
  Future<Vector2> _loadTiledCollisions() async {
    final raw = await rootBundle.loadString('assets/tiles/h15_collisions.json');
    _loadSafeZombieSpawnsFromJson(raw);
    late final TiledMap tiledMap;
    try {
      tiledMap = TileMapParser.parseJson(raw);
    } catch (e) {
      debugPrint('Tiled JSON parse falhou; usando fallback: $e');
      return _loadTiledCollisionsFromJson(raw);
    }

    final mapSize = _readTiledImageSize(tiledMap);
    ObjectGroup? collisionLayer;
    for (final layer in tiledMap.layers) {
      if (layer is ObjectGroup && layer.name == 'Colisoes') {
        collisionLayer = layer;
        break;
      }
    }
    if (collisionLayer == null) {
      debugPrint('Camada "Colisoes" não encontrada.');
      return mapSize;
    }

    for (final obj in collisionLayer.objects) {
      final o = _buildTiledObstacle(obj);
      if (o == null) continue;
      _walls.add(o);
      world.add(o);
    }
    return mapSize;
  }

  Vector2 _loadTiledCollisionsFromJson(String raw) {
    final map = jsonDecode(raw) as Map<String, dynamic>;
    final mapSize = _readTiledImageSizeFromJson(map);
    final layers = (map['layers'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>();
    Map<String, dynamic>? cl;
    for (final l in layers) {
      if (l['name'] == 'Colisoes') {
        cl = l;
        break;
      }
    }
    if (cl == null) {
      debugPrint('Camada "Colisoes" não encontrada (fallback).');
      return mapSize;
    }

    final objects = (cl['objects'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>();
    for (final obj in objects) {
      final o = _buildJsonTiledObstacle(obj);
      if (o == null) continue;
      _walls.add(o);
      world.add(o);
    }
    return mapSize;
  }

  void _loadSafeZombieSpawnsFromJson(String raw) {
    _safeZombieSpawns.clear();
    final map = jsonDecode(raw) as Map<String, dynamic>;
    final layers = (map['layers'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>();

    for (final layer in layers) {
      final name = layer['name'] as String? ?? '';
      if (name != 'SafeZones' && name != 'SpawnPoints') continue;

      final objects = (layer['objects'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>();
      for (final obj in objects) {
        final center = _safeSpawnCenterFromJsonObject(obj);
        if (center != null) _safeZombieSpawns.add(center);
      }
    }

    if (_safeZombieSpawns.isNotEmpty) {
      debugPrint('SpawnPoints/SafeZones carregados: ${_safeZombieSpawns.length}');
    }
  }

  Vector2? _safeSpawnCenterFromJsonObject(Map<String, dynamic> obj) {
    final x = (obj['x'] as num? ?? 0).toDouble();
    final y = (obj['y'] as num? ?? 0).toDouble();
    final polygon = obj['polygon'];
    if (polygon is List && polygon.isNotEmpty) {
      final points = polygon
          .whereType<Map<String, dynamic>>()
          .map((p) => Vector2(x + (p['x'] as num? ?? 0).toDouble(),
              y + (p['y'] as num? ?? 0).toDouble()))
          .toList();
      if (points.isEmpty) return null;
      return points.fold<Vector2>(Vector2.zero(), (sum, p) => sum + p) /
          points.length.toDouble();
    }

    final w = (obj['width'] as num? ?? 0).toDouble();
    final h = (obj['height'] as num? ?? 0).toDouble();
    return Vector2(x + w / 2, y + h / 2);
  }

  Vector2 _readTiledImageSize(TiledMap map) {
    for (final l in map.layers) {
      if (l is ImageLayer) {
        final w = l.image.width?.toDouble();
        final h = l.image.height?.toDouble();
        if (w != null && h != null) return Vector2(w, h);
      }
    }
    return _fallbackMapSize.clone();
  }

  Vector2 _readTiledImageSizeFromJson(Map<String, dynamic> map) {
    final layers = (map['layers'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>();
    for (final l in layers) {
      final w = (l['imagewidth'] as num?)?.toDouble();
      final h = (l['imageheight'] as num?)?.toDouble();
      if (w != null && h != null) return Vector2(w, h);
    }
    return _fallbackMapSize.clone();
  }

  SolidObstacle? _buildTiledObstacle(TiledObject o) {
    final x = o.x;
    final y = o.y;
    if (o.polygon.isNotEmpty) {
      final verts = o.polygon.map((p) => Vector2(x + p.x, y + p.y)).toList();
      if (verts.length >= 3)
        return IsometricWall(vertices: verts, showDebug: showDebugWalls)
          ..priority = 1;
      return null;
    }
    var w = o.width;
    var h = o.height;
    const m = 6.0;
    if (w <= 0 && h <= 0) return null;
    if (w <= 0) w = m;
    if (h <= 0) h = m;
    return InvisibleWall(
        position: Vector2(x, y), size: Vector2(w, h), showDebug: showDebugWalls)
      ..priority = 1;
  }

  SolidObstacle? _buildJsonTiledObstacle(Map<String, dynamic> o) {
    final x = (o['x'] as num? ?? 0).toDouble();
    final y = (o['y'] as num? ?? 0).toDouble();
    final polygon = o['polygon'];
    if (polygon is List) {
      final verts = polygon
          .whereType<Map<String, dynamic>>()
          .map((p) => Vector2(x + (p['x'] as num? ?? 0).toDouble(),
              y + (p['y'] as num? ?? 0).toDouble()))
          .toList();
      if (verts.length >= 3)
        return IsometricWall(vertices: verts, showDebug: showDebugWalls)
          ..priority = 1;
      return null;
    }
    var w = (o['width'] as num? ?? 0).toDouble();
    var h = (o['height'] as num? ?? 0).toDouble();
    const m = 6.0;
    if (w <= 0 && h <= 0) return null;
    if (w <= 0) w = m;
    if (h <= 0) h = m;
    return InvisibleWall(
        position: Vector2(x, y), size: Vector2(w, h), showDebug: showDebugWalls)
      ..priority = 1;
  }

  // ── Combate ─────────────────────────────────────────────────────────────────

  /// Chamado pelo botão ATK no Flutter
  void attack() {
    if (!attackEnabled.value) return;
    if (equippedWeapon.value == null) {
      showHudMessage('Equipe uma arma primeiro!');
      return;
    }
    player?.startAttack();
    _resolveWeaponAttack();
  }

  void damagePlayer(double amount) {
    if (gameOver.value) return;
    currentHealth.value =
        (currentHealth.value - amount).clamp(0, maxHealth).toDouble();
    if (currentHealth.value <= 0) _triggerGameOver();
  }

  void _triggerGameOver() {
    if (gameOver.value) return;
    gameOver.value = true;
    overlays.add('GameOver');
    pauseEngine();
  }

  void reviveAtCheckpoint() {
    overlays.remove('GameOver');
    gameOver.value = false;
    currentHealth.value = maxHealth;
    player?.position = lastCheckpoint.clone();
    _clearZombies();
    zombiesSpawned = 0;
    zombiesKilled.value = 0;
    _hordeActive = false;
    _hordeTimer?.removeFromParent();
    _hordeTimer = null;
    missionText.value = 'Sobreviva à horda (0/$_hordeTargetKills)';
    resumeEngine();
    if (equippedWeapon.value != null && !_hordeCompleted) iniciarHorda();
  }

  void _clearZombies() {
    final activeZombies = <ZombieComponent>{
      ..._zombies,
      ...world.children.whereType<ZombieComponent>(),
      ...children.whereType<ZombieComponent>(),
    };
    for (final zombie in activeZombies) {
      zombie.removeFromParent();
    }
    _zombies.clear();
  }

  void _resolveWeaponAttack() {
    final p = player;
    if (p == null) return;

    final attackRect = p.weaponAttackRect(equippedWeapon.value);
    final defeated = <ZombieComponent>[];

    for (final z in _zombies) {
      if (!z.isMounted) continue;
      if (attackRect.overlaps(z.hitRect)) {
        final dead = z.takeDamage(_weaponDamage(equippedWeapon.value));
        if (dead) defeated.add(z);
      }
    }

    for (final z in defeated) {
      z.removeFromParent();
      _zombies.remove(z);
      zombiesKilled.value++;
      _refreshHordeMissionText();
      if (zombiesKilled.value >= _hordeTargetKills) {
        _completeHordeMission();
        break;
      }
    }
  }

  int _weaponDamage(String? weapon) {
    return weapon == 'Duas Adagas' ? 5 : 10;
  }

  // ── Interação ────────────────────────────────────────────────────────────────

  void interact() {
    if (!canInteract.value || questDialogOpen.value) return;
    if (activeZoneId == 'pc_alvaro' && (questState == 0 || questState == 2)) {
      questDialogOpen.value = true;
      pauseEngine();
      overlays.add('QuestDialog');
      return;
    }
    if (activeZoneId == 'server' && questState == 1) {
      questDialogOpen.value = true;
      pauseEngine();
      overlays.add('ServerDialog');
    }
  }

  String get questDialogText => questState == 2
      ? 'Cuidado! A luz atraiu eles! Pegue esta espada e lute!'
      : 'Sobrevivente, graças a Deus! Aqui é o Prof. Álvaro. Vá ligar os servidores!';

  void closeQuestDialog() {
    overlays.remove('QuestDialog');
    if (questState == 0) {
      questState = 1;
    } else if (questState == 2) {
      questState = 3;
      attackEnabled.value = true;
    }
    questDialogOpen.value = false;
    _refreshInteractionState();
    resumeEngine();
  }

  void restorePowerAndCloseServerDialog() {
    overlays.remove('ServerDialog');
    questState = 2;
    _darkness?.removeFromParent();
    _darkness = null;
    questDialogOpen.value = false;
    _refreshInteractionState();
    resumeEngine();
  }

  void enterInteractableZone(String zoneId) {
    activeZoneId = zoneId;
    _refreshInteractionState();
  }

  void exitInteractableZone(String zoneId) {
    if (activeZoneId != zoneId) return;
    activeZoneId = null;
    _refreshInteractionState();
  }

  void _refreshInteractionState() {
    final si = switch (activeZoneId) {
      'pc_alvaro' => questState == 0 || questState == 2,
      'server' => questState == 1,
      _ => false,
    };
    final sp = activeZoneId == 'paper_sala_b' && equippedWeapon.value == null;
    if (canInteract.value != si) canInteract.value = si;
    if (canReadPaper.value != sp) canReadPaper.value = sp;
  }

  Future<void> equipWeapon(String weapon) async {
    equippedWeapon.value = weapon;
    attackEnabled.value = true;
    canReadPaper.value = false;
    missionText.value = 'Sobreviva à horda (0/$_hordeTargetKills)';
    await swapPlayerWeaponSpriteSheet(weapon);
    iniciarHorda();
    showHudMessage('Arma Equipada!');
  }

  Future<void> swapPlayerWeaponSpriteSheet(String weapon) async {
    final sheetAsset = weapon == 'Duas Adagas'
        ? 'player_espada2mao.png'
        : 'player_espada1mao.png';
    final sheet = await images.load(sheetAsset);
    player?.useWeaponSpriteSheet(sheet);
  }

  // ── Horda (TimerComponent) ──────────────────────────────────────────────────

  /// Inicia a horda de zumbis, criando 1 zumbi por tick.
  void iniciarHorda() {
    if (_hordeActive || _hordeCompleted) return;
    _hordeActive = true;
    zombiesSpawned = 0;

    // Remove timer anterior se houver
    _hordeTimer?.removeFromParent();

    final timer = TimerComponent(
      period: 2.0,
      repeat: true,
      onTick: () {
        if (_hordeCompleted || zombiesSpawned >= _hordeTargetKills) {
          _hordeTimer?.removeFromParent();
          _hordeTimer = null;
          return;
        }
        _spawnZombie();
      },
    );
    _hordeTimer = timer;
    add(timer); // TimerComponent vai ao FlameGame, não ao world
  }

  void _spawnZombie() {
    if (zombiesSpawned >= _hordeTargetKills) {
      _hordeTimer?.removeFromParent();
      _hordeTimer = null;
      return;
    }

    final p = player;
    if (p == null) return;

    final spawn = _findSafeZombieSpawn(p.position);
    if (spawn == null) {
      debugPrint('Nenhum ponto seguro encontrado para spawn de zumbi.');
      return;
    }

    final zombie = ZombieComponent(target: p)
      ..position = spawn
      ..priority = 4;
    _zombies.add(zombie);
    zombiesSpawned++;
    world.add(zombie);
  }

  Vector2? _findSafeZombieSpawn(Vector2 playerPosition) {
    if (_safeZombieSpawns.isNotEmpty) {
      final start = _random.nextInt(_safeZombieSpawns.length);
      for (var i = 0; i < _safeZombieSpawns.length; i++) {
        final candidate =
            _safeZombieSpawns[(start + i) % _safeZombieSpawns.length].clone();
        if (_isSafeZombieSpawn(candidate)) return candidate;
      }
    }

    for (var i = 0; i < _spawnAttemptLimit; i++) {
      final angle = _random.nextDouble() * math.pi * 2;
      final radius = 300.0 + _random.nextDouble() * 260;
      final candidate = Vector2(
        (playerPosition.x + math.cos(angle) * radius)
            .clamp(50.0, _mapSize.x - 50)
            .toDouble(),
        (playerPosition.y + math.sin(angle) * radius)
            .clamp(50.0, _mapSize.y - 50)
            .toDouble(),
      );
      if (_isSafeZombieSpawn(candidate)) return candidate;
    }

    return null;
  }

  bool _isSafeZombieSpawn(Vector2 center) {
    final rect = _zombieSpawnRect(center);
    if (rect.left < 0 ||
        rect.top < 0 ||
        rect.right > _mapSize.x ||
        rect.bottom > _mapSize.y) {
      return false;
    }

    for (final wall in _walls) {
      if (wall.overlapsRect(rect)) return false;
    }

    for (final zombie in _zombies) {
      if (rect.overlaps(zombie.hitRect.inflate(_spawnZombieBuffer))) {
        return false;
      }
    }

    return true;
  }

  Rect _zombieSpawnRect(Vector2 center) {
    return Rect.fromCenter(
      center: Offset(center.x, center.y),
      width: _zombieSpawnHitbox.x + _spawnZombieBuffer * 2,
      height: _zombieSpawnHitbox.y + _spawnZombieBuffer * 2,
    );
  }

  void _spawnInitialZombies() {
    iniciarHorda();
  }

  void _refreshHordeMissionText() {
    if (_hordeCompleted) return;
    missionText.value =
        'Sobreviva à horda (${zombiesKilled.value}/$_hordeTargetKills)';
  }

  void _completeHordeMission() {
    if (_hordeCompleted) return;
    _hordeCompleted = true;
    _hordeActive = false;
    _hordeTimer?.removeFromParent();
    _hordeTimer = null;
    _clearZombies();
    missionText.value = 'Saguão limpo. Aguarde instruções.';
    missionCompletedPopup.value = true;
    showHudMessage('Missão Concluída!');
  }

  void closeMissionCompletedPopup() => missionCompletedPopup.value = false;

  void showHudMessage(String message) {
    hudMessage.value = message;
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (hudMessage.value == message) hudMessage.value = null;
    });
  }

  // ── Timer de sobrevivência ──────────────────────────────────────────────────
  void _updateSurvivalTimer(double dt) {
    _survivalAccumulator += dt;
    if (_survivalAccumulator < 1) return;
    final elapsed = _survivalAccumulator.floor();
    _survivalAccumulator -= elapsed;
    survivalSeconds.value += elapsed;
  }

  // ── Zonas narrativas ────────────────────────────────────────────────────────
  void _setupNarrativeZones() {
    final paperZone = InteractableZone(
      zoneId: 'paper_sala_b',
      position: Vector2(180, 1450),
      size: Vector2(80, 80),
    )..priority = 2;
    _interactables.add(paperZone);
    world.add(paperZone);
  }

  void _setupInteractables(Vector2 ms) {
    final pc = InteractableZone(
        zoneId: 'pc_alvaro',
        position: Vector2(ms.x * .12, ms.y * .53),
        size: Vector2(ms.x * .22, ms.y * .10))
      ..priority = 2;
    final sv = InteractableZone(
        zoneId: 'server',
        position: Vector2(ms.x * .72, ms.y * .72),
        size: Vector2(ms.x * .22, ms.y * .15))
      ..priority = 2;
    _interactables.addAll([pc, sv]);
    world.addAll(_interactables);
  }

  void _setupWalls(Vector2 ms) {
    Vector2 p(double x, double y) => Vector2(ms.x * x, ms.y * y);
    List<Vector2> shrink(List<Vector2> v, [double f = 0.65]) {
      final c = v.fold<Vector2>(Vector2.zero(), (s, e) => s + e) /
          v.length.toDouble();
      return [for (final e in v) c + (e - c) * f];
    }

    final specs = <List<Vector2>>[
      [p(.00, .00), p(1.00, .00), p(1.00, .38), p(.00, .38)],
      [p(.00, .38), p(.36, .38), p(.32, .56), p(.00, .56)],
      shrink([p(.20, .40), p(.45, .35), p(.52, .42), p(.27, .49)]),
      shrink([p(.42, .47), p(.67, .41), p(.74, .49), p(.49, .56)]),
      shrink([p(.64, .55), p(.98, .48), p(1.00, .65), p(.70, .75)]),
      shrink([p(.32, .69), p(.62, .61), p(.70, .70), p(.40, .80)]),
      shrink([p(.19, .81), p(.48, .74), p(.53, .86), p(.23, .94)]),
      shrink([p(.00, .85), p(.60, .85), p(.60, 1.00), p(.00, 1.00)], 0.70),
      shrink([p(.00, .64), p(.20, .64), p(.20, .76), p(.00, .76)]),
      shrink([p(.73, .75), p(.93, .70), p(.96, .82), p(.76, .88)]),
      [Vector2(0, 0), Vector2(5, 0), Vector2(5, ms.y), Vector2(0, ms.y)],
      [
        Vector2(ms.x - 5, 0),
        Vector2(ms.x, 0),
        Vector2(ms.x, ms.y),
        Vector2(ms.x - 5, ms.y)
      ],
      [
        Vector2(0, ms.y - 5),
        Vector2(ms.x, ms.y - 5),
        Vector2(ms.x, ms.y),
        Vector2(0, ms.y)
      ],
    ];
    for (final v in specs) {
      final w = IsometricWall(vertices: v, showDebug: showDebugWalls)
        ..priority = 1;
      _walls.add(w);
      world.add(w);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PlayerComponent
// ─────────────────────────────────────────────────────────────────────────────
enum PlayerAnim {
  idle,
  walkDown,
  walkLeft,
  walkRight,
  walkUp,
  attackDown,
  attackLeft,
  attackRight,
  attackUp,
}

class PlayerComponent extends SpriteAnimationGroupComponent<PlayerAnim>
    with CollisionCallbacks {
  static const double _speed = 180;
  static const int sheetColumns = 4;
  static const int sheetRows = 3;
  static const double frameTrim = 1;
  static const double walkStepTime = 0.14;
  static const double attackStepTime = 0.08;
  static final Vector2 visualSize = Vector2(96, 96);
  static final Vector2 _bodyHBPos = Vector2(34, 40);
  static final Vector2 _bodyHBSize = Vector2(28, 44);

  bool _facingLeft = false;
  bool _isAttacking = false;
  PlayerAnim _lastMoveAnim = PlayerAnim.walkDown;
  Vector2? _lastSafePos;

  PlayerComponent._({required Map<PlayerAnim, SpriteAnimation> animations})
      : super(
            animations: animations,
            current: PlayerAnim.idle,
            size: visualSize.clone(),
            anchor: Anchor.center);

  factory PlayerComponent.fromSpriteSheet(ui.Image image) {
    return PlayerComponent._(animations: _animationsFromSpriteSheet(image));
  }

  static Map<PlayerAnim, SpriteAnimation> _animationsFromSpriteSheet(
      ui.Image image) {
    SpriteAnimation row(
      int r, {
      int n = sheetColumns,
      double stepTime = walkStepTime,
      bool loop = true,
    }) =>
        buildTrimmedRowAnimation(image,
            row: r, amount: n, stepTime: stepTime, loop: loop);
    return {
      PlayerAnim.idle: row(0, n: 1),
      PlayerAnim.walkDown: row(0),
      PlayerAnim.walkRight: row(1),
      PlayerAnim.walkLeft: row(2),
      PlayerAnim.walkUp: row(0),
      PlayerAnim.attackDown: row(0, stepTime: attackStepTime, loop: false),
      PlayerAnim.attackRight: row(1, stepTime: attackStepTime, loop: false),
      PlayerAnim.attackLeft: row(2, stepTime: attackStepTime, loop: false),
      PlayerAnim.attackUp: row(0, stepTime: attackStepTime, loop: false),
    };
  }

  static SpriteAnimation buildTrimmedRowAnimation(
    ui.Image image, {
    required int row,
    required int amount,
    required double stepTime,
    bool loop = true,
  }) {
    final frameSize =
        Vector2(image.width / sheetColumns, image.height / sheetRows);
    return SpriteAnimation.spriteList(
      List<Sprite>.generate(amount, (column) {
        return Sprite(
          image,
          srcPosition: Vector2(
            column * frameSize.x + frameTrim,
            row * frameSize.y + frameTrim,
          ),
          srcSize: Vector2(
            frameSize.x - frameTrim * 2,
            frameSize.y - frameTrim * 2,
          ),
        );
      }),
      stepTime: stepTime,
      loop: loop,
    );
  }

  void useSpriteSheet(ui.Image image) {
    final previous = current ?? PlayerAnim.idle;
    animations = _animationsFromSpriteSheet(image);
    current = previous;
  }

  void useWeaponSpriteSheet(ui.Image image) => useSpriteSheet(image);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    add(RectangleHitbox(position: _bodyHBPos, size: _bodyHBSize));
  }

  void move(Vector2 dir, double dt, Vector2 bounds, List<SolidObstacle> walls) {
    if (dir.length2 <= 0) {
      if (!_isAttacking) current = PlayerAnim.idle;
      return;
    }
    final delta = dir.normalized() * _speed * dt;
    if (!_isAttacking) _updateAnim(dir);
    _tryMove(Vector2(delta.x, 0), bounds, walls);
    _tryMove(Vector2(0, delta.y), bounds, walls);
  }

  void _updateAnim(Vector2 dir) {
    if (dir.x.abs() > dir.y.abs()) {
      current = dir.x > 0 ? PlayerAnim.walkRight : PlayerAnim.walkLeft;
      _facingLeft = dir.x < 0;
    } else {
      current = dir.y > 0 ? PlayerAnim.walkDown : PlayerAnim.walkUp;
    }
    _lastMoveAnim = current ?? PlayerAnim.walkDown;
  }

  void _tryMove(Vector2 delta, Vector2 bounds, List<SolidObstacle> walls) {
    final prev = position.clone();
    _lastSafePos = prev;
    position += delta;
    _clamp(bounds);
    if (_hitsWall(walls)) position = prev;
  }

  void _clamp(Vector2 b) {
    final hw = size.x / 2;
    final hh = size.y / 2;
    position = Vector2(position.x.clamp(hw, b.x - hw).toDouble(),
        position.y.clamp(hh, b.y - hh).toDouble());
  }

  bool _hitsWall(List<SolidObstacle> walls) {
    final f = feetRect;
    for (final w in walls) {
      if (w.overlapsRect(f)) return true;
    }
    return false;
  }

  Rect get feetRect {
    final tl = Offset(position.x - size.x / 2 + _bodyHBPos.x,
        position.y - size.y / 2 + _bodyHBPos.y);
    return Rect.fromLTWH(tl.dx, tl.dy, _bodyHBSize.x, _bodyHBSize.y);
  }

  @override
  void onCollision(Set<Vector2> pts, PositionComponent other) {
    super.onCollision(pts, other);
    if (_isSolid(other)) {
      final s = _lastSafePos;
      if (s != null) position = s;
    }
  }

  bool _isSolid(PositionComponent o) =>
      o is SolidObstacle || o.parent is SolidObstacle;

  @override
  void onCollisionStart(Set<Vector2> pts, PositionComponent other) {
    super.onCollisionStart(pts, other);
    final zone = _zone(other);
    if (zone != null) {
      final g = findGame();
      if (g is H15Game) g.enterInteractableZone(zone.zoneId);
    }
  }

  @override
  void onCollisionEnd(PositionComponent other) {
    super.onCollisionEnd(other);
    final zone = _zone(other);
    if (zone != null) {
      final g = findGame();
      if (g is H15Game) g.exitInteractableZone(zone.zoneId);
    }
  }

  InteractableZone? _zone(PositionComponent o) {
    if (o is InteractableZone) return o;
    if (o.parent is InteractableZone) return o.parent as InteractableZone;
    return null;
  }

  void startAttack() {
    _isAttacking = true;
    current = switch (_lastMoveAnim) {
      PlayerAnim.walkLeft => PlayerAnim.attackLeft,
      PlayerAnim.walkRight => PlayerAnim.attackRight,
      PlayerAnim.walkUp => PlayerAnim.attackUp,
      _ => PlayerAnim.attackDown,
    };
    animationTicker?.reset();
    setOpacity(0.55);
  }

  /// Hitbox de ataque baseada na arma equipada
  Rect weaponAttackRect(String? weapon) {
    final range = weapon == 'Duas Adagas' ? 72.0 : 104.0;
    final height = weapon == 'Duas Adagas' ? 76.0 : 88.0;
    final width = weapon == 'Duas Adagas' ? 82.0 : 112.0;
    final cx = position.x + (_facingLeft ? -range * .48 : range * .48);
    return Rect.fromCenter(
        center: Offset(cx, position.y + 4), width: width, height: height);
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_isAttacking && (animationTicker?.done() ?? false)) {
      _isAttacking = false;
      setOpacity(1);
      current = PlayerAnim.idle;
    }
  }

  @override
  void render(Canvas canvas) {
    // Sombra
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(size.x / 2, size.y + 4),
          width: size.x * .85,
          height: 8),
      Paint()..color = Colors.black.withValues(alpha: 0.35),
    );
    super.render(canvas);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ZombieComponent — animado, com HP e sistema de dano/flash
// ─────────────────────────────────────────────────────────────────────────────
enum ZombieAnim {
  idle,
  walkDown,
  walkLeft,
  walkRight,
  walkUp,
  attackDown,
  attackLeft,
  attackRight,
  attackUp,
}

class ZombieComponent extends SpriteAnimationComponent
    with CollisionCallbacks, HasGameRef<H15Game> {
  final PlayerComponent target;
  static const double _speed = 55;
  static const double _playerHitCooldown = 1.2;
  static const double _playerTouchDamage = 10;
  static final Vector2 _zombieFrameSize = Vector2(148, 140);
  static const double _walkStepTime = 0.15;
  static const double _attackStepTime = 0.08;

  // ── Sistema de vida (Correção 5) ──────────────────────────────────────────
  int health = 15;
  double _hurtFlashTimer = 0;
  double _hitCooldownTimer = 0;
  bool _isAttacking = false;
  ZombieAnim _lastMoveAnim = ZombieAnim.walkDown;
  ZombieAnim _currentAnim = ZombieAnim.idle;
  final Map<ZombieAnim, SpriteAnimation> _animations = {};
  Vector2? _lastSafePos;

  ZombieComponent({required this.target})
      : super(
          size: Vector2(96, 96),
          autoResize: false,
          anchor: Anchor.center,
        );

  Rect get hitRect => Rect.fromCenter(
        center: Offset(position.x, position.y),
        width: size.x * 0.72,
        height: size.y * 0.76,
      );

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    try {
      final sheet = await gameRef.images.load('zumbi_normal.png');
      _animations.addAll(_animationsFromSpriteSheet(sheet));
      _setAnimation(ZombieAnim.idle);
    } catch (e) {
      debugPrint('Falha ao carregar sprite do zumbi: $e');
    }

    add(RectangleHitbox(
      position: Vector2(size.x * .14, size.y * .12),
      size: Vector2(size.x * .72, size.y * .76),
    ));
  }

  /// Aplica [dmg] de dano. Retorna true se o zumbi morreu.
  bool takeDamage(int dmg) {
    health -= dmg;
    _hurtFlashTimer = 0.20; // flash vermelho por 200ms
    if (health <= 0) return true;
    return false;
  }

  @override
  void update(double dt) {
    super.update(dt);

    // Flash de dano
    if (_hurtFlashTimer > 0) {
      _hurtFlashTimer -= dt;
      if (_hurtFlashTimer <= 0) setOpacity(1.0);
    }
    if (_hitCooldownTimer > 0) _hitCooldownTimer -= dt;
    if (_isAttacking && (animationTicker?.done() ?? false)) {
      _isAttacking = false;
      _setAnimation(_lastMoveAnim);
    }

    if (!target.isMounted) return;
    final dir = target.position - position;
    if (dir.length2 < 16) {
      if (!_isAttacking) _setAnimation(ZombieAnim.idle);
      return;
    }
    if (!_isAttacking) _updateAnim(dir);
    final delta = dir.normalized() * _speed * dt;
    _tryMove(Vector2(delta.x, 0));
    _tryMove(Vector2(0, delta.y));
  }

  static Map<ZombieAnim, SpriteAnimation> _animationsFromSpriteSheet(
      ui.Image image) {
    SpriteAnimation row({
      required double rowYOffset,
      double stepTime = _walkStepTime,
      bool loop = true,
    }) =>
        SpriteAnimation.fromFrameData(
          image,
          SpriteAnimationData.sequenced(
            amount: 4,
            stepTime: stepTime,
            textureSize: _zombieFrameSize,
            texturePosition: Vector2(0, rowYOffset),
            loop: loop,
          ),
        );

    return {
      ZombieAnim.idle: row(rowYOffset: 0),
      ZombieAnim.walkDown: row(rowYOffset: 0),
      ZombieAnim.walkRight: row(rowYOffset: 140),
      ZombieAnim.walkLeft: row(rowYOffset: 280),
      ZombieAnim.walkUp: row(rowYOffset: 0),
      ZombieAnim.attackDown:
          row(rowYOffset: 0, stepTime: _attackStepTime, loop: false),
      ZombieAnim.attackRight:
          row(rowYOffset: 140, stepTime: _attackStepTime, loop: false),
      ZombieAnim.attackLeft:
          row(rowYOffset: 280, stepTime: _attackStepTime, loop: false),
      ZombieAnim.attackUp:
          row(rowYOffset: 0, stepTime: _attackStepTime, loop: false),
    };
  }

  void _updateAnim(Vector2 dir) {
    if (dir.x.abs() > dir.y.abs()) {
      _setAnimation(dir.x > 0 ? ZombieAnim.walkRight : ZombieAnim.walkLeft);
    } else {
      _setAnimation(dir.y > 0 ? ZombieAnim.walkDown : ZombieAnim.walkUp);
    }
    _lastMoveAnim = _currentAnim;
  }

  void _setAnimation(ZombieAnim next) {
    if (_currentAnim == next && animation != null) return;
    final nextAnimation = _animations[next];
    if (nextAnimation == null) return;
    _currentAnim = next;
    animation = nextAnimation;
  }

  void _tryMove(Vector2 delta) {
    final prev = position.clone();
    _lastSafePos = prev;
    position += delta;
    _clamp(gameRef._mapSize);
    if (_hitsWall(gameRef._walls)) position = prev;
  }

  void _clamp(Vector2 b) {
    final hw = size.x / 2;
    final hh = size.y / 2;
    position = Vector2(position.x.clamp(hw, b.x - hw).toDouble(),
        position.y.clamp(hh, b.y - hh).toDouble());
  }

  bool _hitsWall(List<SolidObstacle> walls) {
    final rect = hitRect;
    for (final w in walls) {
      if (w.overlapsRect(rect)) return true;
    }
    return false;
  }

  @override
  void onCollision(Set<Vector2> pts, PositionComponent other) {
    super.onCollision(pts, other);
    if (_isSolid(other)) {
      final safe = _lastSafePos;
      if (safe != null) position = safe;
      return;
    }
    final zombie = _zombieFrom(other);
    if (zombie != null && zombie != this) _separateFrom(zombie);
    final player = _playerFrom(other);
    if (player != null) _damagePlayerWithCooldown();
  }

  bool _isSolid(PositionComponent o) =>
      o is SolidObstacle || o.parent is SolidObstacle;

  ZombieComponent? _zombieFrom(PositionComponent o) {
    if (o is ZombieComponent) return o;
    if (o.parent is ZombieComponent) return o.parent as ZombieComponent;
    return null;
  }

  PlayerComponent? _playerFrom(PositionComponent o) {
    if (o is PlayerComponent) return o;
    if (o.parent is PlayerComponent) return o.parent as PlayerComponent;
    return null;
  }

  void _damagePlayerWithCooldown() {
    if (_hitCooldownTimer > 0) return;
    _hitCooldownTimer = _playerHitCooldown;
    gameRef.damagePlayer(_playerTouchDamage);
    _startAttack();
  }

  void _startAttack() {
    _isAttacking = true;
    _setAnimation(switch (_lastMoveAnim) {
      ZombieAnim.walkLeft => ZombieAnim.attackLeft,
      ZombieAnim.walkRight => ZombieAnim.attackRight,
      ZombieAnim.walkUp => ZombieAnim.attackUp,
      _ => ZombieAnim.attackDown,
    });
    animationTicker?.reset();
  }

  void _separateFrom(ZombieComponent other) {
    var away = position - other.position;
    if (away.length2 < 0.0001) {
      away = Vector2(
        math.cos(position.x + position.y),
        math.sin(position.x - position.y),
      );
    }

    final minDistance = size.x * 0.48;
    final distance = away.length;
    if (distance >= minDistance) return;

    final push = away.normalized() * ((minDistance - distance) * 0.5 + 0.8);
    position += push;
    _clamp(gameRef._mapSize);
    if (_hitsWall(gameRef._walls)) {
      final safe = _lastSafePos;
      if (safe != null) position = safe;
    }
  }

  @override
  void render(Canvas canvas) {
    // Sombra
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(size.x / 2, size.y + 3),
          width: size.x * .85,
          height: 7),
      Paint()..color = Colors.black.withValues(alpha: 0.35),
    );

    // Flash vermelho quando toma dano
    if (_hurtFlashTimer > 0) {
      final t = (_hurtFlashTimer / 0.20).clamp(0.0, 1.0);
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.x, size.y),
        Paint()..color = Colors.red.withValues(alpha: t * 0.55),
      );
    }

    super.render(canvas);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Obstáculos e zonas
// ─────────────────────────────────────────────────────────────────────────────
abstract class SolidObstacle extends PositionComponent {
  SolidObstacle({super.position, super.size});
  bool overlapsRect(Rect rect);
}

class InvisibleWall extends SolidObstacle {
  final bool showDebug;
  InvisibleWall(
      {required Vector2 position, required Vector2 size, this.showDebug = true})
      : super(position: position, size: size);

  Rect get wallRect => Rect.fromLTWH(position.x, position.y, size.x, size.y);

  @override
  bool overlapsRect(Rect rect) => wallRect.overlaps(rect);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    debugMode = showDebug;
    add(RectangleHitbox(isSolid: true));
  }

  @override
  void render(Canvas canvas) {
    if (showDebug)
      canvas.drawRect(
          size.toRect(), Paint()..color = Colors.red.withValues(alpha: .24));
    super.render(canvas);
  }
}

class IsometricWall extends SolidObstacle {
  final List<Vector2> vertices;
  final bool showDebug;

  IsometricWall({required this.vertices, this.showDebug = true})
      : super(position: Vector2.zero());

  late final Rect boundsRect = _bounds(vertices);

  @override
  bool overlapsRect(Rect rect) {
    if (!boundsRect.overlaps(rect)) return false;
    final rc = [
      Vector2(rect.left, rect.top),
      Vector2(rect.right, rect.top),
      Vector2(rect.right, rect.bottom),
      Vector2(rect.left, rect.bottom)
    ];
    for (final c in rc) {
      if (_contains(c)) return true;
    }
    for (final v in vertices) {
      if (rect.contains(Offset(v.x, v.y))) return true;
    }
    for (var i = 0; i < vertices.length; i++) {
      final a = vertices[i];
      final b = vertices[(i + 1) % vertices.length];
      for (var j = 0; j < rc.length; j++) {
        if (_intersects(a, b, rc[j], rc[(j + 1) % rc.length])) return true;
      }
    }
    return false;
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    debugMode = showDebug;
    add(PolygonHitbox(vertices, isSolid: true));
  }

  @override
  void render(Canvas canvas) {
    if (showDebug) {
      final path = Path()..moveTo(vertices.first.x, vertices.first.y);
      for (final v in vertices.skip(1)) path.lineTo(v.x, v.y);
      path.close();
      canvas.drawPath(path, Paint()..color = Colors.red.withValues(alpha: .24));
      canvas.drawPath(
          path,
          Paint()
            ..color = Colors.red.withValues(alpha: .85)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5);
    }
    super.render(canvas);
  }

  static Rect _bounds(List<Vector2> v) {
    var x0 = v.first.x, x1 = v.first.x, y0 = v.first.y, y1 = v.first.y;
    for (final e in v.skip(1)) {
      if (e.x < x0) x0 = e.x;
      if (e.x > x1) x1 = e.x;
      if (e.y < y0) y0 = e.y;
      if (e.y > y1) y1 = e.y;
    }
    return Rect.fromLTRB(x0, y0, x1, y1);
  }

  bool _contains(Vector2 p) {
    var inside = false;
    for (var i = 0, j = vertices.length - 1; i < vertices.length; j = i++) {
      final vi = vertices[i];
      final vj = vertices[j];
      if (((vi.y > p.y) != (vj.y > p.y)) &&
          (p.x < (vj.x - vi.x) * (p.y - vi.y) / (vj.y - vi.y) + vi.x))
        inside = !inside;
    }
    return inside;
  }

  bool _intersects(Vector2 a, Vector2 b, Vector2 c, Vector2 d) =>
      _ori(a, b, c) != _ori(a, b, d) && _ori(c, d, a) != _ori(c, d, b);

  int _ori(Vector2 a, Vector2 b, Vector2 c) {
    final v = (b.y - a.y) * (c.x - b.x) - (b.x - a.x) * (c.y - b.y);
    if (v.abs() < 0.0001) return 0;
    return v > 0 ? 1 : 2;
  }
}

class InteractableZone extends PositionComponent with CollisionCallbacks {
  final String zoneId;
  InteractableZone(
      {required this.zoneId, required Vector2 position, required Vector2 size})
      : super(position: position, size: size);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    add(RectangleHitbox(isSolid: false, collisionType: CollisionType.passive));
  }
}

class DarknessOverlay extends Component with HasGameRef<H15Game> {
  final double radius;
  DarknessOverlay({this.radius = 220});

  @override
  void render(Canvas canvas) {
    final ovSize = gameRef.camera.viewport.size;
    final vpSize = ovSize.length2 == 0 ? gameRef.size : ovSize;
    final bounds = Offset.zero & vpSize.toSize();
    final center = _playerScreen(vpSize);

    canvas.saveLayer(bounds, Paint());
    canvas.drawRect(bounds, Paint()..color = const Color(0xD9000000));
    canvas.drawCircle(
      Offset(center.x, center.y),
      radius,
      Paint()
        ..blendMode = BlendMode.dstOut
        ..shader = ui.Gradient.radial(
          Offset(center.x, center.y),
          radius,
          const [Color(0xFFFFFFFF), Color(0xCCFFFFFF), Color(0x00FFFFFF)],
          const [0.0, 0.62, 1.0],
        ),
    );
    canvas.restore();
  }

  Vector2 _playerScreen(Vector2 vpSize) {
    final p = gameRef.player;
    if (p == null) return vpSize / 2;
    final sp = gameRef.camera.localToGlobal(p.position);
    return gameRef.camera.viewport.globalToLocal(sp);
  }
}
