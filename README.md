# PUC Survival RPG

RPG de sobrevivência 2D com geolocalização, desenvolvido em Flutter + Flame para a disciplina de Projeto Integrador III — Sistemas de Informação, PUC-Campinas.

O campus vira o mapa: o jogador precisa estar fisicamente perto de um ponto real (Bloco H-15) para desbloquear a fase.

---

## Início rápido

**Pré-requisito:** Flutter SDK ≥ 3.3.0

```bash
flutter pub get
flutter run
```

O Flutter detecta os dispositivos disponíveis e pergunta onde rodar. Escolha entre dispositivo Android físico (GPS real) ou emulador/Chrome (modo dev sem GPS).

Para rodar diretamente num alvo específico:

```bash
flutter run -d android   # dispositivo Android conectado
flutter run -d chrome    # navegador (GPS desativado — use o botão DEV MODE)
```

> **Firebase:** o arquivo `firebase_options.dart` já está configurado. Se precisar reconfigurar as chaves do projeto, instale o FlutterFire CLI e rode `flutterfire configure` na raiz.

---

## O que tem de diferente

### Geolocalização real
- O jogo lê o GPS em tempo real via `geolocator`.
- Cada fase fica bloqueada até o jogador estar dentro de um raio de **50 metros** das coordenadas do ponto no campus.
- No modo desenvolvedor (`DEV MODE`, acessível pela tela de mapa), o GPS é ignorado para testes sem precisar estar no local.

### Motor de jogo 2D (Flame)
- A fase H-15 usa o Flame como engine: mapa de colisões carregado de JSON (Tiled), sistema de sprites, joystick virtual, câmera com follow e zoom.
- Zumbis com IA de perseguição, sistema de dano, horda com timer e efeitos de impacto em canvas.

### Progressão persistida no Firebase
- Arma equipada e progresso de missão são salvos no Firestore e restaurados na próxima sessão.
- O jogador consegue continuar de onde parou mesmo após fechar o app.

---

## Tecnologias

| Pacote | Uso |
|---|---|
| `flutter` + `dart` | Framework principal |
| `flame` + `flame_tiled` | Engine 2D e mapas de colisão |
| `flame_audio` | Música e efeitos sonoros |
| `firebase_core` + `cloud_firestore` | Persistência em nuvem |
| `geolocator` | Leitura e validação de GPS |
| `google_fonts` | Tipografia da UI |

---

## Estrutura

```
lib/
├── game/           # Engine Flame (H15Game, SurvivalGame)
├── models/         # Modelos de dados (Environment)
├── screens/        # Telas (HomeScreen, MapSelectionScreen, H15LevelScreen)
├── services/       # Serviços (AudioManager, FirebaseService, LocationService)
├── main.dart
└── firebase_options.dart

assets/
├── images/         # Sprites, NPCs, telas, fundo do mapa
├── tiles/          # JSON de colisões (Tiled)
└── audio/          # Trilha sonora
```
