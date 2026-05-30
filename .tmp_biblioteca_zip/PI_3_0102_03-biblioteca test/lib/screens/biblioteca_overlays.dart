import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/firebase_service.dart';
import '../game/biblioteca_game.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Paleta retro compartilhada
// ─────────────────────────────────────────────────────────────────────────────
abstract class _RetroColors {
  static const bg          = Color(0xFF0A0F0A);
  static const bgPanel     = Color(0xFF0D150D);
  static const borderGlow  = Color(0xFF00FF41);
  static const textGreen   = Color(0xFF00FF41);
  static const textDim     = Color(0xFF006B1A);
  static const textAmber   = Color(0xFFFFB000);
  static const textRed     = Color(0xFFFF2222);
  static const scanLine    = Color(0x08000000);
  static const safeGold    = Color(0xFFD4860A);
  static const safeBg      = Color(0xFF0D0D07);
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers reutilizáveis
// ─────────────────────────────────────────────────────────────────────────────

/// Pausa o game enquanto o overlay estiver visível.
class _GamePauseWrapper extends StatefulWidget {
  final BibliotecaGame game;
  final Widget child;
  const _GamePauseWrapper({required this.game, required this.child});

  @override
  State<_GamePauseWrapper> createState() => _GamePauseWrapperState();
}

class _GamePauseWrapperState extends State<_GamePauseWrapper> {
  @override
  void initState()  { super.initState();  widget.game.pauseEngine();  }
  @override
  void dispose()    { widget.game.resumeEngine(); super.dispose();     }
  @override
  Widget build(BuildContext context) => widget.child;
}

/// Efeito de scanlines CRT — desenhado sobre qualquer widget filho.
class _CRTScanlines extends StatelessWidget {
  final Widget child;
  const _CRTScanlines({required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        IgnorePointer(
          child: CustomPaint(
            painter: _ScanlinePainter(),
          ),
        ),
      ],
    );
  }
}

class _ScanlinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = _RetroColors.scanLine;
    for (var y = 0.0; y < size.height; y += 3) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1.5), paint);
    }
  }
  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// Botão com borda pixelada estilo retro.
class _RetroButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final Color color;
  const _RetroButton({
    required this.label,
    required this.onTap,
    this.color = _RetroColors.textGreen,
  });

  @override
  State<_RetroButton> createState() => _RetroButtonState();
}

