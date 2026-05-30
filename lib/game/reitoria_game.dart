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

enum ReitoriaRoute { cure, rescue }

class ReitoriaLevel extends FlameGame with HasCollisionDetection {
  ReitoriaLevel({required this.playerName});

  final String playerName;

  static final Vector2 _fallbackMapSize = Vector2(1600, 900);
  static final Vector2 _fallbackSpawn = Vector2(300, 710);
  static final Vector2 _fallbackMariana = Vector2(780, 465);
  static final Vector2 _fallbackServer = Vector2(820, 440);
  static final Vector2 _fallbackGate = Vector2(1420, 690);
  static final Vector2 _playerSize = Vector2(58, 58);
  static const double _uploadDuration = 120;
  static const double _survivalDuration = 120;
  static const double _nightfallUploadAt = .82;
  static const double _nightfallTimerAt = 25;

  PlayerComponent? player;
  JoystickComponent? _joystick;
  SpriteComponent? _background;
  ReitoriaMarianaComponent? mariana;
  ReitoriaServerComponent? server;
  ReitoriaGateComponent? gate;
  ReitoriaDarknessOverlay? _darkness;

  Vector2 _mapSize = _fallbackMapSize.clone();
  Vector2 _serverPosition = _fallbackServer.clone();
  Vector2 _gatePosition = _fallbackGate.clone();
  final List<SolidObstacle> _walls = [];
  final List<ReitoriaZombieComponent> _zombies = [];
  final math.Random _rng = math.Random();

  final ValueNotifier<double> currentHealth = ValueNotifier(100);
  final ValueNotifier<double> maxHealth = ValueNotifier(100);
  final ValueNotifier<double> uploadProgress = ValueNotifier(0);
  final ValueNotifier<double> serverIntegrity = ValueNotifier(100);
  final ValueNotifier<int> countdownSeconds = ValueNotifier(_survivalDuration.toInt());
  final ValueNotifier<String> missionText =
      ValueNotifier('Missao final: encontre Mariana na Reitoria.');
  final ValueNotifier<String?> hudMessage = ValueNotifier(null);
  final ValueNotifier<bool> dialogOpen = ValueNotifier(false);
  final ValueNotifier<bool> attackEnabled = ValueNotifier(true);
  final ValueNotifier<bool> nightfallActive = ValueNotifier(false);
  final ValueNotifier<bool> gameOver = ValueNotifier(false);
  final ValueNotifier<bool> levelCompleted = ValueNotifier(false);
  final ValueNotifier<ReitoriaRoute> route =
      ValueNotifier(ReitoriaRoute.rescue);

  bool _introShown = false;
  bool _objectiveStarted = false;
  bool _endingOpen = false;
  double _uploadElapsed = 0;
  double _countdownLeft = _survivalDuration;
  double _spawnTimer = 0;
  int _wave = 0;

  @override
  Color backgroundColor() => Colors.black;

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    camera.viewfinder.anchor = Anchor.center;
    camera.viewfinder.position = _fallbackSpawn.clone();

    route.value = await _loadRoute();
    final rawMap = await _loadOptionalMap();
    await _loadBackground(rawMap);
    _loadCollisions(rawMap);

    final playerImage = await images.load('player/player_sprite.jpg');
    final playerComponent = PlayerComponent.fromSpriteSheet(playerImage)
      ..position = _readObjectPosition(rawMap, ['spawn', 'player']) ??
          _clampToMap(_fallbackSpawn, _playerSize)
      ..size = _playerSize
      ..priority = 8;
    player = playerComponent;
    await world.add(playerComponent);

    _serverPosition =
        _readObjectPosition(rawMap, ['server', 'servidor']) ?? _fallbackServer;
    _gatePosition =
        _readObjectPosition(rawMap, ['gate', 'portao', 'saida']) ?? _fallbackGate;
    final marianaPosition =
        _readObjectPosition(rawMap, ['mariana', 'npc']) ?? _fallbackMariana;

