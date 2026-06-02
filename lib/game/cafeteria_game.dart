import 'dart:async' as async;
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/experimental.dart' show Rectangle;
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/game_state.dart';
import '../services/audio_manager.dart';
import '../services/firebase_service.dart';
import 'zumbi_component.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Enums
// ─────────────────────────────────────────────────────────────────────────────
enum CafeteriaDialog { marcosIntro, marcosSecond, reward, exitChoice }

enum QuestStep {
  falarMarcos,    // 0 – speak to Marcos to begin
  coletarPecas,   // 1 – collect the radio piece (break path first)
  ligarRadio,     // 2 – interact with the radio
  matarHorda,     // 3 – defeat the zombie horde
  pegarPapel,     // 4 – collect the document (pecinha)
  pegarFusiveis,  // 5 – collect both fuses
  ativarPainel,   // 6 – activate the electrical panel
  concluirFase,   // 7 – return to Marcos to finish
}

// ─────────────────────────────────────────────────────────────────────────────
// MissionManager — strict 8-step state machine for Área 2.
// ─────────────────────────────────────────────────────────────────────────────
class MissionManager {
  static const int _hordeKillsRequired = 5;

  QuestStep currentStep = QuestStep.falarMarcos;
  int _hordeKills = 0;

  void advance(QuestStep next) {
    currentStep = next;
  }

  /// Call on every zombie kill. Returns true when the horde quota is met.
  bool registerKill() {
    if (currentStep != QuestStep.matarHorda) return false;
    _hordeKills++;
    return _hordeKills >= _hordeKillsRequired;
  }

