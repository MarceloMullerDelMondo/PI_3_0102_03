import 'dart:ui' as ui;

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';

class H15Game extends FlameGame with HasCollisionDetection {
  static const bool showDebugWalls = false;

  PlayerComponent? player;
  JoystickComponent? joystick;
  DarknessComponent? _darkness;
  SpriteComponent? _background;
  final List<SolidObstacle> _walls = [];
  final List<InteractableZone> _interactables = [];
  final List<ZombieComponent> _zombies = [];
  final ValueNotifier<bool> canInteract = ValueNotifier(false);
  final ValueNotifier<bool> questDialogOpen = ValueNotifier(false);
  final ValueNotifier<bool> attackEnabled = ValueNotifier(false);
  String? activeZoneId;
  int questState = 0;

  @override
  Color backgroundColor() => Colors.black;

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    final backgroundSprite = await loadSprite('h15_lab.jpg');
    _background = SpriteComponent(
      sprite: backgroundSprite,
      size: size,
      position: Vector2.zero(),
      priority: -10,
    );
    add(_background!);

    _darkness = DarknessComponent(size: size)
      ..position = Vector2.zero()
      ..priority = -5;
    add(_darkness!);

    _setupWalls(size);
    _setupInteractables(size);

    final playerSprite = await images.load('player_sprite.jpg');
    final playerComponent = PlayerComponent.fromSpriteSheet(playerSprite)
      ..position = Vector2(size.x * 0.30, size.y * 0.60)
      ..priority = 5;
    player = playerComponent;
    add(playerComponent);

    final joystickComponent = JoystickComponent(
      knob: CircleComponent(
        radius: 22,
        paint: Paint()..color = const Color(0xCCF5C842),
      ),
      background: CircleComponent(
        radius: 58,
        paint: Paint()..color = const Color(0x552E1E06),
      ),
      margin: const EdgeInsets.only(left: 28, bottom: 28),
      priority: 20,
    );
    joystick = joystickComponent;
    add(joystickComponent);
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    _background?.size = size;
    _darkness?.size = size;
    if (_walls.isNotEmpty) {
      for (final wall in _walls) {
        wall.removeFromParent();
      }
      _walls.clear();
      _setupWalls(size);
    }
    if (_interactables.isNotEmpty) {
      for (final zone in _interactables) {
        zone.removeFromParent();
      }
      _interactables.clear();
      _setupInteractables(size);
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    final activePlayer = player;
    final activeJoystick = joystick;
    if (activePlayer == null || activeJoystick == null) return;

    activePlayer.move(activeJoystick.relativeDelta, dt, size, _walls);
  }

  void attack() {
    if (!attackEnabled.value) return;
    debugPrint('Ataque realizado!');
    player?.flashAttack();
  }

