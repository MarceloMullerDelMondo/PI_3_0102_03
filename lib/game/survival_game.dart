import 'dart:math';
import 'package:flame/game.dart';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SurvivalGame — motor principal
// ─────────────────────────────────────────────────────────────────────────────
class SurvivalGame extends FlameGame with HasCollisionDetection {
  // ── Estado público (lido pelo HUD Flutter) ─────────────────────────────────
  double playerHp = 100;
  double maxHp = 100;
  double stamina = 100;
  double maxStamina = 100;
  String equippedWeapon = 'SEM ARMA';
  bool isDead = false;

  /// Callback chamado sempre que algo muda (HUD rebuilda)
  VoidCallback? onStateChanged;

  // ── Referências internas ────────────────────────────────────────────────────
  late PlayerComponent _player;
  late CameraComponent _cam;
  final List<ZombieComponent> _zombies = [];

  // Movimento do jogador via D-pad
  double _dirX = 0;
  double _dirY = 0;
  bool _sprinting = false;

  final Random _rng = Random();

  // ── Constantes ──────────────────────────────────────────────────────────────
  static const double _tileSize = 32.0;
  static const double _mapW = 40; // tiles
  static const double _mapH = 28; // tiles
  static const int _zombieCount = 6;
  static const double _playerSpeed = 90.0;
  static const double _sprintMult = 1.7;
  static const double _staminaDrain = 30.0;
  static const double _staminaRegen = 20.0;
  static const double _attackRange = 48.0;
  static const double _attackCooldownSec = 0.8;

  double _attackCooldown = 0;

  // ── onLoad ─────────────────────────────────────────────────────────────────
  @override
  Color backgroundColor() => const Color(0xFF0A0A0A);

  @override
  Future<void> onLoad() async {
    // Câmera
    _cam = CameraComponent(world: world);
    _cam.viewfinder.anchor = Anchor.center;
    addAll([_cam, world]);

    // Mapa
    final mapRenderer = _LabMapComponent(
      tilesX: _mapW.toInt(),
      tilesY: _mapH.toInt(),
      tileSize: _tileSize,
      rng: _rng,
    );
    world.add(mapRenderer);

    // Jogador
    _player = PlayerComponent(tileSize: _tileSize);
    _player.position = Vector2(_mapW * _tileSize / 2, _mapH * _tileSize / 2);
    world.add(_player);

    // Câmera segue o jogador
    _cam.follow(_player);

    // Zumbis
    for (var i = 0; i < _zombieCount; i++) {
      _spawnZombie();
    }

    // Diálogo de arma — aparece 1s após o mapa carregar
    Future.delayed(const Duration(seconds: 1), () {
      if (!isMounted) return;
      overlays.remove('hud');
      overlays.add('weapon_choice');
    });
  }

  void _spawnZombie() {
    final z = ZombieComponent(tileSize: _tileSize);
    // Spawna longe do centro
    double px, py;
    do {
      px = _rng.nextDouble() * _mapW * _tileSize;
      py = _rng.nextDouble() * _mapH * _tileSize;
    } while ((px - _player.position.x).abs() < 150 &&
        (py - _player.position.y).abs() < 150);
    z.position = Vector2(px, py);
    world.add(z);
    _zombies.add(z);
  }

  // ── Update ─────────────────────────────────────────────────────────────────
  @override
  void update(double dt) {
    super.update(dt);
    if (isDead) return;

    _updatePlayerMovement(dt);
    _updateStamina(dt);
    _updateZombies(dt);
    _attackCooldown = (_attackCooldown - dt).clamp(0, 10);
    _checkDeath();
    onStateChanged?.call();
  }

  void _updatePlayerMovement(double dt) {
    if (_dirX == 0 && _dirY == 0) return;

    final isSprinting = _sprinting && stamina > 0;
    final speed = _playerSpeed * (isSprinting ? _sprintMult : 1.0);

    final len = sqrt(_dirX * _dirX + _dirY * _dirY);
    final nx = _dirX / len;
    final ny = _dirY / len;

    final newX = (_player.position.x + nx * speed * dt).clamp(
      16,
      _mapW * _tileSize - 16,
    );
    final newY = (_player.position.y + ny * speed * dt).clamp(
      16,
      _mapH * _tileSize - 16,
    );

    _player.position = Vector2(newX.toDouble(), newY.toDouble());
    _player.setMoving(nx, ny);
  }

