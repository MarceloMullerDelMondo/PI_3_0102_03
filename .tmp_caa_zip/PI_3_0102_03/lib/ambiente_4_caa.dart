// ═══════════════════════════════════════════════════════════════════════════════
// AMBIENTE 4 — CAA  (Nexo de Transmissão)
// Arquivo único consolidado — PI-3  |  Grupo 0102-03
//
// Seções:
//   1. CaaBackendService  — cliente HTTP para a API Flask
//   2. CaaGame + Componentes Flame — motor de jogo, NPC, zumbis, colete, overlay
//   3. CaaMissionScreen + Widgets Flutter — tela, HUD, dialogs
//
// Dependência externa (Ambiente 1):
//   import 'game/h15_game.dart' show InvisibleWall, IsometricWall,
//                                         PlayerComponent, SolidObstacle
// ═══════════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/experimental.dart' show Rectangle;
import 'package:flame/game.dart';
import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

import 'game/h15_game.dart'
    show InvisibleWall, IsometricWall, PlayerComponent, SolidObstacle;

// ───────────────────────────────────────────────────────────────────────────────
// SEÇÃO 1 — CaaBackendService
// Cliente singleton para a API Flask do Ambiente 4.
// Endpoints: /state/sync  /entry/check  /dialog/sargento-rocha
//            /horde/modifiers  /explore/colete  /terminal/decision
// ───────────────────────────────────────────────────────────────────────────────
class CaaBackendService {
  CaaBackendService._();
  static final CaaBackendService instance = CaaBackendService._();

  // Android emulator => 10.0.2.2 ; desktop/web local => 127.0.0.1
  static const String _baseUrl = String.fromEnvironment(
    'CAA_API_BASE_URL',
    defaultValue: 'http://127.0.0.1:5000',
  );

  Uri _uri(String path, [Map<String, String>? q]) {
    final normalizedBase = _normalizeBaseUrl(_baseUrl);
    return Uri.parse('$normalizedBase$path').replace(queryParameters: q);
  }

  String _normalizeBaseUrl(String value) {
    var url = value.trim();
    url = url.replaceAll("'", '');
    url = url.replaceAll('"', '');
    if (url.startsWith('https:/') && !url.startsWith('https://')) {
      url = url.replaceFirst('https:/', 'http://');
    }
    if (url.startsWith('http:/') && !url.startsWith('http://')) {
      url = url.replaceFirst('http:/', 'http://');
    }
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'http://$url';
    }
    return url;
  }

  Future<Map<String, dynamic>> syncDependencies({
    required String playerName,
    required bool ajudouCientista,
    required bool itemCartaoFuncionario,
    required bool itemPonteiroLaser,
    required String? itemEvolucao,
  }) async {
    final res = await http.post(
      _uri('/api/caa/state/sync'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'player_name': playerName,
        'ajudou_cientista': ajudouCientista,
        'item_cartao_funcionario': itemCartaoFuncionario,
        'item_ponteiro_laser': itemPonteiroLaser,
        'item_evolucao': itemEvolucao,
      }),
    );
    return _decode(res);
  }

  Future<Map<String, dynamic>> checkEntry({
    required String playerName,
    required double latitude,
    required double longitude,
  }) async {
    final res = await http.post(
      _uri('/api/caa/entry/check'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'player_name': playerName,
        'latitude': latitude,
        'longitude': longitude,
      }),
    );
    return _decode(res);
  }

  Future<Map<String, dynamic>> dialogChoice({
    required String playerName,
    required String choice,
  }) async {
    final res = await http.post(
      _uri('/api/caa/dialog/sargento-rocha'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'player_name': playerName, 'choice': choice}),
    );
    return _decode(res);
  }

  Future<Map<String, dynamic>> hordeModifiers(String playerName) async {
    final res = await http.get(
      _uri('/api/caa/horde/modifiers', {'player_name': playerName}),
    );
    return _decode(res);
  }

  Future<Map<String, dynamic>> collectColete({
    required String playerName,
  }) async {
    final res = await http.post(
      _uri('/api/caa/explore/colete'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'player_name': playerName}),
    );
    return _decode(res);
  }

  Future<Map<String, dynamic>> saveDecision({
    required String playerName,
    required String choice,
  }) async {
    final res = await http.post(
      _uri('/api/caa/terminal/decision'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'player_name': playerName, 'choice': choice}),
    );
    return _decode(res);
  }

  Map<String, dynamic> _decode(http.Response res) {
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode >= 200 && res.statusCode < 300) return body;
    throw Exception(body['message'] ?? body['error'] ?? 'Erro CAA API');
  }
}

// ───────────────────────────────────────────────────────────────────────────────
// SEÇÃO 2 — CaaGame + Componentes Flame
// Motor principal do Ambiente 4 (CAA — Nexo de Transmissão).
// Requisitos para concluir a missão:
//   1. Falar com Sargento Rocha  (_rochaTalked)
//   2. Eliminar toda a horda     (_zombiesSpawned && _zombies.isEmpty)
//   3. Coletar o Colete Balístico (coleteCollected)
//   4. Usar o Terminal           (_terminalDecisionSaved)
// ───────────────────────────────────────────────────────────────────────────────
class CaaGame extends FlameGame with HasCollisionDetection {
  static const int hordeTargetKills = 15;
  static const double _worldScale = 1.6;

  CaaGame();

  final ValueNotifier<String> statusText =
      ValueNotifier<String>('Nexo de Transmissao pronto.');
  final ValueNotifier<bool> canTalkToRocha = ValueNotifier<bool>(false);
  final ValueNotifier<bool> canUseTerminal = ValueNotifier<bool>(false);
  final ValueNotifier<bool> canAttack = ValueNotifier<bool>(false);
  final ValueNotifier<bool> zombieEventActive = ValueNotifier<bool>(false);
  final ValueNotifier<int> zombieCount = ValueNotifier<int>(0);
  final ValueNotifier<double> currentHealth = ValueNotifier<double>(100);
  final ValueNotifier<int> elapsedSeconds = ValueNotifier<int>(0);
  final ValueNotifier<int> zombiesKilled = ValueNotifier<int>(0);
  final ValueNotifier<bool> missionCompleted = ValueNotifier<bool>(false);
  final ValueNotifier<bool> missionCompletedPopup = ValueNotifier<bool>(false);
  final ValueNotifier<bool> canExit = ValueNotifier<bool>(false);
  final ValueNotifier<String> missionBannerText =
      ValueNotifier<String>('MISSAO EM ANDAMENTO');
  final ValueNotifier<String> missionObjectiveText =
      ValueNotifier<String>('FALE COM O SGT. ROCHA');
  final ValueNotifier<bool> gameOver = ValueNotifier<bool>(false);
  final ValueNotifier<bool> canCollectColete = ValueNotifier<bool>(false);
  final ValueNotifier<bool> coleteCollected = ValueNotifier<bool>(false);

  PlayerComponent? player;
  JoystickComponent? _joystick;
  DarknessOverlay? _darkness;
  final List<SolidObstacle> _walls = [];
  final List<CaaZombieComponent> _zombies = [];
  late final CaaNpcComponent rocha;
  late final CaaTerminalComponent terminal;
  late final CaaColeteItemComponent _coleteItem;
  late final CaaArmorOverlay _armorOverlay;
  bool _zombiesSpawned = false;
  bool _terminalDecisionSaved = false;
  bool _rochaTalked = false;
  double _elapsedAccumulator = 0;

  Vector2 _mapSize = Vector2(1269 * _worldScale, 1041 * _worldScale);