  static String updateQuestText(QuestStep step) {
    switch (step) {
      case QuestStep.falarMarcos:   return 'Fale com Marcos.';
      case QuestStep.coletarPecas:  return 'Colete as pecas necessarias.';
      case QuestStep.ligarRadio:    return 'Ligue o radio.';
      case QuestStep.matarHorda:    return 'Elimine a horda de zumbis.';
      case QuestStep.pegarPapel:    return 'Pegue o papel de instrucoes.';
      case QuestStep.pegarFusiveis: return 'Colete os 2 fusiveis.';
      case QuestStep.ativarPainel:  return 'Ative o painel eletrico.';
      case QuestStep.concluirFase:  return 'Fase concluida! Fale com Marcos.';
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CafeteriaGame
// ─────────────────────────────────────────────────────────────────────────────
class CafeteriaGame extends FlameGame with HasCollisionDetection implements ZumbiGame {
  CafeteriaGame({required this.playerName});

  @override
  bool get debugMode => false; // Suppresses Flame hitbox/bounds debug rendering.

  final String playerName;
  final math.Random _rng = math.Random();
  // Mutable — overwritten from the Tiled image layer dimensions on load.
  Vector2 _mapSize = Vector2(1916, 1568);

  CafeteriaPlayerComponent? player;
  JoystickComponent? _joystick;
  SpriteComponent? _background;
  MarcosComponent? _marcos;
  ElectricalPanelComponent? _panel;
  LockerComponent? _locker;   // used only by fallback path
  ArmarioComponent? _armario; // used by Tiled path
  final List<ZumbiComponent> _zombies = [];
  final List<CafeteriaProp> _props = [];
  final List<CafeteriaPickup> _pickups = [];
  final List<CafWall> _walls = [];

  // ── HUD state ──────────────────────────────────────────────────────────────
  final ValueNotifier<double> currentHealth = ValueNotifier(100);
  final ValueNotifier<double> maxHealth = ValueNotifier(100);
  final ValueNotifier<String> missionText =
      ValueNotifier(MissionManager.updateQuestText(QuestStep.falarMarcos));
  final ValueNotifier<String?> hudMessage = ValueNotifier(null);
  final ValueNotifier<String> interactLabel = ValueNotifier('INTERAGIR');
  final ValueNotifier<bool> canInteract = ValueNotifier(false);
  final ValueNotifier<bool> dialogOpen = ValueNotifier(false);
  final ValueNotifier<bool> gameOver = ValueNotifier(false);
  final ValueNotifier<int> brokenTables = ValueNotifier(0);
  final ValueNotifier<int> emergencyMedkit = ValueNotifier(0);
  final ValueNotifier<int> stimulant = ValueNotifier(0);
  final ValueNotifier<List<String>> secretCodePieces = ValueNotifier([]);
  final ValueNotifier<bool> attackEnabled = ValueNotifier(true);
  final ValueNotifier<int> zombiesKilled = ValueNotifier(0);

  // ── Quest state ───────────────────────────────────────────────────────────
  CafeteriaDialog? activeDialog;
  Object? _nearby;
  int brokenTablesCount = 0;
  final int maxSafeBrokenTables = 5;
  bool zombiesAlerted = false;
  int marcosTrust = 0;
  bool hasEmergencyMedkit = false;
  bool usedReviveThisArea = false;
  int stimulantCount = 0;
  bool radioPowered = false;
  bool radioTuned = false;
  bool secretCodeCompleted = false;
  bool vitalBoostCollected = false;
  bool mainCompleted = false;
  final MissionManager mission = MissionManager();
  int _fusesInstalled = 0;
  async.Timer? _stimTimer;
  double _tableDamageCooldown = 0;
  List<Vector2> _zombieSpawnPoints = [];
  CafeteriaPickup? _pendingSenhaPickup;

  void _advanceMission(QuestStep next) {
    mission.advance(next);
    missionText.value = MissionManager.updateQuestText(next);
    debugPrint('Mission updated to: $next');
  }

  // ── ZumbiGame interface ────────────────────────────────────────────────────
  @override Vector2 get zumbiMapSize => _mapSize;
  @override List<Rect> get zumbiWallRects =>
      _walls.map((w) => w.wallRect).toList(growable: false);
  @override void zumbiDamagePlayer(double amount) => damagePlayer(amount);
  @override List<ZumbiComponent> get spawnedZombies => _zombies;

  @override
  Color backgroundColor() => Colors.black;

  // ── onLoad ─────────────────────────────────────────────────────────────────
  @override
  Future<void> onLoad() async {
    await super.onLoad();
    MusicManager.instance.stopMenuBgm(); // stop menu BGM before any level asset load
    camera.viewfinder.anchor = Anchor.center;

    // 1. Parse Tiled map — throws Exception if the file is missing.
    final spawn = await _spawnFromTiled(await _loadMapJson());

    // 2. Background at confirmed map dimensions.
    try {
      _background = SpriteComponent(
        sprite: await loadSprite('screens/cafeteria_map.png'),
        size: _mapSize,
        position: Vector2.zero(),
        priority: -10,
      );
      world.add(_background!);
    } catch (_) {
      world.add(CafeteriaFallbackMap(size: _mapSize)..priority = -10);
    }

    // 3. Player.
    late final ui.Image playerImg;
    try {
      playerImg = await images.load('player/player_sprite.jpg');
    } catch (_) {
      final rec = ui.PictureRecorder();
      ui.Canvas(rec).drawRect(const ui.Rect.fromLTWH(0, 0, 1, 1), ui.Paint());
      playerImg = await rec.endRecording().toImage(1, 1);
    }
    final playerComp = CafeteriaPlayerComponent.fromImage(playerImg)
      ..position = spawn
      ..priority = 5;
    player = playerComp;
    await world.add(playerComp);

    // 4. Camera — after player is mounted.
    camera.viewfinder.position = spawn;
    final minZoom = math.max(size.x / _mapSize.x, size.y / _mapSize.y);
    camera.viewfinder.zoom = math.max(minZoom, 1.5);
    camera.setBounds(Rectangle.fromLTWH(0, 0, _mapSize.x, _mapSize.y));
    camera.follow(playerComp, snap: true);

    // 5. Weapon from Firebase — always equips at least the basic sword.
    // Safety loadout: if Firebase returns null/empty the player gets 'Espada'
    // so they are never unarmed (critical for DEV skip-level flows).
    FirebaseService.instance.loadWeapon().then((weapon) async {
      final selected = (weapon == null || weapon.isEmpty) ? 'Espada' : weapon;
      final asset = selected == 'Duas Adagas'
          ? 'player/player_espada2mao.png'
          : 'player/player_espada1mao.png';
      try {
        final img = await images.load(asset);
        player?.replaceWithWeaponSheet(img);
      } catch (e) {
        debugPrint('Weapon sprite ($selected): $e');
      }
    }).catchError((_) async {
      // Firebase unavailable — equip the fallback sword silently.
      try {
        final img = await images.load('player/player_espada1mao.png');
        player?.replaceWithWeaponSheet(img);
      } catch (_) {}
    });

    // 6. Joystick.
    _setupJoystick();

    // 8. Intro hint.
    Future<void>.delayed(const Duration(milliseconds: 800), () {
      if (!gameOver.value) showHudMessage('Encontre Marcos no armazem de suprimentos.');
    });

    // 9. Mission state machine — hard reset to step 0 before Firebase may override.
    _advanceMission(QuestStep.falarMarcos);
    debugPrint('HUD initialized with Kills: ${zombiesKilled.value}');

    // 10. Firebase state (may advance currentMissionStep if progress was saved).
    _loadSavedProgress()
        .timeout(const Duration(seconds: 6))
        .catchError((e) => debugPrint('_loadSavedProgress falhou: $e'));
    _syncAreaState().catchError((e) => debugPrint('_syncAreaState onLoad: $e'));
  }

  // ── Tiled map loader ───────────────────────────────────────────────────────

  // Throws if the Tiled JSON is missing — no fallback, no silent failure.
  Future<Map<String, dynamic>> _loadMapJson() async {
    try {
      final raw = await rootBundle
          .loadString('assets/tiles/refeitorio_collisions.json');
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (e) {
      throw Exception(
        'FATAL: refeitorio_collisions.json not found or invalid.\n'
        'Ensure the file exists at assets/tiles/refeitorio_collisions.json.\n'
        'Original error: $e',
      );
    }
  }

  // Reads the map pixel dimensions from the imagelayer entry.
  Vector2 _readMapSizeFromData(Map<String, dynamic> map) {
    for (final layer in (map['layers'] as List<dynamic>)
        .whereType<Map<String, dynamic>>()) {
      if (layer['type'] == 'imagelayer') {
        final w = (layer['imagewidth'] as num? ?? 0).toDouble();
        final h = (layer['imageheight'] as num? ?? 0).toDouble();
        if (w > 0 && h > 0) return Vector2(w, h);
      }
    }
    return Vector2(1916, 1568);
  }

  // Main Tiled parser. Iterates every ObjectGroup layer and spawns the
  // matching component. Returns the player spawn position.
  Future<Vector2> _spawnFromTiled(Map<String, dynamic> mapData) async {
    _mapSize = _readMapSizeFromData(mapData);

    Vector2 playerSpawn = Vector2(1740, 1262); // Tiled default

    final layers = (mapData['layers'] as List<dynamic>)
        .whereType<Map<String, dynamic>>();

    for (final layer in layers) {
      final name = (layer['name'] as String? ?? '').toLowerCase().trim();
      final objects = (layer['objects'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .toList();
      if (objects.isEmpty) continue;

      switch (name) {
        case 'player spawn':
          final pt = _firstPoint(objects);
          if (pt != null) playerSpawn = pt;

        case 'marcos npc':
          final pos = _firstPoint(objects) ?? Vector2(1222, 358);
          _marcos = MarcosComponent(game: this)
            ..position = pos
            ..priority = 8;
          world.add(_marcos!);

        case 'colisoes':
          _spawnWalls(objects);

        case 'fusivel':
          for (final obj in objects) {
            _addPickup('fuse', _floorPosOf(obj));
          }

        case 'pecaradio':
          for (final obj in objects) {
            _addPickup('radioPart', _floorPosOf(obj));
          }

        case 'radio':
          for (final obj in objects) {
            _addPickup('radio', _floorPosOf(obj));
          }

        case 'pecinha':
          for (final obj in objects) {
            _addPickup('pecinha', _floorPosOf(obj));
          }

        case 'armario':
          _spawnArmario(objects.first);

        case 'painel eletrico':
        case 'painelfusivel':
          _spawnPanel(objects.first);

        case 'zumbispawn':   // actual Tiled layer name
        case 'spawnzumbi':   // alias in case it is renamed in Tiled
          _zombieSpawnPoints = objects.map(_floorPosOf).toList();

        case 'papelsenha':    // actual Tiled layer name (paper with 417 code)
        case 'senhaarmario':  // alias
          for (final obj in objects) {
            final sz = CafeteriaGame._pickupDisplaySize('senha');
            final pickup = CafeteriaPickup(kind: 'senha', game: this)
              ..position = _clampToMapBottom(_floorPosOf(obj), sz)
              ..size = sz
              ..priority = 2;
            _pickups.add(pickup);
            world.add(pickup);
          }

        case 'table_front':
          _spawnTableProps(objects, 'objects/table_front.png');
        case 'table_s':
          _spawnTableProps(objects, 'objects/table_s.png');
        case 'table_e':
          _spawnTableProps(objects, 'objects/table_e.png');
        case 'table_ne':
          _spawnTableProps(objects, 'objects/table_ne.png');
        case 'table_se':
          _spawnTableProps(objects, 'objects/table_se.png');
        case 'table_n':
          _spawnTableProps(objects, 'objects/table_n.png');
        case 'table_w':
          _spawnTableProps(objects, 'objects/table_w.png', kind: 'areaC');
      }
    }

    return playerSpawn;
  }

  // ── Tiled wall spawners ────────────────────────────────────────────────────

  void _spawnWalls(List<Map<String, dynamic>> objects) {
    for (final obj in objects) {
      final ox = (obj['x'] as num).toDouble();
      final oy = (obj['y'] as num).toDouble();
      final polygon = obj['polygon'] as List<dynamic>?;
      if (polygon != null && polygon.isNotEmpty) {
        _addPolygonWall(ox, oy, polygon);
      } else {
        final w = (obj['width'] as num? ?? 0).toDouble();
        final h = (obj['height'] as num? ?? 0).toDouble();
        if (w > 0 && h > 0) _addCafWall(Vector2(ox, oy), Vector2(w, h));
      }
    }
  }

  // Polygon → AABB. Guard skips shapes larger than 900 px on any axis.
  void _addPolygonWall(double ox, double oy, List<dynamic> polygon) {
    var minX = double.infinity, minY = double.infinity;
    var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
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
    if (w <= 0 || h <= 0 || w > 900 || h > 900) return;
    _addCafWall(Vector2(ox + minX, oy + minY), Vector2(w, h));
  }

  void _addCafWall(Vector2 pos, Vector2 sz) {
    final w = CafWall(position: pos, size: sz);
    _walls.add(w);
    world.add(w);
  }

  // ── Tiled entity spawners ──────────────────────────────────────────────────

  void _spawnTableProps(
    List<Map<String, dynamic>> objects,
    String asset, {
    String kind = 'table',
  }) {
    for (final obj in objects) {
      final w = (obj['width'] as num? ?? 80).toDouble();
      final h = (obj['height'] as num? ?? 40).toDouble();
      final x = (obj['x'] as num).toDouble() + w / 2;
      final y = (obj['y'] as num).toDouble() + h / 2;
      final spec = CafPropSpec(kind, Vector2(x, y), Vector2(w, h), asset: asset);
      final prop = CafeteriaProp(spec: spec, game: this)..priority = 10;
      _props.add(prop);
      world.add(prop);
    }
  }

  void _spawnPanel(Map<String, dynamic> obj) {
    final w = (obj['width'] as num? ?? 80).toDouble();
    final h = (obj['height'] as num? ?? 60).toDouble();
    final x = (obj['x'] as num).toDouble() + w / 2;
    final y = (obj['y'] as num).toDouble() + h / 2;
    _panel = ElectricalPanelComponent(game: this)
      ..position = Vector2(x, y)
      ..size = Vector2(w, h)
      ..priority = 10;
    world.add(_panel!);
  }

  // Spawns ArmarioComponent with Anchor.bottomCenter.
  // position.x = horizontal center of Tiled rect; position.y = bottom of rect.
  void _spawnArmario(Map<String, dynamic> obj) {
    final w = (obj['width'] as num? ?? 90).toDouble();
    final h = (obj['height'] as num? ?? 102).toDouble();
    final x = (obj['x'] as num).toDouble() + w / 2;  // horizontal center
    final y = (obj['y'] as num).toDouble() + h;       // bottom edge = floor contact
    _armario = ArmarioComponent(game: this)
      ..position = Vector2(x, y)
      ..priority = y.ceil(); // Y-sort: bottomCenter means position.y IS the floor Y
    world.add(_armario!);
    // Block player & zombie movement through the Tiled footprint.
    _addCafWall(Vector2(x - w / 2, y - h), Vector2(w, h));
  }

  // Called by ArmarioComponent.open() — grants one-time +20 HP/maxHP boost.
  void onArmarioOpened() {
    const boost = 20.0;
    maxHealth.value += boost;
    currentHealth.value = math.min(maxHealth.value, currentHealth.value + boost);
    GameState.instance.addMaxHealthBonus(20); // persists across phase transitions
    showHudMessage('Armario aberto! Vida maxima +20.');
    FirebaseService.instance
        .updateInventoryItem(playerName, 'maxHealthBonus', 20)
        .catchError((_) {});
    FirebaseService.instance
        .updateStats(playerName, maxHealthDelta: 20)
        .catchError((_) {});
    _syncAreaState().catchError((_) {});
  }

  // ── Tiled coordinate helpers ───────────────────────────────────────────────

  // Returns x/y of the first object in the list (point or rect top-left).
  Vector2? _firstPoint(List<Map<String, dynamic>> objects) {
    if (objects.isEmpty) return null;
    final obj = objects.first;
    return Vector2(
      (obj['x'] as num).toDouble(),
      (obj['y'] as num).toDouble(),
    );
  }

  void _setupJoystick() {
    // Prioridade 1001 — igual ao H15 que funciona (garante input acima de qualquer overlay)
    _joystick = JoystickComponent(
      knob: CircleComponent(radius: 26, paint: Paint()..color = const Color(0xFFF5C842)),
      background: CircleComponent(radius: 68, paint: Paint()..color = const Color(0xAAE5E7EB)),
      margin: const EdgeInsets.only(left: 28, bottom: 28),
      priority: 1001,
    );
    camera.viewport.add(_joystick!);
  }

  // Clamps a component's CENTER position so its edges never leave the map.
  // Pickups use Anchor.bottomCenter — position.x = center X, position.y = floor Y.
  Vector2 _clampToMapBottom(Vector2 pos, Vector2 size) => Vector2(
        pos.x.clamp(size.x / 2, _mapSize.x - size.x / 2).toDouble(),
        pos.y.clamp(size.y, _mapSize.y).toDouble(),
      );

  // Returns the bottom-center of a Tiled object: (x + w/2, y + h) for rects,
  // or (x, y) for point objects. Matches Anchor.bottomCenter placement.
  Vector2 _floorPosOf(Map<String, dynamic> obj) {
    final x = (obj['x'] as num).toDouble();
    final y = (obj['y'] as num).toDouble();
    final w = (obj['width'] as num? ?? 0).toDouble();
    final h = (obj['height'] as num? ?? 0).toDouble();
    if (obj['point'] == true || (w == 0 && h == 0)) return Vector2(x, y);
    return Vector2(x + w / 2, y + h);
  }

  // Display size per item kind — base values × 1.5 scale for visibility.
  static Vector2 _pickupDisplaySize(String kind) => switch (kind) {
    'fuse'      => Vector2(60, 36),
    'radioPart' => Vector2(42, 42),
    'radio'     => Vector2(60, 45),
    'vitalBoost'=> Vector2(39, 39),
    'pecinha'   => Vector2(36, 36),
    'senha'     => Vector2(33, 42), // folded paper — taller than wide
    _           => Vector2(54, 54),
  };

  // Floor items render under the player (priority 1); interactive props stay above (6).
  static bool _isFloorItem(String kind) =>
      kind == 'fuse' || kind == 'radioPart' || kind == 'vitalBoost' ||
      kind == 'pecinha' || kind == 'senha';

  void _addPickup(String kind, Vector2 floorPos) {
    if (kind == 'vitalBoost' && vitalBoostCollected) return;
    if ((kind == 'fuse' || kind == 'radioPart') && mainCompleted) return;
    final displaySize = _pickupDisplaySize(kind);
    final pickup = CafeteriaPickup(kind: kind, game: this)
      ..position = _clampToMapBottom(floorPos, displaySize)
      ..size = displaySize
      ..priority = _isFloorItem(kind) ? 1 : 6;
    _pickups.add(pickup);
    world.add(pickup);
  }

  void _spawnZombie(Vector2 pos) {
    final p = player;
    if (p == null) return;
    final z = ZumbiComponent(game: this, target: p)
      ..position = pos
      ..priority = 15;
    _zombies.add(z);
    world.add(z);
  }

  // Spawns [count] aggressive zombies in a ring around [nearPosition].
  // The ring radius (120–200 px) keeps zombies outside the table footprint.
  // Each successive wave adds to the total — no cap enforced here.
  void spawnZombieWave(int count, {required Vector2 nearPosition}) {
    const minRadius = 120.0;
    const maxRadius = 200.0;
    for (var i = 0; i < count; i++) {
      final angle = (i / count) * math.pi * 2 + _rng.nextDouble() * 0.9;
      final radius = minRadius + _rng.nextDouble() * (maxRadius - minRadius);
      final pos = Vector2(
        (nearPosition.x + math.cos(angle) * radius)
            .clamp(40.0, _mapSize.x - 40.0),
        (nearPosition.y + math.sin(angle) * radius)
            .clamp(40.0, _mapSize.y - 40.0),
      );
      _spawnZombie(pos);
    }
    showHudMessage('Mesa destruída! $count zumbis aparecem.');
  }

  // ── Update ─────────────────────────────────────────────────────────────────
  @override
  void update(double dt) {
    super.update(dt);
    if (dialogOpen.value || gameOver.value) return;
    final p = player;
    final j = _joystick;
    if (p == null || j == null) return;
    p.move(j.relativeDelta, dt, _mapSize, _walls);
    _checkTableDamage(dt);
    _updateProximity();
    _removeDeadZombies();
  }

  // Mesas sem colisão mas causam dano se o jogador passar sem quebrar primeiro
  void _checkTableDamage(double dt) {
    if (_tableDamageCooldown > 0) {
      _tableDamageCooldown -= dt;
      return;
    }
    final p = player;
    if (p == null) return;
    final px = p.position.x;
    final py = p.position.y;
    for (final prop in _props) {
      if (prop.broken) continue;
      if (prop.kind != 'table' && prop.kind != 'areaC') continue;
      final halfW = prop.size.x * 0.45;
      final halfH = prop.size.y * 0.45;
      final dx = (px - prop.position.x).abs();
      final dy = (py - prop.position.y).abs();
      if (dx < halfW && dy < halfH) {
        _tableDamageCooldown = 1.4;
        damagePlayer(8);
        showHudMessage('Mesa bloqueou o caminho! Quebre-a primeiro (ATK).');
        return;
      }
    }
  }

  void _updateProximity() {
    final p = player;
    if (p == null) return;
    Object? nearby;
    var label = 'INTERAGIR';

    for (final prop in _props.where((e) => !e.broken)) {
      if ((p.position - prop.center).length <= 78) {
        nearby = prop;
        label = prop.label;
        break;
      }
    }
    for (final pickup in _pickups.where((e) => !e.collected)) {
      if ((p.position - pickup.position).length <= 70) {
        nearby = pickup;
        label = pickup.label;
        break;
      }
    }
    // Panel (only interactive while not yet powered)
    if (_panel != null && _panel!.isMounted && !radioPowered) {
      if ((p.position - _panel!.position).length <= 85) {
        nearby = _panel;
        label = 'USAR PAINEL';
      }
    }
    // Armario (only interactive before opened)
    if (_armario != null && _armario!.isMounted && !_armario!.isOpened) {
      if ((p.position - _armario!.position).length <= 90) {
        nearby = _armario;
        label = 'ABRIR ARMARIO';
      }
    }
    // Fallback locker (used when JSON loading fails)
    if (_locker != null && _locker!.isMounted && !_locker!.isOpen) {
      if ((p.position - _locker!.position).length <= 80) {
        nearby = _locker;
        label = 'ABRIR ARMARIO';
      }
    }
    // Marcos always wins — highest interaction priority
    if (_marcos != null && (p.position - _marcos!.position).length <= 95) {
      nearby = _marcos;
      label = 'FALAR';
    }

    _nearby = nearby;
    canInteract.value = nearby != null;
    interactLabel.value = label;
  }

  void _removeDeadZombies() {
    // Only remove zombies that finished loading AND were then unmounted (killed).
    // Checking isLoaded prevents purging newly-spawned zombies that are still
    // in Flame's async onLoad queue (isMounted=false while loading).
    _zombies.removeWhere((z) => z.isLoaded && !z.isMounted);
  }

  // ── Ataque do jogador ──────────────────────────────────────────────────────
  void attack() {
    if (!attackEnabled.value) return;
    final p = player;
    if (p == null) return;
    p.startAttack();

    // Spawn a short-lived hitbox at the player's attack rect (Flame collision
    // approach). Damage is applied via onCollisionStart on _CafSwordHitbox.
    final r = p.attackHitRect;
    world.add(_CafSwordHitbox(
      game: this,
      worldPos: Vector2(r.center.dx, r.center.dy),
      sz: Vector2(r.width, r.height),
    ));

    // Manual backup — runs immediately before the Flame broad-phase catches up
    // (the hitbox above fires on the next update tick). Avoids a 1-frame window
    // where the player can tap and see no damage.
    _resolveAttack(p);
  }

  void _resolveAttack(CafeteriaPlayerComponent p) {
    final attackRect = p.attackHitRect;
    for (final z in List.of(_zombies)) {
      if (!z.isLoaded || !z.isMounted) continue;
      if (attackRect.overlaps(z.hitRect)) {
        final pos = z.position.clone();
        final dead = z.takeDamage(10); // 10 dmg × 2 hits = 20 HP = 2-hit kill
        if (dead) {
          _zombies.remove(z);
          z.removeFromParent();
          world.add(ImpactFlash(position: pos)..priority = 18);
          zombiesKilled.value++;
          if (mission.registerKill()) {
            _advanceMission(QuestStep.pegarPapel);
            showHudMessage('Horda eliminada! Pegue o papel de instrucoes.');
          }
        }
      }
    }
  }

  // ── Interação ──────────────────────────────────────────────────────────────
  void interact() {
    final target = _nearby;
    if (target == null) return;
    if (target is MarcosComponent) {
      if (mission.currentStep == QuestStep.falarMarcos) {
        _openDialog(CafeteriaDialog.marcosIntro);
      } else if (mission.currentStep == QuestStep.concluirFase || mainCompleted) {
        _openDialog(CafeteriaDialog.exitChoice);
      } else {
        showHudMessage('Marcos observa em silencio.');
      }
    } else if (target is ArmarioComponent) {
      openLockerKeypad(); // reuses LockerKeypad overlay; routes to onLockerCorrectCode
    } else if (target is ElectricalPanelComponent) {
      _interactPanel();
    } else if (target is LockerComponent) {
      openLockerKeypad();
    } else if (target is CafeteriaProp) {
      _interactProp(target);
    } else if (target is CafeteriaPickup) {
      _collectPickup(target);
    }
  }

  void _interactProp(CafeteriaProp prop) {
    switch (prop.kind) {
      case 'table':
        prop.breakProp();
        brokenTablesCount++;
        brokenTables.value = brokenTablesCount;
        _syncAreaState().catchError((_) {});
        // Every table break spawns a wave of 5 zombies near the table's position.
        spawnZombieWave(5, nearPosition: prop.position);
      case 'areaC':
        if (mission.currentStep != QuestStep.coletarPecas) {
          showHudMessage('O caminho esta bloqueado. Complete as missoes anteriores.');
          return;
        }
        prop.breakProp();
        showHudMessage('Caminho aberto! Muitos zumbis acordaram!');
        for (var i = 0; i < 8; i++) {
          _spawnZombie(Vector2(885 + _rng.nextDouble() * 170, 210 + _rng.nextDouble() * 210));
        }
        _syncAreaState().catchError((_) {});
      case 'secret1':
      case 'secret2':
      case 'secret3':
        prop.breakProp();
        final piece = {'secret1': '4', 'secret2': '1', 'secret3': '7'}[prop.kind]!;
        final pieces = [...secretCodePieces.value, piece];
        secretCodePieces.value = pieces;
        showHudMessage('Voce encontrou o numero $piece.');
        if (pieces.join() == '417') {
          secretCodeCompleted = true;
          showHudMessage('Codigo 417 completo!');
        }
        _syncAreaState().catchError((_) {});
      default:
        break;
    }
  }

  void _collectPickup(CafeteriaPickup pickup) {
    switch (pickup.kind) {
      case 'radioPart':
        if (mission.currentStep.index < QuestStep.coletarPecas.index) {
          showHudMessage('Ainda nao e possivel coletar isso. Complete as missoes anteriores.');
          return;
        }
        pickup.collect();
        if (mission.currentStep == QuestStep.coletarPecas) {
          _advanceMission(QuestStep.ligarRadio);
          showHudMessage('Peca coletada! Agora ligue o radio.');
        } else {
          showHudMessage('Peca coletada.');
        }
      case 'senha':
        if (mission.currentStep != QuestStep.pegarPapel) {
          showHudMessage('Uma nota misteriosa. Volte depois.');
          return;
        }
        _pendingSenhaPickup = pickup;
        dialogOpen.value = true;
        pauseEngine();
        overlays.add('SenhaArmario');
      case 'fuse':
        if (mission.currentStep.index < QuestStep.pegarFusiveis.index) {
          showHudMessage('Um fusivel. Melhor usar depois.');
          return;
        }
        pickup.collect();
        _fusesInstalled++;
        showHudMessage('Fusivel coletado ($_fusesInstalled/2).');
        if (_fusesInstalled >= 2) {
          _advanceMission(QuestStep.ativarPainel);
        }
      case 'radio':
        if (mission.currentStep != QuestStep.ligarRadio) {
          showHudMessage('Sistemas indisponiveis. Complete as missoes anteriores.');
          return;
        }
        overlays.add('RadioTune');
        dialogOpen.value = true;
        pauseEngine();
      case 'vitalBoost':
        if (!secretCodeCompleted) {
          showHudMessage('O armario esta trancado.');
          return;
        }
        if (vitalBoostCollected) {
          showHudMessage('Ja foi coletado.');
          return;
        }
        pickup.collect();
        vitalBoostCollected = true;
        maxHealth.value += 10;
        currentHealth.value = maxHealth.value;
        FirebaseService.instance.updateInventoryItem(playerName, 'maxHealthBonus', 10).catchError((_) {});
        FirebaseService.instance.updateStats(playerName, maxHealthDelta: 10).catchError((_) {});
        showHudMessage('Reforco Vital! Vida maxima +10.');
        _syncAreaState().catchError((_) {});
      case 'pecinha':
        if (mission.currentStep != QuestStep.pegarPapel) {
          showHudMessage('Ainda nao e o momento certo.');
          return;
        }
        pickup.collect();
        _advanceMission(QuestStep.pegarFusiveis);
        FirebaseService.instance
            .updateInventoryItem(playerName, 'pecinha', 1)
            .catchError((_) {});
        showHudMessage('Papel coletado! Colete os fusiveis.');
        _syncAreaState().catchError((_) {});
    }
  }

  // ── Panel & Locker interactions ───────────────────────────────────────────

  void _interactPanel() {
    if (mission.currentStep != QuestStep.ativarPainel) {
      showHudMessage('Sistemas indisponiveis. Complete as missoes anteriores.');
      return;
    }
    if (_fusesInstalled < 2) {
      showHudMessage('O painel precisa de 2 fusiveis.');
      return;
    }
    if (!radioPowered) {
      openFuseBox();
    } else {
      showHudMessage('Painel ja esta operacional.');
    }
  }

  void openLockerKeypad() {
    dialogOpen.value = true;
    pauseEngine();
    overlays.add('LockerKeypad');
  }

  // Called by LockerKeypadOverlay when the correct PIN is entered.
  void onLockerCorrectCode() {
    overlays.remove('LockerKeypad');
    dialogOpen.value = false;
    resumeEngine();
    // Route to the active cabinet: Tiled path (_armario) or fallback (_locker).
    if (_armario != null && !_armario!.isOpened) {
      _armario!.openArmario();
      onArmarioOpened(); // +20 HP / maxHP
    } else {
      _locker?.openLocker();
      secretCodeCompleted = true;
      showHudMessage('Armario aberto! Coleta o Reforco Vital.');
    }
    _syncAreaState().catchError((_) {});
  }

  // Called by LockerKeypadOverlay when the player cancels.
  void onLockerCancelCode() {
    overlays.remove('LockerKeypad');
    dialogOpen.value = false;
    resumeEngine();
  }

  // ── Painel de Fusíveis (minigame) ─────────────────────────────────────────
  // fuseBoxFusesAvailable is exposed so the overlay can show the player how
  // many fuses they brought to the panel (always 2 when the panel is unlocked).
  int get fuseBoxFusesAvailable => _fusesInstalled;

  void openFuseBox() {
    dialogOpen.value = true;
    pauseEngine();
    overlays.add('FuseBox');
  }

  void completeFuseBox() {
    overlays.remove('FuseBox');
    dialogOpen.value = false;
    resumeEngine();
    if (radioPowered) return;
    radioPowered = true;
    mainCompleted = true;
    _advanceMission(QuestStep.concluirFase);
    FirebaseService.instance.completeArea2(playerName).catchError((_) {});
    _syncAreaState().catchError((_) {});
    _openDialog(CafeteriaDialog.exitChoice);
  }

  // ── Diálogo / estado ───────────────────────────────────────────────────────
  void _openDialog(CafeteriaDialog dialog) {
    activeDialog = dialog;
    dialogOpen.value = true;
    pauseEngine();
    overlays.add('MarcosDialog');
  }

  void closeMarcosDialog() {
    overlays.remove('MarcosDialog');
    dialogOpen.value = false;
    resumeEngine();
  }

  void chooseMarcosIntro(int option) {
    if (option == 1) marcosTrust += 1;
    if (option == 3) marcosTrust -= 2;
    if (marcosTrust <= -2) {
      closeMarcosDialog();
      triggerMineDeath();
      return;
    }
    activeDialog = CafeteriaDialog.marcosSecond;
    _syncAreaState().catchError((_) {});
  }

  void chooseMarcosSecond(int option) {
    if (option == 1) marcosTrust += 1;
    if (option == 2 || option == 3) marcosTrust -= 1;
    _advanceMission(QuestStep.coletarPecas);
    closeMarcosDialog();
    _syncAreaState().catchError((_) {});
  }

  Future<void> chooseReward(String reward) async {
    if (reward == 'medkit') await giveEmergencyMedkit();
    if (reward == 'stimulant') await giveStimulants();
    activeDialog = CafeteriaDialog.exitChoice;
  }

  Future<void> giveEmergencyMedkit() async {
    hasEmergencyMedkit = true;
    emergencyMedkit.value++;
    await FirebaseService.instance.updateInventoryItem(playerName, 'emergencyMedkit', 1).catchError((_) {});
    showHudMessage('Medikit de Emergencia recebido.');
  }

  Future<void> giveStimulants() async {
    stimulantCount += 2;
    stimulant.value = stimulantCount;
    await FirebaseService.instance.updateInventoryItem(playerName, 'stimulant', 2).catchError((_) {});
    showHudMessage('2 estimulantes recebidos.');
  }

  Future<void> useStimulant() async {
    if (stimulantCount <= 0 || _stimTimer != null) return;
    stimulantCount--;
    stimulant.value = stimulantCount;
    FirebaseService.instance.updateInventoryItem(playerName, 'stimulant', -1).catchError((_) {});
    var ticks = 0;
    _stimTimer = async.Timer.periodic(const Duration(seconds: 2), (t) {
      ticks++;
      currentHealth.value = math.min(maxHealth.value, currentHealth.value + 1);
      if (ticks >= 10 || currentHealth.value >= maxHealth.value) {
        t.cancel();
        _stimTimer = null;
      }
    });
  }

  Future<void> _completeMainMissions() async {
    if (mainCompleted) return;
    mainCompleted = true;
    missionText.value = 'Area 2 concluida!';
    await FirebaseService.instance.completeArea2(playerName).catchError((_) {});
    await _syncAreaState().catchError((_) {});
    _openDialog(CafeteriaDialog.reward);
  }

  Future<void> continueExploring() async {
    FirebaseService.instance.completeArea2(playerName).catchError((_) {});
    closeMarcosDialog();
    showHudMessage('CAA desbloqueado. Voce continua no Refeitorio.');
  }

  Future<void> goToArea3(BuildContext context) async {
    await FirebaseService.instance.completeArea2(playerName, moveToArea3: true).catchError((_) {});
    if (context.mounted) Navigator.of(context).pop(true);
  }

  void completeRadioTune() {
    overlays.remove('RadioTune');
    dialogOpen.value = false;
    radioTuned = true;
    if (marcosTrust >= 0) marcosTrust += 1;
    resumeEngine();
    _advanceMission(QuestStep.matarHorda);
    final p = player;
    if (p != null) {
      // Use Tiled spawn points, cycling through them if fewer than 10.
      // Falls back to a single ring position so spawning never silently fails.
      final pts = _zombieSpawnPoints.isNotEmpty
          ? _zombieSpawnPoints
          : List.generate(10, (k) {
              final a = k * math.pi * 2 / 10;
              return Vector2(
                (p.position.x + math.cos(a) * 200).clamp(40.0, _mapSize.x - 40.0),
                (p.position.y + math.sin(a) * 200).clamp(40.0, _mapSize.y - 40.0),
              );
            });

      var spawnedCount = 0;
      var idx = 0;
      while (spawnedCount < 10) {
        final pt = pts[idx % pts.length];
        final z = ZumbiComponent(game: this, target: p)
          ..position = pt.clone()
          ..priority = 10;
        z.isAggressive = true; // force aggression
        _zombies.add(z);
        world.add(z);
        spawnedCount++;
        idx++;
      }
      debugPrint('Spawned $spawnedCount zombies.');
    }
    showHudMessage('Transmissao registrada! Elimine a horda de zumbis.');
    _syncAreaState().catchError((_) {});
  }

  void cancelRadioTune() {
    overlays.remove('RadioTune');
    dialogOpen.value = false;
    resumeEngine();
  }

  void onSenhaArmarioClosed() {
    overlays.remove('SenhaArmario');
    dialogOpen.value = false;
    resumeEngine();
    _pendingSenhaPickup?.collect();
    _pendingSenhaPickup = null;
    secretCodeCompleted = true;
    _advanceMission(QuestStep.pegarFusiveis);
    showHudMessage('Codigo anotado! Colete os fusiveis.');
    _syncAreaState().catchError((_) {});
  }

  // ── Dano / morte ───────────────────────────────────────────────────────────
  void damagePlayer(double amount) {
    if (gameOver.value) return;
    currentHealth.value = math.max(0, currentHealth.value - amount);
    FirebaseService.instance.updateStats(playerName, currentHealth: currentHealth.value.round()).catchError((_) {});
    if (currentHealth.value <= 0) {
      if (hasEmergencyMedkit && !usedReviveThisArea && emergencyMedkit.value > 0) {
        usedReviveThisArea = true;
        hasEmergencyMedkit = false;
        emergencyMedkit.value--;
        currentHealth.value = maxHealth.value * 0.45;
        FirebaseService.instance.updateInventoryItem(playerName, 'emergencyMedkit', -1).catchError((_) {});
        FirebaseService.instance.updateArea2State(playerName, {'usedRevive': true}).catchError((_) {});
        showHudMessage('Medikit usado! Voce sobreviveu.');
        return;
      }
      _triggerGameOver();
    }
  }

  void triggerMineDeath() {
    showHudMessage('Uma mina foi ativada.');
    currentHealth.value = 0;
    _triggerGameOver();
  }

  void _triggerGameOver() {
    gameOver.value = true;
    overlays.add('GameOver');
    pauseEngine();
  }

  void reviveAtCheckpoint() {
    overlays.remove('GameOver');
    gameOver.value = false;
    currentHealth.value = maxHealth.value;
    player?.position = Vector2(420, 430);
    resumeEngine();
  }

  void showHudMessage(String message) {
    hudMessage.value = message;
    Future<void>.delayed(const Duration(seconds: 3), () {
      if (hudMessage.value == message) hudMessage.value = null;
    });
  }

  void devSkipMission() {
    if (mainCompleted) {
      _openDialog(CafeteriaDialog.exitChoice);
      return;
    }
    mainCompleted = true;
    marcosTrust = 2;
    radioPowered = true;
    radioTuned = true;
    _fusesInstalled = 2;
    _advanceMission(QuestStep.concluirFase);
    FirebaseService.instance.completeArea2(playerName).catchError((_) {});
    _syncAreaState().catchError((_) {});
    _openDialog(CafeteriaDialog.reward);
  }

  // ── Firebase ───────────────────────────────────────────────────────────────
  Future<void> _loadSavedProgress() async {
    Map<String, int> inventory;
    Map<String, dynamic> area2State;
    try {
      inventory = await FirebaseService.instance.loadInventory(playerName);
    } catch (e) {
      debugPrint('loadInventory falhou: $e');
      inventory = {'emergencyMedkit': 0, 'stimulant': 0, 'maxHealthBonus': 0};
    }
    try {
      area2State = await FirebaseService.instance.loadArea2State(playerName);
    } catch (e) {
      debugPrint('loadArea2State falhou: $e');
      area2State = {};
    }

    emergencyMedkit.value = inventory['emergencyMedkit'] ?? 0;
    hasEmergencyMedkit = emergencyMedkit.value > 0;
    stimulantCount = inventory['stimulant'] ?? 0;
    stimulant.value = stimulantCount;

    final firebaseBonus = inventory['maxHealthBonus'] ?? 0;
    GameState.instance.syncMaxHealthBonus(firebaseBonus); // keep in-memory in sync
    final bonus = GameState.instance.maxHealthBonus;
    if (bonus > 0) {
      maxHealth.value = 100 + bonus.toDouble();
      currentHealth.value = maxHealth.value;
    }

    mainCompleted = area2State['mainCompleted'] == true;
    radioTuned = area2State['radioQuestCompleted'] == true;
    secretCodeCompleted = area2State['secretCodeCompleted'] == true;
    vitalBoostCollected = area2State['vitalBoostCollected'] == true;
    usedReviveThisArea = area2State['usedRevive'] == true;
    radioPowered = area2State['radioPowered'] == true;
    marcosTrust = area2State['marcosTrust'] is int ? area2State['marcosTrust'] as int : 0;
    brokenTablesCount = area2State['brokenTablesCount'] is int ? area2State['brokenTablesCount'] as int : 0;
    brokenTables.value = brokenTablesCount;

    final pieces = area2State['secretCodePieces'];
    if (pieces is List) {
      secretCodePieces.value = pieces.map((e) => e.toString()).toList();
    }

    if (mainCompleted) {
      missionText.value = 'Area 2 concluida. Explore ou siga para o CAA.';
    } else if (radioPowered) {
      _advanceMission(QuestStep.concluirFase);
    } else {
      final stepIndex = area2State['missionStep'] as int? ?? 0;
      if (stepIndex > 0 && stepIndex < QuestStep.values.length) {
        _advanceMission(QuestStep.values[stepIndex]);
      }
    }
  }

  Future<void> _syncAreaState() {
    return FirebaseService.instance.updateArea2State(playerName, {
      'mainCompleted': mainCompleted,
      'radioQuestCompleted': radioTuned,
      'secretCodeCompleted': secretCodeCompleted,
      'vitalBoostCollected': vitalBoostCollected,
      'marcosTrust': marcosTrust,
      'brokenTablesCount': brokenTablesCount,
      'usedRevive': usedReviveThisArea,
      'missionStep': mission.currentStep.index,
      'radioPowered': radioPowered,
      'secretCodePieces': secretCodePieces.value,
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CafeteriaPlayerComponent — cópia EXATA do PlayerComponent do H15 (funciona)
// ─────────────────────────────────────────────────────────────────────────────
enum CafPlayerAnim {
  idle, walkDown, walkLeft, walkRight, walkUp,
  attackDown, attackLeft, attackRight, attackUp,
}

class CafeteriaPlayerComponent
    extends SpriteAnimationGroupComponent<CafPlayerAnim> {
  static const double _speed = 180;
  static const int _cols = 4;
  static const int _rows = 3;
  static const double _trim = 1.0;
  static const double _walkStep = 0.14;
  static const double _atkStep  = 0.08;
  static const double _atkHold  = 0.15;
  // 64×64 matches NPC scale (Marcos 64×80, zombies 80×80) on the 1142×928 map.
  static final Vector2 visualSize = Vector2(64, 64);
  static final Vector2 _hbPos  = Vector2(22, 26);
  static final Vector2 _hbSize = Vector2(20, 29);

  bool _facingLeft = false;
  bool _isAttacking = false;
  double _atkHoldTimer = 0;
  CafPlayerAnim _lastMove = CafPlayerAnim.walkDown;
  Vector2? _lastSafe;

  CafeteriaPlayerComponent._({required Map<CafPlayerAnim, SpriteAnimation> a})
      : super(animations: a, current: CafPlayerAnim.idle,
              size: visualSize.clone(), anchor: Anchor.center);

  factory CafeteriaPlayerComponent.fromImage(ui.Image img) =>
      CafeteriaPlayerComponent._(a: _buildAnims(img));

  static Map<CafPlayerAnim, SpriteAnimation> _buildAnims(ui.Image img) {
    SpriteAnimation row(int r, {int n = _cols, double st = _walkStep, bool loop = true}) {
      final fw = (img.width  / _cols).floorToDouble();
      final fh = (img.height / _rows).floorToDouble();
      return SpriteAnimation.spriteList(
        List.generate(n, (c) => Sprite(img,
          srcPosition: Vector2(c * fw + _trim, r * fh + _trim),
          srcSize:     Vector2(fw - _trim * 2, fh - _trim * 2))),
        stepTime: st, loop: loop,
      );
    }
    return {
      CafPlayerAnim.idle:        row(0, n: 1),
      CafPlayerAnim.walkDown:    row(0),
      CafPlayerAnim.walkRight:   row(1),
      CafPlayerAnim.walkLeft:    row(2),
      CafPlayerAnim.walkUp:      row(0),
      CafPlayerAnim.attackDown:  row(0, st: _atkStep, loop: false),
      CafPlayerAnim.attackRight: row(1, st: _atkStep, loop: false),
      CafPlayerAnim.attackLeft:  row(2, st: _atkStep, loop: false),
      CafPlayerAnim.attackUp:    row(0, st: _atkStep, loop: false),
    };
  }

  void replaceWithWeaponSheet(ui.Image img) {
    final prev = current ?? CafPlayerAnim.idle;
    animations = _buildAnims(img);
    current = prev;
  }

  // ── Movimento com AABB wall-check (igual ao zombie) ──────────────────────
  void move(Vector2 dir, double dt, Vector2 mapSize, List<CafWall> walls) {
    if (dir.length2 <= 0) {
      if (!_isAttacking) current = CafPlayerAnim.idle;
      return;
    }
    final step = dir.normalized() * _speed * dt;
    if (!_isAttacking) {
      if (dir.x.abs() > dir.y.abs()) {
        _facingLeft = dir.x < 0;
        _lastMove = dir.x > 0 ? CafPlayerAnim.walkRight : CafPlayerAnim.walkLeft;
      } else {
        _lastMove = dir.y > 0 ? CafPlayerAnim.walkDown : CafPlayerAnim.walkUp;
      }
      current = _lastMove;
    }
    _tryMove(Vector2(step.x, 0), mapSize, walls);
    _tryMove(Vector2(0, step.y), mapSize, walls);
  }

  void _tryMove(Vector2 d, Vector2 mapSize, List<CafWall> walls) {
    _lastSafe = position.clone();
    position += d;
    position = Vector2(
      position.x.clamp(size.x / 2, mapSize.x - size.x / 2).toDouble(),
      position.y.clamp(size.y / 2, mapSize.y - size.y / 2).toDouble(),
    );
    if (_hitsWall(walls)) position = _lastSafe!;
  }

  bool _hitsWall(List<CafWall> walls) {
    final r = feetRect;
    for (final w in walls) {
      if (w.wallRect.overlaps(r)) return true;
    }
    return false;
  }

  void startAttack() {
    _isAttacking = true;
    _atkHoldTimer = 0;
    current = switch (_lastMove) {
      CafPlayerAnim.walkLeft  => CafPlayerAnim.attackLeft,
      CafPlayerAnim.walkRight => CafPlayerAnim.attackRight,
      CafPlayerAnim.walkUp    => CafPlayerAnim.attackUp,
      _                       => CafPlayerAnim.attackDown,
    };
    animationTicker?.reset();
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_isAttacking) {
      if (animationTicker?.done() ?? false) {
        _atkHoldTimer += dt;
        if (_atkHoldTimer >= _atkHold) {
          _isAttacking = false;
          _atkHoldTimer = 0;
          current = CafPlayerAnim.idle;
        }
      }
    }
    // Y-sort: with Anchor.center the visual "feet" are half a sprite below the
    // anchor, so we add size.y/2 to get the actual floor contact Y.
    // The same formula on the LockerComponent gives depth comparisons like:
    //   player.feet > locker.feet  →  player priority > locker priority  →  player in front
    //   player.feet < locker.feet  →  player priority < locker priority  →  player behind
    priority = (position.y + size.y / 2).ceil();
  }

  Rect get feetRect {
    final tl = Offset(position.x - size.x / 2 + _hbPos.x,
                      position.y - size.y / 2 + _hbPos.y);
    return Rect.fromLTWH(tl.dx, tl.dy, _hbSize.x, _hbSize.y);
  }

  Rect get attackHitRect {
    const range = 80.0;
    final cx = position.x + (_facingLeft ? -range * .5 : range * .5);
    return Rect.fromCenter(center: Offset(cx, position.y + 4), width: 90, height: 70);
  }

  @override
  void render(Canvas canvas) {
    canvas.drawOval(
      Rect.fromCenter(center: Offset(size.x / 2, size.y + 3),
          width: size.x * .85, height: 8),
      Paint()..color = Colors.black.withValues(alpha: 0.35),
    );
    if (animation != null) {
      super.render(canvas);
    } else {
      _fallback(canvas);
    }
  }

  void _fallback(Canvas canvas) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.x * .22, size.y * .30, size.x * .56, size.y * .54),
        const Radius.circular(8)),
      Paint()..color = const Color(0xFF1F6B1F));
    canvas.drawCircle(Offset(size.x / 2, size.y * .16), size.x * .24,
      Paint()..color = const Color(0xFFD4956A));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.x * .22, size.y * .30, size.x * .56, size.y * .54),
        const Radius.circular(8)),
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CafZombieComponent — transplantado do H15, adaptado para paredes/player do Amb2

// ─────────────────────────────────────────────────────────────────────────────
// MarcosComponent
// ─────────────────────────────────────────────────────────────────────────────
class MarcosComponent extends SpriteComponent with HasGameRef<CafeteriaGame> {
  MarcosComponent({required this.game})
      : super(size: Vector2(64, 80), anchor: Anchor.center);
  @override
  final CafeteriaGame game;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    try {
      sprite = Sprite(await gameRef.images.load('npcs/marcos_standalone.png'));
    } catch (e) {
      debugPrint('Marcos sprite falhou: $e');
    }
  }

  // Same guard as CafeteriaProp: Flame 1.37+ onMount() asserts sprite != null,
  // but this component renders a fallback when the asset isn't available.
  @override
  void onMount() {
    if (sprite != null) super.onMount();
  }

  @override
  void render(Canvas canvas) {
    // Sombra
    canvas.drawOval(
      Rect.fromCenter(center: Offset(size.x / 2, size.y + 2), width: size.x * .78, height: 8),
      Paint()..color = Colors.black.withValues(alpha: 0.38),
    );
    // Fallback SEMPRE primeiro — garante visibilidade
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.x * .28, size.y * .32, size.x * .44, size.y * .46),
        const Radius.circular(4)),
      Paint()..color = const Color(0xFF4B4636));
    canvas.drawCircle(Offset(size.x / 2, size.y * .22), size.x * .20,
      Paint()..color = const Color(0xFFC49A6C));
    // Indicador de NPC (círculo laranja)
    canvas.drawCircle(Offset(size.x / 2, -8), 6,
      Paint()..color = const Color(0xFFF59E0B));
    // Sprite por cima se carregado
    if (sprite != null) {
      super.render(canvas);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CafWall — parede de colisão simples
// ─────────────────────────────────────────────────────────────────────────────
class CafWall extends PositionComponent {
  static bool showDebug = false;

  CafWall({required Vector2 position, required Vector2 size})
      : super(position: position, size: size);

  Rect get wallRect => Rect.fromLTWH(position.x, position.y, size.x, size.y);

  @override
  void render(Canvas canvas) {
    if (!showDebug) return;
    canvas.drawRect(
      size.toRect(),
      Paint()..color = const Color(0x5500FF44),
    );
    canvas.drawRect(
      size.toRect(),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFF00FF44),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CafPropSpec / CafeteriaProp
// ─────────────────────────────────────────────────────────────────────────────
class CafPropSpec {
  CafPropSpec(this.kind, this.position, this.size, {this.asset});
  final String kind;
  final Vector2 position;
  final Vector2 size;
  final String? asset;
}

class CafeteriaProp extends SpriteComponent with HasGameRef<CafeteriaGame> {
  CafeteriaProp({required this.spec, required this.game})
      : super(position: spec.position, size: spec.size, anchor: Anchor.center);
  final CafPropSpec spec;
  @override
  final CafeteriaGame game;
  bool broken = false;
  String get kind => spec.kind;
  @override
  Vector2 get center => position;
  String get label => switch (kind) {
    'table' => 'QUEBRAR MESA',
    'areaC' => 'QUEBRAR BARRICADA',
    'secret1' || 'secret2' || 'secret3' => 'QUEBRAR BARRICADA',
    'lockedRoom' => 'DIGITAR CODIGO',
    _ => 'INTERAGIR',
  };

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    final path = spec.asset;
    if (path == null) return;
    try {
      sprite = Sprite(await gameRef.images.load(path));
    } catch (e) {
      debugPrint('Prop $kind sprite falhou: $e');
    }
  }

  @override
  void onMount() {
    if (sprite != null) super.onMount();
  }

  void breakProp() => broken = true;

  @override
  void render(Canvas canvas) {
    if (broken) {
      _renderBroken(canvas);
      return;
    }
    if (sprite != null) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(size.x / 2, size.y + 3), width: size.x * .85, height: 7),
        Paint()..color = Colors.black.withValues(alpha: 0.25));
      super.render(canvas);
      return;
    }
    _renderFallback(canvas);
  }

  void _renderBroken(Canvas canvas) {
    canvas.drawRect(
      Rect.fromCenter(center: Offset(size.x / 2, size.y / 2), width: size.x * .75, height: size.y * .32),
      Paint()..color = const Color(0xAA3B2415));
    canvas.drawLine(
      Offset(size.x * .18, size.y * .72), Offset(size.x * .82, size.y * .26),
      Paint()..color = const Color(0xFF2B1A10)..strokeWidth = 3);
    canvas.drawLine(
      Offset(size.x * .25, size.y * .30), Offset(size.x * .74, size.y * .70),
      Paint()..color = const Color(0xFF5A3A23)..strokeWidth = 3);
  }

  void _renderFallback(Canvas canvas) {
    final color = switch (kind) {
      'table' => const Color(0xFF6B4A2E),
      'areaC' => const Color(0xFF3F2B1B),
      _ => const Color(0xFF5A3A23),
    };
    canvas.drawRRect(
      RRect.fromRectAndRadius(size.toRect(), const Radius.circular(4)),
      Paint()..color = color);
    canvas.drawRRect(
      RRect.fromRectAndRadius(size.toRect().deflate(2), const Radius.circular(3)),
      Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = const Color(0xFFE7C77A));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CafeteriaPickup — generic item component.
// Add an entry to _kAssets when a new sprite becomes available; the component
// automatically falls back to a colored circle while the asset is missing.
// ─────────────────────────────────────────────────────────────────────────────
class CafeteriaPickup extends SpriteComponent {
  // Anchor.bottomCenter: position.y == floor contact point.
  // Sprites rest on the surface rather than hovering at sprite-centre height.
  CafeteriaPickup({required this.kind, required this.game})
      : super(size: Vector2(40, 40), anchor: Anchor.bottomCenter);

  final String kind;
  final CafeteriaGame game;
  bool collected = false;

  // Map each item kind to its asset path. Add new entries as sprites are created.
  static const _kAssets = <String, String>{
    'fuse':      'objects/fusivel.png',
    'pecinha':   'objects/pecinha.png',
    'radio':     'objects/radio.png',
    'radioPart': 'objects/pecaradio.png',
    'senha':     'objects/mapa.png',
    // 'vitalBoost': 'objects/vital_boost.png',
  };

  static const _kFallbackColors = <String, Color>{
    'fuse':       Color(0xFF60A5FA),
    'radioPart':  Color(0xFFFACC15),
    'radioPanel': Color(0xFF94A3B8),
    'radio':      Color(0xFF22C55E),
    'vitalBoost': Color(0xFFEF4444),
    'pecinha':    Color(0xFF22D3EE),
    'senha':      Color(0xFFFEF9E7),
  };

  String get label => switch (kind) {
    'fuse'       => 'PEGAR FUSIVEL',
    'radioPart'  => 'PEGAR PECA',
    'radioPanel' => 'USAR PAINEL',
    'radio'      => 'SINTONIZAR',
    'vitalBoost' => 'COLETAR',
    'pecinha'    => 'PEGAR PECA',
    'senha'      => 'LER NOTA',
    _            => 'PEGAR',
  };

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    final path = _kAssets[kind];
    if (path != null) {
      try {
        sprite = Sprite(await game.images.load(path));
        debugPrint('CafeteriaPickup[$kind]: $path loaded OK');
      } catch (e) {
        debugPrint('ERROR: Asset not found — $path ($e)');
      }
    }
  }

  // Flame 1.37+ asserts sprite != null in SpriteComponent.onMount(); guard it
  // so items without a sprite asset still mount cleanly and use _renderFallback.
  @override
  void onMount() {
    if (sprite != null) super.onMount();
  }

  void collect() {
    collected = true;
    removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    if (collected) return;
    if (sprite != null) {
      // Drop-shadow so the sprite reads against any map background.
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(size.x / 2, size.y + 3),
          width: size.x * 0.75,
          height: 7,
        ),
        Paint()..color = Colors.black.withValues(alpha: 0.35),
      );
      super.render(canvas);
    } else {
      _renderFallback(canvas);
    }
  }

  void _renderFallback(Canvas canvas) {
    if (kind == 'senha') {
      // Paper icon with golden border
      canvas.drawRRect(
        RRect.fromRectAndRadius(size.toRect(), const Radius.circular(2)),
        Paint()..color = const Color(0xFFFEF9E7),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(size.toRect().deflate(1), const Radius.circular(1)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = const Color(0xFFD4A017),
      );
      // Three "text" lines to suggest a document
      final linePaint = Paint()..color = const Color(0xFF9B7E35)..strokeWidth = 1;
      for (var i = 0; i < 3; i++) {
        final y = size.y * (0.30 + i * 0.20);
        canvas.drawLine(Offset(size.x * 0.18, y), Offset(size.x * 0.82, y), linePaint);
      }
      return;
    }
    final color = _kFallbackColors[kind] ?? Colors.white;
    final r = size.x / 2 - 2;
    final c = Offset(size.x / 2, size.y / 2);
    canvas.drawCircle(c, r, Paint()..color = color.withValues(alpha: .9));
    canvas.drawCircle(c, r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white70);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ImpactFlash — efeito de sangue no hit (igual ao H15)
// ─────────────────────────────────────────────────────────────────────────────
class _BloodParticle {
  Vector2 pos = Vector2.zero();
  Vector2 vel;
  final double radius;
  final Color color;
  _BloodParticle({required this.vel, required this.radius, required this.color});
}

// ─────────────────────────────────────────────────────────────────────────────
// ElectricalPanelComponent — fixed prop that opens the Fuse Box minigame.
// Swap the commented asset path for a real sprite when one is available.
// ─────────────────────────────────────────────────────────────────────────────
class ElectricalPanelComponent extends SpriteComponent {
  ElectricalPanelComponent({required this.game})
      : super(size: Vector2(80, 60), anchor: Anchor.center);

  final CafeteriaGame game;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    try {
      sprite = Sprite(await game.images.load('objects/painelfusivel.png'));
    } catch (_) {}
  }

  @override
  void onMount() {
    if (sprite != null) super.onMount();
  }

  @override
  void render(Canvas canvas) {
    if (sprite != null) {
      super.render(canvas);
    } else {
      _renderFallback(canvas);
    }
  }

  void _renderFallback(Canvas canvas) {
    // Panel body
    canvas.drawRRect(
      RRect.fromRectAndRadius(size.toRect(), const Radius.circular(3)),
      Paint()..color = const Color(0xFF1F2937),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(size.toRect().deflate(2), const Radius.circular(2)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0xFF374151),
    );
    // Status LED: amber = waiting for fuses, green = powered
    final ledColor = game.radioPowered
        ? const Color(0xFF4ADE80)
        : const Color(0xFFF59E0B);
    canvas.drawCircle(
      Offset(size.x * 0.80, size.y * 0.22),
      5,
      Paint()..color = ledColor,
    );
    canvas.drawCircle(
      Offset(size.x * 0.80, size.y * 0.22),
      5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = ledColor.withValues(alpha: 0.5),
    );
    // Two fuse-slot outlines
    for (var i = 0; i < 2; i++) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            size.x * 0.12 + i * (size.x * 0.38),
            size.y * 0.30,
            size.x * 0.28,
            size.y * 0.52,
          ),
          const Radius.circular(2),
        ),
        Paint()
          ..color = game.radioPowered
              ? const Color(0xFF064E3B)
              : const Color(0xFF111827),
      );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LockerComponent — two-state cabinet using armarioabertoefechado.png.
// The image is expected to be a horizontal sprite sheet:
//   left  half → closed state
//   right half → open state
// Adjust srcPosition / srcSize if your image layout differs.
// ─────────────────────────────────────────────────────────────────────────────
class LockerComponent extends SpriteComponent {
  // 80×110: clearly taller than the 64px player for a readable 3/4 silhouette.
  // Anchor.bottomCenter means position.y == floor contact point, which is exactly
  // what Y-sort needs: depth = how far south the base of the object is.
  LockerComponent({required this.game})
      : super(size: Vector2(80, 110), anchor: Anchor.bottomCenter);

  final CafeteriaGame game;
  bool isOpen = false;

  Sprite? _closedSprite;
  Sprite? _openSprite;

  // Y-sort: with Anchor.bottomCenter, position.y IS the floor contact point.
  // priority = position.y → objects with a lower Y (further "up" on screen)
  // render behind objects with a higher Y (further "down"), which is exactly
  // the 3/4-view depth ordering a player expects.
  @override
  void update(double dt) {
    super.update(dt);
    priority = position.y.ceil();
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    try {
      final img = await game.images.load('objects/armarioabertoefechado.png');
      final halfW = (img.width / 2).toDouble();
      final h = img.height.toDouble();
      _closedSprite = Sprite(img,
          srcPosition: Vector2.zero(), srcSize: Vector2(halfW, h));
      _openSprite = Sprite(img,
          srcPosition: Vector2(halfW, 0), srcSize: Vector2(halfW, h));
      sprite = _closedSprite;
    } catch (e) {
      debugPrint('LockerComponent sprite failed: $e');
    }
  }

  @override
  void onMount() {
    if (sprite != null) super.onMount();
  }

  void openLocker() {
    isOpen = true;
    sprite = _openSprite;
  }

  @override
  void render(Canvas canvas) {
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.x / 2, size.y + 4),
        width: size.x * 0.75,
        height: 8,
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.35),
    );
    if (sprite != null) {
      super.render(canvas);
    } else {
      _renderFallback(canvas);
    }
  }

  void _renderFallback(Canvas canvas) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(size.toRect(), const Radius.circular(4)),
      Paint()..color = isOpen ? const Color(0xFF111827) : const Color(0xFF374151),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(size.toRect().deflate(2), const Radius.circular(3)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = isOpen ? const Color(0xFF4B5563) : const Color(0xFF9CA3AF),
    );
    if (!isOpen) {
      // Lock icon
      canvas.drawCircle(Offset(size.x / 2, size.y * 0.48), 9,
          Paint()..color = const Color(0xFF9CA3AF));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
              center: Offset(size.x / 2, size.y * 0.60), width: 14, height: 11),
          const Radius.circular(2),
        ),
        Paint()..color = const Color(0xFF6B7280),
      );
    } else {
      // Open glow
      canvas.drawRRect(
        RRect.fromRectAndRadius(size.toRect().deflate(10), const Radius.circular(3)),
        Paint()..color = const Color(0xFF064E3B),
      );
    }
  }
}

