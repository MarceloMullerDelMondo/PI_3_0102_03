import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../game/cafeteria_game.dart';
import '../models/game_state.dart';
import 'base_game_hud.dart';

class CafeteriaLevelScreen extends StatefulWidget {
  const CafeteriaLevelScreen({
    super.key,
    required this.playerName,
    this.devMode = false,
  });

  final String playerName;
  final bool devMode;

  @override
  State<CafeteriaLevelScreen> createState() => _CafeteriaLevelScreenState();
}

class _CafeteriaLevelScreenState extends State<CafeteriaLevelScreen>
    with WidgetsBindingObserver {
  late final CafeteriaGame _game;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _game = CafeteriaGame(playerName: widget.playerName);
    _setLandscape();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _setPortrait();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _setLandscape();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _setPortrait();
    }
  }

  Future<void> _setLandscape() {
    return SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  Future<void> _setPortrait() {
    return SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          GameWidget<CafeteriaGame>(
            game: _game,
            loadingBuilder: (_) => const Center(
              child: CircularProgressIndicator(color: Color(0xFFF5C842)),
            ),
            overlayBuilderMap: {
              'MarcosDialog':  (_, game) => MarcosDialogOverlay(game: game),
              'RadioTune':     (_, game) => RadioTuneOverlay(game: game),
              'GameOver':      (_, game) => CafeteriaGameOver(game: game),
              'FuseBox':       (_, game) => FuseBoxOverlay(game: game),
              'LockerKeypad':  (_, game) => LockerKeypadOverlay(game: game),
              'SenhaArmario':  (_, game) => SenhaArmarioOverlay(game: game),
            },
          ),
          ValueListenableBuilder<bool>(
            valueListenable: _game.dialogOpen,
            builder: (_, dialogOpen, __) => ValueListenableBuilder<bool>(
              valueListenable: _game.gameOver,
              builder: (_, gameOver, __) {
                if (dialogOpen || gameOver) return const SizedBox.shrink();
                return ValueListenableBuilder<double>(
                  valueListenable: _game.maxHealth,
                  builder: (_, maxHp, __) => BaseGameHud(
                  currentHealth: _game.currentHealth,
                  maxHealth: maxHp,
                  missionText: _game.missionText,
                  hudMessage: _game.hudMessage,
                  onBack: () => Navigator.of(context).pop(false),
                  mapNotifier: GameState.instance.hasMapaNotifier,
                  showKills: true,
                  killsNotifier: _game.zombiesKilled,
                  extraStack: [
                    // Interact button
                    Positioned(
                      right: 145,
                      bottom: 24,
                      child: ValueListenableBuilder<bool>(
                        valueListenable: _game.canInteract,
                        builder: (_, can, __) => AnimatedOpacity(
                          opacity: can ? 1 : 0,
                          duration: const Duration(milliseconds: 140),
                          child: IgnorePointer(
                            ignoring: !can,
                            child: ValueListenableBuilder<String>(
                              valueListenable: _game.interactLabel,
                              builder: (_, label, __) => _PixelButton(
                                label: label,
                                onTap: _game.interact,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Attack + EST column
                    Positioned(
                      right: 20,
                      bottom: 20,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ValueListenableBuilder<bool>(
                            valueListenable: _game.attackEnabled,
                            builder: (_, enabled, __) => _CafAttackButton(
                              enabled: enabled,
                              onTap: _game.attack,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _PixelButton(
                            label: 'EST',
                            onTap: _game.useStimulant,
                          ),
                        ],
                      ),
                    ),
                    // DEV button — anchored below the mission popup (top-right).
                    if (widget.devMode)
                      Positioned(
                        top: 80,
                        right: 12,
                        child: _DevSkipButton(onTap: _game.devSkipMission),
                      ),
                  ],
                ),   // BaseGameHud
                );   // ValueListenableBuilder<double>
              },
            ),
          ),
        ],
      ),
    );
  }
}


class MarcosDialogOverlay extends StatefulWidget {
  const MarcosDialogOverlay({super.key, required this.game});
  final CafeteriaGame game;

  @override
  State<MarcosDialogOverlay> createState() => _MarcosDialogOverlayState();
}

class _MarcosDialogOverlayState extends State<MarcosDialogOverlay> {
  int? _introChoice;
  int? _secondChoice;

  @override
  Widget build(BuildContext context) {
    final dialog = widget.game.activeDialog;
    return Material(
      color: Colors.black.withValues(alpha: .82),
      child: Center(
        child: _DialogFrame(
          title: 'MARCOS',
          child: switch (dialog) {
            CafeteriaDialog.marcosIntro => _intro(),
            CafeteriaDialog.marcosSecond => _second(),
            CafeteriaDialog.reward => _reward(),
            CafeteriaDialog.exitChoice => _exitChoice(context),
            _ => const SizedBox.shrink(),
          },
        ),
      ),
    );
  }

  Widget _intro() {
    final response = switch (_introChoice) {
      1 => 'Pelo menos voce fala como alguem que ainda tem nocao. Aqui dentro, quem faz barulho demais vira comida.',
      2 => 'Respostas? As respostas morreram junto com metade desse campus. Mas talvez voce ainda seja util.',
      3 => 'Entao voce e esse tipo de sobrevivente... bom saber.',
      _ => 'Parado ai. Mais um andando sozinho por esse inferno... voce e corajoso ou so nao sabe morrer direito?',
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Speech(text: response),
        const SizedBox(height: 18),
        if (_introChoice == null) ...[
          _Choice('Calma. Eu so estou tentando sobreviver.', () => setState(() => _introChoice = 1)),
          _Choice('Estou procurando respostas sobre o que aconteceu.', () => setState(() => _introChoice = 2)),
          _Choice('Sai da frente. Eu preciso dos seus suprimentos.', () => setState(() => _introChoice = 3)),
        ] else
          _PixelButton(label: 'CONTINUAR', onTap: () {
            widget.game.chooseMarcosIntro(_introChoice!);
            // chooseMarcosIntro() sets activeDialog on the game object but
            // doesn't notify Flutter. Force a rebuild so the switch arm updates.
            if (mounted) setState(() {});
          }),
      ],
    );
  }

  Widget _second() {
    final response = switch (_secondChoice) {
      1 => 'Na Area C tem uma bateria pequena. A entrada esta barricada... e tem coisa demais do outro lado.',
      2 => 'Entao tambem nao tenho tempo pra dividir suprimento com voce.',
      3 => 'Nao. So estou explicando por que gente arrogante morre rapido.',
      _ => 'Antes de passar por aqui, voce vai provar que nao e so mais um desesperado quebrando tudo e chamando morto.',
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Speech(text: response),
        const SizedBox(height: 18),
        if (_secondChoice == null) ...[
          _Choice('O que voce precisa?', () => setState(() => _secondChoice = 1)),
          _Choice('Nao tenho tempo para favores.', () => setState(() => _secondChoice = 2)),
          _Choice('Voce esta mandando em mim agora?', () => setState(() => _secondChoice = 3)),
        ] else
          _PixelButton(label: 'ACEITAR', onTap: () => widget.game.chooseMarcosSecond(_secondChoice!)),
      ],
    );
  }

  Widget _reward() {
    final trust = widget.game.marcosTrust;
    if (trust >= 2) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _Speech(text: 'Voce nao e tao inutil quanto parece. Tenho duas opcoes. Escolhe uma e nao me faz arrepender.'),
          const SizedBox(height: 18),
          _Choice('Medikit de Emergencia', () async {
            await widget.game.chooseReward('medkit');
            if (mounted) setState(() {});
          }),
          _Choice('Dois Estimulantes', () async {
            await widget.game.chooseReward('stimulant');
            if (mounted) setState(() {});
          }),
        ],
      );
    }
    if (trust == 1) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _Speech(text: 'Voce ajudou. Nao confio em voce, mas divida e divida. Toma isso.'),
          const SizedBox(height: 18),
          _PixelButton(label: 'PEGAR MEDIKIT', onTap: () async {
            await widget.game.chooseReward('medkit');
            if (mounted) setState(() {});
          }),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Speech(text: trust <= -1 ? 'Voce e problema. E problema, hoje, eu nao deixo andando.' : 'Voce fez o basico. Isso nao te torna confiavel.'),
        const SizedBox(height: 18),
        _PixelButton(label: 'CONTINUAR', onTap: () => setState(() => widget.game.activeDialog = CafeteriaDialog.exitChoice)),
      ],
    );
  }

  Widget _exitChoice(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _Speech(text: 'Fase concluida. O caminho pro CAA esta aberto.'),
        const SizedBox(height: 18),
        _Choice('Explorar Refeitorio', () {
          widget.game.continueExploring();
        }),
        _Choice('Ir para Proxima Fase', () {
          widget.game.goToArea3(context);
        }),
      ],
    );
  }
}

