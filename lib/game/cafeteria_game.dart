import 'dart:async' as async;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/experimental.dart' show Rectangle;
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/firebase_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Enums
// ─────────────────────────────────────────────────────────────────────────────
enum CafeteriaDialog { marcosIntro, marcosSecond, reward, exitChoice }

enum CafZombieAnim { idle, walkDown, walkLeft, walkRight, walkUp }

// ─────────────────────────────────────────────────────────────────────────────
// CafeteriaGame
// ─────────────────────────────────────────────────────────────────────────────
class CafeteriaGame extends FlameGame with HasCollisionDetection {
  CafeteriaGame({required this.playerName});

  @override
  bool get debugMode => false; // Suppresses Flame hitbox/bounds debug rendering.

  final String playerName;
  final math.Random _rng = math.Random();
  static final Vector2 _mapSize = Vector2(1142, 928);

  CafeteriaPlayerComponent? player;
  JoystickComponent? _joystick;
  SpriteComponent? _background;
  MarcosComponent? _marcos;
  ElectricalPanelComponent? _panel;
  LockerComponent? _locker;
  final List<CafeteriaZombieComponent> _zombies = [];
  final List<CafeteriaProp> _props = [];
  final List<CafeteriaPickup> _pickups = [];
  final List<CafWall> _walls = [];

  // ── HUD state ──────────────────────────────────────────────────────────────
  final ValueNotifier<double> currentHealth = ValueNotifier(100);
  final ValueNotifier<double> maxHealth = ValueNotifier(100);
  final ValueNotifier<String> missionText =
      ValueNotifier('Missao: atravesse o refeitorio ate Marcos.');
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
  bool areaCQuestStarted = false;
  bool areaCBarricadeBroken = false;
  bool radioPowered = false;
  bool radioTuned = false;
  bool secretCodeCompleted = false;
  bool vitalBoostCollected = false;
  bool mainCompleted = false;
  int _mainStep = 0;
  int _fusesInstalled = 0;
  int _defensesReinforced = 0;
  async.Timer? _stimTimer;
  double _tableDamageCooldown = 0;

  @override
  Color backgroundColor() => Colors.black;

  // ── onLoad ─────────────────────────────────────────────────────────────────
  @override
  Future<void> onLoad() async {
    await super.onLoad();

    // ── Mesma ordem do H15 que funciona ──────────────────────────────────────
    // 1. Posição inicial da câmera (sem zoom/bounds ainda)
    camera.viewfinder.anchor = Anchor.center;
    camera.viewfinder.position = Vector2(420, 430);

    // 2. Background
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

    // 3. Paredes
    _addBorderWalls();
    _setupStaticWalls();

    // 4. Player — carrega sprite e aguarda montagem (igual ao H15)
    late final ui.Image playerImg;
    try {
      playerImg = await images.load('player/player_sprite.jpg');
    } catch (_) {
      // Fallback 1×1 transparente
      final rec = ui.PictureRecorder();
      ui.Canvas(rec).drawRect(const ui.Rect.fromLTWH(0,0,1,1), ui.Paint());
      playerImg = await rec.endRecording().toImage(1, 1);
    }
    final playerComp = CafeteriaPlayerComponent.fromImage(playerImg)
      ..position = Vector2(420, 430)
      ..priority = 5;
    player = playerComp;
    await world.add(playerComp);

    // 5. Zoom + bounds + follow — DEPOIS do player estar montado.
    // The zoom must be high enough that the viewport (size / zoom) never exceeds
    // the map dimensions, otherwise Flame cannot satisfy the bounds constraint
    // and the black void bleeds in at the edges.
    final minZoom = math.max(size.x / _mapSize.x, size.y / _mapSize.y);
    camera.viewfinder.zoom = math.max(minZoom, 1.5);
    camera.setBounds(Rectangle.fromLTWH(0, 0, _mapSize.x, _mapSize.y));
    camera.follow(playerComp, snap: true);

    // 6. Arma salva do H15
    FirebaseService.instance.loadWeapon().then((weapon) async {
      if (weapon == null || weapon.isEmpty) return;
      final asset = weapon == 'Duas Adagas'
          ? 'player/player_espada2mao.png'
          : 'player/player_espada1mao.png';
      try {
        final img = await images.load(asset);
        player?.replaceWithWeaponSheet(img);
        showHudMessage('Arma: $weapon');
      } catch (e) {
        debugPrint('Weapon sprite: $e');
      }
    }).catchError((_) {});

    // 7. NPCs, props, zumbis, joystick
    // Marcos fica no armazém de suprimentos — lado direito do mapa
    _marcos = MarcosComponent(game: this)
      ..position = Vector2(870, 490)
      ..priority = 8;
    world.add(_marcos!);

    _setupProps();
    _spawnInitialZombies();
    _setupJoystick();

    // 8. Dica inicial
    Future<void>.delayed(const Duration(milliseconds: 800), () {
      if (!gameOver.value) showHudMessage('Encontre Marcos no armazem de suprimentos.');
    });

    // 9. Firebase em background
    _loadSavedProgress()
        .timeout(const Duration(seconds: 6))
        .catchError((e) => debugPrint('_loadSavedProgress falhou: $e'));

    _syncAreaState().catchError((e) => debugPrint('_syncAreaState onLoad: $e'));
  }

