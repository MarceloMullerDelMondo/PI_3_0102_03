import 'dart:convert';
import 'dart:math' as math;

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/experimental.dart' show Rectangle;
import 'package:flame/game.dart';
import 'package:flame_tiled/flame_tiled.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'h15_game.dart'
    show
        PlayerComponent,
        SolidObstacle,
        InvisibleWall,
        IsometricWall,
        InteractableZone;

import '../services/firebase_service.dart';
import 'sliding_archive.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Identificadores de zonas interagíveis
// ─────────────────────────────────────────────────────────────────────────────
abstract class ZoneIds {
  static const terminalPrefix  = 'terminal_';
  static String terminal(int n) => '${terminalPrefix}$n';
  static const quadroAvisos    = 'quadro_avisos';
  static const mesaRestauracao = 'mesa_restauracao';
  static const portaSaida      = 'porta_saida'; // chave da porta de emergência
}

// ─────────────────────────────────────────────────────────────────────────────
// Dados de lore dos terminais
// ─────────────────────────────────────────────────────────────────────────────
const List<TerminalLog> kTerminalLogs = [
  TerminalLog(
    title: 'TERMINAL 01 — LAB-BIO-003',
    entries: [
      '[2024-03-12 07:43] Sistema de ventilação desativado. Causa: sobrecarga elétrica.',
      '[2024-03-12 08:01] ALERTA: Contaminação detectada no setor B-7.',
      '[2024-03-12 08:15] Dr. Mendes: "Isolar o vetor. NÃO abrir as portas traseiras."',
      '[2024-03-12 09:02] Conexão perdida com servidor central. Backup local ativo.',
      '[2024-03-12 11:30] Último acesso registrado: Pesquisador ID 0047.',
    ],
  ),
  TerminalLog(
    title: 'TERMINAL 02 — ACERVO DIGITAL',
    entries: [
      '[2024-03-11 22:10] Download de 1.2 GB concluído — "Protocolo Ômega v4.2".',
      '[2024-03-11 22:45] AVISO: Acesso não autorizado ao arquivo SIGMA_ROOT.',
      '[2024-03-12 00:03] Firewall interno desativado por usuário: ADMIN_TEMP.',
      '[2024-03-12 03:17] Sistema de logs corrompido — dados parciais recuperados.',
      '[2024-03-12 06:59] ERRO 0xDEAD: Falha crítica no módulo de isolamento.',
    ],
  ),
  TerminalLog(
    title: 'TERMINAL 03 — REDE INTERNA',
    entries: [
      '[2024-03-10 14:00] Reunião de emergência convocada — sala 204.',
      '[2024-03-10 16:22] Memo: "Não discutir Projeto AURORA com externos."',
      '[2024-03-11 09:00] Acesso ao campus restrito a nível 3 ou superior.',
      '[2024-03-11 18:40] Câmeras do setor C desativadas. Manutenção programada.',
      '[2024-03-12 07:00] EVACUAÇÃO INICIADA — Protocolo Delta em vigor.',
    ],
  ),
];

class TerminalLog {
  final String title;
  final List<String> entries;
  const TerminalLog({required this.title, required this.entries});
}

// ─────────────────────────────────────────────────────────────────────────────
// BibliotecaGame — Fase 2: Biblioteca
// ─────────────────────────────────────────────────────────────────────────────
class BibliotecaGame extends FlameGame with HasCollisionDetection {
  final String playerName;
  BibliotecaGame({this.playerName = ''});

  static const bool showDebugWalls = false;
  static final Vector2 _fallbackMapSize = Vector2(870, 1024);
  // Jogador entra pelo FUNDO do mapa, sobe até a saída no topo-esquerdo
  static final Vector2 _h15EntrySpawn = Vector2(435, 950);

  // ── Posições fallback (espelham as zonas acessíveis) ─────────────────────
  // Terminais ABAIXO da colisão dos computadores (y>545)
  static final List<({Vector2 pos, Vector2 size})> _terminalSpawns = [
    (pos: Vector2(50,  548), size: Vector2(70, 50)),
    (pos: Vector2(130, 548), size: Vector2(70, 50)),
    (pos: Vector2(200, 548), size: Vector2(70, 50)),
  ];
  // Quadro no corredor central, frente à parede do fundo
  static final _quadroPos  = Vector2(295, 45);
  static final _quadroSize = Vector2(150, 55);

  // ── Mapa de Evacuação — corredor central (x=300, y=580 livre) ─────────────
  static final _mapaEvacuacaoPos = Vector2(300, 580);

  // ── Cartão de Acesso — área inferior-direita livre ────────────────────────
  static final _cartaoAcessoPos = Vector2(580, 880);

  // ── Porta de saída — canto superior esquerdo (porta do elevador) ─────────
  static final _portaSaidaPos  = Vector2(0, 0);
  static final _portaSaidaSize = Vector2(170, 150);

