import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/audio_manager.dart';
import '../services/firebase_service.dart';
import '../services/location_service.dart';
import 'biblioteca_level_screen.dart';
import 'caa_level_screen.dart';
import 'cafeteria_level_screen.dart';
import 'h15_level_screen.dart';
import 'reitoria_level_screen.dart';

abstract class _C {
  static const bg = Color(0xFF1A1208);
  static const amber = Color(0xFFD4860A);
  static const amberLight = Color(0xFFF5C842);
  static const btnFill = Color(0xFF2E1E06);
  static const btnBorder = Color(0xFFB87A18);
  static const btnShadow = Color(0xFF0A0600);
  static const hud = Color(0xFFCCA040);
  static const red = Color(0xFF8B0000);
}

const double _gpsUnlockRadiusMeters = 50.0;

class _MapArea {
  final int fase;
  final String nome;
  final double relX;
  final double relY;
  final double relW;
  final double relH;
  final double lat;
  final double lng;

  const _MapArea({
    required this.fase,
    required this.nome,
    required this.relX,
    required this.relY,
    required this.relW,
    required this.relH,
    required this.lat,
    required this.lng,
  });
}

// relX/relY = centre of the marker as a fraction of live screen size.
// Calibrated from the user's screenshot (browser 500×875 game area).
// NOTE: Fase 3 (Biblioteca) marker position and GPS coords need on-site calibration.
const List<_MapArea> _areas = [
  _MapArea(
    fase: 1,
    nome: 'Bloco H-15',
    relX: 0.23,
    relY: 0.78,
    relW: 0.22,
    relH: 0.16,
    lat: -22.834108582764266,
    lng: -47.0526303597742,
  ),
  _MapArea(
    fase: 2,
    nome: 'Refeitorio Central',
    relX: 0.79,
    relY: 0.46,
    relW: 0.22,
    relH: 0.16,
    lat: -22.833053216294353,
    lng: -47.05204664488465,
  ),
  _MapArea(
    fase: 3,
    nome: 'Biblioteca',
    relX: 0.45,
    relY: 0.28,
    relW: 0.22,
    relH: 0.16,
    lat: -22.833823430629206,
    lng: -47.05189353930646,
  ),
  _MapArea(
    fase: 4,
    nome: 'CAA',
    relX: 0.80,
    relY: 0.57,
    relW: 0.22,
    relH: 0.16,
    lat: -22.83336777023198,
    lng: -47.05159051796952,
  ),
  _MapArea(
    fase: 5,
    nome: 'Reitoria',
    relX: 0.78,
    relY: 0.87,
    relW: 0.22,
    relH: 0.16,
    lat: -22.83496957419998,
    lng: -47.0511111103182,
  ),
];

class MapSelectionScreen extends StatefulWidget {
  final String playerName;
  final bool devMode;

  const MapSelectionScreen({
    super.key,
    required this.playerName,
    required this.devMode,
  });

  @override
  State<MapSelectionScreen> createState() => _MapSelectionScreenState();
}