  void _addBorderWalls() {
    const t = 8.0;
    final ms = _mapSize;
    for (final spec in [
      // top, bottom, left, right
      [Vector2.zero(), Vector2(ms.x, t)],
      [Vector2(0, ms.y - t), Vector2(ms.x, t)],
      [Vector2.zero(), Vector2(t, ms.y)],
      [Vector2(ms.x - t, 0), Vector2(t, ms.y)],
    ]) {
      final w = CafWall(position: spec[0], size: spec[1]);
      _walls.add(w);
      world.add(w);
    }
  }

  void _setupStaticWalls() {
    // Sem colisão de paredes — mesas causam dano se não quebradas primeiro
    // Ver _checkTableDamage() no update()
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
  // anchor must be Anchor.center (all props and pickups use this).
  Vector2 _clampToMap(Vector2 center, Vector2 size) => Vector2(
        center.x.clamp(size.x / 2, _mapSize.x - size.x / 2).toDouble(),
        center.y.clamp(size.y / 2, _mapSize.y - size.y / 2).toDouble(),
      );

  void _setupProps() {
    // Props visuais alinhados com as paredes (1142×928)
    final specs = [
      // Mesas visíveis — alinham com CafWall da fileira 1
      CafPropSpec('table', Vector2(170, 183), Vector2(130, 52), asset: 'objects/table_front.png'),
      CafPropSpec('table', Vector2(450, 183), Vector2(130, 52), asset: 'objects/table_s.png'),
      // Mesa adicional entre gap e lado direito
      CafPropSpec('table', Vector2(620, 183), Vector2(130, 52), asset: 'objects/table_e.png'),

      // Mesas visíveis — fileira 2
      CafPropSpec('table', Vector2(160, 318), Vector2(130, 52), asset: 'objects/table_n.png'),
      CafPropSpec('table', Vector2(510, 358), Vector2(90, 100), asset: 'objects/table_ne.png'),
      CafPropSpec('table', Vector2(700, 358), Vector2(92, 100), asset: 'objects/table_se.png'),

      // Barricada da Área C — lado direito do mapa
      CafPropSpec('areaC', Vector2(955, 400), Vector2(130, 58), asset: 'objects/table_w.png'),

      // Barricadas do código secreto (417) — em áreas exploráveis
      CafPropSpec('secret1', Vector2(200, 520), Vector2(94, 44), asset: 'objects/table_e.png'),
      CafPropSpec('secret2', Vector2(780, 620), Vector2(94, 44), asset: 'objects/table_e.png'),
      CafPropSpec('secret3', Vector2(1000, 580), Vector2(94, 44), asset: 'objects/table_e.png'),

      // Pontos de defesa ao redor do armazém de Marcos
      CafPropSpec('defense', Vector2(700, 560), Vector2(60, 42)),
      CafPropSpec('defense', Vector2(820, 590), Vector2(60, 42)),
      CafPropSpec('defense', Vector2(940, 520), Vector2(60, 42)),
    ];
    for (final spec in specs) {
      final safePos = _clampToMap(spec.position, spec.size);
      final safeSpec = CafPropSpec(spec.kind, safePos, spec.size, asset: spec.asset);
      final prop = CafeteriaProp(spec: safeSpec, game: this)..priority = 8;
      _props.add(prop);
      world.add(prop);
    }

    // Pickups posicionados no mapa
    _addPickup('radioPart', Vector2(1020, 320));  // Área C — atrás da barricada
    _addPickup('fuse',      Vector2(260, 180));   // Cozinha — perto das mesas superiores
    _addPickup('fuse',      Vector2(900, 700));   // Armazém — perto de Marcos
    _addPickup('radio',      Vector2(855, 660));  // Armazém — rádio
    _addPickup('vitalBoost', Vector2(1090, 780)); // Sala secreta (código 417)

    // Electrical panel — replaces the old 'radioPanel' CafeteriaPickup.
    _panel = ElectricalPanelComponent(game: this)
      ..position = _clampToMap(Vector2(810, 660), Vector2(80, 60))
      ..priority = 8;
    world.add(_panel!);

    // Locker — replaces the old 'lockedRoom' CafeteriaProp.
    // Uses armarioabertoefechado.png (left half = closed, right half = open).
    // With Anchor.bottomCenter, Y=740 is the floor contact point (wall base).
    // Seed priority to the Y-sort value to avoid a one-frame z-pop on spawn.
    const lockerBaseY = 740.0;
    _locker = LockerComponent(game: this)
      ..position = Vector2(1075, lockerBaseY)
      ..priority = lockerBaseY.ceil();
    world.add(_locker!);
  }

  // Display size per item kind (used for both visual sizing and boundary clamping).
  static Vector2 _pickupDisplaySize(String kind) => switch (kind) {
    'fuse'      => Vector2(24, 24),   // small — lies on the floor
    'radioPart' => Vector2(20, 20),
    'radio'     => Vector2(32, 24),
    'vitalBoost'=> Vector2(26, 26),
    _           => Vector2(36, 36),
  };

  // Floor items render under the player (priority 1); interactive props stay above (6).
  static bool _isFloorItem(String kind) =>
      kind == 'fuse' || kind == 'radioPart' || kind == 'vitalBoost';

  void _addPickup(String kind, Vector2 pos) {
    if (kind == 'vitalBoost' && vitalBoostCollected) return;
    if ((kind == 'fuse' || kind == 'radioPart') && mainCompleted) return;
    final displaySize = _pickupDisplaySize(kind);
    final pickup = CafeteriaPickup(kind: kind, game: this)
      ..position = _clampToMap(pos, displaySize)
      ..size = displaySize
      ..priority = _isFloorItem(kind) ? 1 : 6;
    // Randomise angle for floor items so they look naturally dropped.
    if (_isFloorItem(kind)) {
      pickup.angle = _rng.nextDouble() * math.pi * 2;
    }
    _pickups.add(pickup);
    world.add(pickup);
  }

  void _spawnInitialZombies() {
    // Zumbi próximo — fica agressivo quando o jogador se aproxima (~200px)
    _spawnZombie(Vector2(310, 520), passive: true);
    // Zumbis espalhados pelo mapa
    _spawnZombie(Vector2(750, 195), passive: true);
    _spawnZombie(Vector2(980, 460), passive: true);
    _spawnZombie(Vector2(360, 700), passive: true);
  }

  void _spawnZombie(Vector2 pos, {bool passive = false}) {
    final p = player;
    if (p == null) return;
    final z = CafeteriaZombieComponent(game: this, target: p, passive: passive)
      ..position = pos
      ..priority = 15;
    _zombies.add(z);
    world.add(z);
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
    // Locker (only interactive while closed)
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
    _zombies.removeWhere((z) => !z.isMounted || !z.isAlive);
  }

  // ── Ataque do jogador ──────────────────────────────────────────────────────
  void attack() {
    if (!attackEnabled.value) return;
    player?.startAttack();
    _resolveAttack();
  }

  void _resolveAttack() {
    final p = player;
    if (p == null) return;
    final attackRect = p.attackHitRect;
    // Snapshot prevents ConcurrentModificationError when takeDamage removes a
    // zombie from _zombies mid-iteration.
    for (final z in List.of(_zombies)) {
      if (!z.isAlive || !z.isMounted) continue;
      if (attackRect.overlaps(z.hitRect)) {
        final wasAlive = z.isAlive;
        z.takeDamage(9 + _rng.nextInt(3));
        if (wasAlive && !z.isAlive) {
          // Zombie just died — spawn impact flash at its last known position.
          world.add(ImpactFlash(position: z.position.clone())..priority = 18);
        }
      }
    }
  }

  // ── Interação ──────────────────────────────────────────────────────────────
  void interact() {
    final target = _nearby;
    if (target == null) return;
    if (target is MarcosComponent) {
      if (_mainStep == 0) {
        _openDialog(CafeteriaDialog.marcosIntro);
      } else if (_mainStep == 4 && mainCompleted) {
        _openDialog(CafeteriaDialog.exitChoice);
      } else {
        showHudMessage('Marcos observa em silencio.');
      }
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
        showHudMessage('Mesa quebrada. Barulho: $brokenTablesCount/$maxSafeBrokenTables');
        _syncAreaState().catchError((_) {});
        if (brokenTablesCount > maxSafeBrokenTables && !zombiesAlerted) {
          zombiesAlerted = true;
          showHudMessage('O barulho chamou mortos!');
          for (var i = 0; i < 4; i++) {
            _spawnZombie(Vector2(980 + _rng.nextDouble() * 80, 160 + i * 90.0));
          }
        }
      case 'areaC':
        if (!areaCQuestStarted) {
          showHudMessage('A barricada esta presa. Fale com Marcos.');
          return;
        }
        prop.breakProp();
        areaCBarricadeBroken = true;
        showHudMessage('Area C aberta. Muitos zumbis acordaram!');
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
      case 'defense':
        if (_mainStep < 3) {
          showHudMessage('Ainda nao e hora de reforcar.');
          return;
        }
        prop.breakProp();
        _defensesReinforced++;
        showHudMessage('Defesa reforcada ($_defensesReinforced/3).');
        if (_defensesReinforced >= 3) _completeMainMissions();
      default:
        break;
    }
  }

  void _collectPickup(CafeteriaPickup pickup) {
    switch (pickup.kind) {
      case 'radioPart':
        if (!areaCBarricadeBroken) {
          showHudMessage('Esta atras da barricada da Area C.');
          return;
        }
        pickup.collect();
        _mainStep = 2;
        missionText.value = 'Missao: encontre 2 fusiveis e religue o radio.';
        showHudMessage('Bateria coletada!');
      case 'fuse':
        if (_mainStep < 2) {
          showHudMessage('Um fusivel. Melhor usar depois.');
          return;
        }
        pickup.collect();
        _fusesInstalled++;
        showHudMessage('Fusivel coletado ($_fusesInstalled/2).');
      case 'radio':
        if (!radioPowered) {
          showHudMessage('O radio ainda nao tem energia.');
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
    }
  }

  // ── Panel & Locker interactions ───────────────────────────────────────────

  void _interactPanel() {
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
    _locker?.openLocker();
    secretCodeCompleted = true;
    showHudMessage('Armario aberto! Coleta o Reforco Vital.');
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
    _mainStep = 3;
    missionText.value = 'Missao: reforce os 3 pontos da area segura.';
    showHudMessage('Painel ligado! Radio disponivel.');
    for (var i = 0; i < 3; i++) {
      _spawnZombie(Vector2(230 + i * 110.0, 520), passive: true);
    }
    _syncAreaState().catchError((_) {});
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
    areaCQuestStarted = true;
    _mainStep = 1;
    missionText.value = 'Missao: quebre a barricada da Area C.';
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
    _mainStep = 4;
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
    showHudMessage('Transmissao militar registrada.');
    _syncAreaState().catchError((_) {});
  }

  void cancelRadioTune() {
    overlays.remove('RadioTune');
    dialogOpen.value = false;
    resumeEngine();
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
    _mainStep = 4;
    marcosTrust = 2;
    areaCQuestStarted = true;
    areaCBarricadeBroken = true;
    radioPowered = true;
    radioTuned = true;
    missionText.value = 'Area 2 concluida!';
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

    final bonus = inventory['maxHealthBonus'] ?? 0;
    if (bonus > 0) {
      maxHealth.value = 100 + bonus.toDouble();
      currentHealth.value = maxHealth.value;
    }

    mainCompleted = area2State['mainCompleted'] == true;
    radioTuned = area2State['radioQuestCompleted'] == true;
    secretCodeCompleted = area2State['secretCodeCompleted'] == true;
    vitalBoostCollected = area2State['vitalBoostCollected'] == true;
    usedReviveThisArea = area2State['usedRevive'] == true;
    areaCQuestStarted = area2State['areaCQuestStarted'] == true;
    areaCBarricadeBroken = area2State['areaCBarricadeBroken'] == true;
    radioPowered = area2State['radioPowered'] == true;
    marcosTrust = area2State['marcosTrust'] is int ? area2State['marcosTrust'] as int : 0;
    brokenTablesCount = area2State['brokenTablesCount'] is int ? area2State['brokenTablesCount'] as int : 0;
    brokenTables.value = brokenTablesCount;

    final pieces = area2State['secretCodePieces'];
    if (pieces is List) {
      secretCodePieces.value = pieces.map((e) => e.toString()).toList();
    }

    if (mainCompleted) {
      _mainStep = 4;
      missionText.value = 'Area 2 concluida. Explore ou siga para o CAA.';
    } else if (radioPowered) {
      _mainStep = 3;
      missionText.value = 'Missao: reforce os 3 pontos da area segura.';
    } else if (areaCQuestStarted) {
      _mainStep = areaCBarricadeBroken ? 2 : 1;
      missionText.value = areaCBarricadeBroken
          ? 'Missao: encontre 2 fusiveis e religue o radio.'
          : 'Missao: quebre a barricada da Area C.';
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
      'areaCQuestStarted': areaCQuestStarted,
      'areaCBarricadeBroken': areaCBarricadeBroken,
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
// CafeteriaZombieComponent — sprite animado + HP + flash + dano por toque
// ─────────────────────────────────────────────────────────────────────────────
class CafeteriaZombieComponent extends SpriteAnimationComponent
    with HasGameRef<CafeteriaGame> {
  static const double _speed = 46;
  static const double _hitCooldown = 1.2;
  static final Vector2 _frameSize = Vector2(148, 140);

  @override
  final CafeteriaGame game;
  final CafeteriaPlayerComponent target;
  bool passive;
  bool isAlive = true;
  int hp = 100;
  double _hurtTimer = 0;
  double _hitCooldownTimer = 0;
  CafZombieAnim _currentAnim = CafZombieAnim.idle;
  final Map<CafZombieAnim, SpriteAnimation> _animations = {};

  CafeteriaZombieComponent({required this.game, required this.target, this.passive = false})
      : super(size: Vector2(80, 80), anchor: Anchor.center);

  Rect get hitRect => Rect.fromCenter(
    center: Offset(position.x, position.y),
    width: size.x * 0.70,
    height: size.y * 0.72,
  );

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    try {
      final sheet = await gameRef.images.load('zumbis/zumbi_normal.png');
      _animations.addAll(_buildAnims(sheet));
      _setAnim(CafZombieAnim.idle);
    } catch (e) {
      debugPrint('Zumbi sprite falhou: $e');
    }
    add(RectangleHitbox(
      position: Vector2(size.x * .15, size.y * .14),
      size: Vector2(size.x * .70, size.y * .72),
    ));
  }

  static Map<CafZombieAnim, SpriteAnimation> _buildAnims(ui.Image img) {
    SpriteAnimation row({required double yOffset, double st = 0.15}) =>
        SpriteAnimation.fromFrameData(img,
          SpriteAnimationData.sequenced(
            amount: 4, stepTime: st,
            textureSize: _frameSize,
            texturePosition: Vector2(0, yOffset),
          ));
    return {
      CafZombieAnim.idle: row(yOffset: 0),
      CafZombieAnim.walkDown: row(yOffset: 0),
      CafZombieAnim.walkRight: row(yOffset: 140),
      CafZombieAnim.walkLeft: row(yOffset: 280),
      CafZombieAnim.walkUp: row(yOffset: 0),
    };
  }

  void _setAnim(CafZombieAnim next) {
    if (_currentAnim == next && animation != null) return;
    final a = _animations[next];
    if (a == null) return;
    _currentAnim = next;
    animation = a;
  }

  void takeDamage(int dmg) {
    if (!isAlive) return;
    hp -= dmg;
    if (hp <= 0) {
      isAlive = false;
      // Remove from the game's tracking list before leaving the component tree.
      gameRef._zombies.remove(this);
      removeFromParent();
      return;
    }
    // Dim sprite so the player gets clear hit feedback; restored in update().
    setOpacity(0.35);
    _hurtTimer = 0.25;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!isAlive) return;

    if (_hurtTimer > 0) {
      _hurtTimer -= dt;
      if (_hurtTimer <= 0) {
        _hurtTimer = 0;
        setOpacity(1.0);
      }
    }
    if (_hitCooldownTimer > 0) _hitCooldownTimer -= dt;

    if (!target.isMounted) return;
    final dir = target.position - position;
    final dist = dir.length;

    if (dist < 30) {
      _setAnim(CafZombieAnim.idle);
      if (_hitCooldownTimer <= 0) {
        _hitCooldownTimer = _hitCooldown;
        game.damagePlayer(5);
      }
      return;
    }

    final aggroRange = passive ? 210.0 : 300.0;
    if (dist < aggroRange) {
      passive = false;
      if (dir.x.abs() > dir.y.abs()) {
        _setAnim(dir.x > 0 ? CafZombieAnim.walkRight : CafZombieAnim.walkLeft);
      } else {
        _setAnim(dir.y > 0 ? CafZombieAnim.walkDown : CafZombieAnim.walkUp);
      }
      final step = dir.normalized() * _speed * dt;
      _tryMove(Vector2(step.x, 0));
      _tryMove(Vector2(0, step.y));
      _separateFromOthers();
    } else {
      _setAnim(CafZombieAnim.idle);
    }
  }

  void _tryMove(Vector2 delta) {
    final prev = position.clone();
    position += delta;
    position = Vector2(
      position.x.clamp(size.x / 2, CafeteriaGame._mapSize.x - size.x / 2).toDouble(),
      position.y.clamp(size.y / 2, CafeteriaGame._mapSize.y - size.y / 2).toDouble(),
    );
    if (_hitsWall()) position = prev;
  }

  bool _hitsWall() {
    for (final w in gameRef._walls) {
      if (w.wallRect.overlaps(hitRect)) return true;
    }
    return false;
  }

  void _separateFromOthers() {
    for (final other in gameRef._zombies) {
      if (other == this || !other.isAlive) continue;
      final away = position - other.position;
      final minDist = size.x * 0.50;
      final dist = away.length;
      if (dist < minDist && dist > 0.001) {
        position += away.normalized() * (minDist - dist) * 0.5;
      }
    }
  }

  @override
  void render(Canvas canvas) {
    canvas.drawOval(
      Rect.fromCenter(center: Offset(size.x / 2, size.y + 2), width: size.x * .72, height: 7),
      Paint()..color = Colors.black.withValues(alpha: 0.30),
    );
    if (animation != null) {
      super.render(canvas);
    } else {
      _renderFallback(canvas);
    }
    if (_hurtTimer > 0) {
      final t = (_hurtTimer / 0.20).clamp(0.0, 1.0);
      canvas.drawRect(Rect.fromLTWH(0, 0, size.x, size.y),
        Paint()..color = Colors.red.withValues(alpha: t * 0.55));
    }
  }

  void _renderFallback(Canvas canvas) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.x * .30, size.y * .33, size.x * .40, size.y * .46),
        const Radius.circular(3)),
      Paint()..color = const Color(0xFF4A6B30));
    canvas.drawCircle(Offset(size.x / 2, size.y * .24), size.x * .20,
      Paint()..color = const Color(0xFF8B9B6A));
    canvas.drawCircle(Offset(size.x * .44, size.y * .22), 2, Paint()..color = Colors.red);
    canvas.drawCircle(Offset(size.x * .56, size.y * .22), 2, Paint()..color = Colors.red);
  }
}

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
  CafWall({required Vector2 position, required Vector2 size})
      : super(position: position, size: size);

  Rect get wallRect => Rect.fromLTWH(position.x, position.y, size.x, size.y);
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
    'defense' => 'REFORCAR',
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

  // Flame 1.37+ asserts sprite != null in SpriteComponent.onMount().
  // Props without an asset (lockedRoom, defense) use _renderFallback() instead.
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
      'defense' => const Color(0xFF4B5563),
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
  CafeteriaPickup({required this.kind, required this.game})
      : super(size: Vector2(40, 40), anchor: Anchor.center);

  final String kind;
  final CafeteriaGame game;
  bool collected = false;

  // Map each item kind to its asset path. Add new entries as sprites are created.
  static const _kAssets = <String, String>{
    'fuse': 'objects/fusivel.png',
    // 'radioPart' : 'objects/radio_part.png',
    // 'radioPanel': 'objects/painel_radio.png',
    // 'radio'     : 'objects/radio.png',
    // 'vitalBoost': 'objects/vital_boost.png',
  };

  static const _kFallbackColors = <String, Color>{
    'fuse':       Color(0xFF60A5FA),
    'radioPart':  Color(0xFFFACC15),
    'radioPanel': Color(0xFF94A3B8),
    'radio':      Color(0xFF22C55E),
    'vitalBoost': Color(0xFFEF4444),
  };

  String get label => switch (kind) {
    'fuse'       => 'PEGAR FUSIVEL',
    'radioPart'  => 'PEGAR PECA',
    'radioPanel' => 'USAR PAINEL',
    'radio'      => 'SINTONIZAR',
    'vitalBoost' => 'COLETAR',
    _            => 'PEGAR',
  };

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    final path = _kAssets[kind];
    if (path != null) {
      try {
        sprite = Sprite(await game.images.load(path));
      } catch (e) {
        debugPrint('CafeteriaPickup[$kind] sprite failed: $e');
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
    // try {
    //   sprite = Sprite(await game.images.load('objects/painel_eletrico.png'));
    // } catch (_) {}
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