  // ── Estado público ──────────────────────────────────────────────────────────
  PlayerComponent? player;
  JoystickComponent? _joystick;
  SpriteComponent? _background;
  Vector2 _mapSize = _fallbackMapSize.clone();
  final List<SolidObstacle> _walls = [];
  final List<InteractableZone> _interactables = [];
  final List<SlidingArchiveComponent> _archives = [];
  final List<_BibliotecaZombie> _zombies = [];
  final math.Random _rng = math.Random();

  /// Expõe as paredes para os zumbis verificarem colisão.
  List<SolidObstacle> get walls => _walls;

  // ── Pontos de spawn nas áreas VERDES (corredores livres) ──────────────────
  // Mapeados com base nos objetos visíveis na biblioteca_nova.png
  static final List<Vector2> _safeSpawnPoints = [
    // Corredor central vertical (x=290-430)
    Vector2(360, 200),
    Vector2(360, 350),
    Vector2(360, 460),
    Vector2(360, 610),
    Vector2(360, 660),
    // Corredor direito superior (x=680-825, y=40-415)
    Vector2(750,  90),
    Vector2(750, 220),
    Vector2(750, 340),
    // Área inferior aberta (y=815-980)
    Vector2(200, 880),
    Vector2(360, 910),
    Vector2(500, 890),
    Vector2(720, 880),
    // Topo-esquerda (x=40-295, y=40-140)
    Vector2(170,  80),
    // Entre armário e chão (x=40-295, y=690-730)
    Vector2(120, 710),
  ];

  // ── ValueNotifiers ──────────────────────────────────────────────────────────
  final double maxHealth = 100;
  final ValueNotifier<double> currentHealth    = ValueNotifier(100);
  final ValueNotifier<int>    survivalSeconds  = ValueNotifier(0);
  final ValueNotifier<String> missionText      =
      ValueNotifier('Objetivo: Explorar a biblioteca');
  final ValueNotifier<bool>    canInteract          = ValueNotifier(false);
  final ValueNotifier<bool>    questDialogOpen      = ValueNotifier(false);
  final ValueNotifier<bool>    attackEnabled        = ValueNotifier(false);
  final ValueNotifier<bool>    missionCompletedPopup = ValueNotifier(false);
  final ValueNotifier<bool>    gameOver             = ValueNotifier(false);
  final ValueNotifier<String?> equippedWeapon       = ValueNotifier(null);
  final ValueNotifier<String?> hudMessage           = ValueNotifier(null);
  final ValueNotifier<bool>    minimapFogRemoved    = ValueNotifier(false);
  final ValueNotifier<int>     zombiesKilled        = ValueNotifier(0);

  /// IDs de itens já coletados nesta sessão (evita coleta dupla por re-spawn).
  final Set<String> _collectedLootIds = {};

  String? activeZoneId;
  late Vector2 lastCheckpoint;
  double _survivalAccumulator = 0;
  final List<_DustParticleSystem> _dustSystems = [];

  /// Sinaliza flash de dano na tela (HUD escuta e exibe overlay vermelho)
  final ValueNotifier<bool> playerHitFlash = ValueNotifier(false);

  @override
  Color backgroundColor() => const Color(0xFF8B7355);

  // ── onLoad ──────────────────────────────────────────────────────────────────
  @override
  Future<void> onLoad() async {
    await super.onLoad();
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    _mapSize = await _loadTiledCollisions();

    camera.viewfinder.anchor   = Anchor.center;
    camera.viewfinder.position = _h15EntrySpawn.clone();

    // Background
    try {
      final bgSprite = await _loadBibliotecaBackground();
      _background = SpriteComponent(
          sprite: bgSprite, size: _mapSize,
          position: Vector2.zero(), priority: -10);
      world.add(_background!);
    } catch (_) {
      world.add(_FallbackBackground(size: _mapSize));
    }

    // Jogador
    final playerImage = await images.load('player/player_sprite.jpg');
    lastCheckpoint = _h15EntrySpawn.clone();
    final playerComponent = PlayerComponent.fromSpriteSheet(playerImage)
      ..position = lastCheckpoint.clone()
      ..priority  = 5;
    player = playerComponent;
    await world.add(playerComponent);

    // Câmera
    camera.viewfinder.zoom = 1.2;
    camera.setBounds(Rectangle.fromLTWH(0, 0, _mapSize.x, _mapSize.y));
    camera.follow(playerComponent, snap: true);

    _setupDustParticleSystems();
    _setupInteractableZones();   // ← zonas de interação

    // ── Mapa de Evacuação — item físico no cenário ───────────────────────────
    // Aparece imediatamente visível na Mesa Central.
    // Ao encostar, onLootCollected é chamado com ItemIds.mapaEvacuacao.
    final mapaEvacuacaoItem = HiddenLootItem(
      itemId: ItemIds.mapaEvacuacao,
      position: _mapaEvacuacaoPos,
    )..priority = 4;
    await world.add(mapaEvacuacaoItem);
    mapaEvacuacaoItem.reveal(); // força visibilidade imediata (sem gatilho de trigger)

    // ── Cartão de Acesso — item no fundo da biblioteca ───────────────────────
    // Necessário para entrar no Refeitório (Fase 3).
    final cartaoItem = HiddenLootItem(
      itemId: ItemIds.cartaoAcesso,
      position: _cartaoAcessoPos,
    )..priority = 4;
    await world.add(cartaoItem);
    cartaoItem.reveal();

    // ── Carrega a arma escolhida no H15 (salva em SharedPreferences) ─────────
    await _restoreWeapon();

    // ── Timer de spawn de zumbis (1 a cada 4 s, máx 7 na biblioteca) ────────
    add(TimerComponent(
      period: 4.0,
      repeat: true,
      onTick: _spawnZombie,
    ));

    // Joystick
    final joystickComponent = JoystickComponent(
      knob: CircleComponent(radius: 26,
          paint: Paint()..color = const Color(0xFFF5C842)),
      background: CircleComponent(radius: 68,
          paint: Paint()..color = const Color(0xAAE5E7EB)),
      margin: const EdgeInsets.only(left: 28, bottom: 28),
      priority: 200,
    );
    _joystick = joystickComponent;
    camera.viewport.add(joystickComponent);
  }