class ImpactFlash extends PositionComponent {
  static const _dur = 0.38;
  static const _count = 6;
  static const _palette = [Color(0xFFCC0000), Color(0xFF990000), Color(0xFFFF3333)];
  double _elapsed = 0;
  late final List<_BloodParticle> _particles;
  final math.Random _rng = math.Random();

  ImpactFlash({required Vector2 position})
      : super(position: position, size: Vector2(70, 70), anchor: Anchor.center);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _particles = List.generate(_count, (i) {
      final angle = (i / _count) * math.pi * 2 + _rng.nextDouble() * 0.5;
      final speed = 40.0 + _rng.nextDouble() * 50.0;
      return _BloodParticle(
        vel: Vector2(math.cos(angle) * speed, math.sin(angle) * speed),
        radius: 2.0 + _rng.nextDouble() * 2.5,
        color: _palette[i % _palette.length],
      );
    });
  }

  @override
  void update(double dt) {
    super.update(dt);
    _elapsed += dt;
    if (_elapsed >= _dur) { removeFromParent(); return; }
    for (final p in _particles) {
      p.pos += p.vel * dt;
      p.vel.scale(math.max(0, 1 - dt * 6));
    }
  }

  @override
  void render(Canvas canvas) {
    final t = (_elapsed / _dur).clamp(0.0, 1.0);
    final alpha = (1.0 - t * t).clamp(0.0, 1.0);
    final half = size / 2;
    for (final p in _particles) {
      canvas.drawCircle(
        Offset(half.x + p.pos.x, half.y + p.pos.y), p.radius,
        Paint()..color = p.color.withValues(alpha: alpha));
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CafeteriaFallbackMap
// ─────────────────────────────────────────────────────────────────────────────
class CafeteriaFallbackMap extends PositionComponent {
  CafeteriaFallbackMap({required Vector2 size}) : super(size: size);

  @override
  void render(Canvas canvas) {
    canvas.drawRect(size.toRect(), Paint()..color = const Color(0xFF24211C));
    final tile = Paint()..color = const Color(0xFF3A3329)..style = PaintingStyle.stroke;
    for (var x = 0.0; x < size.x; x += 48) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.y), tile);
    }
    for (var y = 0.0; y < size.y; y += 48) {
      canvas.drawLine(Offset(0, y), Offset(size.x, y), tile);
    }
    // área segura de Marcos em verde
    canvas.drawRect(
      const Rect.fromLTWH(560, 590, 300, 175),
      Paint()..color = const Color(0x3322C55E));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ArmarioComponent — password-protected cabinet with a +20 HP/maxHP reward.
//
// Sprite loading order:
//   1. armario.png          (dedicated closed sprite — add to assets when ready)
//   2. armarioabertoefechado.png left half  (fallback closed state)
//   3. Pure Canvas fallback if both assets fail.
//
// Interaction flow:
//   Player walks within 90 px → "ABRIR ARMARIO" prompt.
//   Player taps INTERAGIR → CafeteriaGame.openLockerKeypad() → overlay.
//   Player enters correct PIN → onLockerCorrectCode() → openArmario().
//   openArmario(): sprite → open state, isOpened = true (idempotent).
//   CafeteriaGame.onArmarioOpened(): maxHealth/currentHealth += 20.
//
// Collision:
//   RectangleHitbox (passive) — for future enemy collision callbacks.
//   _spawnArmario() also adds a CafWall at the same footprint so the
//   player movement system (rect-based, not Flame events) is blocked.
// ─────────────────────────────────────────────────────────────────────────────
class ArmarioComponent extends SpriteComponent {
  // Fixed display size: 80×140 ensures the cabinet is visually taller than
  // the 64px player. Anchor.bottomCenter: position.y == floor contact point.
  ArmarioComponent({required this.game})
      : super(size: Vector2(80, 140), anchor: Anchor.bottomCenter);

  final CafeteriaGame game;
  bool isOpened = false;

  Sprite? _openSprite;

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    // Attempt 1 — dedicated armario.png.
    bool loaded = false;
    try {
      final img = await game.images.load('objects/armario.png');
      sprite = Sprite(img);
      loaded = true;
    } catch (e) {
      debugPrint('ERROR: Asset not found — objects/armario.png ($e)');
    }

    // Attempt 2 — left half of armarioabertoefechado.png.
    if (!loaded) {
      try {
        final img =
            await game.images.load('objects/armarioabertoefechado.png');
        final halfW = (img.width / 2).toDouble();
        final h = img.height.toDouble();
        sprite = Sprite(img,
            srcPosition: Vector2.zero(), srcSize: Vector2(halfW, h));
        _openSprite = Sprite(img,
            srcPosition: Vector2(halfW, 0), srcSize: Vector2(halfW, h));
      } catch (e) {
        debugPrint('ERROR: Asset not found — objects/armarioabertoefechado.png ($e)');
      }
    }

    add(RectangleHitbox(collisionType: CollisionType.passive)
      ..debugMode = false);
  }

  @override
  void onMount() {
    if (sprite != null) super.onMount();
  }

  // Called after correct PIN — flips sprite to open state (idempotent).
  void openArmario() {
    if (isOpened) return;
    isOpened = true;
    if (_openSprite != null) sprite = _openSprite;
  }

  // Y-sort: with Anchor.bottomCenter, position.y IS the floor contact point.
  @override
  void update(double dt) {
    super.update(dt);
    priority = position.y.ceil();
  }

  @override
  void render(Canvas canvas) {
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.x / 2, size.y + 4),
        width: size.x * 0.80,
        height: 10,
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.35),
    );
    if (sprite != null) {
      super.render(canvas);
    } else {
      _renderFallback(canvas);
    }
  }

  void _renderFallback(Canvas canvas) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(size.toRect(), const Radius.circular(4)),
      Paint()
        ..color =
            isOpened ? const Color(0xFF111827) : const Color(0xFF374151),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(size.toRect().deflate(2), const Radius.circular(3)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color =
            isOpened ? const Color(0xFF4B5563) : const Color(0xFF9CA3AF),
    );
    if (!isOpened) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
              center: Offset(size.x * 0.88, size.y / 2), width: 6, height: 20),
          const Radius.circular(2),
        ),
        Paint()..color = const Color(0xFF9CA3AF),
      );
    } else {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            size.toRect().deflate(10), const Radius.circular(3)),
        Paint()..color = const Color(0xFF064E3B),
      );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _CafSwordHitbox — short-lived Flame collision hitbox for melee attacks.
