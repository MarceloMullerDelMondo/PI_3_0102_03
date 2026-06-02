import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/cache.dart';
import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ZumbiGame — interface that any host game must implement to use ZumbiComponent.
// Both CafeteriaGame and (optionally) H15Game satisfy this contract.
// ─────────────────────────────────────────────────────────────────────────────
abstract interface class ZumbiGame {
  /// Flame image cache — provided automatically by FlameGame.
  Images get images;

  /// World bounds for clamping zombie movement.
  Vector2 get zumbiMapSize;

  /// Collision rects from the Tiled Colisoes layer.
  List<Rect> get zumbiWallRects;

  /// Called when a zombie touches the player.
  void zumbiDamagePlayer(double amount);

  /// All currently alive zombie instances — used for separation.
  List<ZumbiComponent> get spawnedZombies;
}

// ─────────────────────────────────────────────────────────────────────────────
// ZumbiAnim — shared animation states (identical to H15's ZombieAnim).
// ─────────────────────────────────────────────────────────────────────────────
enum ZumbiAnim {
  idle,
  walkDown,
  walkLeft,
  walkRight,
  walkUp,
  attackDown,
  attackLeft,
  attackRight,
  attackUp,
}

// ─────────────────────────────────────────────────────────────────────────────
// ZumbiComponent — the single canonical zombie class, reused by every level.
//
// Sprite: assets/images/zumbis/zumbi_normal.png
//   Sheet layout: 3 rows × 4 columns, each frame 148×140 px.
//   Row 0 → walk/idle down, Row 1 → walk right, Row 2 → walk left.
//
// The class is fully game-agnostic: all coupling goes through ZumbiGame.
// ─────────────────────────────────────────────────────────────────────────────
class ZumbiComponent extends SpriteAnimationComponent with CollisionCallbacks {
  static const double speed = 55;
  static const double playerHitCooldown = 1.2;
  static const double playerTouchDamage = 5.0;
  static final Vector2 frameSize = Vector2(148, 140);
  static const double walkStepTime = 0.15;
  static const double attackStepTime = 0.08;

  final ZumbiGame game;

  /// The component this zombie chases. Typically the player.
  final PositionComponent target;

  // 2-hit kill: each sword swing deals 10 damage, so 2 hits = 20 = dead.
  int health = 20;

  /// Always true — zombies are unconditionally aggressive.
  /// Exposed as a settable field so the spawn site can document intent explicitly.
  bool isAggressive = true;

  double _hurtFlashTimer = 0;
  double _hitCooldownTimer = 0;
  bool _isAttacking = false;
  ZumbiAnim _lastMoveAnim = ZumbiAnim.walkDown;
  ZumbiAnim _currentAnim = ZumbiAnim.idle;
  final Map<ZumbiAnim, SpriteAnimation> _animations = {};
  Vector2? _lastSafePos;

  ZumbiComponent({required this.game, required this.target})
      : super(size: Vector2(96, 96), anchor: Anchor.center, autoResize: false);