  Future<Sprite> _loadBibliotecaBackground() async {
    try {
      return await loadSprite('screens/biblioteca_nova.png');
    } catch (_) {
      return loadSprite('screens/biblioteca.jpg');
    }
  }

  // ── Configuração das zonas de interação ─────────────────────────────────────
  void _setupInteractableZones() {
    // Terminais
    for (var i = 0; i < _terminalSpawns.length; i++) {
      final s = _terminalSpawns[i];
      final zone = InteractableZone(
          zoneId: ZoneIds.terminal(i + 1),
          position: s.pos, size: s.size);
      _interactables.add(zone);
      world.add(zone);
    }

    // Quadro de avisos
    world.add(InteractableZone(
        zoneId: ZoneIds.quadroAvisos,
        position: _quadroPos, size: _quadroSize)
      ..let((z) => _interactables.add(z)));

    // Porta de saída de emergência (liberada pelo Mapa de Evacuação)
    world.add(InteractableZone(
        zoneId: ZoneIds.portaSaida,
        position: _portaSaidaPos, size: _portaSaidaSize)
      ..let((z) => _interactables.add(z)));

    debugPrint('Zonas criadas: ${_interactables.length}');
  }

  // ── Dispatcher de interação ──────────────────────────────────────────────────

  /// Chamado pelo botão INTERAGIR no HUD Flutter.
  Future<void> interact() async {
    if (!canInteract.value || questDialogOpen.value) return;
    final zoneId = activeZoneId;
    if (zoneId == null) return;

    if (zoneId.startsWith(ZoneIds.terminalPrefix)) {
      final idx = (int.tryParse(
              zoneId.substring(ZoneIds.terminalPrefix.length)) ?? 1) - 1;
      _openTerminal(idx.clamp(0, kTerminalLogs.length - 1));
      return;
    }
    switch (zoneId) {
      case ZoneIds.quadroAvisos:
        _openQuadroAvisos();
      case ZoneIds.portaSaida:
        await _tryExitThroughDoor();
    }
  }

  void _openTerminal(int index) {
    questDialogOpen.value = true;
    overlays.add('Terminal_$index');
  }

  void closeTerminal(int index) {
    overlays.remove('Terminal_$index');
    questDialogOpen.value = false;
  }

  void _openQuadroAvisos() {
    questDialogOpen.value = true;
    overlays.add('QuadroAvisos');
  }

  /// Abre o mapa do campus a qualquer momento (botão VER MAPA no HUD).
  void showMapa() => _openQuadroAvisos();

  void closeQuadroAvisos() {
    overlays.remove('QuadroAvisos');
    questDialogOpen.value = false;
  }

  // ── Porta de saída de emergência ─────────────────────────────────────────────

  /// Sai pela porta de emergência — avança para a próxima fase.
  Future<void> _tryExitThroughDoor() async {
    if (missionCompletedPopup.value) return; // evita duplo disparo

    showHudMessage('🚪 Saindo para o Refeitório...');
    await syncFaseProgress();

    // Aguarda a mensagem aparecer antes de transicionar
    await Future<void>.delayed(const Duration(seconds: 2));
    missionCompletedPopup.value = true;
  }

  // ── Salvar progresso ─────────────────────────────────────────────────────────
  Future<void> syncFaseProgress() async {
    await FirebaseService.instance.unlockNextPhase(playerName);
    showHudMessage('✅ Progresso salvo com sucesso!');
  }

  // ── Zona enter/exit ──────────────────────────────────────────────────────────
  void enterInteractableZone(String zoneId) {
    activeZoneId = zoneId;
    // Saída automática: basta o jogador pisar na zona
    if (zoneId == ZoneIds.portaSaida) {
      _tryExitThroughDoor();
      return;
    }
    canInteract.value = true;
  }

