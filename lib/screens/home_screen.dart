import 'dart:math'; // usado por _FramePainter e _CompassPainter
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

// Navegue para cá quando a tela de mapa estiver pronta:
// import 'map_selection_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Paleta fiel ao design
// ─────────────────────────────────────────────────────────────────────────────
abstract class _C {
  static const bg = Color(0xFF1A1208);
  static const amber = Color(0xFFD4860A);
  static const amberLight = Color(0xFFF5C842);
  static const amberDark = Color(0xFF7A4A05);
  static const btnFill = Color(0xFF2E1E06);
  static const btnBorder = Color(0xFFB87A18);
  static const btnShadow = Color(0xFF0A0600);
  static const hud = Color(0xFFCCA040);
  static const hudBg = Color(0x99000000);
  static const overlay = Color(0x55000000);
  static const vignette = Color(0xCC000000);
}

// ─────────────────────────────────────────────────────────────────────────────
// HomeScreen
// ─────────────────────────────────────────────────────────────────────────────
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glow;
  late final Animation<double> _glowAnim;

  // Simula leitura GPS dinâmica
  final String _gpsTopRight = 'GPS: -6.5,95,45';
  final String _gpsBottomRight = 'GPS: -22.06, 45,16';
  final String _hudTopLeft = 'NUD: ¥:329';

  @override
  void initState() {
    super.initState();
    _glow = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _glowAnim = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _glow, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _glow.dispose();
    super.dispose();
  }

  // ── Navegação ───────────────────────────────────────────────────────────────

  void _onStartGame() {
    HapticFeedback.mediumImpact();
    // Navigator.of(context).push(MaterialPageRoute(
    //   builder: (_) => const MapSelectionScreen(),
    // ));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: _C.btnFill,
        content: Text(
          'Tela de Mapa — em breve...',
          style: _pixelStyle(12, color: _C.amberLight),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _onOptions() {
    HapticFeedback.lightImpact();
    showDialog(
      context: context,
      builder: (_) => _OptionsDialog(),
    );
  }

  void _onExit() {
    HapticFeedback.lightImpact();
    SystemNavigator.pop();
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: _C.bg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Background
          const _Background(),

          // 2. Vinheta nas bordas
          _Vignette(),

          // 3. Borda dourada da tela (frame estilo RPG)
          _ScreenFrame(),

          // 4. HUD – cantos superiores
          SafeArea(
            child: Stack(
              children: [
                // Topo esquerdo — NUD
                Positioned(
                  top: 6,
                  left: 10,
                  child: _HudChip(text: _hudTopLeft),
                ),
                // Topo direito — GPS
                Positioned(
                  top: 6,
                  right: 10,
                  child: _HudChip(text: _gpsTopRight),
                ),

                // Título principal
                Positioned(
                  top: size.height * 0.06,
                  left: 0,
                  right: 0,
                  child: _TitleBlock(),
                ),

                // Bússola inferior esquerda
                Positioned(
                  bottom: 24,
                  left: 16,
                  child: _Compass(),
                ),

                // GPS inferior direito
                Positioned(
                  bottom: 24,
                  right: 10,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _HudChip(text: _gpsBottomRight),
                      const SizedBox(height: 4),
                      _StarIcon(),
                    ],
                  ),
                ),

                // Botões centrais — parte inferior
                Positioned(
                  bottom: size.height * 0.14,
                  left: 0,
                  right: 0,
                  child: _ButtonColumn(
                    glowAnim: _glowAnim,
                    onStart: _onStartGame,
                    onOptions: _onOptions,
                    onExit: _onExit,
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

// ─────────────────────────────────────────────────────────────────────────────
// Background
// ─────────────────────────────────────────────────────────────────────────────
class _Background extends StatelessWidget {
  const _Background();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.black, // fallback se a imagem não carregar
        image: DecorationImage(
          image: AssetImage('assets/images/start_screen.jpg'),
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Vinheta
// ─────────────────────────────────────────────────────────────────────────────
class _Vignette extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _VignettePainter());
  }
}

class _VignettePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -0.1),
          radius: 0.85,
          colors: [Colors.transparent, _C.vignette],
          stops: const [0.45, 1.0],
        ).createShader(rect),
    );
    // Faixa escura na parte inferior para os botões ficarem legíveis
    canvas.drawRect(
      Rect.fromLTWH(0, size.height * 0.62, size.width, size.height * 0.38),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, _C.bg.withValues(alpha: 0.92)],
        ).createShader(
          Rect.fromLTWH(0, size.height * 0.62, size.width, size.height * 0.38),
        ),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// Frame de tela (borda dourada estilo RPG)
// ─────────────────────────────────────────────────────────────────────────────
class _ScreenFrame extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _FramePainter());
  }
}