class RadioTuneOverlay extends StatefulWidget {
  const RadioTuneOverlay({super.key, required this.game});
  final CafeteriaGame game;

  @override
  State<RadioTuneOverlay> createState() => _RadioTuneOverlayState();
}

class _RadioTuneOverlayState extends State<RadioTuneOverlay> {
  double _freq = 90.0;
  static const double _target = 103.4;
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    final locked = (_freq - _target).abs() <= .2;
    return Material(
      color: Colors.black.withValues(alpha: .9),
      child: Center(
        child: _DialogFrame(
          title: 'RADIO',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${_freq.toStringAsFixed(1)} MHz', style: _font(18, locked ? const Color(0xFF86EFAC) : const Color(0xFFFDE68A))),
              Slider(
                value: _freq,
                min: 87.0,
                max: 108.0,
                divisions: 210,
                activeColor: const Color(0xFFF5C842),
                onChanged: _done ? null : (v) => setState(() => _freq = v),
              ),
              const SizedBox(height: 8),
              if (_done)
                const _Speech(text: '...aqui e o Comando de Emergencia Nacional... nao tentem chegar as capitais... os infectados tomaram a maior parte dos centros urbanos... as linhas militares cairam... procurem abrigo fora das zonas de concentracao... transmissao encerrada...')
              else
                _Speech(text: locked ? 'Sinal encontrado. A frequencia estabilizou.' : 'Chiado. Ajuste a frequencia ate encontrar o sinal.'),
              const SizedBox(height: 18),
              if (!_done)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _PixelButton(label: 'CANCELAR', onTap: widget.game.cancelRadioTune),
                    const SizedBox(width: 12),
                    _PixelButton(label: 'TRAVAR SINAL', onTap: locked ? () => setState(() => _done = true) : null),
                  ],
                )
              else
                _PixelButton(label: 'FECHAR', onTap: widget.game.completeRadioTune),
            ],
          ),
        ),
      ),
    );
  }
}