class _MapSelectionScreenState extends State<MapSelectionScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pinPulse;
  late final Animation<double> _pinScale;

  int _faseAtual = 1;
  bool _loading = true;
  bool _checkingGps = false;
  int? _checkingFase;

  @override
  void initState() {
    super.initState();
    _pinPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    )..repeat(reverse: true);
    _pinScale = Tween<double>(begin: 0.88, end: 1.16).animate(
      CurvedAnimation(parent: _pinPulse, curve: Curves.easeInOut),
    );
    _loadProgress();
  }

  @override
  void dispose() {
    _pinPulse.dispose();
    super.dispose();
  }

  Future<void> _loadProgress() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _faseAtual = prefs.getInt(PrefKeys.faseAtual) ?? 1;
      _loading = false;
    });
  }

  Future<void> _onAreaTap(_MapArea area) async {
    if (_loading || _checkingGps) return;
    HapticFeedback.mediumImpact();

    // Em modo normal: checar progressão e Firebase
    if (!widget.devMode) {
      // CAA (Fase 4) exige que a missão principal do Refeitório esteja concluída.
      if (area.fase == 4) {
        final unlocked =
            await FirebaseService.instance.canAccessArea3(widget.playerName);
        if (!unlocked) {
          _pixelToast(
            'Voce ainda precisa concluir os objetivos do Refeitorio antes de seguir para o CAA.',
            isError: false,
          );
          return;
        }
      }

      if (area.fase > _faseAtual) {
        _pixelToast(
          '[AREA BLOQUEADA] Conclua a zona anterior para liberar este ponto no mapa.',
          isError: false,
        );
        return;
      }
    }

    // Fases futuras ainda nao implementadas (independente do modo)
    if (area.fase > 5) {
      _showWipDialog(area.fase);
      return;
    }

    final accessGranted = await _canEnterArea(area);
    if (!accessGranted || !mounted) return;

    // Capture navigator before any await to avoid cross-async-gap context use.
    final navigator = Navigator.of(context);

    // Stop the menu BGM before entering the level so there is no overlap.
    await AudioManager.instance.stopMenuBgm();

    final completed = await navigator.push<bool>(
      MaterialPageRoute(
        builder: (_) => switch (area.fase) {
          5 => ReitoriaLevelScreen(
              playerName: widget.playerName,
              devMode: widget.devMode,
            ),
          4 => CaaLevelScreen(
              playerName: widget.playerName,
              devMode: widget.devMode,
            ),
          3 => BibliotecaLevelScreen(
              playerName: widget.playerName,
              devMode: widget.devMode,
            ),
          2 => CafeteriaLevelScreen(
              playerName: widget.playerName,
              devMode: widget.devMode,
            ),
          _ => H15LevelScreen(
              playerName: widget.playerName,
              devMode: widget.devMode,
            ),
        },
      ),
    );

    // Restore menu BGM when returning from the level (respects music ON/OFF).
    if (mounted) await AudioManager.instance.resumeMenuBgm();

    if (completed == true && mounted) {
      // Read prefs directly: levels that manage their own progression (e.g. Fase 2
      // calls completeArea2 before popping) will already have advanced faseAtual,
      // so we only call unlockNextPhase when the level has NOT already done so.
      final prefs = await SharedPreferences.getInstance();
      final savedFase = prefs.getInt(PrefKeys.faseAtual) ?? 1;
      if (savedFase <= area.fase) {
        await FirebaseService.instance.unlockNextPhase(widget.playerName);
      }
    }
    if (mounted) await _loadProgress();
  }


  Future<bool> _canEnterArea(_MapArea area) async {
    setState(() {
      _checkingGps = true;
      _checkingFase = area.fase;
    });

    try {
      final result = await LocationService.instance
          .isWithinRadius(
            area.lat,
            area.lng,
            radiusMeters: _gpsUnlockRadiusMeters,
            devMode: widget.devMode,
          )
          .timeout(const Duration(seconds: 12));

      final msg = result.toastMessage;
      if (msg != null) _pixelToast(msg, isError: result.isError);
      return result.allowed;
    } on TimeoutException {
      _pixelToast('[GPS LENTO] Tente novamente em alguns segundos.', isError: true);
      return false;
    } finally {
      if (mounted) {
        setState(() {
          _checkingGps = false;
          _checkingFase = null;
        });
      }
    }
  }

  void _showWipDialog(int fase) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1208),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: Color(0xFFB87A18), width: 2),
        ),
        title: Text(
          'FASE $fase',
          style: GoogleFonts.pressStart2p(
            fontSize: 14,
            color: _C.amberLight,
          ),
        ),
        content: Text(
          'Fase $fase em\ndesenvolvimento...',
          style: GoogleFonts.pressStart2p(
            fontSize: 10,
            color: _C.hud,
            height: 1.9,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'OK',
              style: GoogleFonts.pressStart2p(
                fontSize: 10,
                color: _C.amberLight,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _pixelToast(String message, {required bool isError}) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(14, 0, 14, 24),
          duration: const Duration(seconds: 4),
          content: _PixelToastContent(message: message, isError: isError),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black,
              image: DecorationImage(
                image: AssetImage('assets/images/screens/map_screen.png'),
                fit: BoxFit.cover,
              ),
            ),
          ),
          for (final area in _areas) _buildTransparentHotspot(area, size),
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: _BackButton(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransparentHotspot(_MapArea area, Size size) {
    final width = size.width * area.relW;
    final height = size.height * area.relH;
    final left = size.width * area.relX - width / 2;
    final top = size.height * area.relY - height / 2;

    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _onAreaTap(area),
        child: Center(child: _buildAreaIcon(area)),
      ),
    );
  }

  Widget _buildAreaIcon(_MapArea area) {
    if (_checkingGps && _checkingFase == area.fase) {
      return const SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(color: _C.amberLight, strokeWidth: 2),
      );
    }

    final isCompleted = area.fase < _faseAtual;
    final isLocked = area.fase > _faseAtual;
    final isActive = area.fase == _faseAtual;

    return _MapMarker(
      nome: area.nome,
      fase: area.fase,
      isActive: isActive,
      isCompleted: isCompleted,
      isLocked: isLocked,
      pulseAnim: isActive ? _pinScale : null,
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// _MapMarker â€” pixel-art styled location pin for the map
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _MapMarker extends StatelessWidget {
  final String nome;
  final int fase;
  final bool isActive;
  final bool isCompleted;
  final bool isLocked;
  final Animation<double>? pulseAnim;

  const _MapMarker({
    required this.nome,
    required this.fase,
    required this.isActive,
    required this.isCompleted,
    required this.isLocked,
    this.pulseAnim,
  });

  @override
  Widget build(BuildContext context) {
    if (isActive) {
      return AnimatedBuilder(
        animation: pulseAnim!,
        builder: (_, child) =>
            Transform.scale(scale: pulseAnim!.value, child: child),
        child: _ActiveMarker(nome: nome, fase: fase),
      );
    }
    if (isCompleted) return _CompletedMarker(fase: fase);
    return const _LockedMarker();
  }
}

// â”€â”€ Active â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _ActiveMarker extends StatelessWidget {
  final String nome;
  final int fase;
  const _ActiveMarker({required this.nome, required this.fase});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Badge
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: const Color(0xFF1C0F02),
            border: Border.all(color: _C.amberLight, width: 2.5),
            boxShadow: [
              BoxShadow(
                color: _C.amberLight.withValues(alpha: 0.70),
                blurRadius: 14,
                spreadRadius: 3,
              ),
              const BoxShadow(
                color: Color(0xAA0A0600),
                offset: Offset(0, 3),
                blurRadius: 4,
              ),
            ],
          ),
          child: Center(
            child: Text(
              'F$fase',
              style: GoogleFonts.pressStart2p(
                fontSize: 14,
                color: _C.amberLight,
                shadows: const [
                  Shadow(color: Colors.black, offset: Offset(1, 2)),
                ],
              ),
            ),
          ),
        ),
        // Triangular pointer
        const CustomPaint(
          size: Size(16, 10),
          painter: _TrianglePainter(color: _C.amberLight),
        ),
        const SizedBox(height: 3),
        // Name label
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xEE1A0E02),
            border: Border.all(
              color: _C.amber.withValues(alpha: 0.65),
              width: 1,
            ),
          ),
          child: Text(
            nome,
            textAlign: TextAlign.center,
            style: GoogleFonts.pressStart2p(
              fontSize: 5,
              color: _C.hud,
              height: 1.6,
            ),
          ),
        ),
      ],
    );
  }
}

