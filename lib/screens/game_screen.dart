import 'package:flutter/material.dart';
import 'package:flame/game.dart';
import '../game/survival_game.dart';

/// Tela que envolve o motor Flame e exibe o jogo 2D.
class GameScreen extends StatelessWidget {
  const GameScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GameWidget<SurvivalGame>(
        game: SurvivalGame(),
        overlayBuilderMap: {
          'hud': (context, game) => _HudOverlay(game: game),
          'death': (context, game) => _DeathOverlay(game: game),
          'weapon_choice': (context, game) => _WeaponChoiceOverlay(game: game),
        },
        initialActiveOverlays: const ['hud'],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HUD — vida, stamina, arma equipada
// ─────────────────────────────────────────────────────────────────────────────
class _HudOverlay extends StatefulWidget {
  final SurvivalGame game;
  const _HudOverlay({required this.game});

  @override
  State<_HudOverlay> createState() => _HudOverlayState();
}

class _HudOverlayState extends State<_HudOverlay> {
  @override
  void initState() {
    super.initState();
    widget.game.onStateChanged = () {
      if (mounted) setState(() {});
    };
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    return SafeArea(
      child: Column(
        children: [
          // ── Barra superior ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                // Vida
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'VIDA',
                        style: TextStyle(
                          fontSize: 9,
                          color: Color(0xFF8B0000),
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      _BarWidget(
                        value: game.playerHp / game.maxHp,
                        color: const Color(0xFF8B0000),
                        bgColor: const Color(0xFF2A0000),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Stamina
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'STAMINA',
                        style: TextStyle(
                          fontSize: 9,
                          color: Color(0xFFB8860B),
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      _BarWidget(
                        value: game.stamina / game.maxStamina,
                        color: const Color(0xFFB8860B),
                        bgColor: const Color(0xFF2A1E00),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Arma
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFF4A3F2F)),
                    color: const Color(0xFF0A0A0A),
                  ),
                  child: Text(
                    game.equippedWeapon,
                    style: const TextStyle(
                      fontSize: 9,
                      color: Color(0xFFD4C5A9),
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const Spacer(),

          // ── Controles virtuais ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(bottom: 24, left: 20, right: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // D-pad
                SizedBox(
                  width: 130,
                  height: 130,
                  child: Stack(
                    children: [
                      Positioned(
                        top: 0,
                        left: 45,
                        child: _DpadBtn(
                          '↑',
                          onDown: () => game.moveDir(0, -1),
                          onUp: () => game.moveDir(0, 0),
                        ),
                      ),
                      Positioned(
                        top: 45,
                        left: 0,
                        child: _DpadBtn(
                          '←',
                          onDown: () => game.moveDir(-1, 0),
                          onUp: () => game.moveDir(0, 0),
                        ),
                      ),
                      Positioned(
                        top: 45,
                        left: 90,
                        child: _DpadBtn(
                          '→',
                          onDown: () => game.moveDir(1, 0),
                          onUp: () => game.moveDir(0, 0),
                        ),
                      ),
                      Positioned(
                        top: 90,
                        left: 45,
                        child: _DpadBtn(
                          '↓',
                          onDown: () => game.moveDir(0, 1),
                          onUp: () => game.moveDir(0, 0),
                        ),
                      ),
                    ],
                  ),
                ),

                // Botões de ação
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ActionBtn(
                      label: 'ATK',
                      color: const Color(0xFF8B0000),
                      onTap: game.attack,
                    ),
                    const SizedBox(height: 12),
                    _ActionBtn(
                      label: 'RUN',
                      color: const Color(0xFF4A3F2F),
                      onTap: game.sprint,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Overlay de morte
// ─────────────────────────────────────────────────────────────────────────────
class _DeathOverlay extends StatelessWidget {
  final SurvivalGame game;
  const _DeathOverlay({required this.game});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black87,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'VOCÊ CAIU',
              style: TextStyle(
                fontSize: 36,
                color: Color(0xFF8B0000),
                letterSpacing: 8,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'O campus engoliu mais um sobrevivente.',
              style: TextStyle(fontSize: 13, color: Color(0xFFD4C5A9)),
            ),
            const SizedBox(height: 32),
            _OutlineButton(
              label: '[ TENTAR NOVAMENTE ]',
              onTap: () {
                game.restart();
                game.overlays.remove('death');
                game.overlays.add('hud');
              },
            ),
            const SizedBox(height: 16),
            _OutlineButton(
              label: '[ VOLTAR AO MAPA ]',
              onTap: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Overlay de escolha de arma (Dr. Álvaro)
// ─────────────────────────────────────────────────────────────────────────────
class _WeaponChoiceOverlay extends StatelessWidget {
  final SurvivalGame game;
  const _WeaponChoiceOverlay({required this.game});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black87,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'DR. ÁLVARO FALA:',
                style: TextStyle(
                  fontSize: 11,
                  color: Color(0xFFB8860B),
                  letterSpacing: 4,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '"Você vai precisar de algo para se defender.\nEscolha com sabedoria."',
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFFD4C5A9),
                  height: 1.7,
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: _WeaponCard(
                      emoji: '🔪',
                      name: 'Facão de Campo',
                      desc: 'Silencioso\nNão atrai hordas\nDano médio',
                      onTap: () {
                        game.equipWeapon('FACÃO');
                        game.overlays.remove('weapon_choice');
                        game.overlays.add('hud');
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _WeaponCard(
                      emoji: '⚾',
                      name: 'Taco Modificado',
                      desc: 'Barulhento\nAtrai mais inimigos\nDano alto',
                      onTap: () {
                        game.equipWeapon('TACO');
                        game.overlays.remove('weapon_choice');
                        game.overlays.add('hud');
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers de UI
// ─────────────────────────────────────────────────────────────────────────────

class _BarWidget extends StatelessWidget {
  final double value;
  final Color color;
  final Color bgColor;
  const _BarWidget({
    required this.value,
    required this.color,
    required this.bgColor,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, constraints) => Container(
        height: 6,
        width: constraints.maxWidth,
        color: bgColor,
        child: Align(
          alignment: Alignment.centerLeft,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: constraints.maxWidth * value.clamp(0.0, 1.0),
            color: color,
          ),
        ),
      ),
    );
  }
}

class _DpadBtn extends StatelessWidget {
  final String label;
  final VoidCallback onDown;
  final VoidCallback onUp;
  const _DpadBtn(this.label, {required this.onDown, required this.onUp});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => onDown(),
      onTapUp: (_) => onUp(),
      onTapCancel: onUp,
      child: Container(
        width: 40,
        height: 40,
        color: const Color(0x661A1A1A),
        child: Center(
          child: Text(
            label,
            style: const TextStyle(fontSize: 18, color: Color(0xFFD4C5A9)),
          ),
        ),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionBtn({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.3),
          border: Border.all(color: color, width: 1.5),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
        ),
      ),
    );
  }
}

class _OutlineButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _OutlineButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFB8860B)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Color(0xFFB8860B),
            letterSpacing: 3,
          ),
        ),
      ),
    );
  }
}

class _WeaponCard extends StatelessWidget {
  final String emoji;
  final String name;
  final String desc;
  final VoidCallback onTap;
  const _WeaponCard({
    required this.emoji,
    required this.name,
    required this.desc,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFB8860B)),
          color: const Color(0xFF0D0D0D),
        ),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 32)),
            const SizedBox(height: 8),
            Text(
              name,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFFB8860B),
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              desc,
              style: const TextStyle(
                fontSize: 10,
                color: Color(0xFFAA9977),
                height: 1.6,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