  void interact() {
    if (!canInteract.value || questDialogOpen.value) return;

    if (activeZoneId == 'pc_alvaro' &&
        (questState == 0 || questState == 2)) {
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

  String get questDialogText {
    if (questState == 2) {
      return 'Cuidado! A luz atraiu eles! Pegue esta espada e lute!';
    }
    return 'Sobrevivente, graças a Deus! Aqui é o Prof. Álvaro. Vá ligar os servidores!';
  }

  void closeQuestDialog() {
    overlays.remove('QuestDialog');
    if (questState == 0) {
      questState = 1;
    } else if (questState == 2) {
      questState = 3;
      attackEnabled.value = true;
      _spawnZombies();
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
    final shouldInteract = switch (activeZoneId) {
      'pc_alvaro' => questState == 0 || questState == 2,
      'server' => questState == 1,
      _ => false,
    };

    if (canInteract.value == shouldInteract) return;
    canInteract.value = shouldInteract;
  }

  void _setupInteractables(Vector2 mapSize) {
    final pcZone = InteractableZone(
      zoneId: 'pc_alvaro',
      position: Vector2(mapSize.x * 0.12, mapSize.y * 0.53),
      size: Vector2(mapSize.x * 0.22, mapSize.y * 0.10),
    )..priority = 2;
    final serverZone = InteractableZone(
      zoneId: 'server',
      position: Vector2(mapSize.x * 0.72, mapSize.y * 0.72),
      size: Vector2(mapSize.x * 0.22, mapSize.y * 0.15),
    )..priority = 2;

    _interactables.addAll([pcZone, serverZone]);
    addAll(_interactables);
  }

  void _spawnZombies() {
    if (_zombies.isNotEmpty) return;
    final target = player;
    if (target == null) return;

    for (var i = 0; i < 3; i++) {
      final zombie = ZombieComponent(target: target)
        ..position = Vector2(
          size.x * 0.85 + i * 18,
          size.y * 0.25 + i * 12,
        )
        ..priority = 4;
      _zombies.add(zombie);
      add(zombie);
    }
  }

  void _setupWalls(Vector2 mapSize) {
    Vector2 p(double x, double y) => Vector2(mapSize.x * x, mapSize.y * y);
    List<Vector2> shrink(List<Vector2> vertices, [double factor = 0.65]) {
      final center = vertices.fold<Vector2>(
            Vector2.zero(),
            (sum, vertex) => sum + vertex,
          ) /
          vertices.length.toDouble();
      return [
        for (final vertex in vertices) center + (vertex - center) * factor,
      ];
    }

    final wallSpecs = <List<Vector2>>[
      // Paredão do Fundo e Lousa H-15.
      [
        p(0.00, 0.00),
        p(1.00, 0.00),
        p(1.00, 0.38),
        p(0.00, 0.38),
      ],

      // Parede Esquerda e PC com '!'.
      [
        p(0.00, 0.38),
        p(0.36, 0.38),
        p(0.32, 0.56),
        p(0.00, 0.56),
      ],

      // Ilha de PCs no tapete verde: mesa superior.
      shrink([
        p(0.20, 0.40),
        p(0.45, 0.35),
        p(0.52, 0.42),
        p(0.27, 0.49),
      ]),

      // Ilha de PCs no tapete verde: mesa inferior.
      shrink([
        p(0.42, 0.47),
        p(0.67, 0.41),
        p(0.74, 0.49),
        p(0.49, 0.56),
      ]),

      // Mesas da Direita (Fileira Longa).
      shrink([
        p(0.64, 0.55),
        p(0.98, 0.48),
        p(1.00, 0.65),
        p(0.70, 0.75),
      ]),

      // Ilha de mesas na parte inferior central.
      shrink([
        p(0.32, 0.69),
        p(0.62, 0.61),
        p(0.70, 0.70),
        p(0.40, 0.80),
      ]),

      // Mesas do Canto Inferior Esquerdo.
      shrink([
        p(0.19, 0.81),
        p(0.48, 0.74),
        p(0.53, 0.86),
        p(0.23, 0.94),
      ]),

      // Parede/mesas da borda inferior esquerda.
      shrink([
        p(0.00, 0.85),
        p(0.60, 0.85),
        p(0.60, 1.00),
        p(0.00, 1.00),
      ], 0.70),

      // Máquinas de Vending (Esquerda).
      shrink([
        p(0.00, 0.64),
        p(0.20, 0.64),
        p(0.20, 0.76),
        p(0.00, 0.76),
      ]),

      // Servidores (Canto Inferior Direito).
      shrink([
        p(0.73, 0.75),
        p(0.93, 0.70),
        p(0.96, 0.82),
        p(0.76, 0.88),
      ]),

      // Bordas Laterais de Segurança da Tela.
      [
        Vector2(0, 0),
        Vector2(5, 0),
        Vector2(5, mapSize.y),
        Vector2(0, mapSize.y),
      ],
      [
        Vector2(mapSize.x - 5, 0),
        Vector2(mapSize.x, 0),
        Vector2(mapSize.x, mapSize.y),
        Vector2(mapSize.x - 5, mapSize.y),
      ],
      [
        Vector2(0, mapSize.y - 5),
        Vector2(mapSize.x, mapSize.y - 5),
        Vector2(mapSize.x, mapSize.y),
        Vector2(0, mapSize.y),
      ],
    ];

    for (final vertices in wallSpecs) {
      final wall = IsometricWall(
        vertices: vertices,
        showDebug: showDebugWalls,
      )..priority = 1;
      _walls.add(wall);
      add(wall);
    }
  }
}

enum PlayerAnim { idle, walkDown, walkLeft, walkRight, walkUp }

class PlayerComponent extends SpriteAnimationGroupComponent<PlayerAnim>
    with CollisionCallbacks {
  static const double _speed = 180;
  static final Vector2 _feetHitboxPosition = Vector2(16, 35);
  static final Vector2 _feetHitboxSize = Vector2(16, 10);

  PlayerComponent._({
    required Map<PlayerAnim, SpriteAnimation> animations,
  })
      : super(
          animations: animations,
          current: PlayerAnim.idle,
          size: Vector2(48, 48),
          anchor: Anchor.center,
        );

  factory PlayerComponent.fromSpriteSheet(ui.Image image) {
    final frameSize = Vector2(image.width / 4, image.height / 3);

    SpriteAnimation rowAnimation(int row, {int amount = 4}) {
      return SpriteAnimation.fromFrameData(
        image,
        SpriteAnimationData.sequenced(
          amount: amount,
          stepTime: 0.14,
          textureSize: frameSize,
          texturePosition: Vector2(0, frameSize.y * row),
        ),
      );
    }

    return PlayerComponent._(
      animations: {
        PlayerAnim.idle: rowAnimation(0, amount: 1),
        PlayerAnim.walkDown: rowAnimation(0),
        PlayerAnim.walkRight: rowAnimation(1),
        PlayerAnim.walkLeft: rowAnimation(2),
        PlayerAnim.walkUp: rowAnimation(0),
      },
    );
  }

  double _flashTimer = 0;
  Vector2? _lastSafePosition;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    add(
      RectangleHitbox(
        position: _feetHitboxPosition,
        size: _feetHitboxSize,
      ),
    );
  }

  void move(
    Vector2 direction,
    double dt,
    Vector2 bounds,
    List<SolidObstacle> walls,
  ) {
    if (direction.length2 <= 0) {
      current = PlayerAnim.idle;
      return;
    }

    final delta = direction.normalized() * _speed * dt;
    _updateAnimation(direction);
    _tryMove(Vector2(delta.x, 0), bounds, walls);
    _tryMove(Vector2(0, delta.y), bounds, walls);
  }

  void _updateAnimation(Vector2 direction) {
    if (direction.x.abs() > direction.y.abs()) {
      current = direction.x > 0 ? PlayerAnim.walkRight : PlayerAnim.walkLeft;
    } else {
      current = direction.y > 0 ? PlayerAnim.walkDown : PlayerAnim.walkUp;
    }
  }

  void _tryMove(Vector2 delta, Vector2 bounds, List<SolidObstacle> walls) {
    final previous = position.clone();
    _lastSafePosition = previous;
    position += delta;
    _clampToBounds(bounds);

    if (_touchesAnyWall(walls)) {
      position = previous;
    }
  }

  void _clampToBounds(Vector2 bounds) {
    final halfW = size.x / 2;
    final halfH = size.y / 2;
    position = Vector2(
      position.x.clamp(halfW, bounds.x - halfW).toDouble(),
      position.y.clamp(halfH, bounds.y - halfH).toDouble(),
    );
  }

  bool _touchesAnyWall(List<SolidObstacle> walls) {
    final feet = feetRect;
    for (final wall in walls) {
      if (wall.overlapsRect(feet)) return true;
    }
    return false;
  }

  Rect get feetRect {
    final topLeft = Offset(
      position.x - size.x / 2 + _feetHitboxPosition.x,
      position.y - size.y / 2 + _feetHitboxPosition.y,
    );
    return Rect.fromLTWH(
      topLeft.dx,
      topLeft.dy,
      _feetHitboxSize.x,
      _feetHitboxSize.y,
    );
  }

  @override
  void onCollision(Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollision(intersectionPoints, other);
    if (_isSolidObstacle(other)) {
      final safePosition = _lastSafePosition;
      if (safePosition != null) {
        position = safePosition;
      }
    }
  }

  bool _isSolidObstacle(PositionComponent other) {
    return other is SolidObstacle || other.parent is SolidObstacle;
  }

  @override
  void onCollisionStart(
    Set<Vector2> intersectionPoints,
    PositionComponent other,
  ) {
    super.onCollisionStart(intersectionPoints, other);
    final zone = _interactableZoneFrom(other);
    if (zone != null) {
      final game = findGame();
      if (game is H15Game) {
        game.enterInteractableZone(zone.zoneId);
      }
    }
  }

  @override
  void onCollisionEnd(PositionComponent other) {
    super.onCollisionEnd(other);
    final zone = _interactableZoneFrom(other);
    if (zone != null) {
      final game = findGame();
      if (game is H15Game) {
        game.exitInteractableZone(zone.zoneId);
      }
    }
  }

  InteractableZone? _interactableZoneFrom(PositionComponent other) {
    if (other is InteractableZone) return other;
    final parent = other.parent;
    if (parent is InteractableZone) return parent;
    return null;
  }

  void flashAttack() {
    _flashTimer = 0.18;
    setOpacity(0.55);
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_flashTimer <= 0) return;

    _flashTimer -= dt;
    if (_flashTimer <= 0) {
      setOpacity(1);
    }
  }

  @override
  void render(Canvas canvas) {
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.x / 2, size.y + 4),
        width: size.x * 0.85,
        height: 8,
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.35),
    );
    super.render(canvas);
  }
}