    server = ReitoriaServerComponent(position: _serverPosition)..priority = 5;
    gate = ReitoriaGateComponent(position: _gatePosition)..priority = 5;
    mariana = ReitoriaMarianaComponent(position: marianaPosition)..priority = 7;
    await world.add(server!);
    await world.add(gate!);
    await world.add(mariana!);

    final minZoom = math.max(size.x / _mapSize.x, size.y / _mapSize.y);
    camera.viewfinder.zoom = math.max(minZoom, 1.25);
    camera.setBounds(Rectangle.fromLTWH(0, 0, _mapSize.x, _mapSize.y));
    camera.follow(playerComponent, snap: true);

    _setupJoystick();
    _restoreWeapon();

    async.Timer(const Duration(milliseconds: 650), () {
      if (!isMounted || _introShown) return;
      _openIntroDialog();
    });
  }

  Future<ReitoriaRoute> _loadRoute() async {
    final saved = (await FirebaseService.instance.loadCaaFinalChoice()) ?? '';
    final normalized = saved.toLowerCase();
    if (normalized.contains('cure') ||
        normalized.contains('cura') ||
        normalized.contains('data') ||
        normalized.contains('dados')) {
      return ReitoriaRoute.cure;
    }
    return ReitoriaRoute.rescue;
  }

  Future<Map<String, dynamic>> _loadOptionalMap() async {
    for (final asset in const [
      'assets/tiles/reitoria_map.json',
      'assets/tiles/reitoria.json',
    ]) {
      try {
        final raw = await rootBundle.loadString(asset);
        final map = jsonDecode(raw) as Map<String, dynamic>;
        _mapSize = _readMapSize(map);
        return map;
      } catch (_) {}
    }
    return const {};
  }

  Future<void> _loadBackground(Map<String, dynamic> map) async {
    try {
      final image = await images.load('screens/reitoria_screen.jpeg');
      if (map.isEmpty) _mapSize = Vector2(image.width.toDouble(), image.height.toDouble());
      _background = SpriteComponent(
        sprite: Sprite(image),
        size: _mapSize,
        position: Vector2.zero(),
        priority: -10,
      );
      world.add(_background!);
    } catch (e) {
      debugPrint('Reitoria background failed: $e');
      world.add(ReitoriaFallbackMap(size: _mapSize)..priority = -10);
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

  void _loadCollisions(Map<String, dynamic> map) {
    final objects = _objects(_objectLayer(map, 'Colisoes'));
    for (final obj in objects) {
      final wall = _wallFromObject(obj);
      if (wall == null) continue;
      _walls.add(wall);
      world.add(wall);
    }
    _addBorderWalls();
  }

  SolidObstacle? _wallFromObject(Map<String, dynamic> obj) {
    final x = (obj['x'] as num? ?? 0).toDouble();
    final y = (obj['y'] as num? ?? 0).toDouble();
    final w = (obj['width'] as num? ?? 0).toDouble();
    final h = (obj['height'] as num? ?? 0).toDouble();
    if (w <= 0 || h <= 0) return null;
    return InvisibleWall(position: Vector2(x, y), size: Vector2(w, h));
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
      final wall = InvisibleWall(position: spec.$1, size: spec.$2)..priority = 1;
      _walls.add(wall);
      world.add(wall);
    }
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
        player?.useWeaponSpriteSheet(await images.load(asset));
      } catch (e) {
        debugPrint('Reitoria weapon sprite failed: $e');
      }
    }).catchError((_) {});
  }

  void _openIntroDialog() {
    _introShown = true;
    dialogOpen.value = true;
    pauseEngine();
    overlays.add('MarianaDialog');
  }

  void closeIntroDialog() {
    overlays.remove('MarianaDialog');
    dialogOpen.value = false;
    resumeEngine();
    _startObjective();
  }

  void _startObjective() {
    if (_objectiveStarted) return;
    _objectiveStarted = true;
    if (route.value == ReitoriaRoute.cure) {
      missionText.value = 'Rota Cura: defenda o servidor ate o upload chegar a 100%.';
      showHudMessage('Upload iniciado. Proteja o servidor.');
    } else {
      missionText.value = 'Rota Resgate: sobreviva ate o helicoptero chegar ao portao.';
      showHudMessage('Sinal recebido. Aguente ate o resgate.');
    }
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
    if (!_objectiveStarted) return;

    if (route.value == ReitoriaRoute.cure) {
      _updateCureRoute(dt);
    } else {
      _updateRescueRoute(dt);
    }
    _checkNightfall();
  }

  void _updateCureRoute(double dt) {
    _uploadElapsed = (_uploadElapsed + dt).clamp(0, _uploadDuration);
    uploadProgress.value = _uploadElapsed / _uploadDuration;
    _spawnTimer -= dt;
    if (_spawnTimer <= 0) {
      _spawnTimer = nightfallActive.value ? .9 : 1.45;
      _spawnZombie(target: _serverPosition, nearServer: true);
    }
    if (uploadProgress.value >= 1) {
      _openEnding();
    }
  }

  void _updateRescueRoute(double dt) {
    _countdownLeft = math.max(0, _countdownLeft - dt);
    countdownSeconds.value = _countdownLeft.ceil();
    _spawnTimer -= dt;
    if (_spawnTimer <= 0) {
      _wave++;
      _spawnTimer = nightfallActive.value ? 4.0 : 6.5;
      final count = nightfallActive.value ? 5 : (3 + (_wave ~/ 2).clamp(0, 3));
      for (var i = 0; i < count; i++) {
        _spawnZombie(target: _gatePosition, nearServer: false);
      }
    }
    if (_countdownLeft <= 0) {
      _openEnding();
    }
  }

  void _checkNightfall() {
    final shouldActivate = route.value == ReitoriaRoute.cure
        ? uploadProgress.value >= _nightfallUploadAt
        : _countdownLeft <= _nightfallTimerAt;
    if (!shouldActivate || nightfallActive.value) return;
    nightfallActive.value = true;
    _darkness = ReitoriaDarknessOverlay(game: this, radius: 185)..priority = 1000;
    camera.viewport.add(_darkness!);
    showHudMessage('Anoiteceu. A lanterna e tudo que resta.');
  }

  void _spawnZombie({required Vector2 target, required bool nearServer}) {
    final p = player;
    if (p == null) return;
    final spawn = nearServer ? _spawnAroundServer() : _spawnNearGateWave();
    final zombie = ReitoriaZombieComponent(
      game: this,
      player: p,
      objective: target,
      position: spawn,
      route: route.value,
    )..priority = 6;
    _zombies.add(zombie);
    world.add(zombie);
  }

  Vector2 _spawnAroundServer() {
    final angle = _rng.nextDouble() * math.pi * 2;
    final radius = 340 + _rng.nextDouble() * 220;
    return _clampToMap(
      _serverPosition + Vector2(math.cos(angle), math.sin(angle)) * radius,
      ReitoriaZombieComponent.visualSize,
    );
  }

  Vector2 _spawnNearGateWave() {
    final x = (_gatePosition.x - 280 + _rng.nextDouble() * 420)
        .clamp(80, _mapSize.x - 80)
        .toDouble();
    final y = (_gatePosition.y - 230 + _rng.nextDouble() * 300)
        .clamp(80, _mapSize.y - 80)
        .toDouble();
    return Vector2(x, y);
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
    for (final zombie in List<ReitoriaZombieComponent>.of(_zombies)) {
      if (zombie.isAlive && rect.overlaps(zombie.hitRect)) {
        zombie.takeDamage(10);
      }
    }
  }

  void damagePlayer(double amount) {
    if (gameOver.value || levelCompleted.value) return;
    currentHealth.value = math.max(0, currentHealth.value - amount);
    if (currentHealth.value <= 0) {
      gameOver.value = true;
      missionText.value = 'Voce caiu antes do fim.';
    }
  }

  void damageServer(double amount) {
    if (route.value != ReitoriaRoute.cure || gameOver.value) return;
    serverIntegrity.value = math.max(0, serverIntegrity.value - amount);
    if (serverIntegrity.value <= 0) {
      gameOver.value = true;
      missionText.value = 'O servidor foi destruido.';
    }
  }

  void _openEnding() {
    if (_endingOpen) return;
    _endingOpen = true;
    for (final zombie in List<ReitoriaZombieComponent>.of(_zombies)) {
      zombie.removeFromParent();
    }
    _zombies.clear();
    pauseEngine();
    dialogOpen.value = true;
    overlays.add('FinalEnding');
  }

  Future<void> finishFinale() async {
    if (levelCompleted.value) return;
    await FirebaseService.instance.completeArea5(
      playerName,
      ending: route.value == ReitoriaRoute.cure ? 'cure' : 'rescue',
    );
    overlays.remove('FinalEnding');
    dialogOpen.value = false;
    levelCompleted.value = true;
  }

  void reviveAtCheckpoint() {
    for (final zombie in List<ReitoriaZombieComponent>.of(_zombies)) {
      zombie.removeFromParent();
    }
    _zombies.clear();
    currentHealth.value = maxHealth.value;
    serverIntegrity.value = 100;
    uploadProgress.value = 0;
    _uploadElapsed = 0;
    _countdownLeft = _survivalDuration;
    countdownSeconds.value = _survivalDuration.toInt();
    _spawnTimer = 0;
    _wave = 0;
    nightfallActive.value = false;
    _darkness?.removeFromParent();
    _darkness = null;
    gameOver.value = false;
    player?.position = _fallbackSpawn.clone();
    _objectiveStarted = false;
    _startObjective();
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

  Vector2? _readObjectPosition(Map<String, dynamic> map, List<String> names) {
    final obj = _findObjectByName(map, (name) {
      final lower = name.toLowerCase();
      return names.any(lower.contains);
    });
    if (obj == null) return null;
    return _clampToMap(
      Vector2(
        (obj['x'] as num? ?? 0).toDouble(),
        (obj['y'] as num? ?? 0).toDouble(),
      ),
      Vector2(64, 64),
    );
  }

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

class ReitoriaMarianaComponent extends SpriteComponent {
  ReitoriaMarianaComponent({required super.position})
      : super(size: Vector2(72, 104), anchor: Anchor.center);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    final game = findGame() as ReitoriaLevel;
    try {
      sprite = Sprite(await game.images.load('npcs/npc1beatriz.png'));
    } catch (e) {
      debugPrint('Mariana sprite failed: $e');
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
      canvas.drawCircle(
        Offset(size.x / 2, size.y * .34),
        18,
        Paint()..color = const Color(0xFFC49A6C),
      );
      canvas.drawRect(
        Rect.fromLTWH(size.x * .25, size.y * .48, size.x * .5, size.y * .38),
        Paint()..color = const Color(0xFF5B21B6),
      );
    }
  }
}