  static final Vector2 _spawnPoint  = Vector2(640  * _worldScale, 860 * _worldScale);
  static final Vector2 _exitPos     = Vector2(640  * _worldScale, 980 * _worldScale);
  static final Vector2 _rochaPos    = Vector2(980  * _worldScale, 250 * _worldScale);
  static final Vector2 _terminalPos = Vector2(890  * _worldScale, 310 * _worldScale);
  static final Vector2 _coletePos   = Vector2(195  * _worldScale, 430 * _worldScale);
  static final Rect _zombieTrigger  = Rect.fromLTWH(
    980 * _worldScale, 260 * _worldScale,
    220 * _worldScale, 620 * _worldScale,
  );

  @override
  Color backgroundColor() => Colors.black;

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    try {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } catch (_) {}

    _mapSize = await _loadTiledMap();

    final bg = await loadSprite('screens/caa_environment.jpg');
    final bgComponent = SpriteComponent(
      sprite: bg,
      size: _mapSize.clone(),
      position: Vector2.zero(),
      priority: -10,
    );
    bgComponent.paint.filterQuality = FilterQuality.high;
    world.add(bgComponent);

    final playerImage = await images.load('player/player_sprite.jpg');
    player = PlayerComponent.fromSpriteSheet(playerImage)
      ..position = _spawnPoint.clone()
      ..priority = 5;
    await world.add(player!);

    camera.viewfinder.anchor = Anchor.center;
    camera.viewfinder.zoom = 1.8;
    camera.setBounds(Rectangle.fromLTWH(0, 0, _mapSize.x, _mapSize.y));
    camera.follow(player!, snap: true);

    _darkness = DarknessOverlay(radius: 250)..priority = 1000;
    camera.viewport.add(_darkness!);

    // cutout.png tem canal alpha real → sem fundo, sem blend tricks
    // 120×239 px → ratio 1:2 → size Vector2(80, 159) preserva exato
    rocha = CaaNpcComponent(
      gameRef: this,
      assetPath: 'npcs/sargento_rocha_cutout.png',
      label: 'SARGENTO ROCHA',
      position: _rochaPos,
      size: Vector2(80, 159),
      interactionRadius: 120,
      priority: 6,
    );
    await world.add(rocha);

    terminal = CaaTerminalComponent(gameRef: this, position: _terminalPos);
    await world.add(terminal);

    _coleteItem = CaaColeteItemComponent(gameRef: this, position: _coletePos);
    await world.add(_coleteItem);

    _joystick = JoystickComponent(
      knob: CircleComponent(
        radius: 26,
        paint: Paint()..color = const Color(0xFFF5C842),
      ),
      background: CircleComponent(
        radius: 68,
        paint: Paint()..color = const Color(0xAAE5E7EB),
      ),
      margin: const EdgeInsets.only(left: 24, bottom: 24),
      priority: 200,
    );
    camera.viewport.add(_joystick!);

    await images.load('zumbis/caa_zombie_cutout.png');
    await _equipPlayerFacao();

    _armorOverlay = CaaArmorOverlay(gameRef: this);
    await world.add(_armorOverlay);

    _playAmbientMusic();

