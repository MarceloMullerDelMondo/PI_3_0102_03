import 'dart:async' as async;
import 'dart:convert';
import 'dart:math' as math;

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/experimental.dart' show Rectangle;
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/game_state.dart';
import '../services/firebase_service.dart';
import 'base_hud_component.dart';
import 'h15_game.dart' show PlayerComponent, SolidObstacle;

// ─────────────────────────────────────────────────────────────────────────────
// BibliotecaGame — Phase 3: Exploration & Collection
// ─────────────────────────────────────────────────────────────────────────────
class BibliotecaGame extends FlameGame with HasCollisionDetection {
  BibliotecaGame({required this.playerName});

  final String playerName;

  // ── Fixed map dimensions (confirmed from image layer in collision JSON) ──
  static final Vector2 _kMapSize = Vector2(2044, 1632);
  static final Vector2 _kPlayerSize = Vector2(80, 80);

  // ── Exact spawn coordinates ────────────────────────────────────────────
  static final Vector2 _kPlayerSpawn = Vector2(300, 980);
  static final Vector2 _kCardSpawn = Vector2(1100, 1350);
  static final Vector2 _kMapaSpawn = Vector2(1180, 380);
  static final Vector2 _kExitPos = Vector2(520, 330);
  static final Vector2 _kExitSize = Vector2(100, 100);

  PlayerComponent? player;
  JoystickComponent? _joystick;
  final Vector2 _mapSize = _kMapSize.clone();
  final List<SolidObstacle> _walls = [];

  AccessCardComponent? _card;
  MapaComponent? _mapa;
  PortaTrigger? _doorTrigger;

  // ── HUD ────────────────────────────────────────────────────────────────
  final BaseHudComponent hud = BaseHudComponent(
    initialHealth: 100,
    maxHealth: 100,
    initialMission: 'Missão: Encontre o Cartão de Acesso e o Mapa.',
    countTimer: true,
  );

  // ── Inventory ──────────────────────────────────────────────────────────
  bool hasCartao = false;
  bool hasMapa = false;

  final ValueNotifier<bool> hasCartaoNotifier = ValueNotifier(false);
  final ValueNotifier<bool> hasMapaNotifier = ValueNotifier(false);

  // Legacy alias so biblioteca_level_screen.dart keeps compiling unchanged.
  ValueNotifier<bool> get hasAccessCardNotifier => hasCartaoNotifier;

  // ── Phase flags ────────────────────────────────────────────────────────
  bool _transitioning = false;
  bool _showingCardSwipe = false;
  double _exitDeniedCooldown = 0;
  double _exitOverlayCooldown = 0;

  // True while the player stands in range of the door with both items —
  // drives the "USAR CARTÃO" button visibility in the Flutter HUD layer.
  final ValueNotifier<bool> showCardReaderPrompt = ValueNotifier(false);

  final ValueNotifier<bool> levelCompleted = ValueNotifier(false);

  @override
  Color backgroundColor() => Colors.black;

  // ── onLoad ─────────────────────────────────────────────────────────────
  @override
  Future<void> onLoad() async {
    debugMode = false;
    await super.onLoad();
    camera.viewfinder.anchor = Anchor.center;

    camera.viewport.add(hud);

    await _loadBackground();
    await _loadTiledCollisions();

    // ── Collectibles at exact coordinates ─────────────────────────────
    _card = AccessCardComponent(position: _kCardSpawn.clone())..priority = 4;
    await world.add(_card!);

    _mapa = MapaComponent(position: _kMapaSpawn.clone())..priority = 4;
    await world.add(_mapa!);

    final door = await _findDoorFromTiled();
    _doorTrigger = PortaTrigger(position: door.pos, size: door.size, game: this)
      ..priority = 100;
    await world.add(_doorTrigger!);

    // ── Player ────────────────────────────────────────────────────────
    // hitboxPos/hitboxSize are set BEFORE world.add so onLoad() picks them up.
    // For 80×80: 24×24 box centred at the sprite's feet (bottom-centre quarter).
    //   x = (80 - 24) / 2 = 28   (horizontally centred)
    //   y =  80 - 24     = 56    (bottom 24 px of the sprite)
    final playerImg = await images.load('player/player_sprite.jpg');
    final p = PlayerComponent.fromSpriteSheet(playerImg)
      ..position = _kPlayerSpawn.clone()
      ..size = _kPlayerSize
      ..hitboxPos = Vector2(28, 56)
      ..hitboxSize = Vector2(24, 24)
      ..priority = 5;
    player = p;
    await world.add(p);

    // ── Camera ────────────────────────────────────────────────────────
    camera.viewfinder.position = _kPlayerSpawn.clone();
    final minZoom = math.max(size.x / _mapSize.x, size.y / _mapSize.y);
    camera.viewfinder.zoom = math.max(minZoom, 1.5);
    camera.setBounds(Rectangle.fromLTWH(0, 0, _mapSize.x, _mapSize.y));
    camera.follow(p, snap: true);

    _setupJoystick();
    _restoreWeapon();

    async.Timer(const Duration(milliseconds: 600), () {
      if (isMounted) {
        hud.showMessage('Encontre o Cartão de Acesso e o Mapa na Biblioteca.');
      }
    });
  }

