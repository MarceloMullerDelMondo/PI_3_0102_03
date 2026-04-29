import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/firebase_service.dart';
import 'h15_level_screen.dart';

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

const List<_MapArea> _areas = [
  _MapArea(
    fase: 1,
    nome: 'Bloco H-15',
    relX: 0.25,
    relY: 0.65,
    relW: 0.25,
    relH: 0.15,
    lat: -22.83316,
    lng: -47.05270,
  ),
  _MapArea(
    fase: 2,
    nome: 'Biblioteca Central',
    relX: 0.28,
    relY: 0.35,
    relW: 0.25,
    relH: 0.15,
    lat: -22.83400,
    lng: -47.05350,
  ),
  _MapArea(
    fase: 3,
    nome: 'Refeitório Central',
    relX: 0.78,
    relY: 0.38,
    relW: 0.25,
    relH: 0.15,
    lat: -22.83500,
    lng: -47.05100,
  ),
  _MapArea(
    fase: 4,
    nome: 'CAA',
    relX: 0.80,
    relY: 0.62,
    relW: 0.25,
    relH: 0.15,
    lat: -22.83200,
    lng: -47.05450,
  ),
  _MapArea(
    fase: 5,
    nome: 'Reitoria',
    relX: 0.72,
    relY: 0.85,
    relW: 0.25,
    relH: 0.15,
    lat: -22.83100,
    lng: -47.05200,
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

    if (area.fase > _faseAtual) {
      _pixelToast(
        '[ÁREA BLOQUEADA] Conclua a zona anterior para acessar',
        isError: false,
      );
      return;
    }

    final accessGranted = await _canEnterArea(area);
    if (!accessGranted || !mounted) return;

    final completed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => area.fase == 1
            ? const H15LevelScreen()
            : MissionScreen(fase: area.fase),
      ),
    );

    if (completed == true && mounted && area.fase == _faseAtual) {
      await FirebaseService.instance.unlockNextPhase(widget.playerName);
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _faseAtual = prefs.getInt(PrefKeys.faseAtual) ?? _faseAtual;
      });
    }
  }

  Future<bool> _canEnterArea(_MapArea area) async {
    if (widget.devMode) {
      _pixelToast('[DEV MODE] Acesso liberado sem GPS', isError: false);
      return true;
    }

    if (kIsWeb) {
      _pixelToast(
        '[GPS INDISPONÍVEL] No Chrome, ative o modo DEV para testar.',
        isError: true,
      );
      return false;
    }

    setState(() {
      _checkingGps = true;
      _checkingFase = area.fase;
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _pixelToast('[GPS INDISPONÍVEL] Habilite a localização.', isError: true);
        return false;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _pixelToast('[GPS NEGADO] Permita a localização para entrar.', isError: true);
        return false;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).timeout(const Duration(seconds: 10));

      final distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        area.lat,
        area.lng,
      );

      if (distance <= 50) return true;

      _pixelToast(
        '[SINAL FRACO] Aproxime-se do local.\nDistância atual: ${distance.toStringAsFixed(0)}m',
        isError: true,
      );
      return false;
    } on TimeoutException {
      _pixelToast('[GPS LENTO] Tente novamente em alguns segundos.', isError: true);
      return false;
    } catch (_) {
      _pixelToast('[GPS INDISPONÍVEL] Não foi possível obter sua posição.', isError: true);
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
                image: AssetImage('assets/images/map_screen.jpg'),
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
        width: 24,
        height: 24,
        child: CircularProgressIndicator(
          color: _C.amberLight,
          strokeWidth: 2,
        ),
      );
    }

    if (area.fase < _faseAtual) {
      return Icon(
        Icons.check_circle,
        size: 22,
        color: Colors.white.withValues(alpha: 0.45),
      );
    }

    if (area.fase > _faseAtual) {
      return Icon(
        Icons.lock,
        size: 28,
        color: Colors.black.withValues(alpha: 0.55),
      );
    }

    return AnimatedBuilder(
      animation: _pinScale,
      builder: (_, child) => Transform.scale(
        scale: _pinScale.value,
        child: child,
      ),
      child: Icon(
        Icons.location_on,
        size: 38,
        color: _C.amberLight,
        shadows: [
          Shadow(
            color: _C.amberLight.withValues(alpha: 0.8),
            blurRadius: 14,
          ),
        ],
      ),
    );
  }
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
                      'MISSÃO $fase',
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
          'CONCLUIR MISSÃO\nE SOBREVIVER',
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