//
// Lifecycle: spawned once per attack(), lives ~0.08 s (5 frames at 60 fps),
// then removes itself. During that window Flame's broad-phase detects overlap
// with CafeteriaZombieComponent.RectangleHitbox (CollisionType.active).
//
// onCollisionStart fires once per zombie per swing (_fired guard).
// The manual _resolveAttack() runs in the same frame as a zero-latency backup;
// this hitbox provides the CollisionCallbacks path the user requested.
// ─────────────────────────────────────────────────────────────────────────────
class _CafSwordHitbox extends PositionComponent with CollisionCallbacks {
  _CafSwordHitbox({
    required this.game,
    required Vector2 worldPos,
    required Vector2 sz,
  }) : super(position: worldPos, size: sz, anchor: Anchor.center);

  final CafeteriaGame game;
  bool _fired = false;
  double _life = 0;
  static const double _maxLife = 0.08; // ~5 frames

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    debugMode = false;
    add(RectangleHitbox(collisionType: CollisionType.active)..debugMode = false);
  }

  @override
  void onCollisionStart(Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollisionStart(intersectionPoints, other);
    if (_fired) return;
    // `other` is the zombie's RectangleHitbox; its parent is the zombie.
    final zombie = other.parent;
    if (zombie is ZumbiComponent) {
      _fired = true;
      debugPrint('[COMBAT] SwordHitbox → zombie hit (CollisionCallbacks path)');
      final pos = zombie.position.clone();
      final dead = zombie.takeDamage(10);
      if (dead) {
        game._zombies.remove(zombie);
        zombie.removeFromParent();
        game.world.add(ImpactFlash(position: pos)..priority = 18);
        game.zombiesKilled.value++;
      }
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    _life += dt;
    if (_life >= _maxLife) removeFromParent();
  }
}