// â”€â”€ Completed â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _CompletedMarker extends StatelessWidget {
  final int fase;
  const _CompletedMarker({required this.fase});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFF071207),
            border: Border.all(
              color: const Color(0xFF4ADE80).withValues(alpha: 0.6),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF4ADE80).withValues(alpha: 0.28),
                blurRadius: 8,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                Text(
                  'F$fase',
                  style: GoogleFonts.pressStart2p(
                    fontSize: 8,
                    color: const Color(0xFF4ADE80).withValues(alpha: 0.45),
                  ),
                ),
                const Icon(Icons.check_rounded,
                    color: Color(0xFF4ADE80), size: 20),
              ],
            ),
          ),
        ),
        CustomPaint(
          size: const Size(10, 7),
          painter: _TrianglePainter(
            color: const Color(0xFF4ADE80).withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }
}

// â”€â”€ Locked â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _LockedMarker extends StatelessWidget {
  const _LockedMarker();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.50),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.18),
              width: 1.5,
            ),
          ),
          child: Center(
            child: Icon(
              Icons.lock,
              color: Colors.white.withValues(alpha: 0.30),
              size: 16,
            ),
          ),
        ),
        CustomPaint(
          size: const Size(10, 7),
          painter: _TrianglePainter(
            color: Colors.white.withValues(alpha: 0.18),
          ),
        ),
      ],
    );
  }
}

