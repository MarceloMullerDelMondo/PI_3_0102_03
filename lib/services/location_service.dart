import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Resultado tipado de uma tentativa de obter localização.
sealed class LocationResult {}

class LocationSuccess extends LocationResult {
  final Position position;
  LocationSuccess(this.position);
}

class LocationFailure extends LocationResult {
  final String message;
  LocationFailure(this.message);
}

/// Serviço responsável por permissões e leitura de GPS.
class LocationService {
  LocationService._();
  static final LocationService instance = LocationService._();

  /// Solicita permissões e retorna a posição atual do jogador.
  Future<LocationResult> getCurrentPosition() async {
    if (kIsWeb) {
      return LocationFailure(
        'GPS nativo desativado no navegador.\nUse o modo desenvolvedor para testar no Chrome.',
      );
    }

    // 1. GPS habilitado no device?
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return LocationFailure(
        'O GPS está desativado.\nVá em Configurações para continuar.',
      );
    }

    // 2. Permissão
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return LocationFailure(
          'Permissão de localização negada.\nO jogo precisa do GPS para funcionar.',
        );
      }
    }
    if (permission == LocationPermission.deniedForever) {
      return LocationFailure(
        'Permissão bloqueada permanentemente.\nVá em Configurações > Aplicativos para liberar.',
      );
    }

    // 3. Obtém posição com alta precisão (necessário para raio de 50 m)
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      return LocationSuccess(position);
    } catch (e) {
      return LocationFailure(
        'Não foi possível obter a localização.\nTente novamente ao ar livre.',
      );
    }
  }

  /// Stream de posição contínua (uso futuro — rastreamento em tempo real).
  Stream<Position> get positionStream {
    if (kIsWeb) return const Stream.empty();

    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    );
  }
}