class CafeteriaGameOver extends StatelessWidget {
  const CafeteriaGameOver({super.key, required this.game});
  final CafeteriaGame game;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: .86),
      child: Center(
        child: _DialogFrame(
          title: 'VOCE MORREU',
          child: _PixelButton(label: 'REVIVER NO CHECKPOINT', onTap: game.reviveAtCheckpoint),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FuseBoxOverlay — "Connect the Fuses" minigame
// ─────────────────────────────────────────────────────────────────────────────
class FuseBoxOverlay extends StatefulWidget {
  const FuseBoxOverlay({super.key, required this.game});
  final CafeteriaGame game;

  @override
  State<FuseBoxOverlay> createState() => _FuseBoxOverlayState();
}

class _FuseBoxOverlayState extends State<FuseBoxOverlay> {
  // Two physical slots on the panel — player taps each to insert a fuse.
  // The game guarantees _fusesInstalled >= 2 before this overlay opens,
  // so we always start with 2 fuses in hand.
  final List<bool> _slots = [false, false];

  bool get _allFilled => _slots.every((s) => s);
  int get _fusesInHand => _slots.where((s) => !s).length;

  void _tapSlot(int i) {
    setState(() {
      if (_slots[i]) {
        // Pull fuse back out of the slot.
        _slots[i] = false;
      } else if (_fusesInHand > 0) {
        _slots[i] = true;
      }
    });
  }

  void _confirm() {
    widget.game.completeFuseBox();
  }

  void _cancel() {
    widget.game.overlays.remove('FuseBox');
    widget.game.dialogOpen.value = false;
    widget.game.resumeEngine();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.90),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500),
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
          decoration: BoxDecoration(
            color: const Color(0xFF0A1A0A),
            border: Border.all(color: const Color(0xFF16A34A), width: 2.5),
            boxShadow: const [
              BoxShadow(
                color: Color(0x5516A34A),
                blurRadius: 28,
                spreadRadius: 4,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('PAINEL ELÉTRICO',
                  style: _font(13, const Color(0xFF4ADE80))),
              const SizedBox(height: 10),
              Text(
                'Insira os fusíveis nos slots\npara restaurar o circuito.',
                textAlign: TextAlign.center,
                style: _font(8, const Color(0xFFCCA040), height: 1.8),
              ),
              const SizedBox(height: 6),
              Text(
                'Fusíveis na mão: $_fusesInHand',
                style: _font(
                  8,
                  _fusesInHand > 0
                      ? const Color(0xFF60A5FA)
                      : const Color(0xFF4ADE80),
                ),
              ),
              const SizedBox(height: 22),
              _CircuitBoard(slots: _slots, onSlotTap: _tapSlot),
              const SizedBox(height: 26),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _PixelButton(label: 'CANCELAR', onTap: _cancel),
                  const SizedBox(width: 16),
                  _PixelButton(
                    label: 'CONECTAR',
                    onTap: _allFilled ? _confirm : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Circuit board visual ────────────────────────────────────────────────────
class _CircuitBoard extends StatelessWidget {
  const _CircuitBoard({required this.slots, required this.onSlotTap});
  final List<bool> slots;
  final void Function(int) onSlotTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1F0D),
        border: Border.all(color: const Color(0xFF374151)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _FuseSlot(filled: slots[0], onTap: () => onSlotTap(0)),
          const SizedBox(width: 14),
          const _CircuitTrace(),
          const SizedBox(width: 14),
          _FuseSlot(filled: slots[1], onTap: () => onSlotTap(1)),
        ],
      ),
    );
  }
}

class _FuseSlot extends StatelessWidget {
  const _FuseSlot({required this.filled, required this.onTap});
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 70,
        height: 100,
        decoration: BoxDecoration(
          color: filled
              ? const Color(0xFF064E3B)
              : const Color(0xFF1F2937),
          border: Border.all(
            color: filled
                ? const Color(0xFF10B981)
                : const Color(0xFF4B5563),
            width: 2.5,
          ),
          boxShadow: filled
              ? const [
                  BoxShadow(
                    color: Color(0x4410B981),
                    blurRadius: 14,
                    spreadRadius: 3,
                  )
                ]
              : null,
        ),
        child: filled ? _filledContent() : _emptyContent(),
      ),
    );
  }

  Widget _filledContent() => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Fuse body
          Container(
            width: 28,
            height: 58,
            decoration: BoxDecoration(
              color: const Color(0xFFD97706),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFFFBBF24), width: 1.5),
            ),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _FuseCap(),
                _FuseCap(),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text('OK', style: _font(6, const Color(0xFF4ADE80))),
        ],
      );

  Widget _emptyContent() => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.add_circle_outline,
              color: Color(0xFF4B5563), size: 26),
          const SizedBox(height: 6),
          Text('SLOT\nVAZIO',
              textAlign: TextAlign.center,
              style: _font(5, const Color(0xFF4B5563), height: 1.6)),
        ],
      );
}