    statusText.value = 'Entre no CAA e localize o Sgt. Rocha. [Facao] em maos.';
    missionObjectiveText.value = 'FALE COM O SGT. ROCHA';
    canAttack.value = true;
  }

  Future<void> _equipPlayerFacao() async {
    try {
      final sheet = await images.load('player/player_espada2mao.png');
      player?.useWeaponSpriteSheet(sheet);
    } catch (e) {
      debugPrint('Falha ao carregar sprite do facao: $e');
    }
  }

  void _playAmbientMusic() {
    try {
      FlameAudio.bgm.play('caa_ambient.ogg', volume: 0.35);
    } catch (_) {}
  }

  @override
  void update(double dt) {
    super.update(dt);

    if (!missionCompleted.value && !gameOver.value) {
      _elapsedAccumulator += dt;
      elapsedSeconds.value = _elapsedAccumulator.floor();
    }

    final p = player;
    final j = _joystick;
    if (p != null && j != null) {
      p.move(j.relativeDelta, dt, _mapSize, _walls);
      _updateInteractionStates(p.position);
    }
  }

  Future<Vector2> _loadTiledMap() async {
    try {
      final raw = await rootBundle.loadString('assets/tiles/caa_map.json');
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final size = _readMapSize(map) * _worldScale;
      _loadCollisionsFromMap(map);
      return size;
    } catch (e) {
      debugPrint('Falha ao carregar tilemap do CAA: $e');
      _setupFallbackWalls();
      return _mapSize.clone();
    }
  }

  Vector2 _readMapSize(Map<String, dynamic> map) {
    final layers = (map['layers'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>();
    for (final layer in layers) {
      final w = (layer['imagewidth'] as num?)?.toDouble();
      final h = (layer['imageheight'] as num?)?.toDouble();
      if (w != null && h != null) return Vector2(w, h);
    }
    final width = (map['width'] as num?)?.toDouble();
    final height = (map['height'] as num?)?.toDouble();
    final tw = (map['tilewidth'] as num?)?.toDouble();
    final th = (map['tileheight'] as num?)?.toDouble();
    if (width != null && height != null && tw != null && th != null) {
      return Vector2(width * tw, height * th);
    }
    return _mapSize.clone();
  }

  void _loadCollisionsFromMap(Map<String, dynamic> map) {
    final layers = (map['layers'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>();
    final collisionLayer = layers.firstWhere(
      (l) => l['name'] == 'Colisoes',
      orElse: () => <String, dynamic>{},
    );
    final objects = (collisionLayer['objects'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>();
    for (final obj in objects) {
      final wall = _buildObstacle(obj);
      if (wall == null) continue;
      _walls.add(wall);
      world.add(wall);
    }
  }

  SolidObstacle? _buildObstacle(Map<String, dynamic> obj) {
    final x = (obj['x'] as num? ?? 0).toDouble() * _worldScale;
    final y = (obj['y'] as num? ?? 0).toDouble() * _worldScale;
    final polygon = obj['polygon'];

    if (polygon is List) {
      final points = polygon
          .whereType<Map<String, dynamic>>()
          .map((pt) => Vector2(
                x + (pt['x'] as num? ?? 0).toDouble() * _worldScale,
                y + (pt['y'] as num? ?? 0).toDouble() * _worldScale,
              ))
          .toList();
      if (points.length >= 3) {
        return IsometricWall(vertices: points, showDebug: false)..priority = 1;
      }
      return null;
    }

    var width  = (obj['width']  as num? ?? 0).toDouble() * _worldScale;
    var height = (obj['height'] as num? ?? 0).toDouble() * _worldScale;
    if (width <= 0 && height <= 0) return null;
    if (width  <= 0) width  = 6;
    if (height <= 0) height = 6;

    return InvisibleWall(
      position: Vector2(x, y),
      size: Vector2(width, height),
      showDebug: false,
    )..priority = 1;
  }

  void _setupFallbackWalls() {
    final w = _mapSize.x;
    final h = _mapSize.y;
    const s = _worldScale;

    final rects = <Rect>[
      Rect.fromLTWH(0, 0, w, 18 * s),
      Rect.fromLTWH(0, h - 18 * s, w, 18 * s),
      Rect.fromLTWH(0, 0, 18 * s, h),
      Rect.fromLTWH(w - 18 * s, 0, 18 * s, h),
      Rect.fromLTWH(50 * s,   80 * s,  180 * s, 40 * s),
      Rect.fromLTWH(50 * s,  240 * s,  185 * s, 38 * s),
      Rect.fromLTWH(50 * s,  405 * s,  180 * s, 36 * s),
      Rect.fromLTWH(350 * s,  95 * s,  110 * s, 50 * s),
      Rect.fromLTWH(350 * s, 255 * s,  110 * s, 50 * s),
      Rect.fromLTWH(350 * s, 420 * s,  110 * s, 50 * s),
      Rect.fromLTWH(555 * s,  95 * s,  105 * s, 50 * s),
      Rect.fromLTWH(555 * s, 255 * s,  105 * s, 50 * s),
      Rect.fromLTWH(555 * s, 420 * s,  105 * s, 50 * s),
      Rect.fromLTWH(835 * s,  95 * s,  170 * s, 50 * s),
      Rect.fromLTWH(835 * s, 255 * s,  170 * s, 50 * s),
      Rect.fromLTWH(835 * s, 570 * s,  170 * s, 42 * s),
      Rect.fromLTWH(1050 * s,  0,       40 * s, 170 * s),
      Rect.fromLTWH(0,        650 * s,  250 * s, 42 * s),
      Rect.fromLTWH(250 * s,  810 * s,  530 * s, 42 * s),
    ];

    for (final rect in rects) {
      final wall = InvisibleWall(
        position: Vector2(rect.left, rect.top),
        size: Vector2(rect.width, rect.height),
        showDebug: false,
      );
      _walls.add(wall);
      world.add(wall);
    }
  }

  void _updateInteractionStates(Vector2 position) {
    final nearRocha = (position - rocha.position).length <= rocha.interactionRadius;

    final prereqsMet = _rochaTalked &&
        _zombiesSpawned &&
        _zombies.isEmpty &&
        coleteCollected.value;
    final nearTerminal =
        (position - terminal.position).length <= terminal.interactionRadius;

    final nearColete = !coleteCollected.value &&
        (position - _coleteItem.position).length <= _coleteItem.interactionRadius;

    if (canTalkToRocha.value != nearRocha) canTalkToRocha.value = nearRocha;
    if (canUseTerminal.value != (nearTerminal && prereqsMet)) {
      canUseTerminal.value = nearTerminal && prereqsMet;
    }
    if (canCollectColete.value != nearColete) canCollectColete.value = nearColete;

    if (missionCompleted.value) {
      final nearExit = (position - _exitPos).length <= 130;
      if (canExit.value != nearExit) canExit.value = nearExit;
    }

    if (!_zombiesSpawned &&
        _zombieTrigger.contains(Offset(position.x, position.y))) {
      triggerZombieEvent();
    }
  }

  void _updateObjectiveText() {
    if (!_rochaTalked) {
      missionObjectiveText.value = 'FALE COM O SGT. ROCHA';
      return;
    }
    if (!_zombiesSpawned || _zombies.isNotEmpty) {
      missionObjectiveText.value = !coleteCollected.value
          ? 'HORDA + COLETE BALISTICO'
          : 'ELIMINE TODOS OS ZUMBIS';
      return;
    }
    if (!coleteCollected.value) {
      missionObjectiveText.value = 'ENCONTRE O COLETE BALISTICO';
      return;
    }
    if (!_terminalDecisionSaved) {
      missionObjectiveText.value = 'USE O TERMINAL DE TRANSMISSAO';
      return;
    }
    missionObjectiveText.value = 'VOLTE A ENTRADA PARA SAIR';
  }

  void triggerZombieEvent() {
    if (_zombiesSpawned) return;
    _zombiesSpawned = true;
    zombieEventActive.value = true;
    canAttack.value = true;
    statusText.value = 'Sinais de ataque detectados. Zumbis entrando pela ala leste.';
    _updateObjectiveText();

    const s = _worldScale;
    _spawnWave([
      Vector2(1030 * s, 360 * s), Vector2(1100 * s, 410 * s),
      Vector2(1155 * s, 520 * s), Vector2(1040 * s, 460 * s),
      Vector2(980  * s, 560 * s),
    ]);
    Future.delayed(const Duration(milliseconds: 700), () {
      if (!isMounted) return;
      _spawnWave([
        Vector2(1110 * s, 620 * s), Vector2(1180 * s, 430 * s),
        Vector2(1090 * s, 520 * s), Vector2(990  * s, 660 * s),
        Vector2(1150 * s, 700 * s),
      ]);
    });
    Future.delayed(const Duration(milliseconds: 1400), () {
      if (!isMounted) return;
      _spawnWave([
        Vector2(1080 * s, 740 * s), Vector2(1210 * s, 560 * s),
        Vector2(1035 * s, 760 * s), Vector2(1170 * s, 820 * s),
        Vector2(960  * s, 420 * s),
      ]);
    });
  }

  void _spawnWave(List<Vector2> points) {
    for (final spawn in points) {
      final zombie = CaaZombieComponent(
        gameRef: this,
        target: player!,
        assetPath: 'zumbis/caa_zombie_cutout.png',
        position: spawn,
      );
      _zombies.add(zombie);
      world.add(zombie);
    }
    zombieCount.value = _zombies.length;
  }

  void attack() {
    final p = player;
    if (p == null || !canAttack.value) return;

    p.startAttack();

    final attackRect = p.weaponAttackRect('FACAO');
    final defeated = <CaaZombieComponent>[];
    for (final zombie in _zombies) {
      if (!zombie.isMounted) continue;
      if (attackRect.overlaps(zombie.hitRect)) {
        if (zombie.takeDamage(10)) defeated.add(zombie);
      }
    }

    for (final zombie in defeated) {
      zombie.removeFromParent();
      _zombies.remove(zombie);
    }

    if (defeated.isNotEmpty) zombiesKilled.value += defeated.length;
    if (_zombiesSpawned) {
      missionObjectiveText.value =
          'SOBREVIVA A HORDA (${zombiesKilled.value}/$hordeTargetKills)';
    }

    zombieCount.value = _zombies.length;
    if (_zombies.isEmpty && _zombiesSpawned) {
      statusText.value = coleteCollected.value
          ? 'Setor limpo! Use o terminal de transmissao.'
          : 'Setor limpo! Encontre o colete balistico antes de usar o terminal.';
      missionBannerText.value = 'SETOR LIMPO';
      _updateObjectiveText();
      _checkMissionCompletion();
    }
  }

  void damagePlayer(double amount) {
    if (gameOver.value || missionCompleted.value) return;
    final reducedAmount = coleteCollected.value ? amount * 0.5 : amount;
    currentHealth.value =
        (currentHealth.value - reducedAmount).clamp(0, 100).toDouble();
    if (currentHealth.value <= 0) {
      gameOver.value = true;
      statusText.value = 'Voce caiu. A missao falhou.';
      missionBannerText.value = 'FIM DE JOGO';
      canAttack.value = false;
      pauseEngine();
    }
  }

  void setStatus(String message) => statusText.value = message;
  void setTerminalReady(bool ready) => canUseTerminal.value = ready;

  void registerTerminalDecision(String choice) {
    _terminalDecisionSaved = true;
    missionBannerText.value = switch (choice) {
      'resgate_portao_1' => 'RESGATE SELECIONADO',
      _ => 'PROTOCOLO DE DADOS ATIVADO',
    };
    _updateObjectiveText();
    _checkMissionCompletion();
  }

  void _checkMissionCompletion() {
    if (missionCompleted.value) return;
    if (!_rochaTalked || !_zombiesSpawned || _zombies.isNotEmpty ||
        !coleteCollected.value || !_terminalDecisionSaved) {
      return;
    }

    missionCompleted.value = true;
    missionCompletedPopup.value = true;
    missionBannerText.value = 'MISSAO COMPLETA';
    missionObjectiveText.value = 'VOLTE A ENTRADA PARA SAIR';
    statusText.value = 'Nexo estabilizado! Explore o ambiente e volte pela entrada.';
    canAttack.value = false;
    _darkness?.expandToRadius(560);
    try { FlameAudio.bgm.stop(); } catch (_) {}
    try {
      SystemSound.play(SystemSoundType.alert);
      HapticFeedback.heavyImpact();
    } catch (_) {}
    pauseEngine();
  }

  void dismissMissionPopup() {
    missionCompletedPopup.value = false;
    resumeEngine();
  }

  void markColeteCollected() {
    coleteCollected.value = true;
    canCollectColete.value = false;
    _coleteItem.removeFromParent();
    statusText.value = '[Colete Balistico] equipado. Dano -50%.';
    _updateObjectiveText();
  }

  void markRochaTalked() {
    _rochaTalked = true;
    statusText.value = 'Rocha consultado. Agora: enfrente a horda e encontre o colete.';
    _updateObjectiveText();
  }

  @override
  void onRemove() {
    try { FlameAudio.bgm.stop(); } catch (_) {}
    statusText.dispose();
    canTalkToRocha.dispose();
    canUseTerminal.dispose();
    canAttack.dispose();
    zombieEventActive.dispose();
    zombieCount.dispose();
    currentHealth.dispose();
    elapsedSeconds.dispose();
    zombiesKilled.dispose();
    missionCompleted.dispose();
    missionCompletedPopup.dispose();
    canExit.dispose();
    missionBannerText.dispose();
    missionObjectiveText.dispose();
    gameOver.dispose();
    canCollectColete.dispose();
    coleteCollected.dispose();
    super.onRemove();
  }
}

// ── NPC: Sargento Rocha ────────────────────────────────────────────────────────
// Suporta extração de frame de sprite sheet via srcPosition/srcSize.
// useMultiplyBlend = true remove fundo branco de JPG (BlendMode.multiply).
class CaaNpcComponent extends SpriteComponent {
  final CaaGame gameRef;
  final String assetPath;
  final String label;
  final double interactionRadius;
  final Vector2? srcPosition;
  final Vector2? srcSize;
  final bool useMultiplyBlend;

  CaaNpcComponent({
    required this.gameRef,
    required this.assetPath,
    required this.label,
    required Vector2 position,
    Vector2? size,
    this.interactionRadius = 100,
    int priority = 6,
    this.srcPosition,
    this.srcSize,
    this.useMultiplyBlend = false,
  }) : super(
          position: position,
          anchor: Anchor.bottomCenter,
          size: size ?? Vector2(96, 128),
          priority: priority,
        );

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    try {
      final img = await gameRef.images.load(assetPath);
      sprite = Sprite(img, srcPosition: srcPosition, srcSize: srcSize);
      paint.filterQuality = FilterQuality.high;
      // darken: min(src, dst) — fundo branco do JPG desaparece no cenário escuro,
      // pixels escuros do personagem ficam preservados
      if (useMultiplyBlend) paint.blendMode = BlendMode.darken;
    } catch (e) {
      debugPrint('Falha ao carregar sprite $assetPath: $e');
    }
  }

  @override
  void render(Canvas canvas) {
    // Com Anchor.bottomCenter, os pés ficam em (size.x/2, size.y)
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.x / 2, size.y - 2),
        width: size.x * 0.65,
        height: 10,
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.45),
    );
    super.render(canvas);
  }
}

// ── Terminal de Transmissão ────────────────────────────────────────────────────
class CaaTerminalComponent extends PositionComponent {
  final CaaGame gameRef;
  final double interactionRadius;

  CaaTerminalComponent({
    required this.gameRef,
    required Vector2 position,
    this.interactionRadius = 110,
  }) : super(
          position: position,
          anchor: Anchor.center,
          size: Vector2(96, 96),
          priority: 6,
        );

  @override
  void render(Canvas canvas) {
    final center = Offset(size.x / 2, size.y / 2);
    canvas.drawCircle(center, 22,
        Paint()..color = const Color(0xFF1F2937)..style = PaintingStyle.fill);
    canvas.drawCircle(
      center, 23,
      Paint()
        ..color = const Color(0xFFF5C842).withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawRect(
      Rect.fromCenter(center: center, width: 22, height: 34),
      Paint()..color = const Color(0xFF4B5563),
    );
    super.render(canvas);
  }
}

// ── Zumbi da Horda ─────────────────────────────────────────────────────────────
class CaaZombieComponent extends SpriteComponent {
  final CaaGame gameRef;
  final PlayerComponent target;
  final String assetPath;
  final double speed;
  int health = 15;
  double _hitCooldownTimer = 0;
  static const double _playerHitCooldown = 1.0;
  static const double _touchDamage = 7;

  CaaZombieComponent({
    required this.gameRef,
    required this.target,
    required this.assetPath,
    required Vector2 position,
    this.speed = 34,
  }) : super(
          position: position,
          size: Vector2(96, 96),
          anchor: Anchor.center,
          priority: 7,
        );

  Rect get hitRect => Rect.fromCenter(
        center: Offset(position.x, position.y),
        width: size.x * 0.72,
        height: size.y * 0.76,
      );

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    sprite = await gameRef.loadSprite(assetPath);
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!target.isMounted) return;
    if (_hitCooldownTimer > 0) _hitCooldownTimer -= dt;
    final dir = target.position - position;
    if (dir.length2 < 4) return;
    position += dir.normalized() * speed * dt;
    if (dir.length < 42 && _hitCooldownTimer <= 0) {
      _hitCooldownTimer = _playerHitCooldown;
      gameRef.damagePlayer(_touchDamage);
    }
  }

  bool takeDamage(int dmg) {
    health -= dmg;
    return health <= 0;
  }

  @override
  void render(Canvas canvas) {
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.x / 2, size.y + 3),
        width: size.x * 0.80,
        height: 7,
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.35),
    );
    super.render(canvas);
  }
}

