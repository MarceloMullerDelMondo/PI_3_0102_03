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

abstract class BibliotecaZoneIds {
  static const terminalPrefix = 'terminal_';
  static const documentPrefix = 'documento_';
  static const quadroAvisos = 'quadro_avisos';
  static const portaSaida = 'porta_saida';
}

abstract class BibliotecaItemIds {
  static const cartaoAcesso = 'cartao_acesso_funcionario';
}

class BibliotecaLoreEntry {
  const BibliotecaLoreEntry({
    required this.title,
    required this.body,
  });

  final String title;
  final String body;
}

const List<BibliotecaLoreEntry> kBibliotecaLoreEntries = [
  BibliotecaLoreEntry(
    title: 'RELATORIO DE INCIDENTE X-24',
    body:
        'A primeira falha registrada veio do setor de arquivos digitais. O terminal indica que o acesso aos registros biologicos foi forçado minutos antes do alarme geral.',
  ),
  BibliotecaLoreEntry(
    title: 'MEMORANDO INTERNO',
    body:
        'O campus entrou em confinamento parcial as 07:00. Funcionarios de nivel 3 receberam cartoes temporarios para liberar rotas ate o CAA.',
  ),
  BibliotecaLoreEntry(
    title: 'LOG DO ACERVO DIGITAL',
    body:
        'Fragmentos recuperados mencionam o Protocolo Delta e uma rota de evacuacao pelo corredor norte da Biblioteca. A porta rejeita usuarios sem credencial.',
  ),
  BibliotecaLoreEntry(
    title: 'QUADRO DE AVISOS',
    body:
        'Um mapa rabiscado destaca a saida de emergencia e uma nota: "Cartao de funcionario necessario para seguir ao CAA".',
  ),
];

class BibliotecaGame extends FlameGame with HasCollisionDetection {
  BibliotecaGame({required this.playerName});

  final String playerName;

  static final Vector2 _fallbackMapSize = Vector2(870, 1024);
  static final Vector2 _fallbackSpawn = Vector2(435, 930);
  static final Vector2 _fallbackCardPosition = Vector2(580, 880);

  // The H15 PlayerComponent defaults to 96×96, which is too large relative to
  // the library's furniture. This constant is used for both spawn-clamping and
  // the post-load size override so every reference stays in sync.
  static final Vector2 _playerSize = Vector2(48, 48);

  PlayerComponent? player;
  JoystickComponent? _joystick;
  SpriteComponent? _background;

  Vector2 _mapSize = _fallbackMapSize.clone();
  final List<SolidObstacle> _walls = [];
  final List<BibliotecaInteractable> _interactables = [];
  final List<BibliotecaPickup> _pickups = [];

  final ValueNotifier<String> missionText = ValueNotifier(
    'Missao: investigue os terminais e encontre o Cartao de Acesso.',
  );
  final ValueNotifier<String?> hudMessage = ValueNotifier(null);
  final ValueNotifier<bool> canInteract = ValueNotifier(false);
  final ValueNotifier<String> interactLabel = ValueNotifier('INTERAGIR');
  final ValueNotifier<bool> dialogOpen = ValueNotifier(false);
  final ValueNotifier<bool> levelCompleted = ValueNotifier(false);
  final ValueNotifier<BibliotecaLoreEntry?> activeLore = ValueNotifier(null);
  final ValueNotifier<bool> hasAccessCardNotifier = ValueNotifier(false);

  BibliotecaInteractable? _nearbyInteractable;
  bool hasAccessCard = false;
  bool _transitioning = false;

  @override
  Color backgroundColor() => Colors.black;

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    camera.viewfinder.anchor = Anchor.center;
    camera.viewfinder.position = _fallbackSpawn.clone();

    final rawMap = await _loadTiledMap();
    await _loadBackground();
    _addBorderWalls();
    _loadInteractableObjects(rawMap);
    _spawnAccessCard(rawMap);