  void _updateStamina(double dt) {
    if (_sprinting && (_dirX != 0 || _dirY != 0) && stamina > 0) {
      stamina = (stamina - _staminaDrain * dt).clamp(0, maxStamina);
    } else if (!_sprinting || (_dirX == 0 && _dirY == 0)) {
      stamina = (stamina + _staminaRegen * dt).clamp(0, maxStamina);
    }
  }

  void _updateZombies(double dt) {
    for (final z in _zombies) {
      if (!z.isAlive) continue;

      // Move em direção ao jogador
      final dx = _player.position.x - z.position.x;
      final dy = _player.position.y - z.position.y;
      final dist = sqrt(dx * dx + dy * dy);

      if (dist < 20) {
        // Ataca jogador
        z.attackTimer += dt;
        if (z.attackTimer >= z.attackInterval) {
          z.attackTimer = 0;
          playerHp = (playerHp - z.damage).clamp(0, maxHp);
          _player.flash();
        }
      } else if (dist < 300) {
        final speed = z.speed;
        z.position.x += (dx / dist) * speed * dt;
        z.position.y += (dy / dist) * speed * dt;
        z.setMoving(dx / dist, dy / dist);
      }
    }
    // Remove zumbis mortos da lista
    _zombies.removeWhere((z) => !z.isAlive);
  }

  void _checkDeath() {
    if (playerHp <= 0 && !isDead) {
      isDead = true;
      overlays.remove('hud');
      overlays.add('death');
    }
  }

  // ── API pública (chamada pelo HUD) ──────────────────────────────────────────

  void moveDir(double x, double y) {
    _dirX = x;
    _dirY = y;
    if (x == 0 && y == 0) _player.setMoving(0, 0);
  }

  void sprint() {
    _sprinting = !_sprinting;
  }

  void attack() {
    if (_attackCooldown > 0) return;
    _attackCooldown = _attackCooldownSec;

    final damage = equippedWeapon == 'TACO' ? 45.0 : 30.0;

    for (final z in _zombies) {
      if (!z.isAlive) continue;
      final dx = z.position.x - _player.position.x;
      final dy = z.position.y - _player.position.y;
      final dist = sqrt(dx * dx + dy * dy);
      if (dist <= _attackRange) {
        z.takeDamage(damage);
        _player.swingAnimation();
        if (!z.isAlive && _zombies.where((z) => z.isAlive).isEmpty) {
          _respawnZombies();
        }
      }
    }
  }

  void equipWeapon(String weapon) {
    equippedWeapon = weapon;
  }

  void restart() {
    isDead = false;
    playerHp = maxHp;
    stamina = maxStamina;
    _player.position = Vector2(_mapW * _tileSize / 2, _mapH * _tileSize / 2);
    for (final z in _zombies) {
      z.removeFromParent();
    }
    _zombies.clear();
    for (var i = 0; i < _zombieCount; i++) {
      _spawnZombie();
    }
  }