// ── Colete Balístico (item flutuante) ─────────────────────────────────────────
class CaaColeteItemComponent extends PositionComponent {
  final CaaGame gameRef;
  final double interactionRadius;
  double _pulseTime = 0;
  double _bobTime = 0;

  CaaColeteItemComponent({
    required this.gameRef,
    required Vector2 position,
    this.interactionRadius = 90,
  }) : super(
          position: position,
          anchor: Anchor.center,
          size: Vector2(64, 64),
          priority: 4,
        );

  @override
  void update(double dt) {
    super.update(dt);
    _pulseTime += dt;
    _bobTime += dt;
  }

  @override
  void render(Canvas canvas) {
    final pulse = 0.55 + 0.45 * math.sin(_pulseTime * 2.6);
    final bob = math.sin(_bobTime * 2.0) * 6.0;
    final cx = size.x / 2;
    final cy = size.y / 2;

    canvas.save();
    canvas.translate(0, bob);

    canvas.drawCircle(Offset(cx, cy), 28,
        Paint()..color = Color.fromRGBO(34, 197, 94, pulse * 0.25)..style = PaintingStyle.fill);
    canvas.drawCircle(Offset(cx, cy), 24,
        Paint()..color = const Color(0xFF0F2918)..style = PaintingStyle.fill);
    canvas.drawCircle(Offset(cx, cy), 24,
        Paint()..color = Color.fromRGBO(34, 197, 94, pulse)..style = PaintingStyle.stroke..strokeWidth = 2.8);

    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(cx - 10, cy - 12, 20, 24), const Radius.circular(4)),
      Paint()..color = Color.fromRGBO(34, 197, 94, pulse * 0.6)..style = PaintingStyle.fill,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(cx - 10, cy - 12, 20, 24), const Radius.circular(4)),
      Paint()..color = Color.fromRGBO(74, 222, 128, pulse)..style = PaintingStyle.stroke..strokeWidth = 1.8,
    );
    canvas.drawRect(Rect.fromLTWH(cx - 12, cy - 15, 7, 6),
        Paint()..color = Color.fromRGBO(74, 222, 128, pulse));
    canvas.drawRect(Rect.fromLTWH(cx + 5, cy - 15, 7, 6),
        Paint()..color = Color.fromRGBO(74, 222, 128, pulse));
    canvas.drawLine(Offset(cx, cy - 10), Offset(cx, cy + 10),
        Paint()..color = Color.fromRGBO(134, 239, 172, pulse)..strokeWidth = 1.2);

    canvas.restore();
    super.render(canvas);
  }
}

