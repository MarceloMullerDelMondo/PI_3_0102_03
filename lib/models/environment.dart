import 'package:geolocator/geolocator.dart';

/// Representa um ambiente/localização do mundo do jogo.
class Environment {
  final String id;
  final String name;
  final String description;
  final String lore;
  final double latitude;
  final double longitude;
  final double unlockRadiusMeters;
  final String npcName;
  final String npcDescription;

  const Environment({
    required this.id,
    required this.name,
    required this.description,
    required this.lore,
    required this.latitude,
    required this.longitude,
    required this.unlockRadiusMeters,
    required this.npcName,
    required this.npcDescription,
  });

  /// Distância em metros entre o jogador e este ambiente.
  double distanceTo(Position playerPosition) {
    return Geolocator.distanceBetween(
      playerPosition.latitude,
      playerPosition.longitude,
      latitude,
      longitude,
    );
  }

  /// True se o jogador está dentro do raio de desbloqueio.
  bool isUnlockedBy(Position playerPosition) =>
      distanceTo(playerPosition) <= unlockRadiusMeters;
}

/// Registro estático de todos os ambientes do campus.
abstract class EnvironmentRegistry {
  static const Environment blocoH15 = Environment(
    id: 'h15_lab',
    name: 'Bloco H-15',
    description: 'Laboratório Improvisado — Setor UV',
    lore:
        'O Bloco H-15 foi isolado nas primeiras horas do surto. '
        'As luzes UV piscam sem parar. O ar é pesado e o cheiro '
        'de reagentes químicos gruda na garganta. Este é o último '
        'refúgio seguro do campus.',
    latitude: -22.83316,
    longitude: -47.05270,
    unlockRadiusMeters: 50.0,
    npcName: 'Dr. Álvaro',
    npcDescription:
        'Um professor de biologia idoso cercado de microscópios e '
        'anotações rabiscadas. Ele não confia em ninguém — ainda.',
  );

  static const List<Environment> all = [blocoH15];
}