class ReitoriaServerComponent extends PositionComponent {
  ReitoriaServerComponent({required super.position})
      : super(size: Vector2(92, 78), anchor: Anchor.center);

  @override
  void render(Canvas canvas) {
    final rect = size.toRect();
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      Paint()..color = const Color(0xFF111827),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.deflate(5), const Radius.circular(3)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFF22D3EE),
    );
    for (var i = 0; i < 4; i++) {
      canvas.drawCircle(
        Offset(18 + i * 18, size.y * .52),
        4,
        Paint()..color = i.isEven ? const Color(0xFF22C55E) : const Color(0xFFFACC15),
      );
    }
  }
}

class ReitoriaGateComponent extends PositionComponent {
  ReitoriaGateComponent({required super.position})
      : super(size: Vector2(104, 74), anchor: Anchor.center);

  @override
  void render(Canvas canvas) {
    canvas.drawRect(size.toRect(), Paint()..color = const Color(0xAA0F172A));
    canvas.drawRect(
      size.toRect().deflate(5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = const Color(0xFFF5C842),
    );
  }
}

class ReitoriaZombieComponent extends SpriteComponent {
  ReitoriaZombieComponent({
    required this.game,
    required this.player,
    required this.objective,
    required this.route,
    required Vector2 position,
  }) : super(position: position, size: visualSize.clone(), anchor: Anchor.center);