class _RetroButtonState extends State<_RetroButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown:   (_) => setState(() => _pressed = true),
      onTapUp:     (_) { setState(() => _pressed = false); widget.onTap(); },
      onTapCancel: ()  => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 60),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: widget.color, width: 1.5),
          color: _pressed
              ? widget.color.withValues(alpha: 0.18)
              : Colors.transparent,
          boxShadow: _pressed
              ? []
              : [BoxShadow(color: widget.color.withValues(alpha: 0.25),
                           blurRadius: 8)],
        ),
        child: Text(
          '[ ${widget.label} ]',
          style: TextStyle(
            color: widget.color,
            fontSize: 11,
            fontFamily: 'monospace',
            letterSpacing: 2,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 1. TerminalCRTOverlay — exibe logs de lore com efeito typewriter
// ─────────────────────────────────────────────────────────────────────────────
class TerminalCRTOverlay extends StatefulWidget {
  final BibliotecaGame game;
  final int terminalIndex;   // 0-based

  const TerminalCRTOverlay({
    super.key,
    required this.game,
    required this.terminalIndex,
  });

  @override
  State<TerminalCRTOverlay> createState() => _TerminalCRTOverlayState();
}

class _TerminalCRTOverlayState extends State<TerminalCRTOverlay>
    with SingleTickerProviderStateMixin {
  late final TerminalLog _log;
  final List<String> _visibleLines  = [];
  String _currentLine               = '';
  int    _lineIdx                   = 0;
  int    _charIdx                   = 0;
  bool   _done                      = false;
  Timer? _typeTimer;

  // Cursor piscante
  late final AnimationController _cursorCtrl;

  @override
  void initState() {
    super.initState();
    _log = kTerminalLogs[widget.terminalIndex
        .clamp(0, kTerminalLogs.length - 1)];

    _cursorCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500))
      ..repeat(reverse: true);

    // Boot delay
    Future<void>.delayed(const Duration(milliseconds: 400), _typeNext);
  }

  void _typeNext() {
    if (!mounted) return;
    if (_lineIdx >= _log.entries.length) {
      setState(() => _done = true);
      return;
    }

    final fullLine = _log.entries[_lineIdx];
    if (_charIdx < fullLine.length) {
      setState(() {
        _currentLine = fullLine.substring(0, _charIdx + 1);
        _charIdx++;
      });
      _typeTimer = Timer(const Duration(milliseconds: 18), _typeNext);
    } else {
      // Linha completa → avança para a próxima
      setState(() {
        _visibleLines.add(fullLine);
        _currentLine = '';
        _lineIdx++;
        _charIdx     = 0;
      });
      _typeTimer = Timer(const Duration(milliseconds: 220), _typeNext);
    }
  }

  void _skipToEnd() {
    _typeTimer?.cancel();
    setState(() {
      _visibleLines.clear();
      _visibleLines.addAll(_log.entries);
      _currentLine = '';
      _done        = true;
    });
  }

  @override
  void dispose() {
    _typeTimer?.cancel();
    _cursorCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _GamePauseWrapper(
      game: widget.game,
      child: _CRTScanlines(
        child: Material(
          color: _RetroColors.bg.withValues(alpha: 0.95),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600, maxHeight: 420),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: BoxDecoration(
                  color: _RetroColors.bgPanel,
                  border: Border.all(color: _RetroColors.borderGlow, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: _RetroColors.borderGlow.withValues(alpha: 0.25),
                      blurRadius: 24,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Barra de título ────────────────────────────────────
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      color: _RetroColors.borderGlow.withValues(alpha: 0.08),
                      child: Row(
                        children: [
                          const Text('█ ', style: TextStyle(
                              color: _RetroColors.borderGlow, fontSize: 10)),
                          Expanded(
                            child: Text(
                              _log.title,
                              style: const TextStyle(
                                color: _RetroColors.textGreen,
                                fontSize: 10,
                                fontFamily: 'monospace',
                                letterSpacing: 1.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const Text(
                            'PUC-CAMPUS :: SISTEMA LOCAL',
                            style: TextStyle(
                              color: _RetroColors.textDim,
                              fontSize: 8,
                              fontFamily: 'monospace',
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // ── Área de log ────────────────────────────────────────
                    Expanded(
                      child: SingleChildScrollView(
                        reverse: true,
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Boot header
                            const Text(
                              'SISTEMA INICIALIZADO.\nCARREGANDO LOG LOCAL...\n',
                              style: TextStyle(
                                color: _RetroColors.textDim,
                                fontSize: 9,
                                fontFamily: 'monospace',
                                height: 1.6,
                              ),
                            ),
                            // Linhas já reveladas
                            for (final line in _visibleLines)
                              _LogLine(text: line),
                            // Linha em digitação
                            if (_currentLine.isNotEmpty)
                              AnimatedBuilder(
                                animation: _cursorCtrl,
                                builder: (_, __) => _LogLine(
                                  text: _currentLine,
                                  cursor: _cursorCtrl.value > 0.5,
                                ),
                              ),
                            // Cursor idle no final
                            if (_done)
                              AnimatedBuilder(
                                animation: _cursorCtrl,
                                builder: (_, __) => Text(
                                  _cursorCtrl.value > 0.5 ? '█' : '',
                                  style: const TextStyle(
                                    color: _RetroColors.textGreen,
                                    fontSize: 11,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    // ── Barra de botões ────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (!_done)
                            _RetroButton(
                              label: 'PULAR',
                              color: _RetroColors.textDim,
                              onTap: _skipToEnd,
                            ),
                          const SizedBox(width: 10),
                          _RetroButton(
                            label: 'FECHAR',
                            onTap: () =>
                                widget.game.closeTerminal(widget.terminalIndex),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Linha individual do log com coloração condicional
class _LogLine extends StatelessWidget {
  final String text;
  final bool   cursor;
  const _LogLine({required this.text, this.cursor = false});

  static Color _colorFor(String line) {
    final upper = line.toUpperCase();
    if (upper.contains('ALERTA') || upper.contains('ERRO') ||
        upper.contains('EVACUAÇÃO')) return _RetroColors.textRed;
    if (upper.contains('AVISO') || upper.contains('NÃO')) return _RetroColors.textAmber;
    return _RetroColors.textGreen;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        cursor ? '$text█' : text,
        style: TextStyle(
          color: _colorFor(text),
          fontSize: 10,
          fontFamily: 'monospace',
          height: 1.55,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. QuadroAvisosOverlay — mapa pixel art do Campus I
// ─────────────────────────────────────────────────────────────────────────────
class QuadroAvisosOverlay extends StatelessWidget {
  final BibliotecaGame game;
  const QuadroAvisosOverlay({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    return _GamePauseWrapper(
      game: game,
      child: Material(
        color: Colors.black.withValues(alpha: 0.88),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680, maxHeight: 500),
            child: Container(
              margin: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1208),
                border: Border.all(
                    color: _RetroColors.safeGold, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: _RetroColors.safeGold.withValues(alpha: 0.2),
                    blurRadius: 20,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Título
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    color: _RetroColors.safeGold.withValues(alpha: 0.08),
                    child: const Row(
                      children: [
                        Icon(Icons.map_outlined,
                            color: _RetroColors.safeGold, size: 14),
                        SizedBox(width: 8),
                        Text(
                          'QUADRO DE AVISOS — MAPA DO CAMPUS I',
                          style: TextStyle(
                            color: _RetroColors.safeGold,
                            fontSize: 10,
                            fontFamily: 'monospace',
                            letterSpacing: 1.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Mapa real do campus
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Image.asset(
                          'assets/images/screens/mapa_campus.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                  // Botão fechar
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: _RetroButton(
                        label: 'FECHAR',
                        color: _RetroColors.safeGold,
                        onTap: game.closeQuadroAvisos,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}