// â”€â”€ Triangle pointer â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _TrianglePainter extends CustomPainter {
  final Color color;
  const _TrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..lineTo(size.width, 0)
        ..lineTo(size.width / 2, size.height)
        ..close(),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _TrianglePainter old) => old.color != color;
}

class _BackButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).pop(),
      child: SizedBox(
        width: 44,
        height: 44,
        child: Icon(
          Icons.arrow_back,
          color: _C.amberLight.withValues(alpha: 0.85),
          size: 28,
        ),
      ),
    );
  }
}

class _PixelToastContent extends StatelessWidget {
  final String message;
  final bool isError;

  const _PixelToastContent({
    required this.message,
    required this.isError,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isError ? const Color(0xEE1A0000) : const Color(0xEE1A1208),
        border: Border.all(
          color: isError ? _C.red : _C.btnBorder,
          width: 1.5,
        ),
      ),
      child: Text(
        message,
        style: GoogleFonts.pressStart2p(
          fontSize: 8,
          color: isError ? const Color(0xFFFF7777) : _C.amberLight,
          height: 1.8,
        ),
      ),
    );
  }
}

class MissionScreen extends StatelessWidget {
  final int fase;

  const MissionScreen({
    super.key,
    required this.fase,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.bg,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'MISSÃƒO $fase',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.pressStart2p(
                        fontSize: 18,
                        color: _C.amberLight,
                        shadows: const [
                          Shadow(offset: Offset(2, 2), color: _C.btnShadow),
                        ],
                      ),
                    ),
                    const SizedBox(height: 42),
                    _CompleteMissionButton(
                      onTap: () => Navigator.of(context).pop(true),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 14,
              left: 14,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).pop(false),
                child: Text(
                  '< ABANDONAR',
                  style: GoogleFonts.pressStart2p(fontSize: 8, color: _C.hud),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompleteMissionButton extends StatefulWidget {
  final VoidCallback onTap;

  const _CompleteMissionButton({required this.onTap});

  @override
  State<_CompleteMissionButton> createState() => _CompleteMissionButtonState();
}

class _CompleteMissionButtonState extends State<_CompleteMissionButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        transform: Matrix4.translationValues(0, _pressed ? 4 : 0, 0),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
        decoration: BoxDecoration(
          color: _pressed ? const Color(0xFF3A2508) : _C.btnFill,
          border: Border.all(color: _C.amber, width: 2),
          boxShadow: _pressed
              ? null
              : const [
                  BoxShadow(
                    color: _C.btnShadow,
                    offset: Offset(0, 5),
                    blurRadius: 0,
                  ),
                ],
        ),
        child: Text(
          'CONCLUIR MISSÃƒO\nE SOBREVIVER',
          textAlign: TextAlign.center,
          style: GoogleFonts.pressStart2p(
            fontSize: 13,
            color: _C.amberLight,
            height: 1.8,
            shadows: const [
              Shadow(offset: Offset(2, 2), color: _C.btnShadow),
            ],
          ),
        ),
      ),
    );
  }
}