  void exitInteractableZone(String zoneId) {
    if (activeZoneId != zoneId) return;
    activeZoneId  = null;
    canInteract.value = false;
  }

  // ── Update ──────────────────────────────────────────────────────────────────
  @override
  void update(double dt) {
    super.update(dt);
    _updateSurvivalTimer(dt);
    final p = player;
    final j = _joystick;
    if (p == null || j == null) return;
    p.move(j.relativeDelta, dt, _mapSize, _walls, archives: _archives);
  }

  // ── Tiled ───────────────────────────────────────────────────────────────────
  Future<Vector2> _loadTiledCollisions() async {
    late final String raw;
    try {
      raw = await rootBundle.loadString('assets/tiles/biblioteca.json');
    } catch (e) {
      debugPrint('biblioteca.json não encontrado: $e');
      return _fallbackMapSize.clone();
    }

    _loadWindowPositionsFromJson(raw);

    late final TiledMap tiledMap;
    try {
      tiledMap = TileMapParser.parseJson(raw);
    } catch (e) {
      debugPrint('Tiled parse falhou: $e');
      return _loadTiledCollisionsFromJson(raw);
    }

    final mapSize = _readTiledImageSize(tiledMap);

    for (final layer in tiledMap.layers) {
      if (layer is ObjectGroup && layer.name == 'Colisoes') {
        for (final obj in layer.objects) {
          final o = _buildTiledObstacle(obj);
          if (o == null) continue;
          _walls.add(o);
          world.add(o);
        }
      }
    }

    _loadInteractableZonesFromTiled(tiledMap);
    return mapSize;
  }

  /// Substitui as zonas hardcoded pelas definidas no Tiled (camada "Interagiveis").
  void _loadInteractableZonesFromTiled(TiledMap tiledMap) {
    ObjectGroup? layer;
    for (final l in tiledMap.layers) {
      if (l is ObjectGroup && l.name == 'Interagiveis') {
        layer = l;
        break;
      }
    }
    if (layer == null) return;

    for (final z in _interactables) z.removeFromParent();
    _interactables.clear();

    for (final obj in layer.objects) {
      final zoneId = obj.properties.getValue<String>('zoneId')?.toString();
      if (zoneId == null || zoneId.isEmpty) continue;
      final zone = InteractableZone(
        zoneId: zoneId,
        position: Vector2(obj.x, obj.y),
        size: Vector2(
            obj.width.clamp(20, 9999).toDouble(),
            obj.height.clamp(20, 9999).toDouble()),
      );
      _interactables.add(zone);
      world.add(zone);
    }
    debugPrint('Zonas do Tiled: ${_interactables.length}');
  }

  final List<Vector2> _windowCenters = [];

