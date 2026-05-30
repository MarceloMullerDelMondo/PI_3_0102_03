import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

// ─────────────────────────────────────────────────────────────────────────────
// LocationResult — resultado tipado de getCurrentPosition()
// ─────────────────────────────────────────────────────────────────────────────
sealed class LocationResult {}

class LocationSuccess extends LocationResult {
  final Position position;
  LocationSuccess(this.position);
}

class LocationFailure extends LocationResult {
  final String message;
  LocationFailure(this.message);
}

// ─────────────────────────────────────────────────────────────────────────────
// LocationCheckResult — resultado tipado de isWithinRadius()
//
// Cada subtipo carrega o que a tela precisa saber sem reexpor Geolocator:
//   .allowed       → pode entrar no level?
//   .toastMessage  → texto para o _pixelToast (null = sem toast)
//   .isError       → toast vermelho (true) ou informativo (false)
// ─────────────────────────────────────────────────────────────────────────────
sealed class LocationCheckResult {
  const LocationCheckResult();
  bool get allowed;
  String? get toastMessage;
  bool get isError;
}

/// GPS ignorado: devMode ativo ou plataforma desktop sem hardware GPS.
class CheckBypassed extends LocationCheckResult {
  const CheckBypassed(this._reason);
  final String _reason;
  @override bool get allowed => true;
  @override String? get toastMessage => _reason;
  @override bool get isError => false;
}

/// Jogador dentro do raio — pode entrar.
class CheckWithin extends LocationCheckResult {
  const CheckWithin(this.distanceMeters);
  final double distanceMeters;
  @override bool get allowed => true;
  @override String? get toastMessage => null; // sem toast quando dentro
  @override bool get isError => false;
}

/// Jogador fora do raio — mostra distância.
class CheckTooFar extends LocationCheckResult {
  const CheckTooFar({required this.distanceMeters, required this.radiusMeters});
  final double distanceMeters;
  final double radiusMeters;
  @override bool get allowed => false;
  @override String? get toastMessage =>
      '[FORA DA AREA] Va ate a localizacao da zona.\n'
      'Raio: ${radiusMeters.toStringAsFixed(0)}m | '
      'Distancia: ${distanceMeters.toStringAsFixed(0)}m';
  @override bool get isError => true;
}

/// Erro de GPS: permissão negada, serviço desligado, plataforma web, etc.
class CheckError extends LocationCheckResult {
  const CheckError(this._message);
  final String _message;
  @override bool get allowed => false;
  @override String? get toastMessage => _message;
  @override bool get isError => true;
}

// ─────────────────────────────────────────────────────────────────────────────
// LocationService — singleton
// ─────────────────────────────────────────────────────────────────────────────
class LocationService {
  LocationService._();
  static final LocationService instance = LocationService._();

  // Desktop platforms (Windows, Linux, macOS) have no GPS hardware.
  // isWithinRadius returns CheckBypassed automatically for them.
  bool get _isDesktopPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS);

  // ── Permission helpers ────────────────────────────────────────────────────

  /// Verifica e, se necessário, solicita permissão de localização.
  /// Retorna um [LocationFailure] descritivo se algo bloquear, null se ok.
  Future<LocationFailure?> _ensurePermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return LocationFailure(
        'O GPS está desativado.\nVá em Configurações para continuar.',
      );
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return LocationFailure(
          'Permissão de localização negada.\n'
          'O jogo precisa do GPS para funcionar.',
        );
      }
    }
    if (permission == LocationPermission.deniedForever) {
      return LocationFailure(
        'Permissão bloqueada permanentemente.\n'
        'Vá em Configurações > Aplicativos para liberar.',
      );
    }
    return null;
  }

  // ── Posição atual ─────────────────────────────────────────────────────────

  /// Solicita permissões e retorna a posição atual do jogador.
  Future<LocationResult> getCurrentPosition() async {
    if (kIsWeb) {
      return LocationFailure(
        'GPS nativo desativado no navegador.\n'
        'Use o modo desenvolvedor para testar no Chrome.',
      );
    }

    final permError = await _ensurePermission();
    if (permError != null) return permError;

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      return LocationSuccess(position);
    } catch (e) {
      return LocationFailure(
        'Não foi possível obter a localização.\n'
        'Tente novamente ao ar livre.',
      );
    }
  }

  // ── Radius check ──────────────────────────────────────────────────────────

  /// Verifica se o jogador está dentro de [radiusMeters] da posição alvo.
  ///
  /// Bypass automático quando:
  ///  • [devMode] == true (modo desenvolvedor explícito)
  ///  • plataforma desktop (Windows / Linux / macOS) — sem hardware GPS
  ///
  /// No web retorna [CheckError] para direcionar o usuário ao devMode.
  Future<LocationCheckResult> isWithinRadius(
    double targetLat,
    double targetLng, {
    double radiusMeters = 50.0,
    bool devMode = false,
  }) async {
    if (devMode) {
      return const CheckBypassed('[DEV MODE] GPS bypassed — acesso liberado');
    }
    if (_isDesktopPlatform) {
      return const CheckBypassed(
        '[PC MODE] Sem GPS no desktop — acesso liberado para testes',
      );
    }
    if (kIsWeb) {
      return const CheckError(
        '[GPS INDISPONÍVEL] No Chrome, ative o modo DEV para testar.',
      );
    }

    final loc = await getCurrentPosition();
    return switch (loc) {
      LocationFailure(:final message) => CheckError(message),
      LocationSuccess(:final position) => _evaluate(
          position, targetLat, targetLng, radiusMeters),
    };
  }

  LocationCheckResult _evaluate(
    Position pos, double targetLat, double targetLng, double radius) {
    final d = Geolocator.distanceBetween(
      pos.latitude, pos.longitude, targetLat, targetLng);
    return d <= radius
        ? CheckWithin(d)
        : CheckTooFar(distanceMeters: d, radiusMeters: radius);
  }

  // ── Streams ───────────────────────────────────────────────────────────────

  Stream<Position> get positionStream {
    if (kIsWeb || _isDesktopPlatform) return const Stream.empty();
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    );
  }

  Stream<LocationResult> watchPosition() async* {
    if (kIsWeb || _isDesktopPlatform) return;

    final permError = await _ensurePermission();
    if (permError != null) {
      yield permError;
      return;
    }

    await for (final position in positionStream) {
      yield LocationSuccess(position);
    }
  }
}
