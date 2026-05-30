import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flame/game.dart';

import '../game/biblioteca_game.dart';
import '../screens/biblioteca_overlays.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BibliotecaLevelScreen
//
// Registra todos os overlays e monta o HUD da Fase 2.
//
// Overlays registrados:
//   • 'Terminal_0', 'Terminal_1', 'Terminal_2' — Terminais de Consulta CRT
//   • 'QuadroAvisos'    — Mapa do Campus I em pixel art
//   • 'MesaRestauracao' — Zona Segura: salvar + inventário
//   • 'GameOver'        — Tela de game over
//
// NOTA sobre PlayerComponent e BibliotecaGame:
//   O PlayerComponent (de h15_game.dart) só chama enterInteractableZone()
//   quando `findGame() is H15Game`. Para corrigir isso sem alterar h15_game.dart,
//   adicione o seguinte trecho no PlayerComponent.onCollisionStart:
//
//     } else if (g is BibliotecaGame) {
//       g.enterInteractableZone(zone.zoneId);
//     }
//
//   e no onCollisionEnd:
//
//     } else if (g is BibliotecaGame) {
//       g.exitInteractableZone(zone.zoneId);
//     }
// ─────────────────────────────────────────────────────────────────────────────
class BibliotecaLevelScreen extends StatefulWidget {
  final String playerName;
  const BibliotecaLevelScreen({super.key, required this.playerName});

  @override
  State<BibliotecaLevelScreen> createState() => _BibliotecaLevelScreenState();
}

class _BibliotecaLevelScreenState extends State<BibliotecaLevelScreen> {
  late final BibliotecaGame _game;