class _FramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const m = 6.0; // margem
    const r = 4.0; // raio do canto

    final outerRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(m, m, size.width - m * 2, size.height - m * 2),
      const Radius.circular(r),
    );

    // Borda externa fina dourada
    canvas.drawRRect(
      outerRect,
      Paint()
        ..color = _C.btnBorder.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Segunda borda (2px para dentro)
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
            m + 3, m + 3, size.width - (m + 3) * 2, size.height - (m + 3) * 2),
        const Radius.circular(r - 1),
      ),
      Paint()
        ..color = _C.amber.withValues(alpha: 0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );

    // Ornamentos nos 4 cantos
    _drawCornerOrnament(canvas, Offset(m + 2, m + 2), 0);
    _drawCornerOrnament(canvas, Offset(size.width - m - 2, m + 2), pi / 2);
    _drawCornerOrnament(
        canvas, Offset(size.width - m - 2, size.height - m - 2), pi);
    _drawCornerOrnament(canvas, Offset(m + 2, size.height - m - 2), 3 * pi / 2);
  }

  void _drawCornerOrnament(Canvas canvas, Offset center, double rotation) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation);
    final paint = Paint()
      ..color = _C.amber.withValues(alpha: 0.7)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;
    canvas.drawLine(const Offset(0, 0), const Offset(10, 0), paint);
    canvas.drawLine(const Offset(0, 0), const Offset(0, 10), paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// HUD Chip (pequeno painel monoespaçado no canto)
// ─────────────────────────────────────────────────────────────────────────────
class _HudChip extends StatelessWidget {
  final String text;
  const _HudChip({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: _C.hudBg,
        border: Border.all(color: _C.hud.withValues(alpha: 0.5), width: 1),
      ),
      child: Text(text, style: _pixelStyle(7, color: _C.hud)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Título INICIAR EXPLORAÇÃO / PUC CAMPINAS
// ─────────────────────────────────────────────────────────────────────────────
class _TitleBlock extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          // Linha superior — texto menor
          Text(
            'INICIAR EXPLORAÇÃO',
            textAlign: TextAlign.center,
            style: _pixelStyle(
              16,
              color: _C.amberLight,
              shadow: _C.amberDark,
            ),
          ),
          const SizedBox(height: 4),
          // Linha principal — maior e mais impactante
          Text(
            'PUC CAMPINAS',
            textAlign: TextAlign.center,
            style: _pixelStyle(
              22,
              color: _C.amber,
              shadow: _C.btnShadow,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Coluna de botões
// ─────────────────────────────────────────────────────────────────────────────
class _ButtonColumn extends StatelessWidget {
  final Animation<double> glowAnim;
  final VoidCallback onStart;
  final VoidCallback onOptions;
  final VoidCallback onExit;

  const _ButtonColumn({
    required this.glowAnim,
    required this.onStart,
    required this.onOptions,
    required this.onExit,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // START GAME — destaque com glow animado
          AnimatedBuilder(
            animation: glowAnim,
            builder: (_, __) => _PixelButton(
              label: 'START GAME',
              primary: true,
              glowIntensity: glowAnim.value,
              onTap: onStart,
            ),
          ),
          const SizedBox(height: 14),
          _PixelButton(
            label: 'OPTIONS',
            primary: false,
            glowIntensity: 0,
            onTap: onOptions,
          ),
          const SizedBox(height: 14),
          _PixelButton(
            label: 'EXIT GAME',
            primary: false,
            glowIntensity: 0,
            onTap: onExit,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PixelButton — botão estilo RPG com borda dupla e pixel corners
// ─────────────────────────────────────────────────────────────────────────────
class _PixelButton extends StatefulWidget {
  final String label;
  final bool primary;
  final double glowIntensity;
  final VoidCallback onTap;

  const _PixelButton({
    required this.label,
    required this.primary,
    required this.glowIntensity,
    required this.onTap,
  });

  @override
  State<_PixelButton> createState() => _PixelButtonState();
}

class _PixelButtonState extends State<_PixelButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final baseColor = widget.primary ? _C.amber : _C.btnBorder;
    final fillColor = widget.primary
        ? (_pressed ? _C.amberDark : _C.btnFill)
        : (_pressed ? const Color(0xFF1A1006) : const Color(0xFF150E04));

    final glowColor = widget.primary
        ? _C.amberLight.withValues(alpha: widget.glowIntensity * 0.6)
        : Colors.transparent;

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        transform: Matrix4.translationValues(0, _pressed ? 3 : 0, 0),
        child: CustomPaint(
          painter: _ButtonPainter(
            borderColor: baseColor,
            fillColor: fillColor,
            glowColor: glowColor,
            pressed: _pressed,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
            child: Center(
              child: Text(
                widget.label,
                style: _pixelStyle(
                  widget.primary ? 15 : 13,
                  color: widget.primary
                      ? Color.lerp(
                          _C.amberLight,
                          Colors.white,
                          widget.glowIntensity * 0.3,
                        )!
                      : _C.hud,
                  shadow: _C.btnShadow,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ButtonPainter extends CustomPainter {
  final Color borderColor;
  final Color fillColor;
  final Color glowColor;
  final bool pressed;

  _ButtonPainter({
    required this.borderColor,
    required this.fillColor,
    required this.glowColor,
    required this.pressed,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    const c = 4.0; // corte nos cantos (pixel art)

    // Sombra inferior (profundidade 3D)
    if (!pressed) {
      final shadowPath = Path()
        ..moveTo(c, h)
        ..lineTo(w - c, h)
        ..lineTo(w, h - c)
        ..lineTo(w, h + 4)
        ..lineTo(0, h + 4)
        ..close();
      canvas.drawPath(shadowPath, Paint()..color = _C.btnShadow);
    }

    // Shape do botão (octógono levemente cortado)
    final shape = Path()
      ..moveTo(c, 0)
      ..lineTo(w - c, 0)
      ..lineTo(w, c)
      ..lineTo(w, h - c)
      ..lineTo(w - c, h)
      ..lineTo(c, h)
      ..lineTo(0, h - c)
      ..lineTo(0, c)
      ..close();

    // Preenchimento
    canvas.drawPath(shape, Paint()..color = fillColor);

    // Glow no START GAME
    if (glowColor != Colors.transparent) {
      canvas.drawPath(
        shape,
        Paint()
          ..color = glowColor
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }

    // Borda externa
    canvas.drawPath(
      shape,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Linha interna clara (bevel top/left)
    final bevelPath = Path()
      ..moveTo(c + 2, 2)
      ..lineTo(w - c - 2, 2)
      ..lineTo(w - 2, c + 2)
      ..lineTo(w - 2, h * 0.4);
    canvas.drawPath(
      bevelPath,
      Paint()
        ..color = borderColor.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // Pixel ornamentos nos cantos superiores
    final pix = Paint()..color = borderColor;
    canvas.drawRect(Rect.fromLTWH(0, 0, 3, 1), pix);
    canvas.drawRect(Rect.fromLTWH(0, 0, 1, 3), pix);
    canvas.drawRect(Rect.fromLTWH(w - 3, 0, 3, 1), pix);
    canvas.drawRect(Rect.fromLTWH(w - 1, 0, 1, 3), pix);
  }

  @override
  bool shouldRepaint(covariant _ButtonPainter old) =>
      old.fillColor != fillColor ||
      old.glowColor != glowColor ||
      old.pressed != pressed;
}

// ─────────────────────────────────────────────────────────────────────────────
// Bússola
// ─────────────────────────────────────────────────────────────────────────────
class _Compass extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: _C.hudBg,
        border: Border.all(color: _C.hud.withValues(alpha: 0.5), width: 1),
        shape: BoxShape.circle,
      ),
      child: CustomPaint(painter: _CompassPainter()),
    );
  }
}

class _CompassPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2 - 2;

    final paint = Paint()
      ..color = _C.hud
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    // Círculo
    canvas.drawCircle(Offset(cx, cy), r, paint);

    // Rosa dos ventos
    final cardinalPaint = Paint()
      ..color = _C.amberLight
      ..style = PaintingStyle.fill;

    // Norte
    final north = Path()
      ..moveTo(cx, cy - r + 3)
      ..lineTo(cx - 4, cy - 4)
      ..lineTo(cx + 4, cy - 4)
      ..close();
    canvas.drawPath(north, cardinalPaint);

    // Sul
    final south = Path()
      ..moveTo(cx, cy + r - 3)
      ..lineTo(cx - 4, cy + 4)
      ..lineTo(cx + 4, cy + 4)
      ..close();
    canvas.drawPath(south, Paint()..color = _C.hud.withValues(alpha: 0.5));

    // Leste e Oeste
    canvas.drawLine(Offset(cx - r + 3, cy), Offset(cx - 4, cy), paint);
    canvas.drawLine(Offset(cx + 4, cy), Offset(cx + r - 3, cy), paint);

    // Letras N S E O
    void drawLetter(String l, double x, double y) {
      final tp = TextPainter(
        text: TextSpan(
          text: l,
          style: TextStyle(
            fontSize: 6,
            color: l == 'N' ? _C.amberLight : _C.hud,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, y - tp.height / 2));
    }

    drawLetter('N', cx, cy - r + 7);
    drawLetter('S', cx, cy + r - 7);
    drawLetter('L', cx + r - 7, cy);
    drawLetter('O', cx - r + 7, cy);

    // Centro
    canvas.drawCircle(
      Offset(cx, cy),
      2,
      Paint()..color = _C.amberLight,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// Ícone de estrela (canto inferior direito)
// ─────────────────────────────────────────────────────────────────────────────
class _StarIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(20, 20),
      painter: _StarPainter(),
    );
  }
}

class _StarPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final paint = Paint()..color = _C.hud.withValues(alpha: 0.8);

    // Losango simples (estrela de 4 pontas pixelada)
    final path = Path()
      ..moveTo(cx, 0)
      ..lineTo(cx + 4, cy)
      ..lineTo(cx, size.height)
      ..lineTo(cx - 4, cy)
      ..close();
    canvas.drawPath(path, paint);

    final path2 = Path()
      ..moveTo(0, cy)
      ..lineTo(cx, cy - 4)
      ..lineTo(size.width, cy)
      ..lineTo(cx, cy + 4)
      ..close();
    canvas.drawPath(path2, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// Dialog de opções (placeholder)
// ─────────────────────────────────────────────────────────────────────────────
class _OptionsDialog extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: _C.bg,
      shape: const RoundedRectangleBorder(),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: _C.btnBorder, width: 2),
          color: _C.btnFill,
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('OPTIONS', style: _pixelStyle(16, color: _C.amberLight)),
            const SizedBox(height: 20),
            _OptionRow(label: 'SFX', initial: true),
            const SizedBox(height: 12),
            _OptionRow(label: 'MÚSICA', initial: true),
            const SizedBox(height: 12),
            _OptionRow(label: 'VIBRAÇÃO', initial: true),
            const SizedBox(height: 24),
            _PixelButton(
              label: 'FECHAR',
              primary: true,
              glowIntensity: 0.8,
              onTap: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionRow extends StatefulWidget {
  final String label;
  final bool initial;
  const _OptionRow({required this.label, required this.initial});

  @override
  State<_OptionRow> createState() => _OptionRowState();
}

class _OptionRowState extends State<_OptionRow> {
  late bool _on;

  @override
  void initState() {
    super.initState();
    _on = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(widget.label, style: _pixelStyle(11, color: _C.hud)),
        GestureDetector(
          onTap: () => setState(() => _on = !_on),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              border: Border.all(color: _on ? _C.amber : _C.amberDark),
              color:
                  _on ? _C.amber.withValues(alpha: 0.15) : Colors.transparent,
            ),
            child: Text(
              _on ? 'ON' : 'OFF',
              style: _pixelStyle(10, color: _on ? _C.amberLight : _C.amberDark),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helper — estilo de texto pixelado (Press Start 2P)
// ─────────────────────────────────────────────────────────────────────────────
TextStyle _pixelStyle(
  double size, {
  Color color = _C.amber,
  Color? shadow,
}) {
  return GoogleFonts.pressStart2p(
    fontSize: size,
    color: color,
    shadows: shadow != null
        ? [
            Shadow(offset: const Offset(2, 2), color: shadow),
            Shadow(offset: const Offset(3, 3), blurRadius: 0, color: shadow),
          ]
        : null,
  );
}
