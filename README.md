---

# Projeto Integrador 3: PUC Survival RPG 🧟‍♂️📍

Este projeto tem como objetivo desenvolver um RPG mobile de sobrevivência baseado em geolocalização para a disciplina de Projeto Integrador III do curso de Sistemas de Informação da PUC-Campinas. O jogo utiliza o mundo real (focado no Campus I) como mapa para uma narrativa imersiva de sobrevivência e gestão de recursos pós-apocalíptica.

## 🛠️ Tecnologias Utilizadas

* **Flutter & Dart:** Framework principal para o desenvolvimento multiplataforma.
* **Firebase (Firestore):** Banco de dados em tempo real e em nuvem para salvar o progresso, inventário e decisões do jogador.
* **Geolocator:** Pacote para leitura e validação de coordenadas de GPS em tempo real.
* **Flame:** Motor de jogo 2D integrado ao Flutter para renderização de elementos gráficos e HUDs.

---

## 📱 Funcionalidades e Módulos do Jogo

O aplicativo transforma o ambiente universitário em zonas de exploração, onde o jogador precisa se mover fisicamente para interagir com o jogo.

### 📌 Módulo de Exploração (Geolocalização)
* **Leitura de GPS em Tempo Real:** Rastreio do jogador para liberação de eventos baseados em proximidade.
* **Validação de Raio (50m):** O jogador só consegue interagir com os pontos de interesse (ex: Bloco H-15) se estiver fisicamente próximo às coordenadas cadastradas.
* **Cadastro Estático de Ambientes:** Mapeamento de locais chave do campus (Laboratórios, Biblioteca, etc.).

### 📌 Módulo de Narrativa e Sobrevivência
* **Interação com NPCs:** Diálogos e missões acionados por localização (ex: Encontro com o Dr. Álvaro no Laboratório).
* **Sistema de Inventário:** Escolha e armazenamento de itens de sobrevivência (Facão, Taco) persistidos no Firestore.
* **Interface Imersiva:** Tema "Dark" pós-apocalíptico com painéis de status (Scanning, Found, Error).

---

## 📂 Estrutura do Projeto

```text
rpg_puc_survival/
├── lib/
│   ├── game/               # Lógica do motor Flame (SurvivalGame)
│   ├── models/             # Classes de dados (Environment, etc.)
│   ├── screens/            # Telas da interface gráfica (home_screen, game_screen)
│   ├── services/           # Regras de negócio e APIs (location_service)
│   ├── main.dart           # Ponto de entrada da aplicação
│   └── firebase_options.dart # Configurações de conexão do Firebase
├── android/                # Configurações nativas Android
├── web/                    # Configurações nativas Web
├── pubspec.yaml            # Gerenciador de dependências
└── README.md               # Documentação do projeto
```

---

## 🚀 Como Executar o Projeto

### Pré-requisitos
* **Flutter SDK** (versão 3.3.0 ou superior)
* **Android Studio** (para emuladores ou compilação nativa) ou **Google Chrome** (para testes Web)
* Conta Google configurada no **Firebase Console**

### Configuração do Ambiente

**1. Clone o repositório**
```bash
git clone [https://github.com/seu-usuario/rpg_puc_survival.git](https://github.com/seu-usuario/rpg_puc_survival.git)
cd rpg_puc_survival
```

**2. Instale as dependências**
```bash
flutter pub get
```

**3. Configure o Firebase (Se necessário reconstruir as chaves)**
* Certifique-se de ter o FlutterFire CLI instalado.
* Rode o comando na raiz do projeto para gerar o `firebase_options.dart`:
```bash
flutterfire configure
```

**4. Execute o projeto**
Para testar a lógica de GPS de forma estática via navegador:
```bash
flutter run -d chrome
```
Para testar no seu dispositivo físico Android (com GPS real):
```bash
flutter run
```

---