  Rect get hitRect => Rect.fromCenter(
        center: Offset(position.x, position.y),
        width: size.x * 0.72,
        height: size.y * 0.76,
      );

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    try {
      final sheet = await game.images.load('zumbis/zumbi_normal.png');
      _animations.addAll(_buildAnims(sheet));
      _setAnim(ZumbiAnim.idle);
    } catch (e) {
      debugPrint('ZumbiComponent: sprite load failed — $e');
    }
    add(RectangleHitbox(
      position: Vector2(size.x * .14, size.y * .12),
      size: Vector2(size.x * .72, size.y * .76),
      collisionType: CollisionType.active,
    )..debugMode = false);
  }

  /// Applies [dmg] damage. Returns true when the zombie dies.
  bool takeDamage(int dmg) {
    debugPrint('[COMBAT] ZumbiComponent.takeDamage($dmg) — hp=${health - dmg}');
    health -= dmg;
    _hurtFlashTimer = 0.20;
    return health <= 0;
  }

  @override
  void update(double dt) {
    super.update(dt);

    if (_hurtFlashTimer > 0) {
      _hurtFlashTimer -= dt;
      if (_hurtFlashTimer <= 0) _hurtFlashTimer = 0;
    }
    if (_hitCooldownTimer > 0) _hitCooldownTimer -= dt;
    if (_isAttacking && (animationTicker?.done() ?? false)) {
      _isAttacking = false;
      _setAnim(_lastMoveAnim);
    }

    if (!target.isMounted) return;
    final dir = target.position - position;
    final dist = dir.length;

    if (dist < 30) {
      _setAnim(ZumbiAnim.idle);
      if (_hitCooldownTimer <= 0) {
        _hitCooldownTimer = playerHitCooldown;
        game.zumbiDamagePlayer(playerTouchDamage);
        _startAttack();
      }
      return;
    }

    // Always aggressive — no idle range gate.
    if (!_isAttacking) _updateAnim(dir);
    final step = dir.normalized() * speed * dt;
    _tryMove(Vector2(step.x, 0));
    _tryMove(Vector2(0, step.y));
    _separate();
    priority = (position.y + size.y / 2).ceil();
  }

  // ── Animation helpers ──────────────────────────────────────────────────────

  static Map<ZumbiAnim, SpriteAnimation> _buildAnims(ui.Image img) {
    SpriteAnimation row({
      required double yOffset,
      double st = walkStepTime,
      bool loop = true,
    }) =>
        SpriteAnimation.fromFrameData(
          img,
          SpriteAnimationData.sequenced(
            amount: 4,
            stepTime: st,
            textureSize: frameSize,
            texturePosition: Vector2(0, yOffset),
            loop: loop,
          ),
        );
    return {
      ZumbiAnim.idle:        row(yOffset: 0),
      ZumbiAnim.walkDown:    row(yOffset: 0),
      ZumbiAnim.walkRight:   row(yOffset: 140),
      ZumbiAnim.walkLeft:    row(yOffset: 280),
      ZumbiAnim.walkUp:      row(yOffset: 0),
      ZumbiAnim.attackDown:  row(yOffset: 0,   st: attackStepTime, loop: false),
      ZumbiAnim.attackRight: row(yOffset: 140, st: attackStepTime, loop: false),
      ZumbiAnim.attackLeft:  row(yOffset: 280, st: attackStepTime, loop: false),
      ZumbiAnim.attackUp:    row(yOffset: 0,   st: attackStepTime, loop: false),
    };
  }

  void _updateAnim(Vector2 dir) {
    if (dir.x.abs() > dir.y.abs()) {
      _setAnim(dir.x > 0 ? ZumbiAnim.walkRight : ZumbiAnim.walkLeft);
    } else {
      _setAnim(dir.y > 0 ? ZumbiAnim.walkDown : ZumbiAnim.walkUp);
    }
    _lastMoveAnim = _currentAnim;
  }

  void _setAnim(ZumbiAnim next) {
    if (_currentAnim == next && animation != null) return;
    final a = _animations[next];
    if (a == null) return;
    _currentAnim = next;
    animation = a;
  }

  void _startAttack() {
    _isAttacking = true;
    _setAnim(switch (_lastMoveAnim) {
      ZumbiAnim.walkLeft  => ZumbiAnim.attackLeft,
      ZumbiAnim.walkRight => ZumbiAnim.attackRight,
      ZumbiAnim.walkUp    => ZumbiAnim.attackUp,
      _                   => ZumbiAnim.attackDown,
    });
    animationTicker?.reset();
  }

  // ── Movement & collision ───────────────────────────────────────────────────

  void _tryMove(Vector2 delta) {
    _lastSafePos = position.clone();
    position += delta;
    final mx = game.zumbiMapSize;
    position = Vector2(
      position.x.clamp(size.x / 2, mx.x - size.x / 2).toDouble(),
      position.y.clamp(size.y / 2, mx.y - size.y / 2).toDouble(),
    );
    if (_hitsWall()) position = _lastSafePos!;
  }

  bool _hitsWall() {
    final rect = hitRect;
    for (final wallRect in game.zumbiWallRects) {
      if (wallRect.overlaps(rect)) return true;
    }
    return false;
  }

  void _separate() {
    for (final other in game.spawnedZombies) {
      if (other == this || !other.isMounted) continue;
      var away = position - other.position;
      if (away.length2 < 0.0001) {
        away = Vector2(
          math.cos(position.x + position.y),
          math.sin(position.x - position.y),
        );
      }
      final minDist = size.x * 0.50;
      final dist = away.length;
      if (dist >= minDist) continue;
      position += away.normalized() * ((minDist - dist) * 0.5 + 0.8);
    }
  }

  // ── Rendering ──────────────────────────────────────────────────────────────

  @override
  void render(Canvas canvas) {
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(size.x / 2, size.y + 3),
          width: size.x * .85,
          height: 7),
      Paint()..color = Colors.black.withValues(alpha: 0.35),
    );
    if (animation != null) {
      super.render(canvas);
    } else {
      _renderFallback(canvas);
    }
    if (_hurtFlashTimer > 0) {
      final t = (_hurtFlashTimer / 0.20).clamp(0.0, 1.0);
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.x, size.y),
        Paint()..color = Colors.red.withValues(alpha: t * 0.55),
      );
    }
  }

  // Brown silhouette fallback — NOT a green placeholder rectangle.
  void _renderFallback(Canvas canvas) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.x * .30, size.y * .33, size.x * .40, size.y * .46),
        const Radius.circular(3),
      ),
      Paint()..color = const Color(0xFF4A3C28),
    );
    canvas.drawCircle(
      Offset(size.x / 2, size.y * .24),
      size.x * .20,
      Paint()..color = const Color(0xFF8B7355),
    );
    canvas.drawCircle(Offset(size.x * .44, size.y * .22), 2,
        Paint()..color = const Color(0xFFCC0000));
    canvas.drawCircle(Offset(size.x * .56, size.y * .22), 2,
        Paint()..color = const Color(0xFFCC0000));
  }
}