class ZombieComponent extends RectangleComponent with CollisionCallbacks {
  final PlayerComponent target;
  static const double _speed = 55;

  ZombieComponent({required this.target})
      : super(
          size: Vector2(30, 38),
          anchor: Anchor.center,
          paint: Paint()..color = const Color(0xFF14532D),
        );

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    add(RectangleHitbox());
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!target.isMounted) return;

    final direction = target.position - position;
    if (direction.length2 < 16) return;
    position += direction.normalized() * _speed * dt;
  }

  @override
  void render(Canvas canvas) {
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.x / 2, size.y + 3),
        width: size.x * 0.85,
        height: 7,
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.35),
    );
    super.render(canvas);
  }
}

abstract class SolidObstacle extends PositionComponent {
  SolidObstacle({
    super.position,
    super.size,
  });

  bool overlapsRect(Rect rect);
}

class InvisibleWall extends SolidObstacle {
  final bool showDebug;

  InvisibleWall({
    required Vector2 position,
    required Vector2 size,
    this.showDebug = true,
  }) : super(
          position: position,
          size: size,
        );

  Rect get wallRect => Rect.fromLTWH(position.x, position.y, size.x, size.y);

  @override
  bool overlapsRect(Rect rect) => wallRect.overlaps(rect);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    debugMode = showDebug;
    add(RectangleHitbox());
  }

  @override
  void render(Canvas canvas) {
    if (showDebug) {
      canvas.drawRect(
        size.toRect(),
        Paint()..color = Colors.red.withValues(alpha: 0.24),
      );
    }
    super.render(canvas);
  }
}