  // ── update ─────────────────────────────────────────────────────────────
  @override
  void update(double dt) {
    super.update(dt);
    if (_transitioning) return;

    final p = player;
    final j = _joystick;
    if (p != null && j != null && !_showingCardSwipe) {
      p.move(j.relativeDelta, dt, _mapSize, _walls);
    }

    if (_exitDeniedCooldown > 0) _exitDeniedCooldown -= dt;
    if (_exitOverlayCooldown > 0) _exitOverlayCooldown -= dt;

    _checkCardCollection();
    _checkMapaCollection();
    // Door interaction handled by PortaTrigger.onCollisionStart/End
  }

  // ── Collection ─────────────────────────────────────────────────────────

  void _checkCardCollection() {
    final card = _card;
    final p = player;
    if (card == null || card.collected || p == null) return;
    if ((p.position - card.position).length <= 56) _collectCard();
  }

  void _collectCard() {
    _card!.collect();
    hasCartao = true;
    hasCartaoNotifier.value = true;
    _updateMission();
    hud.showMessage('Cartão de Acesso Coletado!');
    FirebaseService.instance
        .addItem(playerName, 'cartao_acesso_funcionario')
        .catchError((_) {});
  }

  void _checkMapaCollection() {
    final m = _mapa;
    final p = player;
    if (m == null || m.collected || p == null) return;
    if ((p.position - m.position).length <= 56) _collectMapa();
  }

  void _collectMapa() {
    _mapa!.collect();
    hasMapa = true;
    hasMapaNotifier.value = true;
    GameState.instance.setHasMapa(); // persists the map button into CAA & Reitoria
    _updateMission();
    hud.showMessage('Mapa da Biblioteca Coletado!');
    FirebaseService.instance
        .addItem(playerName, 'mapa_biblioteca')
        .catchError((_) {});
  }

  void _updateMission() {
    if (hasCartao && hasMapa) {
      hud.missionText.value = 'Itens coletados! Fuja pela porta principal.';
    } else if (hasCartao) {
      hud.missionText.value = 'Missão: Encontre o Mapa.';
    } else if (hasMapa) {
      hud.missionText.value = 'Missão: Encontre o Cartão de Acesso.';
    }
  }

  // ── Exit door / card reader ────────────────────────────────────────────

  // Called by PortaTrigger.onCollisionStart when PlayerComponent enters.
  void onPlayerEntersDoor() {
    debugPrint('Door trigger: player entered!');
    if (_exitOverlayCooldown > 0) return;
    if (!hasCartao || !hasMapa) {
      if (_exitDeniedCooldown <= 0) {
        final missing = <String>[];
        if (!hasCartao) missing.add('Cartão');
        if (!hasMapa) missing.add('Mapa');
        hud.showMessage('Trancado. Falta: ${missing.join(' e ')}.');
        _exitDeniedCooldown = 3.0;
      }
      return;
    }
    showCardReaderPrompt.value = true;
  }

  // Called by PortaTrigger.onCollisionEnd when PlayerComponent leaves.
  void onPlayerExitsDoor() {
    showCardReaderPrompt.value = false;
  }

  // Called by the "USAR CARTÃO" HUD button.
  void openCardSwipe() {
    if (_showingCardSwipe) return;
    _showingCardSwipe = true;
    hud.paused = true;
    overlays.add('CardSwipe');
  }

  // Called by CardSwipeOverlay after a successful swipe.
  void onCardSwipeSuccess() {
    if (_transitioning) return;
    overlays.remove('CardSwipe');
    _showingCardSwipe = false;
    showCardReaderPrompt.value = false;
    _transitioning = true;
    hud.paused = false;
    FirebaseService.instance.unlockNextPhase(playerName).then((_) {
      levelCompleted.value = true;
    }).catchError((_) {
      levelCompleted.value = true;
    });
  }

  // Called by the CANCELAR button inside CardSwipeOverlay.
  void dismissCardSwipe() {
    overlays.remove('CardSwipe');
    _showingCardSwipe = false;
    hud.paused = false;
    _exitOverlayCooldown = 2.0;
  }

