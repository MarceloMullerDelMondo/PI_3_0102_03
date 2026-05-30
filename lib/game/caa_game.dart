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

enum CAAFinalChoice { rescueSignal, cureData }

class CAALevel extends FlameGame with HasCollisionDetection {
  CAALevel({required this.playerName});

  final String playerName;

  static const int hordeTarget = 12;
  static final Vector2 _fallbackMapSize = Vector2(1269, 1041);
  static final Vector2 _fallbackSpawn = Vector2(640, 865);
  static final Vector2 _rochaPosition = Vector2(735, 500);
  static final Vector2 _radioTerminalPosition = Vector2(885, 315);
  static final Vector2 _playerSize = Vector2(58, 58);

  PlayerComponent? player;
  JoystickComponent? _joystick;
  SpriteComponent? _background;
  CaaRochaComponent? rocha;
  CaaRadioTerminalComponent? radioTerminal;

  Vector2 _mapSize = _fallbackMapSize.clone();
  final List<SolidObstacle> _walls = [];
  final List<CaaZombieComponent> _zombies = [];
  final math.Random _rng = math.Random();

  final ValueNotifier<double> currentHealth = ValueNotifier(100);
  final ValueNotifier<double> maxHealth = ValueNotifier(100);
  final ValueNotifier<String> missionText =
      ValueNotifier('Missao: fale com Sargento Rocha no CAA.');
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

  Object? _nearby;
  bool _talkedToRocha = false;
  bool _hordeStarted = false;
  bool _choiceOverlayOpen = false;
  bool _choiceSaved = false;
  int _spawned = 0;

  @override
  Color backgroundColor() => Colors.black;

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    camera.viewfinder.anchor = Anchor.center;
    camera.viewfinder.position = _fallbackSpawn.clone();

    final rawMap = await _loadTiledMap();
    await _loadBackground();
    _loadCollisions(rawMap);

    final playerImage = await images.load('player/player_sprite.jpg');
    final playerComponent = PlayerComponent.fromSpriteSheet(playerImage)
      ..position = _readSpawn(rawMap)
      ..size = _playerSize
      ..priority = 6;
    player = playerComponent;
    await world.add(playerComponent);

    final minZoom = math.max(size.x / _mapSize.x, size.y / _mapSize.y);
    camera.viewfinder.zoom = math.max(minZoom, 1.35);
    camera.setBounds(Rectangle.fromLTWH(0, 0, _mapSize.x, _mapSize.y));
    camera.follow(playerComponent, snap: true);

    rocha = CaaRochaComponent(position: _rochaPosition)..priority = 8;
    radioTerminal = CaaRadioTerminalComponent(position: _radioTerminalPosition)
      ..priority = 7;
    await world.add(rocha!);
    await world.add(radioTerminal!);

    _setupJoystick();
    _restoreWeapon();