class IsometricWall extends SolidObstacle {
  final List<Vector2> vertices;
  final bool showDebug;

  IsometricWall({
    required this.vertices,
    this.showDebug = true,
  }) : super(position: Vector2.zero());

  late final Rect boundsRect = _calculateBounds(vertices);

  @override
  bool overlapsRect(Rect rect) {
    if (!boundsRect.overlaps(rect)) return false;

    final rectCorners = [
      Vector2(rect.left, rect.top),
      Vector2(rect.right, rect.top),
      Vector2(rect.right, rect.bottom),
      Vector2(rect.left, rect.bottom),
    ];

    for (final corner in rectCorners) {
      if (_containsPoint(corner)) return true;
    }

    for (final vertex in vertices) {
      if (rect.contains(Offset(vertex.x, vertex.y))) return true;
    }

    for (var i = 0; i < vertices.length; i++) {
      final a = vertices[i];
      final b = vertices[(i + 1) % vertices.length];
      for (var j = 0; j < rectCorners.length; j++) {
        final c = rectCorners[j];
        final d = rectCorners[(j + 1) % rectCorners.length];
        if (_segmentsIntersect(a, b, c, d)) return true;
      }
    }

    return false;
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    debugMode = showDebug;
    add(PolygonHitbox(vertices));
  }