// Small metal cap drawn on both ends of the fuse body.
class _FuseCap extends StatelessWidget {
  const _FuseCap();

  @override
  Widget build(BuildContext context) => Container(
        height: 8,
        decoration: const BoxDecoration(
          color: Color(0xFF9CA3AF),
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(3),
            bottom: Radius.circular(3),
          ),
        ),
      );
}

// Stylised circuit trace connecting the two fuse slots.
class _CircuitTrace extends StatelessWidget {
  const _CircuitTrace();

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: const Size(50, 100),
        painter: _TracePainter(),
      );
}

class _TracePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF15803D)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Simple U-shaped trace between the two slots.
    final path = Path()
      ..moveTo(0, size.height / 2)
      ..lineTo(size.width * 0.25, size.height / 2)
      ..lineTo(size.width * 0.25, size.height * 0.22)
      ..lineTo(size.width * 0.75, size.height * 0.22)
      ..lineTo(size.width * 0.75, size.height / 2)
      ..lineTo(size.width, size.height / 2);
    canvas.drawPath(path, paint);

    // Terminal nodes
    for (final dx in [0.0, size.width]) {
      canvas.drawCircle(
        Offset(dx, size.height / 2),
        5,
        Paint()..color = const Color(0xFF4ADE80),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// LockerKeypadOverlay — industrial numeric PIN pad.
// PIN is "417" (matches the in-game secret code pieces 4-1-7).
// ─────────────────────────────────────────────────────────────────────────────
class LockerKeypadOverlay extends StatefulWidget {
  const LockerKeypadOverlay({super.key, required this.game});
  final CafeteriaGame game;

  @override
  State<LockerKeypadOverlay> createState() => _LockerKeypadOverlayState();
}

class _LockerKeypadOverlayState extends State<LockerKeypadOverlay> {
  static const _correctPin = '417';
  static const _maxLen = 3;

  String _input = '';
  bool _denied = false;

  void _press(String digit) {
    if (_input.length >= _maxLen || _denied) return;
    setState(() => _input += digit);
  }

  void _clear() => setState(() {
        _input = '';
        _denied = false;
      });

  void _confirm() {
    if (_input == _correctPin) {
      widget.game.onLockerCorrectCode();
    } else {
      setState(() {
        _denied = true;
        _input = '';
      });
      Future<void>.delayed(const Duration(milliseconds: 1600), () {
        if (mounted) setState(() => _denied = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final canConfirm = _input.length == _maxLen && !_denied;
    return Material(
      color: Colors.black.withValues(alpha: 0.93),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 320),
          margin: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF080808),
            border: Border.all(
              color: _denied
                  ? const Color(0xFF991B1B)
                  : const Color(0xFF2D2D2D),
              width: 2,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Header bar ──────────────────────────────────────────────
              Container(
                width: double.infinity,
                color: const Color(0xFF111111),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                child: Text(
                  'PAINEL DE ACESSO',
                  textAlign: TextAlign.center,
                  style: _font(8, const Color(0xFF6B7280)),
                ),
              ),
              // ── PIN display ─────────────────────────────────────────────
              Container(
                margin: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.black,
                  border: Border.all(
                    color: _denied
                        ? const Color(0xFFDC2626)
                        : const Color(0xFF1F2937),
                    width: 1.5,
                  ),
                ),
                child: Center(
                  child: _denied
                      ? Text('ACESSO NEGADO',
                          style: _font(9, const Color(0xFFDC2626)))
                      : Text(
                          _input.padRight(_maxLen, '_'),
                          style: _font(22, const Color(0xFF4ADE80)),
                        ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Text(
                  'CODIGO DE $_maxLen DIGITOS',
                  style: _font(6, const Color(0xFF4B5563)),
                ),
              ),
              // ── Keypad ──────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                  children: [
                    _row(['1', '2', '3']),
                    const SizedBox(height: 6),
                    _row(['4', '5', '6']),
                    const SizedBox(height: 6),
                    _row(['7', '8', '9']),
                    const SizedBox(height: 6),
                    Row(children: [
                      Expanded(
                          child: _KeypadButton(
                              label: 'CLR',
                              onTap: _clear,
                              isAccent: true)),
                      const SizedBox(width: 6),
                      Expanded(
                          child: _KeypadButton(
                              label: '0',
                              onTap: () => _press('0'))),
                      const SizedBox(width: 6),
                      Expanded(
                          child: _KeypadButton(
                              label: '↵',
                              onTap: canConfirm ? _confirm : null,
                              isAccent: true,
                              isConfirm: true)),
                    ]),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              // ── Cancel bar ──────────────────────────────────────────────
              GestureDetector(
                onTap: widget.game.onLockerCancelCode,
                child: Container(
                  width: double.infinity,
                  color: const Color(0xFF111111),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  child: Text(
                    '[ CANCELAR ]',
                    textAlign: TextAlign.center,
                    style: _font(7, const Color(0xFF4B5563)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(List<String> digits) => Row(
        children: [
          for (int i = 0; i < digits.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
                child: _KeypadButton(
                    label: digits[i], onTap: () => _press(digits[i]))),
          ],
        ],
      );
}

// ── Single keypad button ─────────────────────────────────────────────────────
class _KeypadButton extends StatefulWidget {
  const _KeypadButton({
    required this.label,
    required this.onTap,
    this.isAccent = false,
    this.isConfirm = false,
  });
  final String label;
  final VoidCallback? onTap;
  final bool isAccent;
  final bool isConfirm;

  @override
  State<_KeypadButton> createState() => _KeypadButtonState();
}

class _KeypadButtonState extends State<_KeypadButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final bg = widget.isConfirm
        ? (enabled ? const Color(0xFF14532D) : const Color(0xFF0A2918))
        : widget.isAccent
            ? const Color(0xFF1A1A1A)
            : const Color(0xFF0F0F0F);
    final border = widget.isConfirm
        ? (enabled ? const Color(0xFF16A34A) : const Color(0xFF1F2937))
        : const Color(0xFF2D2D2D);
    final textColor = enabled
        ? (widget.isConfirm
            ? const Color(0xFF4ADE80)
            : const Color(0xFFD1D5DB))
        : const Color(0xFF374151);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
      onTapUp: enabled
          ? (_) {
              setState(() => _pressed = false);
              widget.onTap!();
            }
          : null,
      onTapCancel: () => setState(() => _pressed = false),
      // Transform.translate uses Offset — avoids the Matrix4 ambiguity
      // that arises when both Flame and Flutter are imported together.
      child: Transform.translate(
        offset: Offset(0, _pressed ? 2.0 : 0.0),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 55),
          height: 50,
          decoration: BoxDecoration(
            color: _pressed ? bg.withValues(alpha: 0.6) : bg,
            border: Border.all(color: border, width: 1.5),
            boxShadow: _pressed
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.65),
                      offset: const Offset(0, 3),
                    )
                  ],
          ),
          child: Center(
            child: Text(
              widget.label,
              style: _font(
                widget.label.length > 1 ? 7 : 13,
                textColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DialogFrame extends StatelessWidget {
  const _DialogFrame({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 720),
      margin: const EdgeInsets.all(24),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xF20A0A0A),
        border: Border.all(color: const Color(0xFFF5C842), width: 3),
        boxShadow: const [BoxShadow(color: Colors.black, offset: Offset(5, 5))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, textAlign: TextAlign.center, style: _font(16, const Color(0xFFF5C842))),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _Speech extends StatelessWidget {
  const _Speech({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: _font(10, const Color(0xFFE5E7EB), height: 1.8),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice(this.label, this.onTap);
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _PixelButton(label: label, onTap: onTap),
    );
  }
}


class _PixelButton extends StatelessWidget {
  const _PixelButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: enabled ? const Color(0xFF2E1E06) : const Color(0xFF1F2937),
          border: Border.all(
            color: enabled ? const Color(0xFFF5C842) : const Color(0xFF4B5563),
            width: 2,
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: _font(8, enabled ? const Color(0xFFFDE68A) : const Color(0xFF9CA3AF), height: 1.5),
        ),
      ),
    );
  }
}

class _CafAttackButton extends StatefulWidget {
  final bool enabled;
  final VoidCallback onTap;
  const _CafAttackButton({required this.enabled, required this.onTap});

  @override
  State<_CafAttackButton> createState() => _CafAttackButtonState();
}

class _CafAttackButtonState extends State<_CafAttackButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) {
        setState(() => _pressed = false);
        if (widget.enabled) widget.onTap();
      },
      child: AnimatedScale(
        duration: const Duration(milliseconds: 70),
        scale: _pressed ? 0.88 : 1.0,
        child: Container(
          width: 90,
          height: 90,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.enabled
                ? const Color(0xDD2A0505)
                : const Color(0x884A4A4A),
            border: Border.all(
              color: widget.enabled ? Colors.redAccent : const Color(0xFF777777),
              width: 3.5,
            ),
            boxShadow: widget.enabled
                ? const [
                    BoxShadow(
                        color: Color(0xCCFF3333),
                        blurRadius: 18,
                        spreadRadius: 2),
                    BoxShadow(
                        color: Color(0xAA0A0600), offset: Offset(0, 4)),
                  ]
                : const [
                    BoxShadow(
                        color: Color(0xAA0A0600), offset: Offset(0, 4))
                  ],
          ),
          child: Center(
            child: Text(
              'ATK',
              style: _font(11,
                  widget.enabled ? Colors.redAccent : const Color(0xFFB0B0B0)),
            ),
          ),
        ),
      ),
    );
  }
}

class _DevSkipButton extends StatelessWidget {
  const _DevSkipButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xDD001400),
          border: Border.all(color: const Color(0xFF00FF00), width: 1.5),
        ),
        child: Text('[DEV] PULAR MISSÃO', style: _font(7, const Color(0xFF00FF00))),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SenhaArmarioOverlay — shows the cabinet password "417" as a found document.
// Closed by the player → game.onSenhaArmarioClosed() advances quest step.
// ─────────────────────────────────────────────────────────────────────────────
class SenhaArmarioOverlay extends StatelessWidget {
  const SenhaArmarioOverlay({super.key, required this.game});
  final CafeteriaGame game;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: game.onSenhaArmarioClosed,
      child: Container(
        color: Colors.black.withValues(alpha: 0.72),
        child: Center(
          child: Container(
            width: 260,
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF9E7),
              border: Border.all(color: const Color(0xFFD4A017), width: 2.5),
              borderRadius: BorderRadius.circular(4),
              boxShadow: const [
                BoxShadow(color: Colors.black54, blurRadius: 18, offset: Offset(4, 6)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('NOTA ENCONTRADA',
                    style: _font(7, const Color(0xFF6B4A2E)),
                    textAlign: TextAlign.center),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFF9B7E35)),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Text('417',
                      style: _font(36, const Color(0xFF1F1F1F)),
                      textAlign: TextAlign.center),
                ),
                const SizedBox(height: 14),
                Text('SENHA DO ARMARIO',
                    style: _font(6, const Color(0xFF8B6A2E)),
                    textAlign: TextAlign.center),
                const SizedBox(height: 22),
                GestureDetector(
                  onTap: game.onSenhaArmarioClosed,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6B4A2E),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text('FECHAR', style: _font(8, Colors.white)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

TextStyle _font(double size, Color color, {double height = 1.2}) {
  return GoogleFonts.pressStart2p(
    fontSize: size,
    color: color,
    height: height,
    shadows: const [Shadow(color: Colors.black, offset: Offset(2, 2))],
  );
}