  static final Vector2 visualSize = Vector2(62, 62);
  static const double _speed = 68;
  static const double _touchDamage = 7;
  static const double _serverDamage = 5;

  final ReitoriaLevel game;
  final PlayerComponent player;
  final Vector2 objective;
  final ReitoriaRoute route;
  int health = 22;
  double _hitCooldown = 0;
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
      sprite = Sprite(await game.images.load('zumbis/zumbi_normal.png'));
    } catch (e) {
      debugPrint('Reitoria zombie sprite failed: $e');
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

    final playerClose = (player.position - position).length <= 160;
    final target = playerClose ? player.position : objective;
    var dir = target - position;
    if (dir.length2 > 4) {
      dir = dir.normalized();
      final boost = game.nightfallActive.value ? 1.22 : 1.0;
      position += dir * _speed * boost * dt;
      position = Vector2(
        position.x.clamp(size.x / 2, game._mapSize.x - size.x / 2).toDouble(),
        position.y.clamp(size.y / 2, game._mapSize.y - size.y / 2).toDouble(),
      );
    }

    if (_hitCooldown > 0) return;
    if (hitRect.overlaps(player.feetRect.inflate(16))) {
      _hitCooldown = 1.0;
      game.damagePlayer(_touchDamage);
      return;
    }
    if (route == ReitoriaRoute.cure &&
        (position - objective).length <= 56) {
      _hitCooldown = 1.2;
      game.damageServer(_serverDamage);
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

class ReitoriaDarknessOverlay extends Component {
  ReitoriaDarknessOverlay({required this.game, this.radius = 185});

  final ReitoriaLevel game;
  final double radius;

  @override
  void render(Canvas canvas) {
    final viewportSize = game.camera.viewport.size.length2 == 0
        ? game.size
        : game.camera.viewport.size;
    final bounds = Offset.zero & viewportSize.toSize();
    final center = _playerScreen(viewportSize);

    canvas.saveLayer(bounds, Paint());
    canvas.drawRect(bounds, Paint()..color = const Color(0xE6000000));
    canvas.drawCircle(
      Offset(center.x, center.y),
      radius,
      Paint()
        ..blendMode = BlendMode.dstOut
        ..shader = const RadialGradient(
          colors: [Colors.white, Color(0xCCFFFFFF), Color(0x00FFFFFF)],
          stops: [0.0, 0.6, 1.0],
        ).createShader(
          Rect.fromCircle(center: Offset(center.x, center.y), radius: radius),
        ),
    );
    canvas.restore();
  }

  Vector2 _playerScreen(Vector2 viewportSize) {
    final p = game.player;
    if (p == null) return viewportSize / 2;
    final global = game.camera.localToGlobal(p.position);
    return game.camera.viewport.globalToLocal(global);
  }
}

class ReitoriaFallbackMap extends PositionComponent {
  ReitoriaFallbackMap({required Vector2 size}) : super(size: size);

  @override
  void render(Canvas canvas) {
    canvas.drawRect(size.toRect(), Paint()..color = const Color(0xFF1F2937));
    final grid = Paint()
      ..color = const Color(0x2234D399)
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.x; x += 64) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.y), grid);
    }
    for (var y = 0.0; y < size.y; y += 64) {
      canvas.drawLine(Offset(0, y), Offset(size.x, y), grid);
    }
  }
}