  void _respawnZombies() {
    Future.delayed(const Duration(seconds: 3), () {
      for (var i = 0; i < _zombieCount; i++) {
        _spawnZombie();
      }
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PlayerComponent — desenhado via Canvas (pixel art)
// ─────────────────────────────────────────────────────────────────────────────
class PlayerComponent extends PositionComponent {
  PlayerComponent({required double tileSize})
      : super(
          size: Vector2(tileSize * 0.9, tileSize * 0.9),
          anchor: Anchor.center,
        );

  double _dx = 0, _dy = 0;
  bool _isMoving = false;
  bool _isFlashing = false;
  bool _isSwinging = false;
  double _animTimer = 0;
  int _frame = 0;

  void setMoving(double dx, double dy) {
    _dx = dx;
    _dy = dy;
    _isMoving = dx != 0 || dy != 0;
  }

  void flash() {
    _isFlashing = true;
    Future.delayed(
      const Duration(milliseconds: 200),
      () => _isFlashing = false,
    );
  }

  void swingAnimation() {
    _isSwinging = true;
    Future.delayed(
      const Duration(milliseconds: 300),
      () => _isSwinging = false,
    );
  }

  @override
  void update(double dt) {
    _animTimer += dt;
    if (_animTimer > 0.15) {
      _animTimer = 0;
      _frame = (_frame + 1) % 2;
    }
  }

  @override
  void render(Canvas canvas) {
    final s = size.x;
    final half = s / 2;

    // Sombra
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(half, s * 0.92),
        width: s * 0.5,
        height: s * 0.12,
      ),
      Paint()..color = Colors.black38,
    );

    // Corpo
    final bodyColor =
        _isFlashing ? const Color(0xFFFF4444) : const Color(0xFF3A6B3A);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(half - s * 0.22, s * 0.35, s * 0.44, s * 0.48),
        const Radius.circular(3),
      ),
      Paint()..color = bodyColor,
    );

    // Cabeça
    canvas.drawCircle(
      Offset(half, s * 0.28),
      s * 0.21,
      Paint()..color = const Color(0xFFD4A574),
    );

    // Olhos
    canvas.drawCircle(
      Offset(half - 3, s * 0.25),
      2,
      Paint()..color = Colors.black87,
    );
    canvas.drawCircle(
      Offset(half + 3, s * 0.25),
      2,
      Paint()..color = Colors.black87,
    );

    // Pernas (animação simples)
    final legOff = _isMoving ? (_frame == 0 ? -3.0 : 3.0) : 0.0;
    final legPaint = Paint()..color = const Color(0xFF2A4A2A);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(half - s * 0.18, s * 0.76 + legOff, s * 0.14, s * 0.2),
        const Radius.circular(2),
      ),
      legPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(half + s * 0.04, s * 0.76 - legOff, s * 0.14, s * 0.2),
        const Radius.circular(2),
      ),
      legPaint,
    );

    // Arma (swing animation)
    if (_isSwinging) {
      final weaponPaint = Paint()
        ..color = const Color(0xFFB8860B)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      canvas.drawLine(
        Offset(half + s * 0.22, s * 0.42),
        Offset(half + s * 0.52, s * 0.2),
        weaponPaint,
      );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ZombieComponent
// ─────────────────────────────────────────────────────────────────────────────
class ZombieComponent extends PositionComponent {
  final double speed;
  final double damage;
  final double attackInterval;
  double attackTimer = 0;
  bool isAlive = true;
  double hp = 60;

  double _animTimer = 0;
  int _frame = 0;
  bool _isHurt = false;
  double _dirX = 0, _dirY = 0;

  ZombieComponent({required double tileSize})
      : speed = 35 + Random().nextDouble() * 20,
        damage = 8 + Random().nextDouble() * 7,
        attackInterval = 1.0 + Random().nextDouble() * 0.5,
        super(
          size: Vector2(tileSize * 0.85, tileSize * 0.85),
          anchor: Anchor.center,
        );

  void setMoving(double dx, double dy) {
    _dirX = dx;
    _dirY = dy;
  }

  void takeDamage(double dmg) {
    hp -= dmg;
    _isHurt = true;
    Future.delayed(const Duration(milliseconds: 150), () => _isHurt = false);
    if (hp <= 0) {
      isAlive = false;
      removeFromParent();
    }
  }

  @override
  void update(double dt) {
    _animTimer += dt;
    if (_animTimer > 0.2) {
      _animTimer = 0;
      _frame = (_frame + 1) % 2;
    }
  }

  @override
  void render(Canvas canvas) {
    if (!isAlive) return;
    final s = size.x;
    final half = s / 2;

    // Sombra
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(half, s * 0.92),
        width: s * 0.5,
        height: s * 0.12,
      ),
      Paint()..color = Colors.black26,
    );

    // Corpo zumbi (verde podre)
    final bodyColor =
        _isHurt ? const Color(0xFFFF6666) : const Color(0xFF4A6B30);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(half - s * 0.22, s * 0.35, s * 0.44, s * 0.48),
        const Radius.circular(3),
      ),
      Paint()..color = bodyColor,
    );

    // Cabeça
    canvas.drawCircle(
      Offset(half, s * 0.26),
      s * 0.22,
      Paint()..color = const Color(0xFF8B9B6A),
    );

    // Olhos vermelhos
    final eyePaint = Paint()..color = const Color(0xFFCC2200);
    canvas.drawCircle(Offset(half - 3.5, s * 0.23), 2.5, eyePaint);
    canvas.drawCircle(Offset(half + 3.5, s * 0.23), 2.5, eyePaint);

    // Boca aberta
    canvas.drawArc(
      Rect.fromCenter(center: Offset(half, s * 0.31), width: 8, height: 6),
      0,
      pi,
      true,
      Paint()..color = Colors.black87,
    );

    // Pernas arrastando
    final legOff = (_frame == 0 ? -2.0 : 2.0);
    final legPaint = Paint()..color = const Color(0xFF3A5020);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(half - s * 0.18, s * 0.76 + legOff, s * 0.14, s * 0.2),
        const Radius.circular(2),
      ),
      legPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(half + s * 0.04, s * 0.76 - legOff, s * 0.14, s * 0.2),
        const Radius.circular(2),
      ),
      legPaint,
    );

    // Barra de HP acima
    final barW = s * 0.9;
    final barX = half - barW / 2;
    canvas.drawRect(
      Rect.fromLTWH(barX, -8, barW, 4),
      Paint()..color = const Color(0xFF330000),
    );
    canvas.drawRect(
      Rect.fromLTWH(barX, -8, barW * (hp / 60).clamp(0, 1), 4),
      Paint()..color = const Color(0xFF8B0000),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LabMapComponent — mapa do laboratório H-15 desenhado via Canvas
// ─────────────────────────────────────────────────────────────────────────────
class _LabMapComponent extends Component {
  final int tilesX;
  final int tilesY;
  final double tileSize;
  final Random rng;

  late List<List<_TileType>> _grid;

  _LabMapComponent({
    required this.tilesX,
    required this.tilesY,
    required this.tileSize,
    required this.rng,
  });

  @override
  Future<void> onLoad() async {
    _grid = _generateMap();
  }

  List<List<_TileType>> _generateMap() {
    final grid = List.generate(
      tilesY,
      (_) => List.filled(tilesX, _TileType.floor),
    );

    // Bordas = paredes
    for (var y = 0; y < tilesY; y++) {
      for (var x = 0; x < tilesX; x++) {
        if (x == 0 || y == 0 || x == tilesX - 1 || y == tilesY - 1) {
          grid[y][x] = _TileType.wall;
        }
      }
    }

    // Paredes internas — bancadas de laboratório
    final obstacles = [
      // Bancadas horizontais
      [5, 5, 10, 5], [5, 12, 10, 12], [5, 19, 10, 19],
      [25, 5, 35, 5], [25, 12, 35, 12], [25, 19, 35, 19],
      // Pilares
      [15, 8, 15, 8], [15, 16, 15, 16], [20, 8, 20, 8], [20, 16, 20, 16],
    ];

    for (final o in obstacles) {
      for (var x = o[0]; x <= o[2]; x++) {
        for (var y = o[1]; y <= o[3]; y++) {
          if (x < tilesX && y < tilesY) grid[y][x] = _TileType.wall;
        }
      }
    }

    // Manchas de sangue / detalhes aleatórios
    for (var i = 0; i < 30; i++) {
      final x = 1 + rng.nextInt(tilesX - 2);
      final y = 1 + rng.nextInt(tilesY - 2);
      if (grid[y][x] == _TileType.floor) grid[y][x] = _TileType.stain;
    }

    return grid;
  }

  @override
  void render(Canvas canvas) {
    for (var y = 0; y < tilesY; y++) {
      for (var x = 0; x < tilesX; x++) {
        final tile = _grid[y][x];
        final rect = Rect.fromLTWH(
          x * tileSize,
          y * tileSize,
          tileSize,
          tileSize,
        );
        _paintTile(canvas, rect, tile);
      }
    }
  }

  void _paintTile(Canvas canvas, Rect rect, _TileType tile) {
    switch (tile) {
      case _TileType.floor:
        canvas.drawRect(rect, Paint()..color = const Color(0xFF141414));
        // Grade de piso
        canvas.drawRect(
          rect.deflate(0.5),
          Paint()
            ..color = const Color(0xFF1E1E1E)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.5,
        );

      case _TileType.wall:
        canvas.drawRect(rect, Paint()..color = const Color(0xFF2A2A2A));
        canvas.drawRect(
          rect.deflate(1),
          Paint()..color = const Color(0xFF333333),
        );
        // Detalhe de parede
        canvas.drawRect(
          Rect.fromLTWH(rect.left + 2, rect.top + 2, rect.width - 4, 2),
          Paint()..color = const Color(0xFF404040),
        );

      case _TileType.stain:
        canvas.drawRect(rect, Paint()..color = const Color(0xFF141414));
        canvas.drawCircle(
          rect.center,
          tileSize * 0.2,
          Paint()..color = const Color(0xFF3D0000).withValues(alpha: 0.8),
        );
    }
  }
}

enum _TileType { floor, wall, stain }