// ── Overlay de Armadura (colete equipado) ─────────────────────────────────────
class CaaArmorOverlay extends PositionComponent {
  final CaaGame gameRef;
  bool _active = false;
  double _pulseTime = 0;

  CaaArmorOverlay({required this.gameRef})
      : super(anchor: Anchor.center, size: Vector2(60, 60), priority: 4);

  void activate() => _active = true;

  @override
  void update(double dt) {
    super.update(dt);
    if (!_active) return;
    _pulseTime += dt;
    final p = gameRef.player;
    if (p != null) position = p.position.clone();
  }

  @override
  void render(Canvas canvas) {
    if (!_active) return;
    final pulse = 0.55 + 0.45 * math.sin(_pulseTime * 2.8);
    final cx = size.x / 2;
    final cy = size.y / 2;

    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy + 10), width: 44, height: 14),
      Paint()..color = Color.fromRGBO(34, 197, 94, pulse * 0.5)..style = PaintingStyle.fill,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy + 10), width: 44, height: 14),
      Paint()..color = Color.fromRGBO(34, 197, 94, pulse)..style = PaintingStyle.stroke..strokeWidth = 2.2,
    );

    final vestRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - 10, cy - 18, 20, 26), const Radius.circular(3));
    canvas.drawRRect(vestRect,
        Paint()..color = Color.fromRGBO(34, 197, 94, pulse * 0.35)..style = PaintingStyle.fill);
    canvas.drawRRect(vestRect,
        Paint()..color = Color.fromRGBO(34, 197, 94, pulse)..style = PaintingStyle.stroke..strokeWidth = 1.6);

    super.render(canvas);
  }
}

// ── Overlay de Escuridão (spotlight animável) ─────────────────────────────────
class DarknessOverlay extends Component with HasGameReference<CaaGame> {
  double _radius;
  double _targetRadius;
  static const double _expandSpeed = 160;

  DarknessOverlay({double radius = 220})
      : _radius = radius,
        _targetRadius = radius;

  void expandToRadius(double target) => _targetRadius = target;

  @override
  void update(double dt) {
    super.update(dt);
    if (_radius < _targetRadius) {
      _radius = (_radius + _expandSpeed * dt).clamp(0, _targetRadius);
    }
  }

  @override
  void render(Canvas canvas) {
    final vpSize = game.camera.viewport.size;
    final size = vpSize.length2 == 0 ? game.size : vpSize;
    final bounds = Offset.zero & size.toSize();
    final center = _playerScreen(size);

    canvas.saveLayer(bounds, Paint());
    canvas.drawRect(bounds, Paint()..color = const Color(0xD9000000));
    canvas.drawCircle(
      Offset(center.x, center.y),
      _radius,
      Paint()
        ..blendMode = BlendMode.dstOut
        ..shader = ui.Gradient.radial(
          Offset(center.x, center.y),
          _radius,
          const [Color(0xFFFFFFFF), Color(0xCCFFFFFF), Color(0x00FFFFFF)],
          const [0.0, 0.65, 1.0],
        ),
    );
    canvas.restore();
  }

  Vector2 _playerScreen(Vector2 vpSize) {
    final p = game.player;
    if (p == null) return vpSize / 2;
    final sp = game.camera.localToGlobal(p.position);
    return game.camera.viewport.globalToLocal(sp);
  }
}

// ───────────────────────────────────────────────────────────────────────────────
// SEÇÃO 3 — CaaMissionScreen + Widgets Flutter
// Tela principal do Ambiente 4: GameWidget, HUD, dialogs de bottom-sheet.
// ───────────────────────────────────────────────────────────────────────────────
class CaaMissionScreen extends StatefulWidget {
  final String playerName;
  final double latitude;
  final double longitude;

  // devMode mantido para compatibilidade com map_selection_screen mas ignorado
  // ignore: avoid_unused_constructor_parameters
  const CaaMissionScreen({
    super.key,
    required this.playerName,
    bool devMode = false,
    required this.latitude,
    required this.longitude,
  });

  @override
  State<CaaMissionScreen> createState() => _CaaMissionScreenState();
}

class _CaaMissionScreenState extends State<CaaMissionScreen> {
  late final CaaGame _game;
  bool _backendOptional = false;

  @override
  void initState() {
    super.initState();
    _game = CaaGame();
  }

  @override
  void dispose() {
    try {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    } catch (_) {}
    super.dispose();
  }