    final playerImage = await images.load('player/player_sprite.jpg');
    final playerComponent = PlayerComponent.fromSpriteSheet(playerImage)
      ..position = _readSpawn(rawMap)
      ..priority = 5
      ..size = _playerSize; // scale down from H15's 96×96 to fit library proportions
    player = playerComponent;
    await world.add(playerComponent);

    final minZoom = math.max(size.x / _mapSize.x, size.y / _mapSize.y);
    camera.viewfinder.zoom = math.max(minZoom, 1.5);
    camera.setBounds(Rectangle.fromLTWH(0, 0, _mapSize.x, _mapSize.y));
    camera.follow(playerComponent, snap: true);

    _setupJoystick();
    _restoreWeapon();

    async.Timer(const Duration(milliseconds: 700), () {
      if (!isMounted) return;
      showHudMessage('Procure documentos, terminais e o cartao de funcionario.');
    });
  }

  Future<Map<String, dynamic>> _loadTiledMap() async {
    try {
      final raw = await rootBundle.loadString('assets/tiles/biblioteca.json');
      final map = jsonDecode(raw) as Map<String, dynamic>;
      _mapSize = _readMapSize(map);
      return map;
    } catch (e) {
      debugPrint('Biblioteca map load failed: $e');
      _mapSize = _fallbackMapSize.clone();
      return const {};
    }
  }

  Vector2 _readMapSize(Map<String, dynamic> map) {
    final layers = _layers(map);
    for (final layer in layers) {
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
        sprite: await loadSprite('screens/biblioteca.png'),
        size: _mapSize,
        position: Vector2.zero(),
        priority: -10,
      );
      world.add(_background!);
    } catch (e) {
      debugPrint('Biblioteca background failed: $e');
      world.add(BibliotecaFallbackMap(size: _mapSize)..priority = -10);
    }
  }

  void _addBorderWalls() {
    const t = 8.0;
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

  void _loadInteractableObjects(Map<String, dynamic> map) {
    final layer = _objectLayer(map, 'Interagiveis');
    final objects = _objects(layer);
    if (objects.isEmpty) {
      _addFallbackInteractables();
      return;
    }

    var loreIndex = 0;
    for (final obj in objects) {
      final id = _stringProperty(obj, 'zoneId') ?? obj['name'] as String? ?? '';
      if (id.isEmpty) continue;

      final kind = _kindForZone(id);
      if (kind == BibliotecaInteractableKind.unknown) continue;

      final entry = kind == BibliotecaInteractableKind.exit
          ? null
          : kBibliotecaLoreEntries[
              loreIndex.clamp(0, kBibliotecaLoreEntries.length - 1)];
      if (entry != null) loreIndex++;

      _addInteractable(
        BibliotecaInteractable(
          zoneId: id,
          kind: kind,
          lore: entry,
          position: Vector2(
            (obj['x'] as num? ?? 0).toDouble(),
            (obj['y'] as num? ?? 0).toDouble(),
          ),
          size: Vector2(
            math.max((obj['width'] as num? ?? 0).toDouble(), 24),
            math.max((obj['height'] as num? ?? 0).toDouble(), 24),
          ),
        ),
      );
    }
  }

  void _addFallbackInteractables() {
    final specs = [
      ('terminal_1', BibliotecaInteractableKind.lore, Vector2(50, 548), Vector2(70, 50)),
      ('terminal_2', BibliotecaInteractableKind.lore, Vector2(130, 548), Vector2(70, 50)),
      ('terminal_3', BibliotecaInteractableKind.lore, Vector2(200, 548), Vector2(70, 50)),
      ('quadro_avisos', BibliotecaInteractableKind.lore, Vector2(295, 45), Vector2(150, 55)),
      ('porta_saida', BibliotecaInteractableKind.exit, Vector2(0, 0), Vector2(170, 150)),
    ];
    for (var i = 0; i < specs.length; i++) {
      final spec = specs[i];
      _addInteractable(
        BibliotecaInteractable(
          zoneId: spec.$1,
          kind: spec.$2,
          lore: spec.$2 == BibliotecaInteractableKind.exit
              ? null
              : kBibliotecaLoreEntries[i.clamp(0, kBibliotecaLoreEntries.length - 1)],
          position: spec.$3,
          size: spec.$4,
        ),
      );
    }
  }

  void _addInteractable(BibliotecaInteractable component) {
    _interactables.add(component);
    world.add(component);
  }

  BibliotecaInteractableKind _kindForZone(String id) {
    final lower = id.toLowerCase();
    if (lower == BibliotecaZoneIds.portaSaida ||
        lower.contains('porta') ||
        lower.contains('exit') ||
        lower.contains('saida')) {
      return BibliotecaInteractableKind.exit;
    }
    if (lower.startsWith(BibliotecaZoneIds.terminalPrefix) ||
        lower.startsWith(BibliotecaZoneIds.documentPrefix) ||
        lower.contains('terminal') ||
        lower.contains('document') ||
        lower.contains('relatorio') ||
        lower.contains('quadro')) {
      return BibliotecaInteractableKind.lore;
    }
    return BibliotecaInteractableKind.unknown;
  }

  void _spawnAccessCard(Map<String, dynamic> map) {
    final object = _findObjectByName(map, (name) {
      final lower = name.toLowerCase();
      return lower.contains('cartao') ||
          lower.contains('card') ||
          lower.contains('acesso');
    });
    final pos = object == null
        ? _fallbackCardPosition
        : Vector2(
            (object['x'] as num? ?? 0).toDouble() +
                (object['width'] as num? ?? 0).toDouble() / 2,
            (object['y'] as num? ?? 0).toDouble() +
                (object['height'] as num? ?? 0).toDouble() / 2,
          );
    final card = BibliotecaPickup(
      itemId: BibliotecaItemIds.cartaoAcesso,
      label: 'PEGAR CARTAO',
      position: _clampToMap(pos, Vector2(42, 28)),
      size: Vector2(42, 28),
    );
    _pickups.add(card);
    world.add(card);
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
        debugPrint('Biblioteca weapon sprite failed: $e');
      }
    }).catchError((_) {});
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (dialogOpen.value || _transitioning) return;

    final p = player;
    final j = _joystick;
    if (p == null || j == null) return;

    p.move(j.relativeDelta, dt, _mapSize, _walls);
    _updatePickupCollection();
    _updateProximity();
  }

  void _updatePickupCollection() {
    final p = player;
    if (p == null) return;
    for (final pickup in List<BibliotecaPickup>.of(_pickups)) {
      if (pickup.collected) continue;
      if ((p.position - pickup.position).length <= 56) {
        _collectPickup(pickup);
      }
    }
  }

  void _collectPickup(BibliotecaPickup pickup) {
    pickup.collect();
    if (pickup.itemId == BibliotecaItemIds.cartaoAcesso) {
      hasAccessCard = true;
      hasAccessCardNotifier.value = true;
      missionText.value = 'Missao: use o Cartao de Acesso na saida para o CAA.';
      showHudMessage('Cartao de Acesso de Funcionario coletado.');
      FirebaseService.instance
          .addItem(playerName, BibliotecaItemIds.cartaoAcesso)
          .catchError((e) => debugPrint('addItem cartao_acesso failed: $e'));
    }
  }

  void _updateProximity() {
    final p = player;
    if (p == null) return;

    BibliotecaInteractable? nearby;
    var bestDistance = double.infinity;
    for (final item in _interactables) {
      final distance = (p.position - item.center).length;
      final insideExit =
          item.kind == BibliotecaInteractableKind.exit &&
              item.rect.inflate(16).contains(Offset(p.position.x, p.position.y));
      if ((distance <= item.interactionRadius || insideExit) &&
          distance < bestDistance) {
        nearby = item;
        bestDistance = distance;
      }
    }

    _nearbyInteractable = nearby;
    canInteract.value = nearby != null;
    interactLabel.value = switch (nearby?.kind) {
      BibliotecaInteractableKind.lore => 'INVESTIGAR',
      // Show the card requirement in the button label so the player knows
      // exactly what's blocking them before they even press it.
      BibliotecaInteractableKind.exit =>
        hasAccessCard ? 'ENTRAR' : 'USAR CARTAO',
      _ => 'INTERAGIR',
    };
  }

  Future<void> interact() async {
    final target = _nearbyInteractable;
    if (target == null || dialogOpen.value || _transitioning) return;

    switch (target.kind) {
      case BibliotecaInteractableKind.lore:
        final lore = target.lore ?? kBibliotecaLoreEntries.first;
        activeLore.value = lore;
        dialogOpen.value = true;
        overlays.add('Lore');
      case BibliotecaInteractableKind.exit:
        await _tryExit();
      case BibliotecaInteractableKind.unknown:
        break;
    }
  }

  void closeLore() {
    overlays.remove('Lore');
    activeLore.value = null;
    dialogOpen.value = false;
  }

  Future<void> _tryExit() async {
    if (!hasAccessCard) {
      showHudMessage('Acesso Negado: Cartão Necessário');
      return;
    }
    _transitioning = true;
    canInteract.value = false;
    showHudMessage('Acesso liberado. Rota para o CAA desbloqueada.');
    await FirebaseService.instance.unlockNextPhase(playerName);
    await async.Future<void>.delayed(const Duration(milliseconds: 850));
    levelCompleted.value = true;
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

  String? _stringProperty(Map<String, dynamic> obj, String name) {
    final props = obj['properties'];
    if (props is! List) return null;
    for (final prop in props.whereType<Map<String, dynamic>>()) {
      if (prop['name'] == name) return prop['value']?.toString();
    }
    return null;
  }

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

enum BibliotecaInteractableKind { lore, exit, unknown }

class BibliotecaInteractable extends PositionComponent {
  BibliotecaInteractable({
    required this.zoneId,
    required this.kind,
    required this.lore,
    required super.position,
    required super.size,
  }) : super(priority: 1);

  final String zoneId;
  final BibliotecaInteractableKind kind;
  final BibliotecaLoreEntry? lore;

  Rect get rect => Rect.fromLTWH(position.x, position.y, size.x, size.y);
  @override
  Vector2 get center => Vector2(position.x + size.x / 2, position.y + size.y / 2);
  double get interactionRadius => kind == BibliotecaInteractableKind.exit ? 96 : 72;
}

class BibliotecaPickup extends PositionComponent {
  BibliotecaPickup({
    required this.itemId,
    required this.label,
    required super.position,
    required super.size,
  }) : super(anchor: Anchor.center, priority: 4);

  final String itemId;
  final String label;
  bool collected = false;
  double _pulse = 0;

  void collect() {
    collected = true;
    removeFromParent();
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    add(RectangleHitbox(collisionType: CollisionType.passive));
  }

  @override
  void update(double dt) {
    super.update(dt);
    _pulse += dt;
  }

  @override
  void render(Canvas canvas) {
    if (collected) return;
    final glow = 0.55 + math.sin(_pulse * 5) * 0.18;
    final rect = Rect.fromCenter(
      center: Offset(size.x / 2, size.y / 2),
      width: size.x,
      height: size.y,
    );

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

class BibliotecaFallbackMap extends PositionComponent {
  BibliotecaFallbackMap({required Vector2 size})
      : super(size: size, position: Vector2.zero());

  @override
  void render(Canvas canvas) {
    canvas.drawRect(size.toRect(), Paint()..color = const Color(0xFF2F2A24));
    final line = Paint()
      ..color = const Color(0x334A5568)
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.x; x += 48) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.y), line);
    }
    for (var y = 0.0; y < size.y; y += 48) {
      canvas.drawLine(Offset(0, y), Offset(size.x, y), line);
    }
  }
}