  // ── Door position: Tiled lookup with coordinate fallback ──────────────
  //
  // Searches for an object named 'Porta' (or 'door'/'saida') first in the
  // 'Interacoes' layer, then in 'Colisoes'.  If nothing is found the
  // static _kExitPos / _kExitSize constants are used so the level still
  // loads even without the Tiled object.
  Future<({Vector2 pos, Vector2 size})> _findDoorFromTiled() async {
    try {
      final raw =
          await rootBundle.loadString('assets/tiles/biblioteca_collisions.json');
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final layers =
          (map['layers'] as List<dynamic>).whereType<Map<String, dynamic>>();

      for (final layerName in ['Interacoes', 'Colisoes']) {
        for (final layer in layers) {
          if (layer['name'] != layerName) continue;
          final objects = (layer['objects'] as List<dynamic>? ?? [])
              .whereType<Map<String, dynamic>>();
          for (final obj in objects) {
            final name = (obj['name'] as String? ?? '').toLowerCase();
            if (!name.contains('porta') &&
                !name.contains('door') &&
                !name.contains('saida')) {
              continue;
            }
            final x = (obj['x'] as num).toDouble();
            final y = (obj['y'] as num).toDouble();
            final w = math.max((obj['width'] as num? ?? 0).toDouble(), 60.0);
            final h = math.max((obj['height'] as num? ?? 0).toDouble(), 60.0);
            debugPrint(
                'BibliotecaGame: Porta found in "$layerName" at ($x, $y) ${w}x$h');
            return (pos: Vector2(x, y), size: Vector2(w, h));
          }
        }
      }
    } catch (e) {
      debugPrint('BibliotecaGame: door lookup failed — using fallback: $e');
    }
    debugPrint('BibliotecaGame: no Porta object found — fallback $_kExitPos');
    return (pos: _kExitPos.clone(), size: _kExitSize.clone());
  }

  // ── Background ─────────────────────────────────────────────────────────

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