  Future<void> _openRochaDialog() async {
    _game.pauseEngine();
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _RochaDialog(
        onFormula: () => Navigator.of(context).pop('trouxe_formula_h15'),
        onSurvive: () => Navigator.of(context).pop('so_quero_sair_vivo'),
      ),
    );
    _game.resumeEngine();
    if (choice == null) return;
    await _handleRochaChoice(choice);
  }

  Future<void> _handleRochaChoice(String choice) async {
    try {
      final result = await _callBackendOrLocalRocha(choice);
      final payload = result['result'] as Map<String, dynamic>? ?? const {};
      final message = (payload['message'] ?? 'Dialogo concluido.').toString();
      final event = (payload['event'] ?? '').toString();
      _game.markRochaTalked();
      if (event == 'horde_combat_activated') {
        _game.setStatus(message);
        _game.triggerZombieEvent();
      } else {
        _game.setStatus(message);
      }
      setState(() {});
    } catch (e) {
      _game.setStatus('Erro no dialogo: $e');
      setState(() {});
    }
  }

  Future<void> _openExploreDialog() async {
    _game.pauseEngine();
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ColeteFoundDialog(
        onCollect: () => Navigator.of(context).pop(true),
        onIgnore: () => Navigator.of(context).pop(false),
      ),
    );
    _game.resumeEngine();
    if (confirmed != true) return;
    await _handleColeteCollect();
  }

  Future<void> _handleColeteCollect() async {
    try {
      final result = await _callBackendOrLocalColete();
      final payload = result['result'] as Map<String, dynamic>? ?? const {};
      final message = (payload['message'] ?? 'Item coletado.').toString();
      _game.markColeteCollected();
      _game.setStatus(message);
      setState(() {});
    } catch (e) {
      _game.setStatus('Erro ao coletar item: $e');
      setState(() {});
    }
  }

  Future<Map<String, dynamic>> _callBackendOrLocalColete() async {
    if (_backendOptional) return _localColeteResult();
    try {
      return await CaaBackendService.instance.collectColete(
          playerName: widget.playerName);
    } catch (_) {
      _backendOptional = true;
      return _localColeteResult();
    }
  }

  Map<String, dynamic> _localColeteResult() => {
        'ok': true,
        'result': {
          'item_collected': 'colete_balistico',
          'message': 'Voce encontrou um [Colete Balistico]. O dano dos zumbis cai pela metade.',
          'inventory_update': {'item': 'colete_balistico', 'damage_reduction_pct': 50},
        },
      };

  Future<void> _openTerminalDialog() async {
    _game.pauseEngine();
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _TerminalDialog(
        onRescue: () => Navigator.of(context).pop('resgate_portao_1'),
        onData: () => Navigator.of(context).pop('transmissao_dados_reitoria'),
      ),
    );
    _game.resumeEngine();
    if (choice == null) return;
    await _handleTerminalChoice(choice);
  }

  Future<void> _handleTerminalChoice(String choice) async {
    try {
      final result = await _callBackendOrLocalTerminal(choice);
      final payload = result['result'] as Map<String, dynamic>? ?? const {};
      final radio = payload['radio_output'] as Map<String, dynamic>?;
      if (radio != null) {
        _game.setStatus((radio['message'] ?? 'Sinal encaminhado.').toString());
      }
      _game.registerTerminalDecision(choice);
      setState(() {});
    } catch (e) {
      _game.setStatus('Erro ao salvar dilema: $e');
      setState(() {});
    }
  }

  Future<Map<String, dynamic>> _callBackendOrLocalRocha(String choice) async {
    if (_backendOptional) return _localRochaResult(choice);
    try {
      return await CaaBackendService.instance.dialogChoice(
          playerName: widget.playerName, choice: choice);
    } catch (_) {
      _backendOptional = true;
      return _localRochaResult(choice);
    }
  }

  Future<Map<String, dynamic>> _callBackendOrLocalTerminal(String choice) async {
    if (_backendOptional) return _localTerminalResult(choice);
    try {
      return await CaaBackendService.instance.saveDecision(
          playerName: widget.playerName, choice: choice);
    } catch (_) {
      _backendOptional = true;
      return _localTerminalResult(choice);
    }
  }

  Map<String, dynamic> _localRochaResult(String choice) {
    if (choice == 'trouxe_formula_h15') {
      return {
        'ok': true,
        'result': {
          'event': 'dialog_formula_path',
          'message': 'Rocha: A formula pode mudar tudo. Leve isso a serio.',
          'bonus_lore_final_esperanca': true,
        },
      };
    }
    return {
      'ok': true,
      'result': {
        'event': 'horde_combat_activated',
        'message': 'Rocha: Segura a linha. A horda entrou no setor leste.',
        'horde_modifiers': {
          'precision_bonus_pct': 15.0,
          'extra_hp': 30,
          'can_revive_once': false,
        },
      },
    };
  }

  Map<String, dynamic> _localTerminalResult(String choice) {
    if (choice == 'resgate_portao_1') {
      return {
        'ok': true,
        'result': {
          'saved': true,
          'next_state_seed': 'resgate',
          'radio_output': {
            'source': 'Estacionamentos',
            'message': 'Portao 1 confirmado. Corram para a evacuacao.',
            'next_map_hint': 'rota_portao_1',
          },
        },
      };
    }
    return {
      'ok': true,
      'result': {
        'saved': true,
        'next_state_seed': 'cura',
        'radio_output': {
          'source': 'Reitoria',
          'message': 'Reitoria confirmou os dados. Iniciando protocolo da cura.',
          'next_map_hint': 'rota_reitoria',
        },
      },
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GameWidget<CaaGame>(
        game: _game,
        overlayBuilderMap: {
          'hud': (context, game) => _CaaHudOverlay(
                game: game,
                onBack: () => Navigator.of(context).pop(false),
                onTalk: _openRochaDialog,
                onTerminal: _openTerminalDialog,
                onExplore: _openExploreDialog,
                onMissionAck: _game.dismissMissionPopup,
                onExit: () => Navigator.of(context).pop(true),
              ),
        },
        initialActiveOverlays: const ['hud'],
      ),
    );
  }
}

// ── HUD Overlay ───────────────────────────────────────────────────────────────
class _CaaHudOverlay extends StatelessWidget {
  final CaaGame game;
  final VoidCallback onBack;
  final VoidCallback onTalk;
  final VoidCallback onTerminal;
  final VoidCallback onExplore;
  final VoidCallback onMissionAck;
  final VoidCallback onExit;