  @override
  void render(Canvas canvas) {
    if (showDebug) {
      final path = Path()..moveTo(vertices.first.x, vertices.first.y);
      for (final vertex in vertices.skip(1)) {
        path.lineTo(vertex.x, vertex.y);
      }
      path.close();

      canvas.drawPath(
        path,
        Paint()..color = Colors.red.withValues(alpha: 0.24),
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.red.withValues(alpha: 0.85)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
    super.render(canvas);
  }

  static Rect _calculateBounds(List<Vector2> vertices) {
    var minX = vertices.first.x;
    var maxX = vertices.first.x;
    var minY = vertices.first.y;
    var maxY = vertices.first.y;

    for (final vertex in vertices.skip(1)) {
      minX = vertex.x < minX ? vertex.x : minX;
      maxX = vertex.x > maxX ? vertex.x : maxX;
      minY = vertex.y < minY ? vertex.y : minY;
      maxY = vertex.y > maxY ? vertex.y : maxY;
    }

    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  bool _containsPoint(Vector2 point) {
    var inside = false;
    for (var i = 0, j = vertices.length - 1; i < vertices.length; j = i++) {
      final vi = vertices[i];
      final vj = vertices[j];
      final intersects = ((vi.y > point.y) != (vj.y > point.y)) &&
          (point.x <
              (vj.x - vi.x) * (point.y - vi.y) / (vj.y - vi.y) + vi.x);
      if (intersects) inside = !inside;
    }
    return inside;
  }

  bool _segmentsIntersect(Vector2 a, Vector2 b, Vector2 c, Vector2 d) {
    final o1 = _orientation(a, b, c);
    final o2 = _orientation(a, b, d);
    final o3 = _orientation(c, d, a);
    final o4 = _orientation(c, d, b);

    return o1 != o2 && o3 != o4;
  }

  int _orientation(Vector2 a, Vector2 b, Vector2 c) {
    final value = (b.y - a.y) * (c.x - b.x) - (b.x - a.x) * (c.y - b.y);
    if (value.abs() < 0.0001) return 0;
    return value > 0 ? 1 : 2;
  }
}

class InteractableZone extends PositionComponent with CollisionCallbacks {
  final String zoneId;

  InteractableZone({
    required this.zoneId,
    required Vector2 position,
    required Vector2 size,
  }) : super(
          position: position,
          size: size,
        );

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    add(
      RectangleHitbox(
        isSolid: false,
        collisionType: CollisionType.passive,
      ),
    );
  }
}

class DarknessComponent extends RectangleComponent {
  DarknessComponent({required Vector2 size})
      : super(
          size: size,
          paint: Paint()..color = Colors.black.withValues(alpha: 0.70),
        );
}