  @override
  void initState() {
    super.initState();
    _game = BibliotecaGame(playerName: widget.playerName);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  // ── Mapa de overlays ─────────────────────────────────────────────────────────
  Map<String, Widget Function(BuildContext, BibliotecaGame)>
      get _overlayBuilders {
    return {
      // Terminais de Consulta — um por índice
      for (var i = 0; i < kTerminalLogs.length; i++)
        'Terminal_$i': (ctx, game) =>
            TerminalCRTOverlay(game: game, terminalIndex: i),

      // Quadro de Avisos
      'QuadroAvisos': (ctx, game) => QuadroAvisosOverlay(game: game),

      // Game Over
      'GameOver': (ctx, game) => _BibliotecaGameOverOverlay(game: game),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Motor Flame ──────────────────────────────────────────────────
          GameWidget<BibliotecaGame>(
            game: _game,
            loadingBuilder: (_) => const _LoadingScreen(),
            overlayBuilderMap: _overlayBuilders,
          ),

          // ── Flash vermelho de dano (igual ao feedback visual do H15) ────
          ValueListenableBuilder<bool>(
            valueListenable: _game.playerHitFlash,
            builder: (_, hit, __) => IgnorePointer(
              child: AnimatedOpacity(
                opacity: hit ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 80),
                child: Container(
                  color: const Color(0x558B0000),
                ),
              ),
            ),
          ),

          // ── HUD Flutter (oculto quando overlay está aberto ou game over) ─
          ValueListenableBuilder<bool>(
            valueListenable: _game.questDialogOpen,
            builder: (_, dialogOpen, __) =>
                ValueListenableBuilder<bool>(
              valueListenable: _game.gameOver,
              builder: (_, isGameOver, __) {
                if (dialogOpen || isGameOver) return const SizedBox.shrink();
                return _BibliotecaHUD(
                  game: _game,
                  onBack: () => Navigator.of(context).pop(false),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _BibliotecaHUD — HUD em landscape com botão INTERAGIR contextual
// ─────────────────────────────────────────────────────────────────────────────
class _BibliotecaHUD extends StatelessWidget {
  final BibliotecaGame game;
  final VoidCallback onBack;

  const _BibliotecaHUD({required this.game, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Stack(
        children: [
          // ── TOPO ESQUERDO: Voltar + HP + Tempo ──────────────────────────
          Positioned(
            top: 10, left: 12,
            child: _LeftPanel(game: game, onBack: onBack),
          ),

          // ── TOPO DIREITO: Missão ─────────────────────────────────────────
          Positioned(
            top: 10, right: 12,
            child: ValueListenableBuilder<String>(
              valueListenable: game.missionText,
              builder: (_, mission, __) => _MissionTracker(text: mission),
            ),
          ),

          // ── CENTRO: Toast HUD ────────────────────────────────────────────
          Positioned(
            top: 80, left: 0, right: 0,
            child: ValueListenableBuilder<String?>(
              valueListenable: game.hudMessage,
              builder: (_, msg, __) => AnimatedOpacity(
                opacity: msg == null ? 0 : 1,
                duration: const Duration(milliseconds: 160),
                child: IgnorePointer(
                  child: Center(child: _HudToast(message: msg ?? '')),
                ),
              ),
            ),
          ),

          // ── DIREITA CENTRO: Botão INTERAGIR ─────────────────────────────
          // Aparece apenas quando o jogador está em uma zona interagível.
          Positioned(
            right: 140, bottom: 40,
            child: ValueListenableBuilder<bool>(
              valueListenable: game.canInteract,
              builder: (_, canInteract, __) {
                return AnimatedOpacity(
                  opacity: canInteract ? 1 : 0,
                  duration: const Duration(milliseconds: 140),
                  child: IgnorePointer(
                    ignoring: !canInteract,
                    child: _InteractButton(
                      label: _interactLabel(game.activeZoneId),
                      onTap: game.interact,
                    ),
                  ),
                );
              },
            ),
          ),

          // ── DIREITA: Botão ATACAR ────────────────────────────────────────
          Positioned(
            right: 20, bottom: 40,
            child: ValueListenableBuilder<bool>(
              valueListenable: game.attackEnabled,
              builder: (_, enabled, __) => AnimatedOpacity(
                opacity: enabled ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: IgnorePointer(
                  ignoring: !enabled,
                  child: _AttackButton(onTap: game.attack),
                ),
              ),
            ),
          ),

          // ── TOPO CENTRO: Botão VER MAPA (aparece após coletar o mapa) ──
          Positioned(
            top: 10, left: 0, right: 0,
            child: ValueListenableBuilder<bool>(
              valueListenable: game.minimapFogRemoved,
              builder: (_, hasMap, __) => AnimatedOpacity(
                opacity: hasMap ? 1 : 0,
                duration: const Duration(milliseconds: 300),
                child: IgnorePointer(
                  ignoring: !hasMap,
                  child: Center(
                    child: _InteractButton(
                      label: 'VER MAPA',
                      onTap: game.showMapa,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Rótulo do botão varia de acordo com a zona ativa.
  String _interactLabel(String? zoneId) {
    if (zoneId == null) return 'INTERAGIR';
    if (zoneId.startsWith(ZoneIds.terminalPrefix)) return 'USAR TERMINAL';
    switch (zoneId) {
      case ZoneIds.quadroAvisos:    return 'LER QUADRO';
      case ZoneIds.mesaRestauracao: return 'ZONA SEGURA';
      case ZoneIds.portaSaida:      return 'SAINDO...';
      default:                      return 'INTERAGIR';
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _LeftPanel — HP + tempo de sobrevivência + botão Voltar
// ─────────────────────────────────────────────────────────────────────────────
class _LeftPanel extends StatelessWidget {
  final BibliotecaGame game;
  final VoidCallback onBack;
  const _LeftPanel({required this.game, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        border: Border.all(color: const Color(0xFF4A3F2F), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Voltar
          GestureDetector(
            onTap: onBack,
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.arrow_back_ios, color: Color(0xFFB8860B), size: 10),
                SizedBox(width: 2),
                Text('VOLTAR',
                    style: TextStyle(
                        color: Color(0xFFB8860B),
                        fontSize: 9,
                        fontFamily: 'monospace',
                        letterSpacing: 1.5)),
              ],
            ),
          ),
          const SizedBox(height: 6),
          // HP
          const Text('VIDA',
              style: TextStyle(
                  color: Color(0xFF8B0000),
                  fontSize: 8,
                  fontFamily: 'monospace',
                  letterSpacing: 2)),
          const SizedBox(height: 2),
          ValueListenableBuilder<double>(
            valueListenable: game.currentHealth,
            builder: (_, hp, __) => _Bar(
              value: hp / game.maxHealth,
              color: const Color(0xFFCC2222),
              bgColor: const Color(0xFF2A0000),
            ),
          ),
          const SizedBox(height: 6),
          // Tempo
          ValueListenableBuilder<int>(
            valueListenable: game.survivalSeconds,
            builder: (_, secs, __) => Text(
              'TEMPO: ${_fmt(secs)}',
              style: const TextStyle(
                  color: Color(0xFF886644),
                  fontSize: 8,
                  fontFamily: 'monospace',
                  letterSpacing: 1),
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(int s) {
    final m = s ~/ 60;
    final sec = s % 60;
    return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }
}

class _Bar extends StatelessWidget {
  final double value;
  final Color color, bgColor;
  const _Bar({required this.value, required this.color, required this.bgColor});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 110,
      height: 6,
      child: LayoutBuilder(
        builder: (_, c) => Container(
          color: bgColor,
          child: Align(
            alignment: Alignment.centerLeft,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: c.maxWidth * value.clamp(0.0, 1.0),
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _MissionTracker
// ─────────────────────────────────────────────────────────────────────────────
class _MissionTracker extends StatelessWidget {
  final String text;
  const _MissionTracker({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        border: Border.all(color: const Color(0xFF4A3F2F), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.track_changes,
              color: Color(0xFFB8860B), size: 10),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: Color(0xFFD4C5A9),
              fontSize: 9,
              fontFamily: 'monospace',
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _HudToast
// ─────────────────────────────────────────────────────────────────────────────
class _HudToast extends StatelessWidget {
  final String message;
  const _HudToast({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.78),
        border: Border.all(color: const Color(0xFFB8860B), width: 1),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFB8860B).withValues(alpha: 0.2),
            blurRadius: 12,
          ),
        ],
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: Color(0xFFD4C5A9),
          fontSize: 11,
          fontFamily: 'monospace',
          letterSpacing: 1,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _InteractButton — botão de ação contextual
// ─────────────────────────────────────────────────────────────────────────────
class _InteractButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  const _InteractButton({required this.label, required this.onTap});

  @override
  State<_InteractButton> createState() => _InteractButtonState();
}

class _InteractButtonState extends State<_InteractButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown:   (_) => setState(() => _pressed = true),
      onTapUp:     (_) { setState(() => _pressed = false); widget.onTap(); },
      onTapCancel: ()  => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 60),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: _pressed
              ? const Color(0xFFB8860B).withValues(alpha: 0.22)
              : Colors.black.withValues(alpha: 0.65),
          border: Border.all(
            color: const Color(0xFFD4860A),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFD4860A).withValues(alpha: 0.25),
              blurRadius: 10,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.touch_app_outlined,
                color: Color(0xFFD4860A), size: 16),
            const SizedBox(height: 4),
            Text(
              widget.label,
              style: const TextStyle(
                color: Color(0xFFD4C5A9),
                fontSize: 9,
                fontFamily: 'monospace',
                letterSpacing: 1.5,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _AttackButton — botão de ataque circular (canto inferior direito)
// ─────────────────────────────────────────────────────────────────────────────
class _AttackButton extends StatefulWidget {
  final VoidCallback onTap;
  const _AttackButton({required this.onTap});

  @override
  State<_AttackButton> createState() => _AttackButtonState();
}

class _AttackButtonState extends State<_AttackButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown:   (_) => setState(() => _pressed = true),
      onTapUp:     (_) { setState(() => _pressed = false); widget.onTap(); },
      onTapCancel: ()  => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 60),
        width: 72, height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _pressed
              ? const Color(0xFF8B0000).withValues(alpha: 0.5)
              : Colors.black.withValues(alpha: 0.70),
          border: Border.all(color: const Color(0xFF8B0000), width: 2.5),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF8B0000).withValues(alpha: 0.40),
              blurRadius: 12,
            ),
          ],
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.sports_martial_arts, color: Color(0xFFFF4444), size: 22),
            SizedBox(height: 2),
            Text(
              'ATK',
              style: TextStyle(
                color: Color(0xFFFF6666),
                fontSize: 9,
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _BibliotecaGameOverOverlay
// ─────────────────────────────────────────────────────────────────────────────
class _BibliotecaGameOverOverlay extends StatelessWidget {
  final BibliotecaGame game;
  const _BibliotecaGameOverOverlay({required this.game});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.92),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'VOCÊ CAIU',
              style: TextStyle(
                color: Color(0xFF8B0000),
                fontSize: 36,
                fontFamily: 'monospace',
                letterSpacing: 8,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'A biblioteca guarda seus segredos. Por enquanto.',
              style: TextStyle(
                  color: Color(0xFFAA9977),
                  fontSize: 12,
                  fontFamily: 'monospace'),
            ),
            const SizedBox(height: 36),
            _OutlineBtn(
              label: '[ REVIVER NO CHECKPOINT ]',
              color: const Color(0xFFD4860A),
              onTap: game.reviveAtCheckpoint,
            ),
            const SizedBox(height: 14),
            _OutlineBtn(
              label: '[ VOLTAR AO MAPA ]',
              color: const Color(0xFF886644),
              onTap: () => Navigator.of(context).pop(false),
            ),
          ],
        ),
      ),
    );
  }
}

class _OutlineBtn extends StatelessWidget {
  final String label;
  final Color  color;
  final VoidCallback onTap;
  const _OutlineBtn({required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        decoration: BoxDecoration(border: Border.all(color: color)),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontFamily: 'monospace',
            letterSpacing: 2,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _LoadingScreen
// ─────────────────────────────────────────────────────────────────────────────
class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 36, height: 36,
              child: CircularProgressIndicator(
                  color: Color(0xFFD4860A), strokeWidth: 3),
            ),
            SizedBox(height: 20),
            Text(
              'CARREGANDO BIBLIOTECA...',
              style: TextStyle(
                color: Color(0xFFD4860A),
                fontSize: 11,
                fontFamily: 'monospace',
                letterSpacing: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
