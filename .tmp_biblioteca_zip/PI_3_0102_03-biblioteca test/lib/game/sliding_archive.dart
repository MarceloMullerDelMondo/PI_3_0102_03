import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'h15_game.dart' show SolidObstacle, InvisibleWall, PlayerComponent;
import 'biblioteca_game.dart' show BibliotecaGame;
import '../services/firebase_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Enums e constantes
// ─────────────────────────────────────────────────────────────────────────────

/// Eixo ao longo do qual o arquivo pode deslizar.
/// Definido pela propriedade `slideAxis` do objeto no Tiled ('horizontal' | 'vertical').
enum SlideAxis { horizontal, vertical }

/// Velocidade de deslizamento do arquivo — muito menor que o jogador (180 px/s).
const double kArchiveSlideSpeed = 48.0;

/// Distância máxima de deslizamento a partir da posição original (px).
const double kArchiveMaxSlide = 240.0;

/// Tamanho visual padrão de um arquivo (usado no fallback sem sprite).
final Vector2 kArchiveDefaultSize = Vector2(72, 96);

// ─────────────────────────────────────────────────────────────────────────────
// SlidingArchiveComponent
//
// Herda de SpriteComponent para exibir o sprite do arquivo.
// Possui uma RectangleHitbox SÓLIDA (isSolid: true) que bloqueia o jogador
// e é usada para detectar colisão de outros arquivos e paredes.
//
// Lógica de push:
//   O PlayerComponent detecta a colisão com este componente via
//   onCollision/onCollisionStart e chama `tryPush(dir)`. O arquivo só se move
//   se o eixo do empurrão bate com `slideAxis` e não há obstáculo à frente.
// ─────────────────────────────────────────────────────────────────────────────
class SlidingArchiveComponent extends SpriteComponent
    with CollisionCallbacks
    implements SolidObstacle {
  // ── Identidade ──────────────────────────────────────────────────────────────
  final String archiveId;
  final SlideAxis slideAxis;

  // ── Limites de movimento ────────────────────────────────────────────────────
  /// Posição inicial, gravada em onLoad, usada para calcular o deslocamento.
  late final Vector2 _originPos;

  /// Deslocamento acumulado relativo a [_originPos]. Faixa: [-max, +max].
  double _slideOffset = 0;

  // ── Referências externas ─────────────────────────────────────────────────────
  /// Paredes e outros obstáculos sólidos para checar colisão antes de mover.
  final List<SolidObstacle> solidObstacles;

  /// Loot secreto que fica escondido atrás deste arquivo. Revelado ao deslocar.
  HiddenLootItem? hiddenLoot;

  // ── Hitbox AABB pública (usada por _hitsObstacle) ───────────────────────────
  Rect get solidRect => Rect.fromLTWH(
        position.x,
        position.y,
        size.x,
        size.y,
      );

  // ── Construtor ───────────────────────────────────────────────────────────────
  SlidingArchiveComponent({
    required this.archiveId,
    required this.slideAxis,
    required this.solidObstacles,
    required Vector2 position,
    required Vector2 size,
    Sprite? sprite,
  }) : super(
          sprite: sprite,
          position: position,
          size: size,
          anchor: Anchor.topLeft,
          priority: 4, // abaixo do jogador (5) para isometria correta
        );

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _originPos = position.clone();

    // Hitbox sólida — bloqueia jogador como uma parede
    add(RectangleHitbox(isSolid: true));
  }

  // ── overlapsRect — implementação de SolidObstacle ────────────────────────────
  /// Satisfaz a interface SolidObstacle para que o PlayerComponent._hitsWall()
  /// consiga verificar este arquivo como obstáculo.
  @override
  bool overlapsRect(Rect r) => solidRect.overlaps(r);

  // ── Lógica de empurrão ───────────────────────────────────────────────────────
  /// Chamado pelo [BibliotecaGame] quando o jogador colide com este arquivo
  /// enquanto se move na direção [playerDir].
  ///
  /// Retorna true se o arquivo se moveu (útil para feedback visual/sonoro).
  bool tryPush(Vector2 playerDir, double dt) {
    // 1. Verifica se a direção do jogador é compatível com o eixo permitido.
    final pushDir = _resolveAxis(playerDir);
    if (pushDir == 0) return false; // empurrão em eixo bloqueado, ignora

    // 2. Calcula o quanto vai deslizar neste frame.
    final step = kArchiveSlideSpeed * dt;

    // 3. Calcula nova posição hipotética.
    final nextOffset = (_slideOffset + pushDir * step)
        .clamp(-kArchiveMaxSlide, kArchiveMaxSlide);
    final delta = nextOffset - _slideOffset;
    if (delta.abs() < 0.001) return false; // já no limite máximo

    // 4. Checa se a nova posição colide com obstáculos sólidos.
    final nextPos = slideAxis == SlideAxis.horizontal
        ? Vector2(position.x + delta, position.y)
        : Vector2(position.x, position.y + delta);
    if (_hitsObstacle(nextPos)) return false;

    // 5. Move o arquivo.
    _slideOffset = nextOffset;
    position = nextPos;

    // 6. Revela o loot escondido se deslocou o suficiente.
    _checkRevealLoot();

    return true;
  }

  /// Projeta [playerDir] no eixo permitido e retorna +1, -1 ou 0.
  double _resolveAxis(Vector2 dir) {
    if (slideAxis == SlideAxis.horizontal) {
      return dir.x.abs() > dir.y.abs() ? dir.x.sign : 0;
    } else {
      return dir.y.abs() > dir.x.abs() ? dir.y.sign : 0;
    }
  }

  /// Verifica se a posição hipotética [nextPos] colide com algum SolidObstacle
  /// (exceto a si mesmo) ou com outro SlidingArchiveComponent.
  bool _hitsObstacle(Vector2 nextPos) {
    final futureRect = Rect.fromLTWH(
      nextPos.x + 4, // margem interna de 4 px para evitar "grinding" nas bordas
      nextPos.y + 4,
      size.x - 8,
      size.y - 8,
    );
    for (final o in solidObstacles) {
      if (identical(o, this)) continue;
      if (o.overlapsRect(futureRect)) return true;
    }
    return false;
  }

  // ── Revelar loot ─────────────────────────────────────────────────────────────
  static const double _revealThreshold = 60.0;

  void _checkRevealLoot() {
    final loot = hiddenLoot;
    if (loot == null || loot.isRevealed) return;
    if (_slideOffset.abs() >= _revealThreshold) {
      loot.reveal();
    }
  }

  // ── Render: fallback sem sprite ──────────────────────────────────────────────
  @override
  void render(Canvas canvas) {
    if (sprite == null) {
      // Placeholder visual para desenvolvimento
      canvas.drawRect(
        size.toRect(),
        Paint()..color = const Color(0xFF5D4037),
      );
      canvas.drawRect(
        size.toRect(),
        Paint()
          ..color = const Color(0xFF8D6E63)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      // Linhas de arquivo
      final linePaint = Paint()
        ..color = const Color(0xAA8D6E63)
        ..strokeWidth = 1;
      for (var y = 12.0; y < size.y - 4; y += 10) {
        canvas.drawLine(Offset(8, y), Offset(size.x - 8, y), linePaint);
      }
    } else {
      super.render(canvas);
    }

    // Seta de direção — ajuda o jogador a perceber que é empurrável
    _renderPushArrow(canvas);
  }

  void _renderPushArrow(Canvas canvas) {
    final arrowPaint = Paint()
      ..color = const Color(0xCCFFD54F)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final cx = size.x / 2;
    final cy = size.y / 2;
    if (slideAxis == SlideAxis.horizontal) {
      _drawArrow(canvas, arrowPaint, Offset(cx - 14, cy), Offset(cx + 14, cy));
    } else {
      _drawArrow(canvas, arrowPaint, Offset(cx, cy - 14), Offset(cx, cy + 14));
    }
  }

  void _drawArrow(Canvas canvas, Paint p, Offset from, Offset to) {
    canvas.drawLine(from, to, p);
    final dir = (to - from);
    final norm = dir / dir.distance;
    final head = 6.0;
    canvas.drawLine(
        to, to - Offset(norm.dx - norm.dy, norm.dy + norm.dx) * head, p);
    canvas.drawLine(
        to, to - Offset(norm.dx + norm.dy, norm.dy - norm.dx) * head, p);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HiddenLootItem
//
// Item invisível que se torna coletável quando o arquivo à sua frente
// é movido >= [_revealThreshold] px.
//
// Ao ser coletado (jogador toca), chama [BibliotecaGame.onLootCollected].
// ─────────────────────────────────────────────────────────────────────────────
class HiddenLootItem extends PositionComponent with CollisionCallbacks {
  final String itemId;

  bool _revealed = false;
  bool _collected = false;
  double _pulseTimer = 0;

  bool get isRevealed => _revealed;
  bool get isCollected => _collected;

  // Sprite opcional — sem sprite usa placeholder colorido por tipo de item
  Sprite? _sprite;

  HiddenLootItem({
    required this.itemId,
    required Vector2 position,
    Vector2? size,
    Sprite? sprite,
  }) : super(
          position: position,
          size: size ?? Vector2(40, 40),
          anchor: Anchor.center,
          priority: 3, // abaixo do arquivo
        ) {
    _sprite = sprite;
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    // Começa invisível e sem hitbox ativa
    add(RectangleHitbox(
      isSolid: false,
      collisionType: CollisionType.passive,
    )..debugMode = false);
  }

  /// Torna o item visível e coletável.
  void reveal() {
    if (_revealed) return;
    _revealed = true;
    debugPrint('[HiddenLoot] $itemId revelado!');
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!_revealed || _collected) return;
    _pulseTimer += dt;
  }

  @override
  void render(Canvas canvas) {
    if (!_revealed || _collected) return;

    // Pulso de brilho
    final pulse = (0.6 + 0.4 * (_pulseTimer * 2.5).abs().remainder(1.0));
    final glowRadius = size.x * 0.7 * pulse;

    canvas.drawCircle(
      Offset(size.x / 2, size.y / 2),
      glowRadius,
      Paint()
        ..color = _glowColor.withValues(alpha: 0.3 * pulse)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    if (_sprite != null) {
      _sprite!.render(canvas, position: Vector2.zero(), size: size);
    } else {
      // Placeholder: ícone simples por tipo de item
      final iconPaint = Paint()..color = _glowColor;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(4, 4, size.x - 8, size.y - 8),
          const Radius.circular(4),
        ),
        iconPaint,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(4, 4, size.x - 8, size.y - 8),
          const Radius.circular(4),
        ),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  Color get _glowColor {
    return switch (itemId) {
      'municao' => const Color(0xFFFFD700),
      'mapa_campus' => const Color(0xFF4FC3F7),
      'ponteiro_laser' => const Color(0xFFEF5350),
      'livro_primeiros_socorros' => const Color(0xFF66BB6A),
      _ => const Color(0xFFFFFFFF),
    };
  }

  // ── Coleta ───────────────────────────────────────────────────────────────────
  @override
  void onCollisionStart(Set<Vector2> pts, PositionComponent other) {
    super.onCollisionStart(pts, other);
    if (!_revealed || _collected) return;
    final isPlayer =
        other is PlayerComponent || other.parent is PlayerComponent;
    if (!isPlayer) return;
    _collect();
  }

  Future<void> _collect() async {
    if (_collected) return;
    _collected = true;

    final game = findGame();
    if (game is BibliotecaGame) {
      await game.onLootCollected(itemId);
    }

    // Remove com pequena animação de fade (recria como componente efêmero)
    removeFromParent();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ArchiveLoader
//
// Utilitário estático que lê a camada "ArquivosDeslizantes" do mapa Tiled e
// instancia os SlidingArchiveComponent + HiddenLootItem correspondentes.
//
// Propriedades esperadas por objeto no Tiled:
//   archiveId   : string  — ID único (ex: "arquivo_a")
//   slideAxis   : string  — "horizontal" | "vertical"
//   hiddenItemId: string? — ID do item escondido (ex: "municao"), opcional
//   hiddenItemDx: float?  — offset X do item em relação ao arquivo
//   hiddenItemDy: float?  — offset Y do item em relação ao arquivo
// ─────────────────────────────────────────────────────────────────────────────
class ArchiveLoader {
  ArchiveLoader._();

  static const String _layerName = 'ArquivosDeslizantes';

  /// Carrega do mapa Tiled (já parseado como JSON bruto) e adiciona ao world
  /// via [addToWorld]. Retorna a lista de arquivos criados.
  static Future<List<SlidingArchiveComponent>> loadFromJson({
    required String tiledJson,
    required List<SolidObstacle> solidObstacles,
    required Future<void> Function(Component) addToWorld,
    ui.Image? archiveSprite,
  }) async {
    final archives = <SlidingArchiveComponent>[];

    late final Map<String, dynamic> map;
    try {
      map = jsonDecode(tiledJson) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[ArchiveLoader] Falha ao decodificar JSON: $e');
      return archives;
    }

    final layers = (map['layers'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>();

    Map<String, dynamic>? archiveLayer;
    for (final l in layers) {
      if ((l['name'] as String? ?? '') == _layerName) {
        archiveLayer = l;
        break;
      }
    }

    if (archiveLayer == null) {
      debugPrint('[ArchiveLoader] Camada "$_layerName" não encontrada — '
          'usando spawns de fallback.');
      return _loadFallback(
          solidObstacles: solidObstacles,
          addToWorld: addToWorld,
          archiveSprite: archiveSprite);
    }

    final objects = (archiveLayer['objects'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>();

    for (final obj in objects) {
      final props = _parseProps(obj['properties']);

      final archiveId = props['archiveId'] as String? ?? obj['name'] as String? ?? 'arquivo_${archives.length}';
      final axisStr   = props['slideAxis'] as String? ?? 'horizontal';
      final axis      = axisStr == 'vertical' ? SlideAxis.vertical : SlideAxis.horizontal;

      final x = (obj['x'] as num? ?? 0).toDouble();
      final y = (obj['y'] as num? ?? 0).toDouble();
      final w = ((obj['width']  as num?)?.toDouble() ?? kArchiveDefaultSize.x).clamp(20.0, 9999.0);
      final h = ((obj['height'] as num?)?.toDouble() ?? kArchiveDefaultSize.y).clamp(20.0, 9999.0);

      final archive = SlidingArchiveComponent(
        archiveId: archiveId,
        slideAxis: axis,
        solidObstacles: solidObstacles,
        position: Vector2(x, y),
        size: Vector2(w, h),
        sprite: archiveSprite != null ? Sprite(archiveSprite) : null,
      );

      // Registra o arquivo como obstáculo sólido para os outros arquivos
      solidObstacles.add(archive);
      await addToWorld(archive);
      archives.add(archive);

      // Cria o loot escondido, se especificado
      final hiddenItemId = props['hiddenItemId'] as String?;
      if (hiddenItemId != null && hiddenItemId.isNotEmpty) {
        final dx = (props['hiddenItemDx'] as num? ?? 0).toDouble();
        final dy = (props['hiddenItemDy'] as num? ?? kArchiveDefaultSize.y / 2).toDouble();

        final loot = HiddenLootItem(
          itemId: hiddenItemId,
          position: Vector2(x + w / 2 + dx, y + h / 2 + dy),
        );
        archive.hiddenLoot = loot;
        await addToWorld(loot);
        debugPrint('[ArchiveLoader] Loot "$hiddenItemId" criado atrás de "$archiveId"');
      }
    }

    debugPrint('[ArchiveLoader] ${archives.length} arquivo(s) carregado(s) do Tiled.');
    return archives;
  }

  /// Fallback: 3 arquivos hardcoded para desenvolvimento sem Tiled pronto.
  static Future<List<SlidingArchiveComponent>> _loadFallback({
    required List<SolidObstacle> solidObstacles,
    required Future<void> Function(Component) addToWorld,
    ui.Image? archiveSprite,
  }) async {
    final archives = <SlidingArchiveComponent>[];

    // Dados das posições de fallback:
    // ┌──────────────────────────────────────────────────────────────────────┐
    // │  Corredor horizontal (mesas de estudo, faixa y ~ 500)                │
    // │    Arquivo A — bloqueia passagem central, loot: municao              │
    // │  Corredor vertical (estantes laterais, faixa x ~ 800)               │
    // │    Arquivo B — sem loot visível; empurrar para revelar saída         │
    // │  Canto secreto (x~1600, y~900)                                      │
    // │    Arquivo C — loot: mapa_campus                                     │
    // └──────────────────────────────────────────────────────────────────────┘
    final configs = [
      (
        id: 'arquivo_a',
        axis: SlideAxis.horizontal,
        pos: Vector2(640, 480),
        size: kArchiveDefaultSize,
        lootId: 'municao',
        lootDy: 100.0,
      ),
      (
        id: 'arquivo_b',
        axis: SlideAxis.vertical,
        pos: Vector2(800, 600),
        size: kArchiveDefaultSize,
        lootId: '',
        lootDy: 0.0,
      ),
      (
        id: 'arquivo_c',
        axis: SlideAxis.horizontal,
        pos: Vector2(1560, 880),
        size: kArchiveDefaultSize,
        lootId: 'mapa_campus',
        lootDy: 80.0,
      ),
    ];

    for (final cfg in configs) {
      final archive = SlidingArchiveComponent(
        archiveId: cfg.id,
        slideAxis: cfg.axis,
        solidObstacles: solidObstacles,
        position: cfg.pos,
        size: cfg.size,
        sprite: archiveSprite != null ? Sprite(archiveSprite) : null,
      );
      solidObstacles.add(archive);
      await addToWorld(archive);
      archives.add(archive);

      if (cfg.lootId.isNotEmpty) {
        final loot = HiddenLootItem(
          itemId: cfg.lootId,
          position: Vector2(
            cfg.pos.x + cfg.size.x / 2,
            cfg.pos.y + cfg.size.y / 2 + cfg.lootDy,
          ),
        );
        archive.hiddenLoot = loot;
        await addToWorld(loot);
      }
    }

    debugPrint('[ArchiveLoader] Fallback: ${archives.length} arquivos criados.');
    return archives;
  }

  /// Converte a lista de propriedades do formato Tiled em Map simples.
  static Map<String, dynamic> _parseProps(dynamic raw) {
    if (raw is! List) return {};
    final result = <String, dynamic>{};
    for (final p in raw.whereType<Map<String, dynamic>>()) {
      final name  = p['name']  as String?;
      final value = p['value'];
      if (name != null) result[name] = value;
    }
    return result;
  }
}