  void _loadWindowPositionsFromJson(String raw) {
    _windowCenters.clear();
    final map = jsonDecode(raw) as Map<String, dynamic>;
    final layers = (map['layers'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>();
    for (final layer in layers) {
      if ((layer['name'] as String? ?? '') != 'Janelas') continue;
      for (final obj in (layer['objects'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()) {
        final x = (obj['x'] as num? ?? 0).toDouble();
        final y = (obj['y'] as num? ?? 0).toDouble();
        final w = (obj['width']  as num? ?? 0).toDouble();
        final h = (obj['height'] as num? ?? 0).toDouble();
        _windowCenters.add(Vector2(x + w / 2, y + h / 2));
      }
    }
  }

  Vector2 _loadTiledCollisionsFromJson(String raw) {
    final map     = jsonDecode(raw) as Map<String, dynamic>;
    final mapSize = _readTiledImageSizeFromJson(map);
    final layers  = (map['layers'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>();
    for (final l in layers) {
      if (l['name'] != 'Colisoes') continue;
      for (final obj in (l['objects'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()) {
        final o = _buildJsonTiledObstacle(obj);
        if (o == null) continue;
        _walls.add(o);
        world.add(o);
      }
    }
    return mapSize;
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
      final w = (l['imagewidth']  as num?)?.toDouble();
      final h = (l['imageheight'] as num?)?.toDouble();
      if (w != null && h != null) return Vector2(w, h);
    }
    return _fallbackMapSize.clone();
  }

  SolidObstacle? _buildTiledObstacle(TiledObject o) {
    final x = o.x; final y = o.y;
    if (o.polygon.isNotEmpty) {
      final verts = o.polygon.map((p) => Vector2(x + p.x, y + p.y)).toList();
      if (verts.length >= 3)
        return IsometricWall(vertices: verts, showDebug: showDebugWalls)..priority = 1;
      return null;
    }
    var w = o.width; var h = o.height;
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
      final verts = polygon.whereType<Map<String, dynamic>>()
          .map((p) => Vector2(x + (p['x'] as num? ?? 0).toDouble(),
                              y + (p['y'] as num? ?? 0).toDouble()))
          .toList();
      if (verts.length >= 3)
        return IsometricWall(vertices: verts, showDebug: showDebugWalls)..priority = 1;
      return null;
    }
    var w = (o['width']  as num? ?? 0).toDouble();
    var h = (o['height'] as num? ?? 0).toDouble();
    const m = 6.0;
    if (w <= 0 && h <= 0) return null;
    if (w <= 0) w = m;
    if (h <= 0) h = m;
    return InvisibleWall(
        position: Vector2(x, y), size: Vector2(w, h), showDebug: showDebugWalls)
      ..priority = 1;
  }

  // ── Partículas ───────────────────────────────────────────────────────────────
  void _setupDustParticleSystems() {
    final positions = _windowCenters.isNotEmpty
        ? _windowCenters : _fallbackWindowPositions();
    for (final center in positions) {
      final system = _DustParticleSystem(center: center);
      _dustSystems.add(system);
      world.add(system..priority = 50);
    }
  }

  List<Vector2> _fallbackWindowPositions() {
    final positions = <Vector2>[];
    final stepY = _mapSize.y / 5;
    for (var i = 1; i <= 4; i++) {
      positions.add(Vector2(80, stepY * i));
      positions.add(Vector2(_mapSize.x - 80, stepY * i));
    }
    return positions;
  }

  // ── Utilitários públicos ─────────────────────────────────────────────────────
  void damagePlayer(double amount) {
    if (gameOver.value) return;
    currentHealth.value = (currentHealth.value - amount).clamp(0, maxHealth).toDouble();
    // Flash vermelho na tela (igual ao efeito visual do H15)
    playerHitFlash.value = true;
    Future<void>.delayed(const Duration(milliseconds: 200), () {
      playerHitFlash.value = false;
    });
    if (currentHealth.value <= 0) _triggerGameOver();
  }

  Future<void> healPlayer(double baseAmount) async {
    if (gameOver.value) return;
    final mult = await FirebaseService.instance.loadHealBonusMultiplier();
    currentHealth.value = (currentHealth.value + baseAmount * mult).clamp(0, maxHealth).toDouble();
  }

  void _triggerGameOver() {
    if (gameOver.value) return;
    gameOver.value = true;
    overlays.add('GameOver');
    pauseEngine();
  }

  void reviveAtCheckpoint() {
    overlays.remove('GameOver');
    gameOver.value    = false;
    currentHealth.value = maxHealth;
    player?.position  = lastCheckpoint.clone();
    resumeEngine();
  }

  void showHudMessage(String message) {
    hudMessage.value = message;
    Future<void>.delayed(const Duration(seconds: 3), () {
      if (hudMessage.value == message) hudMessage.value = null;
    });
  }

  // ── Restaura a arma escolhida no H15 ────────────────────────────────────────
  Future<void> _restoreWeapon() async {
    attackEnabled.value = true;

    final saved = await FirebaseService.instance.loadWeapon();
    final weapon = (saved != null && saved.isNotEmpty) ? saved : 'Espada 1 Mão';
    equippedWeapon.value = weapon;

    // Carrega o sprite sheet correspondente à arma escolhida
    final sheetAsset = weapon == 'Duas Adagas'
        ? 'player/player_espada2mao.png'
        : 'player/player_espada1mao.png';
    try {
      final sheet = await images.load(sheetAsset);
      player?.useWeaponSpriteSheet(sheet);
    } catch (e) {
      debugPrint('[Biblioteca] Sprite da arma não carregado: $e');
    }
  }

  // ── Handler de coleta de loot ────────────────────────────────────────────────

  /// Chamado pelo [HiddenLootItem] quando o jogador coleta o item.
  Future<void> onLootCollected(String itemId) async {
    // Idempotência — evita efeito duplo se o componente for recriado
    if (_collectedLootIds.contains(itemId)) return;
    _collectedLootIds.add(itemId);

    debugPrint('[Biblioteca] Item coletado: $itemId');

    switch (itemId) {
      // ── Munição ─────────────────────────────────────────────────────────────
      case 'municao':
        await FirebaseService.instance.addItem(playerName, 'municao');
        showHudMessage('🔴  Munição coletada!');

      // ── Mapa do Campus ───────────────────────────────────────────────────────
      // Remove a névoa de guerra do minimapa via ValueNotifier.
      // O widget Flutter do minimapa escuta [minimapFogRemoved] e reage.
      case ItemIds.mapaCampus:
        await FirebaseService.instance.addItem(playerName, ItemIds.mapaCampus);
        minimapFogRemoved.value = true;
        showHudMessage('🗺️  Mapa do Campus obtido! Minimapa revelado.');

      // ── Ponteiro Laser ───────────────────────────────────────────────────────
      // Salva no Firebase; bônus de precisão implementado no sistema de combate.
      case ItemIds.ponteiroLaser:
        await FirebaseService.instance.addItem(playerName, ItemIds.ponteiroLaser);
        showHudMessage('🔴  Ponteiro Laser coletado!');

      // ── Livro de Primeiros Socorros ──────────────────────────────────────────
      // Salva flag permanente de +10 % de eficácia de cura via Firebase/Prefs.
      case ItemIds.livroPrimeirosSocorros:
        await FirebaseService.instance.collectFirstAidBook(playerName);
        showHudMessage('📖  Livro de Primeiros Socorros: cura +10 % permanente!');

      // ── Mapa de Evacuação ────────────────────────────────────────────────────
      // Registra no inventário, atualiza HUD e muda o objetivo da missão.
      // A porta de saída lê o inventário para liberar ou bloquear a saída.
      case ItemIds.mapaEvacuacao:
        await FirebaseService.instance.addItem(playerName, ItemIds.mapaEvacuacao);
        showHudMessage('🗺️ Mapa de Evacuação coletado! Rota segura descoberta.');
        missionText.value = 'Objetivo: Fuja pela porta de emergência';

      // ── Cartão de Acesso ─────────────────────────────────────────────────────
      // Salvo no inventário; libera a entrada no Refeitório Central (Fase 3).
      case ItemIds.cartaoAcesso:
        await FirebaseService.instance.addItem(playerName, ItemIds.cartaoAcesso);
        showHudMessage('🪪 Cartão de Acesso encontrado! Refeitório desbloqueado.');
        missionText.value = 'Objetivo: Saia pela porta de emergência';

      default:
        await FirebaseService.instance.addItem(playerName, itemId);
        showHudMessage('📦  Item coletado: $itemId');
    }
  }

  void _updateSurvivalTimer(double dt) {
    _survivalAccumulator += dt;
    if (_survivalAccumulator < 1) return;
    final elapsed = _survivalAccumulator.floor();
    _survivalAccumulator -= elapsed;
    survivalSeconds.value += elapsed;
  }

  // ── Spawn de zumbis — apenas nas áreas verdes (pontos pré-definidos) ────────
  void _spawnZombie() {
    if (gameOver.value) return;
    if (_zombies.length >= 7) return;
    final p = player;
    if (p == null) return;

    // Filtra pontos que não colidem com paredes e estão longe do jogador
    final candidates = _safeSpawnPoints.where((pt) {
      // Deve estar longe o suficiente do jogador (>150px)
      if ((pt - p.position).length < 150) return false;
      // Não deve sobrepor nenhuma parede
      final r = Rect.fromCenter(center: Offset(pt.x, pt.y), width: 80, height: 80);
      return !_walls.any((w) => w.overlapsRect(r));
    }).toList();

    if (candidates.isEmpty) return;

    // Escolhe um ponto aleatório dentre os válidos
    final pos = candidates[_rng.nextInt(candidates.length)].clone();
    final zombie = _BibliotecaZombie(target: p, startPos: pos);
    _zombies.add(zombie);
    world.add(zombie);
  }

  // ── Ataque do jogador ────────────────────────────────────────────────────────
  void attack() {
    if (!attackEnabled.value || gameOver.value) return;
    player?.startAttack();
    final p = player;
    if (p == null) return;

    final attackRect = p.weaponAttackRect(equippedWeapon.value);
    final dead = <_BibliotecaZombie>[];

    for (final z in _zombies) {
      if (!z.isMounted) continue;
      if (attackRect.overlaps(z.hitRect)) {
        if (z.takeDamage(9)) dead.add(z);
      }
    }
    for (final z in dead) {
      z.removeFromParent();
      _zombies.remove(z);
      zombiesKilled.value++;
    }
  }

  /// Chamado pelo [_BibliotecaZombie] quando ele é destruído por colisão.
  void onZombieDead(_BibliotecaZombie z) {
    _zombies.remove(z);
    zombiesKilled.value++;
  }
}

// ── Extensão auxiliar (evita criar variáveis temporárias) ────────────────────
extension _Let<T> on T {
  T let(void Function(T) f) { f(this); return this; }
}

// ─────────────────────────────────────────────────────────────────────────────
// _BibliotecaZombie — zumbi simples que persegue o jogador
// ─────────────────────────────────────────────────────────────────────────────
// _BibliotecaZombie — comportamento idêntico ao ZombieComponent do H15
// ─────────────────────────────────────────────────────────────────────────────
enum _ZAnim { idle, walkDown, walkLeft, walkRight, walkUp,
              attackDown, attackLeft, attackRight, attackUp }

class _BibliotecaZombie extends SpriteAnimationComponent
    with CollisionCallbacks, HasGameReference<BibliotecaGame> {

  final PlayerComponent target;
  static const double _speed          = 55.0;
  static const double _hitCooldown    = 1.2;
  static const double _touchDamage    = 1.0;
  static const double _walkStep       = 0.15;
  static const double _atkStep        = 0.08;
  static final Vector2 _frameSize     = Vector2(148, 140);

  int    health        = 15;
  double _hitTimer     = 0;
  double _hurtFlash    = 0;
  bool   _isAttacking  = false;
  _ZAnim _lastMove     = _ZAnim.walkDown;
  _ZAnim _currentAnim  = _ZAnim.idle;
  final Map<_ZAnim, SpriteAnimation> _anims = {};
  Vector2? _lastSafe;

  _BibliotecaZombie({required this.target, required Vector2 startPos})
      : super(size: Vector2(96, 96), anchor: Anchor.center,
               position: startPos, priority: 4, autoResize: false);

  Rect get hitRect => Rect.fromCenter(
      center: Offset(position.x, position.y),
      width: size.x * 0.72, height: size.y * 0.76);

  bool takeDamage(int dmg) {
    health -= dmg;
    _hurtFlash = 0.20;
    return health <= 0;
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    try {
      final sheet = await game.images.load('zumbis/zumbi_normal.png');

      SpriteAnimation row(double yOff, {double step = _walkStep, bool loop = true}) =>
          SpriteAnimation.fromFrameData(sheet, SpriteAnimationData.sequenced(
            amount: 4, stepTime: step,
            textureSize: _frameSize, texturePosition: Vector2(0, yOff), loop: loop));

      _anims.addAll({
        _ZAnim.idle:        row(0),
        _ZAnim.walkDown:    row(0),
        _ZAnim.walkRight:   row(140),
        _ZAnim.walkLeft:    row(280),
        _ZAnim.walkUp:      row(0),
        _ZAnim.attackDown:  row(0,   step: _atkStep, loop: false),
        _ZAnim.attackRight: row(140, step: _atkStep, loop: false),
        _ZAnim.attackLeft:  row(280, step: _atkStep, loop: false),
        _ZAnim.attackUp:    row(0,   step: _atkStep, loop: false),
      });
      _setAnim(_ZAnim.idle);
    } catch (_) {}

    add(RectangleHitbox(
      position: Vector2(size.x * .14, size.y * .12),
      size:     Vector2(size.x * .72, size.y * .76),
    ));
  }

  void _setAnim(_ZAnim next) {
    if (_currentAnim == next && animation != null) return;
    final a = _anims[next];
    if (a == null) return;
    _currentAnim = next;
    animation = a;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_hurtFlash > 0) { _hurtFlash -= dt; if (_hurtFlash <= 0) setOpacity(1.0); }
    if (_hitTimer  > 0) _hitTimer -= dt;
    if (_isAttacking && (animationTicker?.done() ?? false)) {
      _isAttacking = false;
      _setAnim(_lastMove);
    }
    if (!target.isMounted) return;

    final dir = target.position - position;
    if (dir.length2 < 16) { if (!_isAttacking) _setAnim(_ZAnim.idle); return; }
    if (!_isAttacking) _updateDir(dir);

    final delta = dir.normalized() * _speed * dt;
    _tryMove(Vector2(delta.x, 0));
    _tryMove(Vector2(0, delta.y));

    // Separação de outros zumbis
    for (final z in game._zombies) {
      if (identical(z, this) || !z.isMounted) continue;
      _separateFrom(z);
    }
  }

  void _updateDir(Vector2 dir) {
    if (dir.x.abs() > dir.y.abs()) {
      _setAnim(dir.x > 0 ? _ZAnim.walkRight : _ZAnim.walkLeft);
    } else {
      _setAnim(dir.y > 0 ? _ZAnim.walkDown : _ZAnim.walkUp);
    }
    _lastMove = _currentAnim;
  }

  void _tryMove(Vector2 delta) {
    _lastSafe = position.clone();
    position += delta;
    final ms = game._mapSize;
    final hw = size.x / 2; final hh = size.y / 2;
    position = Vector2(position.x.clamp(hw, ms.x - hw).toDouble(),
                       position.y.clamp(hh, ms.y - hh).toDouble());
    if (_hitsWall()) position = _lastSafe!;
  }

  bool _hitsWall() {
    final r = hitRect;
    for (final w in game.walls) { if (w.overlapsRect(r)) return true; }
    return false;
  }

  void _separateFrom(_BibliotecaZombie other) {
    var away = position - other.position;
    if (away.length2 < 0.0001)
      away = Vector2(math.cos(position.x), math.sin(position.y));
    final minDist = size.x * 0.48;
    final dist = away.length;
    if (dist >= minDist) return;
    position += away.normalized() * ((minDist - dist) * 0.5 + 0.8);
    final ms = game._mapSize;
    final hw = size.x / 2; final hh = size.y / 2;
    position = Vector2(position.x.clamp(hw, ms.x - hw).toDouble(),
                       position.y.clamp(hh, ms.y - hh).toDouble());
    if (_hitsWall()) { final s = _lastSafe; if (s != null) position = s; }
  }

  @override
  void onCollision(Set<Vector2> pts, PositionComponent other) {
    super.onCollision(pts, other);
    // Parede → volta para posição segura
    if (other is SolidObstacle || other.parent is SolidObstacle) {
      final s = _lastSafe;
      if (s != null) position = s;
      return;
    }
    // Outro zumbi → separação
    if (other is _BibliotecaZombie || other.parent is _BibliotecaZombie) return;
    // Jogador → dano com cooldown (igual H15)
    final isPlayer = other is PlayerComponent || other.parent is PlayerComponent;
    if (isPlayer && _hitTimer <= 0) {
      _hitTimer = _hitCooldown;
      game.damagePlayer(_touchDamage);
      _startAttack();
    }
  }

  void _startAttack() {
    _isAttacking = true;
    final atkAnim = switch (_lastMove) {
      _ZAnim.walkLeft  => _ZAnim.attackLeft,
      _ZAnim.walkRight => _ZAnim.attackRight,
      _ZAnim.walkUp    => _ZAnim.attackUp,
      _               => _ZAnim.attackDown,
    };
    _setAnim(atkAnim);
    animationTicker?.reset();
  }

  @override
  void render(Canvas canvas) {
    // Sombra
    canvas.drawOval(
      Rect.fromCenter(center: Offset(size.x / 2, size.y + 3),
          width: size.x * .85, height: 7),
      Paint()..color = Colors.black.withValues(alpha: 0.35),
    );
    super.render(canvas);
    if (_hurtFlash > 0) {
      final t = (_hurtFlash / 0.20).clamp(0.0, 1.0);
      canvas.drawRect(Rect.fromLTWH(0, 0, size.x, size.y),
          Paint()..color = Colors.red.withValues(alpha: t * 0.55));
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _DustParticleSystem
// ─────────────────────────────────────────────────────────────────────────────
class _DustParticle {
  Vector2 position, velocity;
  double alpha, radius, life, maxLife;
  _DustParticle({required this.position, required this.velocity,
    required this.alpha, required this.radius,
    required this.life, required this.maxLife});
}

class _DustParticleSystem extends Component {
  static const int    _maxParticles = 35;
  static const double _spawnRadius  = 90.0;
  static const double _maxSpeed     = 18.0;
  final Vector2 center;
  final math.Random _rng = math.Random();
  final List<_DustParticle> _particles = [];

  _DustParticleSystem({required this.center}) : super();

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    for (var i = 0; i < _maxParticles; i++)
      _particles.add(_spawnParticle(initialPhase: true));
  }

  _DustParticle _spawnParticle({bool initialPhase = false}) {
    final angle   = _rng.nextDouble() * math.pi * 2;
    final dist    = _rng.nextDouble() * _spawnRadius;
    final pos     = center + Vector2(math.cos(angle) * dist, math.sin(angle) * dist);
    final vx      = (_rng.nextDouble() - 0.5) * _maxSpeed * 0.6;
    final vy      = -(_rng.nextDouble() * _maxSpeed * 0.5 + 2);
    final maxLife = 4.0 + _rng.nextDouble() * 4.0;
    return _DustParticle(
      position: pos, velocity: Vector2(vx, vy), alpha: 0.0,
      radius: 0.8 + _rng.nextDouble() * 1.8,
      life: initialPhase ? _rng.nextDouble() * maxLife : 0.0,
      maxLife: maxLife,
    );
  }

  @override
  void update(double dt) {
    super.update(dt);
    for (var i = 0; i < _particles.length; i++) {
      final p = _particles[i];
      p.life += dt;
      if (p.life >= p.maxLife) { _particles[i] = _spawnParticle(); continue; }
      final t = p.life / p.maxLife;
      if      (t < 0.20) p.alpha = (t / 0.20).clamp(0.0, 1.0) * 0.75;
      else if (t > 0.75) p.alpha = ((1.0 - t) / 0.25).clamp(0.0, 1.0) * 0.75;
      else               p.alpha = 0.75;
      final drift = math.sin(p.life * 1.2 + p.position.y * 0.01) * _maxSpeed * 0.3;
      p.position += Vector2(p.velocity.x + drift, p.velocity.y) * dt;
    }
  }

  @override
  void render(Canvas canvas) {
    for (final p in _particles) {
      if (p.alpha <= 0) continue;
      canvas.drawCircle(Offset(p.position.x, p.position.y), p.radius,
          Paint()..color = const Color(0xFFFFF8DC).withValues(alpha: p.alpha));
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _FallbackBackground
// ─────────────────────────────────────────────────────────────────────────────
class _FallbackBackground extends PositionComponent {
  _FallbackBackground({required Vector2 size})
      : super(position: Vector2.zero(), size: size, priority: -10);

  @override
  void render(Canvas canvas) {
    canvas.drawRect(size.toRect(), Paint()..color = const Color(0xFF5C4033));
    final paint = Paint()..color = const Color(0x22FFFFFF)..strokeWidth = 1;
    const step = 128.0;
    for (var x = 0.0; x < size.x; x += step)
      canvas.drawLine(Offset(x, 0), Offset(x, size.y), paint);
    for (var y = 0.0; y < size.y; y += step)
      canvas.drawLine(Offset(0, y), Offset(size.x, y), paint);
  }
}