  // ── Tiled collision parser ─────────────────────────────────────────────
  //
  // Processes ALL objects in the "Colisoes" ObjectGroup:
  //   • Rectangles  → spawned directly.
  //   • Polygons    → converted to their axis-aligned bounding box (AABB).
  //     A size guard (> 900 px on either axis) skips any accidental
  //     map-spanning polygon that would create phantom walls.
  // Falls back to border walls if the file is missing.
  Future<void> _loadTiledCollisions() async {
    try {
      final raw =
          await rootBundle.loadString('assets/tiles/biblioteca_collisions.json');
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final layers =
          (map['layers'] as List<dynamic>).whereType<Map<String, dynamic>>();

      for (final layer in layers) {
        if (layer['name'] != 'Colisoes') continue;
        final objects = (layer['objects'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>();

        for (final obj in objects) {
          final objX = (obj['x'] as num).toDouble();
          final objY = (obj['y'] as num).toDouble();

          final polygon = obj['polygon'] as List<dynamic>?;
          if (polygon != null && polygon.isNotEmpty) {
            _addPolygonWall(objX, objY, polygon);
          } else {
            final w = (obj['width'] as num? ?? 0).toDouble();
            final h = (obj['height'] as num? ?? 0).toDouble();
            if (w > 0 && h > 0) _addWall(Vector2(objX, objY), Vector2(w, h));
          }
        }
        break;
      }
    } catch (e) {
      debugPrint('BibliotecaGame: collisions failed — border walls: $e');
      _addBorderWalls();
    }
  }

  // Converte polígono para AABB. Ignora se a caixa for maior que 900 px
  // em qualquer eixo — sinal de que o polígono cobre área demais.
  void _addPolygonWall(double ox, double oy, List<dynamic> polygon) {
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;

    for (final v in polygon.whereType<Map<String, dynamic>>()) {
      final vx = (v['x'] as num).toDouble();
      final vy = (v['y'] as num).toDouble();
      if (vx < minX) minX = vx;
      if (vy < minY) minY = vy;
      if (vx > maxX) maxX = vx;
      if (vy > maxY) maxY = vy;
    }

    final w = maxX - minX;
    final h = maxY - minY;
    if (w <= 0 || h <= 0) return;
    if (w > 900 || h > 900) return; // guard contra polígonos gigantes
    _addWall(Vector2(ox + minX, oy + minY), Vector2(w, h));
  }

  void _addWall(Vector2 position, Vector2 size) {
    final wall = _BibliotecaWall(position: position, size: size)
      ..priority = 1;
    _walls.add(wall);
    world.add(wall);
  }

  void _addBorderWalls() {
    const t = 8.0;
    for (final s in [
      (Vector2.zero(), Vector2(_mapSize.x, t)),
      (Vector2(0, _mapSize.y - t), Vector2(_mapSize.x, t)),
      (Vector2.zero(), Vector2(t, _mapSize.y)),
      (Vector2(_mapSize.x - t, 0), Vector2(t, _mapSize.y)),
    ]) {
      _addWall(s.$1, s.$2);
    }
  }

  // ── Weapon ─────────────────────────────────────────────────────────────

  void _restoreWeapon() {
    FirebaseService.instance.loadWeapon().then((weapon) async {
      final selected = (weapon == null || weapon.isEmpty) ? 'Espada' : weapon;
      GameState.instance.setWeapon(selected);
      try {
        player?.useWeaponSpriteSheet(
          await images.load(GameState.instance.weaponAssetPath),
        );
      } catch (_) {}
    }).catchError((_) async {
      try {
        player?.useWeaponSpriteSheet(
          await images.load(GameState.instance.weaponAssetPath),
        );
      } catch (_) {}
    });
  }

  // ── Joystick ───────────────────────────────────────────────────────────

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
}

// ─────────────────────────────────────────────────────────────────────────────
// _BibliotecaWall — invisible passive collision wall
// Uses CollisionType.passive so active colliders (future enemies) trigger
// onCollision callbacks, while the player relies on the SolidObstacle rect check.
// ─────────────────────────────────────────────────────────────────────────────
class _BibliotecaWall extends SolidObstacle {
  _BibliotecaWall({required Vector2 position, required Vector2 size})
      : super(position: position, size: size);

  @override
  bool overlapsRect(Rect rect) =>
      Rect.fromLTWH(position.x, position.y, size.x, size.y).overlaps(rect);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    debugMode = false;
    add(RectangleHitbox(collisionType: CollisionType.passive)..debugMode = false);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AccessCardComponent — renders cartaoacesso.png at a flat card aspect ratio.
// No custom render override: SpriteComponent draws the sprite automatically
// with a transparent background and zero added borders.
// ─────────────────────────────────────────────────────────────────────────────
class AccessCardComponent extends SpriteComponent {
  AccessCardComponent({required Vector2 position})
      : super(position: position, size: Vector2(80, 50), anchor: Anchor.center, priority: 10);

  bool collected = false;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    debugMode = false;
    final game = findGame()!;
    try {
      sprite = Sprite(await game.images.load('objects/cartaoacesso.png'));
    } catch (_) {}
  }

  void collect() {
    collected = true;
    removeFromParent();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MapaComponent — renders mapa.png at a square aspect ratio.
// No custom render override: SpriteComponent draws the sprite automatically
// with a transparent background and zero added borders.
// ─────────────────────────────────────────────────────────────────────────────
class MapaComponent extends SpriteComponent {
  MapaComponent({required Vector2 position})
      : super(position: position, size: Vector2(64, 64), anchor: Anchor.center, priority: 10);

  bool collected = false;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    debugMode = false;
    final game = findGame()!;
    try {
      sprite = Sprite(await game.images.load('objects/mapa.png'));
    } catch (_) {}
  }

  void collect() {
    collected = true;
    removeFromParent();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PortaTrigger — collision-based door proximity zone.
//
// Uses Flame's onCollisionStart / onCollisionEnd instead of a per-frame
// distance check, so it fires exactly once per enter / leave event.
//
// debugMode is ON temporarily — a yellow box appears over the trigger area
// so you can confirm alignment with the map graphic.
// Flip both debugMode lines to `false` once verified.
// ─────────────────────────────────────────────────────────────────────────────
class PortaTrigger extends PositionComponent with CollisionCallbacks {
  PortaTrigger({
    required Vector2 position,
    required Vector2 size,
    required this.game,
  }) : super(position: position, size: size);

  final BibliotecaGame game;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    debugMode = false;
    add(
      RectangleHitbox(collisionType: CollisionType.passive)
        ..debugMode = false,
    );
  }

  @override
  void onCollisionStart(
      Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollisionStart(intersectionPoints, other);
    if (_isPlayer(other)) game.onPlayerEntersDoor();
  }

  @override
  void onCollisionEnd(PositionComponent other) {
    super.onCollisionEnd(other);
    if (_isPlayer(other)) game.onPlayerExitsDoor();
  }

  // `other` is the ShapeHitbox — parent is the actual component.
  bool _isPlayer(PositionComponent c) =>
      c is PlayerComponent || c.parent is PlayerComponent;
}

// ─────────────────────────────────────────────────────────────────────────────
// BibliotecaFallbackMap — rendered only when background image fails to load
// ─────────────────────────────────────────────────────────────────────────────
class BibliotecaFallbackMap extends PositionComponent {
  BibliotecaFallbackMap({required Vector2 mapSize})
      : super(size: mapSize, position: Vector2.zero());

  @override
  void render(Canvas canvas) {
    canvas.drawRect(size.toRect(), Paint()..color = const Color(0xFF2F2A24));
    final grid = Paint()
      ..color = const Color(0x224A5568)
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.x; x += 64) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.y), grid);
    }
    for (var y = 0.0; y < size.y; y += 64) {
      canvas.drawLine(Offset(0, y), Offset(size.x, y), grid);
    }
  }
}
