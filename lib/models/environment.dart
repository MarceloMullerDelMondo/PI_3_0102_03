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

  static const Environment bibliotecaCentral = Environment(
    id: 'biblioteca_central',
    name: 'Biblioteca Central',
    description: 'Arquivo contaminado — Setor de Pesquisa',
    lore:
        'A Biblioteca Central virou um abrigo silencioso depois do surto. '
        'Entre estantes tombadas e terminais ainda ligados, parte dos '
        'registros do campus pode revelar como a infeccao se espalhou.',
    latitude: -22.83400,
    longitude: -47.05350,
    unlockRadiusMeters: 50.0,
    npcName: 'Prof. Helena',
    npcDescription:
        'Uma pesquisadora que protege os arquivos do campus e procura '
        'evidencias sobre a origem da contaminacao.',
  );

  static const Environment refeitorioCentral = Environment(
    id: 'refeitorio_central',
    name: 'Refeitorio Central',
    description: 'Zona de sobrevivencia improvisada',
    lore:
        'O Refeitorio Central foi transformado em abrigo depois que as rotas '
        'principais cairam. Mesas viradas, barricadas e caixas de suprimentos '
        'dividem o espaco entre vivos desconfiados e infectados atraidos por '
        'qualquer barulho.',
    latitude: -22.833018,
    longitude: -47.052069,
    unlockRadiusMeters: 50.0,
    npcName: 'Marcos',
    npcDescription:
        'Um sobrevivente pragmatico e desconfiado que troca ajuda por servico '
        'e nao perdoa ameacas perto dos suprimentos.',
  );

  static const Environment caa = Environment(
    id: 'caa',
    name: 'CAA',
    description: 'Proxima zona bloqueada',
    lore:
        'O caminho para o CAA so se torna viavel depois que a area segura do '
        'Refeitorio e reforcada e Marcos libera a passagem.',
    latitude: -22.83200,
    longitude: -47.05450,
    unlockRadiusMeters: 50.0,
    npcName: '',
    npcDescription: '',
  );

  static const List<Environment> all = [
    blocoH15,
    bibliotecaCentral,
    refeitorioCentral,
    caa,
  ];
}