    async.Timer(const Duration(milliseconds: 700), () {
      if (!isMounted || gameOver.value) return;
      showHudMessage('Sargento Rocha guarda o terminal de transmissao.');
    });
  }

  Future<Map<String, dynamic>> _loadTiledMap() async {
    try {
      final raw = await rootBundle.loadString('assets/tiles/caa_map.json');
      final map = jsonDecode(raw) as Map<String, dynamic>;
      _mapSize = _readMapSize(map);
      return map;
    } catch (e) {
      debugPrint('CAA map load failed: $e');
      _mapSize = _fallbackMapSize.clone();
      return const {};
    }
  }

  Vector2 _readMapSize(Map<String, dynamic> map) {
    for (final layer in _layers(map)) {
      final w = (layer['imagewidth'] as num?)?.toDouble();
      final h = (layer['imageheight'] as num?)?.toDouble();
      if (w != null && h != null) return Vector2(w, h);
    }
    final width = (map['width'] as num? ?? 0).toDouble();
    final height = (map['height'] as num? ?? 0).toDouble();
    final tileW = (map['tilewidth'] as num? ?? 16).toDouble();
    final tileH = (map['tileheight'] as num? ?? 16).toDouble();
    if (width > 0 && height > 0) return Vector2(width * tileW, height * tileH);
    return _fallbackMapSize.clone();
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

  void _loadCollisions(Map<String, dynamic> map) {
    final layer = _objectLayer(map, 'Colisoes');
    final objects = _objects(layer);
    if (objects.isEmpty) {
      _addBorderWalls();
      return;
    }
    for (final obj in objects) {
      final wall = _wallFromObject(obj);
      if (wall == null) continue;
      _walls.add(wall);
      world.add(wall);
    }
  }

  void _addBorderWalls() {
    const t = 10.0;
    final specs = [
      (Vector2.zero(), Vector2(_mapSize.x, t)),
      (Vector2(0, _mapSize.y - t), Vector2(_mapSize.x, t)),
      (Vector2.zero(), Vector2(t, _mapSize.y)),
      (Vector2(_mapSize.x - t, 0), Vector2(t, _mapSize.y)),
    ];
    for (final spec in specs) {
      final wall = InvisibleWall(
        position: spec.$1,
        size: spec.$2,
        showDebug: false,
      )..priority = 1;
      _walls.add(wall);
      world.add(wall);
    }
  }

  SolidObstacle? _wallFromObject(Map<String, dynamic> obj) {
    final x = (obj['x'] as num? ?? 0).toDouble();
    final y = (obj['y'] as num? ?? 0).toDouble();
    final w = (obj['width'] as num? ?? 0).toDouble();
    final h = (obj['height'] as num? ?? 0).toDouble();
    if (w <= 0 || h <= 0) return null;
    return InvisibleWall(
      position: Vector2(x, y),
      size: Vector2(w, h),
      showDebug: false,
    )..priority = 1;
  }

  Vector2 _readSpawn(Map<String, dynamic> map) {
    final object = _findObjectByName(map, (name) {
      final lower = name.toLowerCase();
      return lower.contains('spawn') || lower.contains('player');
    });
    if (object == null) return _clampToMap(_fallbackSpawn, _playerSize);
    return _clampToMap(
      Vector2(
        (object['x'] as num? ?? 0).toDouble(),
        (object['y'] as num? ?? 0).toDouble(),
      ),
      _playerSize,
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

  void _restoreWeapon() {
    FirebaseService.instance.loadWeapon().then((weapon) async {
      final selected = (weapon == null || weapon.isEmpty) ? 'Espada' : weapon;
      final asset = selected == 'Duas Adagas'
          ? 'player/player_espada2mao.png'
          : 'player/player_espada1mao.png';
      try {
        final img = await images.load(asset);
        player?.useWeaponSpriteSheet(img);
      } catch (e) {
        debugPrint('CAA weapon sprite failed: $e');
      }
    }).catchError((_) {});
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (dialogOpen.value || gameOver.value || levelCompleted.value) return;

    final p = player;
    final j = _joystick;
    if (p == null || j == null) return;

    p.move(j.relativeDelta, dt, _mapSize, _walls);
    _updateInteractionState();
    _removeDeadZombies();
    _maybeOpenFinalChoice();
  }

  void _updateInteractionState() {
    final p = player;
    if (p == null) return;

    Object? nearby;
    var label = 'INTERAGIR';
    if (rocha != null && (p.position - rocha!.position).length <= 90) {
      nearby = rocha;
      label = 'FALAR';
    }
    if (radioTerminal != null &&
        (p.position - radioTerminal!.position).length <= 105 &&
        !_hordeStarted) {
      nearby = radioTerminal;
      label = 'USAR RADIO';
    }

    _nearby = nearby;
    canInteract.value = nearby != null;
    interactLabel.value = label;
  }

  void interact() {
    final target = _nearby;
    if (target == null || dialogOpen.value) return;
    if (target is CaaRochaComponent) {
      _talkToRocha();
    } else if (target is CaaRadioTerminalComponent) {
      triggerHordeEvent();
    }
  }

  void _talkToRocha() {
    _talkedToRocha = true;
    missionText.value = 'Missao: use o radio e defenda o terminal.';
    showHudMessage('Rocha: "Ative o radio. Eu seguro a mesa central."');
  }

  void triggerHordeEvent() {
    if (_hordeStarted) return;
    _hordeStarted = true;
    _spawned = 0;
    hordeActive.value = true;
    canInteract.value = false;
    missionText.value = 'Missao: defenda o CAA da horda.';
    showHudMessage('Horda detectada. Defenda o terminal!');

    final spawnPoints = _edgeSpawnPoints();
    for (var i = 0; i < hordeTarget; i++) {
      async.Timer(Duration(milliseconds: i * 260), () {
        if (!isMounted || gameOver.value || levelCompleted.value) return;
        final base = spawnPoints[i % spawnPoints.length];
        final jitter = Vector2(_rng.nextDouble() * 40 - 20, _rng.nextDouble() * 40 - 20);
        _spawnZombie(_clampToMap(base + jitter, CaaZombieComponent.visualSize));
      });
    }
  }

  List<Vector2> _edgeSpawnPoints() => [
        Vector2(48, 80),
        Vector2(_mapSize.x - 48, 120),
        Vector2(58, _mapSize.y - 100),
        Vector2(_mapSize.x - 70, _mapSize.y - 120),
        Vector2(_mapSize.x * .50, 50),
        Vector2(_mapSize.x * .50, _mapSize.y - 56),
      ];

  void _spawnZombie(Vector2 position) {
    final p = player;
    if (p == null) return;
    final zombie = CaaZombieComponent(
      game: this,
      target: p,
      position: position,
    )..priority = 9;
    _zombies.add(zombie);
    _spawned++;
    zombiesRemaining.value = _zombies.length;
    world.add(zombie);
  }

  void attack() {
    if (!attackEnabled.value || gameOver.value || dialogOpen.value) return;
    final p = player;
    if (p == null) return;
    p.startAttack();
    final attackRect = p.weaponAttackRect(null);
    for (final zombie in List<CaaZombieComponent>.of(_zombies)) {
      if (!zombie.isMounted || !zombie.isAlive) continue;
      if (attackRect.overlaps(zombie.hitRect)) {
        zombie.takeDamage(10);
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

  void _removeDeadZombies() {
    var changed = false;
    for (final zombie in List<CaaZombieComponent>.of(_zombies)) {
      if (zombie.isAlive && zombie.isMounted) continue;
      _zombies.remove(zombie);
      changed = true;
      zombiesKilled.value++;
    }
    if (changed) zombiesRemaining.value = _zombies.length;
  }

  void _maybeOpenFinalChoice() {
    if (!_hordeStarted ||
        _choiceOverlayOpen ||
        _choiceSaved ||
        _spawned < hordeTarget ||
        _zombies.isNotEmpty) {
      return;
    }
    hordeActive.value = false;
    missionText.value = 'Missao: escolha o destino do sinal.';
    _choiceOverlayOpen = true;
    dialogOpen.value = true;
    overlays.add('FinalChoice');
  }

  Future<void> chooseFinalSignal(CAAFinalChoice choice) async {
    if (_choiceSaved) return;
    _choiceSaved = true;
    final value = switch (choice) {
      CAAFinalChoice.rescueSignal => 'rescue_signal',
      CAAFinalChoice.cureData => 'cure_data',
    };
    await FirebaseService.instance.completeArea4(playerName, finalChoice: value);
    overlays.remove('FinalChoice');
    dialogOpen.value = false;
    showHudMessage('Sinal enviado. Reitoria desbloqueada.');
    await async.Future<void>.delayed(const Duration(milliseconds: 800));
    levelCompleted.value = true;
  }

  void reviveAtCheckpoint() {
    for (final zombie in List<CaaZombieComponent>.of(_zombies)) {
      zombie.removeFromParent();
    }
    _zombies.clear();
    _spawned = 0;
    _hordeStarted = false;
    _choiceOverlayOpen = false;
    hordeActive.value = false;
    zombiesRemaining.value = 0;
    currentHealth.value = maxHealth.value;
    gameOver.value = false;
    player?.position = _fallbackSpawn.clone();
    missionText.value = _talkedToRocha
        ? 'Missao: use o radio e defenda o terminal.'
        : 'Missao: fale com Sargento Rocha no CAA.';
  }

  void showHudMessage(String message) {
    hudMessage.value = message;
    async.Timer(const Duration(seconds: 3), () {
      if (hudMessage.value == message) hudMessage.value = null;
    });
  }

  Vector2 _clampToMap(Vector2 center, Vector2 componentSize) => Vector2(
        center.x
            .clamp(componentSize.x / 2, _mapSize.x - componentSize.x / 2)
            .toDouble(),
        center.y
            .clamp(componentSize.y / 2, _mapSize.y - componentSize.y / 2)
            .toDouble(),
      );

  List<Map<String, dynamic>> _layers(Map<String, dynamic> map) =>
      (map['layers'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();

  Map<String, dynamic>? _objectLayer(Map<String, dynamic> map, String name) {
    for (final layer in _layers(map)) {
      if ((layer['name'] as String? ?? '') == name) return layer;
    }
    return null;
  }

  List<Map<String, dynamic>> _objects(Map<String, dynamic>? layer) =>
      (layer?['objects'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();

  Map<String, dynamic>? _findObjectByName(
    Map<String, dynamic> map,
    bool Function(String name) test,
  ) {
    for (final layer in _layers(map)) {
      for (final obj in _objects(layer)) {
        final name = obj['name']?.toString() ?? '';
        if (test(name)) return obj;
      }
    }
    return null;
  }
}

class CaaRochaComponent extends SpriteComponent {
  CaaRochaComponent({required super.position})
      : super(size: Vector2(72, 112), anchor: Anchor.center);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    final game = findGame() as CAALevel;
    try {
      sprite = Sprite(await game.images.load('npcs/sargento_rocha_cutout.png'));
    } catch (e) {
      debugPrint('Sargento Rocha sprite failed: $e');
    }
  }

  @override
  void render(Canvas canvas) {
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.x / 2, size.y + 3),
        width: size.x * .75,
        height: 8,
      ),
      Paint()..color = Colors.black.withValues(alpha: .35),
    );
    if (sprite != null) {
      super.render(canvas);
    } else {
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

class CaaRadioTerminalComponent extends PositionComponent {
  CaaRadioTerminalComponent({required super.position})
      : super(size: Vector2(74, 58), anchor: Anchor.center);

  @override
  void render(Canvas canvas) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(size.toRect(), const Radius.circular(4)),
      Paint()..color = const Color(0xFF111827),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(size.toRect().deflate(3), const Radius.circular(3)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFF38BDF8),
    );
    canvas.drawCircle(
      Offset(size.x * .78, size.y * .25),
      5,
      Paint()..color = const Color(0xFF22C55E),
    );
    canvas.drawLine(
      Offset(size.x * .20, size.y * .62),
      Offset(size.x * .62, size.y * .62),
      Paint()
        ..color = const Color(0xFFFACC15)
        ..strokeWidth = 3,
    );
  }
}

class CaaZombieComponent extends SpriteComponent {
  CaaZombieComponent({
    required this.game,
    required this.target,
    required Vector2 position,
  }) : super(
          position: position,
          size: visualSize.clone(),
          anchor: Anchor.center,
        );

  static final Vector2 visualSize = Vector2(62, 62);
  static const double _speed = 62;
  static const double _damageCooldown = 1.0;
  static const double _touchDamage = 7;

  final CAALevel game;
  final PlayerComponent target;
  int health = 20;
  double _hitCooldown = 0;
  double _flash = 0;
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
      sprite = Sprite(await game.images.load('zumbis/caa_zombie_cutout.png'));
    } catch (e) {
      debugPrint('CAA zombie sprite failed: $e');
    }
    add(RectangleHitbox(collisionType: CollisionType.passive));
  }

  void takeDamage(int amount) {
    if (!isAlive) return;
    health -= amount;
    _flash = .18;
    if (health <= 0) removeFromParent();
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!isAlive) return;
    if (_hitCooldown > 0) _hitCooldown -= dt;
    if (_flash > 0) _flash -= dt;

    var dir = target.position - position;
    if (dir.length2 > 4) {
      dir = dir.normalized();
      position += dir * _speed * dt;
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
    if (sprite != null) {
      super.render(canvas);
    } else {
      canvas.drawCircle(
        Offset(size.x / 2, size.y / 2),
        size.x * .36,
        Paint()..color = const Color(0xFF3F6212),
      );
    }
    if (_flash > 0) {
      canvas.drawRect(
        size.toRect(),
        Paint()..color = Colors.red.withValues(alpha: .45),
      );
    }
  }
}

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