  const _CaaHudOverlay({
    required this.game,
    required this.onBack,
    required this.onTalk,
    required this.onTerminal,
    required this.onExplore,
    required this.onMissionAck,
    required this.onExit,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Stack(
        children: [
          Positioned(
            top: 10,
            left: 12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    _PixelButton(label: 'VOLTAR', onTap: onBack),
                    const SizedBox(width: 8),
                    ValueListenableBuilder<double>(
                      valueListenable: game.currentHealth,
                      builder: (_, hp, __) => _HealthBar(current: hp, max: 100),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                _SurvivalStats(game: game),
              ],
            ),
          ),
          Positioned(
            top: 10,
            right: 12,
            child: ValueListenableBuilder<String>(
              valueListenable: game.missionObjectiveText,
              builder: (_, text, __) => _MissionTracker(text: text),
            ),
          ),
          Positioned(
            top: 90,
            left: 0,
            right: 0,
            child: ValueListenableBuilder<String>(
              valueListenable: game.statusText,
              builder: (_, msg, __) => IgnorePointer(
                child: Center(child: _StatusToast(message: msg)),
              ),
            ),
          ),
          Positioned(
            right: 164,
            bottom: 28,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                ValueListenableBuilder<bool>(
                  valueListenable: game.canTalkToRocha,
                  builder: (_, can, __) => AnimatedOpacity(
                    opacity: can ? 1 : 0,
                    duration: const Duration(milliseconds: 140),
                    child: IgnorePointer(
                      ignoring: !can,
                      child: _PixelButton(label: 'FALAR', onTap: onTalk),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                ValueListenableBuilder<bool>(
                  valueListenable: game.canUseTerminal,
                  builder: (_, can, __) => AnimatedOpacity(
                    opacity: can ? 1 : 0,
                    duration: const Duration(milliseconds: 140),
                    child: IgnorePointer(
                      ignoring: !can,
                      child: _PixelButton(label: 'TRANSMISSAO', onTap: onTerminal),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                ValueListenableBuilder<bool>(
                  valueListenable: game.canCollectColete,
                  builder: (_, can, __) => AnimatedOpacity(
                    opacity: can ? 1 : 0,
                    duration: const Duration(milliseconds: 140),
                    child: IgnorePointer(
                      ignoring: !can,
                      child: _PixelButton(
                        label: 'COLETAR',
                        onTap: onExplore,
                        borderColor: const Color(0xFF22C55E),
                        textColor: const Color(0xFF22C55E),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                ValueListenableBuilder<bool>(
                  valueListenable: game.canExit,
                  builder: (_, can, __) => AnimatedOpacity(
                    opacity: can ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: IgnorePointer(
                      ignoring: !can,
                      child: _PixelButton(
                        label: '>> SAIR <<',
                        onTap: onExit,
                        borderColor: const Color(0xFFF59E0B),
                        textColor: const Color(0xFFFFF3B0),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            right: 20,
            bottom: 20,
            child: ValueListenableBuilder<bool>(
              valueListenable: game.canAttack,
              builder: (_, enabled, __) => _AttackButton(
                enabled: enabled,
                onTap: enabled ? game.attack : null,
              ),
            ),
          ),
          Positioned.fill(
            child: ValueListenableBuilder<bool>(
              valueListenable: game.missionCompletedPopup,
              builder: (_, visible, __) => IgnorePointer(
                ignoring: !visible,
                child: AnimatedOpacity(
                  opacity: visible ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 180),
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.72),
                    alignment: Alignment.center,
                    child: _MissionCompletePopup(onClose: onMissionAck),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Health Bar ────────────────────────────────────────────────────────────────
class _HealthBar extends StatelessWidget {
  final double current;
  final double max;
  const _HealthBar({required this.current, required this.max});

  @override
  Widget build(BuildContext context) {
    final progress = (current / max).clamp(0.0, 1.0);
    final barColor =
        progress > 0.35 ? const Color(0xFF22C55E) : const Color(0xFFEF4444);

    return Container(
      width: 180,
      height: 32,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xF207070B),
        border: Border.all(color: Colors.amber.shade900, width: 2),
        boxShadow: const [BoxShadow(color: Color(0xAA000000), offset: Offset(2, 2))],
      ),
      child: Row(
        children: [
          const Text('♥',
              style: TextStyle(fontSize: 14, color: Color(0xFFEF4444), height: 1)),
          const SizedBox(width: 5),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(color: const Color(0xFF3F3F46)),
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: progress,
                  child: Container(color: barColor),
                ),
                Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '${current.round()}/${max.round()}',
                      style: GoogleFonts.pressStart2p(
                        fontSize: 9,
                        color: Colors.white,
                        shadows: const [
                          Shadow(color: Colors.black, offset: Offset(1.5, 1.5), blurRadius: 3)
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Survival Stats (timer + kills + colete) ───────────────────────────────────
class _SurvivalStats extends StatelessWidget {
  final CaaGame game;
  const _SurvivalStats({required this.game});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xE607070B),
        border: Border.all(color: const Color(0xFFF59E0B), width: 2),
        boxShadow: const [
          BoxShadow(color: Color(0xCC000000), offset: Offset(3, 3)),
          BoxShadow(color: Color(0x55F59E0B), blurRadius: 10),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ValueListenableBuilder<int>(
            valueListenable: game.elapsedSeconds,
            builder: (_, s, __) => Text(
              _fmt(s),
              style: GoogleFonts.pressStart2p(
                fontSize: 11,
                color: Colors.white,
                shadows: const [Shadow(color: Colors.black, offset: Offset(1.5, 1.5), blurRadius: 3)],
              ),
            ),
          ),
          const SizedBox(width: 18),
          ValueListenableBuilder<int>(
            valueListenable: game.zombiesKilled,
            builder: (_, k, __) => Text(
              '☠ $k',
              style: GoogleFonts.pressStart2p(
                fontSize: 14,
                color: const Color(0xFFFFF3B0),
                shadows: const [Shadow(color: Colors.black, offset: Offset(1.5, 1.5), blurRadius: 3)],
              ),
            ),
          ),
          const SizedBox(width: 14),
          ValueListenableBuilder<bool>(
            valueListenable: game.coleteCollected,
            builder: (_, equipped, __) => AnimatedOpacity(
              opacity: equipped ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: Text(
                '🛡 COLETE',
                style: GoogleFonts.pressStart2p(
                  fontSize: 10,
                  color: const Color(0xFF4ADE80),
                  shadows: const [Shadow(color: Colors.black, offset: Offset(1.5, 1.5), blurRadius: 3)],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(int s) =>
      '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
}

// ── Mission Tracker (topo direito) ────────────────────────────────────────────
class _MissionTracker extends StatelessWidget {
  final String text;
  const _MissionTracker({required this.text});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xE607070B),
          border: Border.all(color: const Color(0xFFF59E0B), width: 2.5),
          boxShadow: const [
            BoxShadow(color: Color(0xCC000000), offset: Offset(3, 3)),
            BoxShadow(color: Color(0x44F59E0B), blurRadius: 12),
          ],
        ),
        child: Text(
          text,
          textAlign: TextAlign.right,
          style: GoogleFonts.pressStart2p(
            fontSize: 10,
            color: const Color(0xFFFFF3B0),
            height: 1.6,
            shadows: const [Shadow(color: Colors.black, offset: Offset(1.5, 1.5), blurRadius: 3)],
          ),
        ),
      ),
    );
  }
}

// ── Status Toast (centro superior) ───────────────────────────────────────────
class _StatusToast extends StatelessWidget {
  final String message;
  const _StatusToast({required this.message});

  @override
  Widget build(BuildContext context) {
    if (message.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xDD0A0600),
        border: Border.all(color: Colors.amber, width: 2),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: GoogleFonts.pressStart2p(
          fontSize: 9,
          color: const Color(0xFFFDE68A),
          height: 1.5,
          shadows: const [Shadow(color: Colors.black, offset: Offset(1.5, 1.5), blurRadius: 3)],
        ),
      ),
    );
  }
}

// ── Mission Complete Popup ────────────────────────────────────────────────────
class _MissionCompletePopup extends StatelessWidget {
  final VoidCallback onClose;
  const _MissionCompletePopup({required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        color: const Color(0xF20F1A10),
        border: Border.all(color: const Color(0xFFF59E0B), width: 3),
        boxShadow: const [
          BoxShadow(color: Color(0xAA000000), offset: Offset(4, 4)),
          BoxShadow(color: Color(0x88FFD700), blurRadius: 28, spreadRadius: 3),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'MISSÃO CONCLUÍDA!',
            textAlign: TextAlign.center,
            style: GoogleFonts.pressStart2p(
              fontSize: 18,
              color: const Color(0xFFFFF3B0),
              height: 1.5,
              shadows: const [Shadow(color: Colors.black, offset: Offset(2, 2), blurRadius: 3)],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
            decoration: BoxDecoration(
              color: const Color(0x33FF4444),
              border: Border.all(color: const Color(0xFFEF4444), width: 1.5),
            ),
            child: Text(
              '⚠ PREPARE-SE PARA A MISSÃO FINAL',
              textAlign: TextAlign.center,
              style: GoogleFonts.pressStart2p(
                fontSize: 9,
                color: const Color(0xFFFF8888),
                height: 1.6,
                shadows: const [Shadow(color: Colors.black, offset: Offset(1.5, 1.5))],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Nexo estabilizado.\nO sinal foi enviado.',
            textAlign: TextAlign.center,
            style: GoogleFonts.pressStart2p(fontSize: 9, color: const Color(0xFFFFF7D6), height: 1.9),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0x2200FF88),
              border: Border.all(color: const Color(0xFF22C55E), width: 1.2),
            ),
            child: Text(
              'Explore o ambiente.\nVolte pela entrada para ir a missao final.',
              textAlign: TextAlign.center,
              style: GoogleFonts.pressStart2p(fontSize: 7, color: const Color(0xFF86EFAC), height: 1.8),
            ),
          ),
          const SizedBox(height: 20),
          _PixelButton(label: 'EXPLORAR AMBIENTE', onTap: onClose),
        ],
      ),
    );
  }
}

// ── Attack Button (círculo vermelho neon) ─────────────────────────────────────
class _AttackButton extends StatefulWidget {
  final VoidCallback? onTap;
  final bool enabled;
  const _AttackButton({required this.onTap, required this.enabled});

  @override
  State<_AttackButton> createState() => _AttackButtonState();
}

class _AttackButtonState extends State<_AttackButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) {
        setState(() => _pressed = false);
        if (widget.enabled && widget.onTap != null) widget.onTap!();
      },
      child: AnimatedScale(
        duration: const Duration(milliseconds: 70),
        scale: _pressed ? 0.88 : 1.0,
        child: Container(
          width: 136,
          height: 136,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.enabled ? const Color(0xDD2A0505) : const Color(0x884A4A4A),
            border: Border.all(
              color: widget.enabled ? Colors.redAccent : const Color(0xFF777777),
              width: 4,
            ),
            boxShadow: widget.enabled
                ? [
                    BoxShadow(
                        color: Colors.redAccent.withValues(alpha: 0.65),
                        blurRadius: 22,
                        spreadRadius: 3),
                    const BoxShadow(color: Color(0xAA0A0600), offset: Offset(0, 5)),
                  ]
                : const [BoxShadow(color: Color(0xAA0A0600), offset: Offset(0, 4))],
          ),
          alignment: Alignment.center,
          child: Text(
            'ATK',
            style: GoogleFonts.pressStart2p(
              fontSize: 13,
              color: widget.enabled ? Colors.redAccent : const Color(0xFFB0B0B0),
              shadows: const [Shadow(color: Colors.black, offset: Offset(2, 2))],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Pixel Button genérico ─────────────────────────────────────────────────────
class _PixelButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final Color borderColor;
  final Color textColor;

  const _PixelButton({
    required this.label,
    required this.onTap,
    this.borderColor = Colors.amber,
    this.textColor = const Color(0xFFFFF3B0),
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xCC0A0600),
          border: Border.all(color: borderColor, width: 2),
          boxShadow: [BoxShadow(color: borderColor.withValues(alpha: 0.3), blurRadius: 6)],
        ),
        child: Text(
          label,
          style: GoogleFonts.pressStart2p(
            fontSize: 10,
            color: textColor,
            shadows: const [Shadow(color: Colors.black, offset: Offset(1.5, 1.5), blurRadius: 3)],
          ),
        ),
      ),
    );
  }
}

// ── Dialog: Sargento Rocha (2 etapas) ────────────────────────────────────────
class _RochaDialog extends StatefulWidget {
  final VoidCallback onFormula;
  final VoidCallback onSurvive;
  const _RochaDialog({required this.onFormula, required this.onSurvive});

  @override
  State<_RochaDialog> createState() => _RochaDialogState();
}

class _RochaDialogState extends State<_RochaDialog> {
  int _step = 0;
  bool _cameFromH15 = false;

  Widget _buildOriginStep() => _wrap([
        _header(),
        const SizedBox(height: 10),
        _flavor('Rocha te olha de cima a baixo sem baixar a LMG do suporte.'),
        const SizedBox(height: 8),
        _speech('"Ei. Antes de qualquer coisa — de onde voce veio?\nEsse campus ta um inferno."'),
        const SizedBox(height: 18),
        Wrap(spacing: 12, runSpacing: 12, children: [
          _DialogButton(
            label: 'DO LABORATORIO H-15',
            onTap: () => setState(() { _cameFromH15 = true; _step = 1; }),
          ),
          _DialogButton(
            label: 'NAO E DA SUA CONTA',
            onTap: () => setState(() { _cameFromH15 = false; _step = 1; }),
            borderColor: const Color(0xFFEF4444),
            textColor: const Color(0xFFEF4444),
          ),
        ]),
      ]);

  Widget _buildMainStep() {
    final reaction = _cameFromH15
        ? 'Rocha relaxa os ombros.\n"H-15... entao voce sabe o que esta em jogo. Pode falar."'
        : 'Rocha sorri de canto.\n"Atrevimento. Gosto. Mas aqui sou eu que mando. Pode falar."';

    return _wrap([
      _header(),
      const SizedBox(height: 10),
      _flavor(reaction),
      const SizedBox(height: 12),
      _speech('"O CAA virou um ponto de colapso. O que voce veio buscar?"'),
      const SizedBox(height: 18),
      Wrap(spacing: 12, runSpacing: 12, children: [
        _DialogButton(label: 'ESTOU COM A FORMULA H-15', onTap: widget.onFormula),
        _DialogButton(label: 'SO QUERO SAIR VIVO', onTap: widget.onSurvive),
      ]),
    ]);
  }

  Widget _wrap(List<Widget> children) => Container(
        key: ValueKey(_step),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xE61A1208),
          border: Border.all(color: const Color(0xFFF5C842), width: 1.5),
        ),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children),
      );

  Widget _header() => Text('SARGENTO ROCHA',
      style: GoogleFonts.pressStart2p(fontSize: 10, color: const Color(0xFFF5C842)));

  Widget _flavor(String t) => Text(t,
      style: GoogleFonts.pressStart2p(fontSize: 7, color: const Color(0xFF9CA3AF), height: 1.9));

  Widget _speech(String t) => Text(t,
      style: GoogleFonts.pressStart2p(fontSize: 8, color: Colors.white, height: 1.9));

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: _step == 0 ? _buildOriginStep() : _buildMainStep(),
      );
}

// ── Dialog: Terminal ──────────────────────────────────────────────────────────
class _TerminalDialog extends StatelessWidget {
  final VoidCallback onRescue;
  final VoidCallback onData;
  const _TerminalDialog({required this.onRescue, required this.onData});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xE61A1208),
        border: Border.all(color: const Color(0xFFF5C842), width: 1.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('TERMINAL — NEXO DE TRANSMISSAO',
              style: GoogleFonts.pressStart2p(fontSize: 10, color: const Color(0xFFF5C842))),
          const SizedBox(height: 12),
          Text('Decida o destino do sinal de longo alcance.',
              style: GoogleFonts.pressStart2p(fontSize: 8, color: Colors.white, height: 1.8)),
          const SizedBox(height: 16),
          Wrap(spacing: 12, runSpacing: 12, children: [
            _DialogButton(label: 'SINAL DE RESGATE', onTap: onRescue),
            _DialogButton(label: 'SINAL DE DADOS', onTap: onData),
          ]),
        ],
      ),
    );
  }
}

// ── Dialog: Colete Encontrado ─────────────────────────────────────────────────
class _ColeteFoundDialog extends StatelessWidget {
  final VoidCallback onCollect;
  final VoidCallback onIgnore;
  const _ColeteFoundDialog({required this.onCollect, required this.onIgnore});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xE61A1208),
        border: Border.all(color: const Color(0xFF22C55E), width: 1.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ITEM ENCONTRADO',
              style: GoogleFonts.pressStart2p(fontSize: 10, color: const Color(0xFF22C55E))),
          const SizedBox(height: 14),
          Text('[Colete Balistico] — Dano dos zumbis reduzido 50%.',
              style: GoogleFonts.pressStart2p(fontSize: 7, color: Colors.white, height: 1.8)),
          const SizedBox(height: 16),
          Wrap(spacing: 12, runSpacing: 12, children: [
            _DialogButton(
              label: 'COLETAR',
              onTap: onCollect,
              borderColor: const Color(0xFF22C55E),
              textColor: const Color(0xFF22C55E),
            ),
            _DialogButton(label: 'DEIXAR', onTap: onIgnore),
          ]),
        ],
      ),
    );
  }
}

// ── Dialog Button ─────────────────────────────────────────────────────────────
class _DialogButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final Color borderColor;
  final Color textColor;

  const _DialogButton({
    required this.label,
    required this.onTap,
    this.borderColor = const Color(0xFFF5C842),
    this.textColor = const Color(0xFFF5C842),
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF2E1E06),
          border: Border.all(color: borderColor, width: 1.5),
        ),
        child: Text(
          label,
          style: GoogleFonts.pressStart2p(fontSize: 7, color: textColor, height: 1.6),
        ),
      ),
    );
  }
}
