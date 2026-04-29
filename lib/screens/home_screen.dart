import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/firebase_service.dart';
import 'map_selection_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Paleta
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
  static const vignette = Color(0xCC000000);
  static const red = Color(0xFF8B0000);
  static const devGreen = Color(0xFF00FF88);
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
  // ── Animação de glow ──────────────────────────────────────────────────────
  late final AnimationController _glow;
  late final Animation<double> _glowAnim;

  // ── Estado do jogador ─────────────────────────────────────────────────────
  PlayerProfile? _profile; // null → ainda não logado
  bool _loadingProfile = true; // lendo SharedPreferences no boot

  // ── Modo desenvolvedor ────────────────────────────────────────────────────
  bool _devMode = false;

  // ── HUD strings (estáticas na home) ──────────────────────────────────────
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

    _bootLoad();
  }

  @override
  void dispose() {
    _glow.dispose();
    super.dispose();
  }

  // ── Boot: tenta recuperar sessão local ────────────────────────────────────

  Future<void> _bootLoad() async {
    PlayerProfile? cached;

    try {
      final prefs = await SharedPreferences.getInstance()
          .timeout(const Duration(seconds: 5));
      _devMode = prefs.getBool(PrefKeys.devMode) ?? false;
      cached = await FirebaseService.instance
          .loadFromPrefs()
          .timeout(const Duration(seconds: 5));
    } catch (e, st) {
      debugPrint('Falha ao carregar perfil local: $e');
      debugPrintStack(stackTrace: st);
    }

    if (!mounted) return;
    setState(() {
      _profile = cached;
      _loadingProfile = false;
    });

    // Se não tem perfil salvo, abre o login logo que a tela carrega
    if (cached == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showLoginDialog();
      });
    }
  }

  // ── Dialogs ───────────────────────────────────────────────────────────────

  void _showLoginDialog() {
    showDialog(
      context: context,
      barrierDismissible: false, // obriga o login
      barrierColor: Colors.black87,
      builder: (_) => _LoginDialog(
        onConfirm: _handleLogin,
      ),
    );
  }

  Future<void> _handleLogin(String nome) async {
    if (nome.trim().isEmpty) return;

    // Loading enquanto consulta Firestore
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (_) =>
          const _LoadingDialog(message: 'CONECTANDO AO SERVIDOR...'),
    );

    try {
      final profile = await FirebaseService.instance
          .loginOrCreate(nome)
          .timeout(const Duration(seconds: 12));
      if (!mounted) return;

      Navigator.of(context).pop(); // fecha loading
      setState(() => _profile = profile);

      _pixelToast(
        profile.isNew
            ? '✅ NOVO PERFIL CRIADO.\nBOA SORTE, ${profile.nome}.'
            : '👾 BEM-VINDO DE VOLTA,\n${profile.nome}.',
        isError: false,
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // fecha loading
      _pixelToast('❌ ERRO AO CONECTAR.\nVerifique a rede.', isError: true);
    }
  }

  void _showProfileDialog() {
    if (_profile == null) {
      _showLoginDialog();
      return;
    }
    showDialog(
      context: context,
      builder: (_) => _ProfileDialog(
        profile: _profile!,
        devMode: _devMode,
        onToggleDev: _toggleDevMode,
        onLogout: _handleLogout,
      ),
    );
  }

  Future<void> _handleLogout() async {
    Navigator.of(context).pop();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(PrefKeys.playerName);
    await prefs.remove(PrefKeys.faseAtual);
    await prefs.remove(PrefKeys.itens);
    if (!mounted) return;
    setState(() => _profile = null);
    _showLoginDialog();
  }

  Future<void> _toggleDevMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PrefKeys.devMode, value);
    if (!mounted) return;
    setState(() => _devMode = value);
    _pixelToast(
      value
          ? '🛠 MODO DEV ATIVADO\nGPS ignorado no mapa.'
          : '🔒 MODO DEV DESATIVADO',
      isError: false,
    );
  }

  // ── Navegação principal ───────────────────────────────────────────────────

  void _onStartGame() {
    if (_profile == null) {
      _showLoginDialog();
      return;
    }
    HapticFeedback.mediumImpact();
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, anim, __) => MapSelectionScreen(
          playerName: _profile!.nome,
          devMode: _devMode,
        ),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 600),
      ),
    );
  }

  void _onOptions() {
    HapticFeedback.lightImpact();
    showDialog(context: context, builder: (_) => _OptionsDialog());
  }

  // ── Toast pixel art ───────────────────────────────────────────────────────

  void _pixelToast(String msg, {required bool isError}) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          duration: const Duration(seconds: 4),
          content: _PixelSnackContent(message: msg, isError: isError),
        ),
      );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final loggedIn = _profile != null;

    return Scaffold(
      backgroundColor: _C.bg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Background
          const _Background(),

          // 2. Vinheta
          const _Vignette(),

          // 3. Frame dourado
          const _ScreenFrame(),

          // 4. Conteúdo
          SafeArea(
            child: Stack(
              children: [
                // ── HUD topo esquerdo ─────────────────────────────────────
                Positioned(
                  top: 6,
                  left: 10,
                  child: _HudChip(text: _hudTopLeft),
                ),

                // ── HUD topo direito ──────────────────────────────────────
                Positioned(
                  top: 6,
                  right: 10,
                  child: _HudChip(text: _gpsTopRight),
                ),

                // ── Badge de jogador logado (topo centro) ─────────────────
                if (loggedIn)
                  Positioned(
                    top: 6,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: _PlayerBadge(
                        profile: _profile!,
                        devMode: _devMode,
                      ),
                    ),
                  ),

                // ── Título ────────────────────────────────────────────────
                Positioned(
                  top: size.height * 0.06,
                  left: 0,
                  right: 0,
                  child: const _TitleBlock(),
                ),

                // ── Bússola ───────────────────────────────────────────────
                Positioned(
                  bottom: 24,
                  left: 16,
                  child: const _Compass(),
                ),

                // ── GPS inferior direito ──────────────────────────────────
                Positioned(
                  bottom: 24,
                  right: 10,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _HudChip(text: _gpsBottomRight),
                      const SizedBox(height: 4),
                      const _StarIcon(),
                    ],
                  ),
                ),

                // ── Botões ────────────────────────────────────────────────
                Positioned(
                  bottom: size.height * 0.13,
                  left: 0,
                  right: 0,
                  child: _loadingProfile
                      ? Center(
                          child: Column(
                            children: [
                              const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                    color: _C.amber, strokeWidth: 2),
                              ),
                              const SizedBox(height: 12),
                              Text('CARREGANDO...',
                                  style: _pixelStyle(8, color: _C.hud)),
                            ],
                          ),
                        )
                      : AnimatedBuilder(
                          animation: _glowAnim,
                          builder: (_, __) => _ButtonColumn(
                            glowAnim: _glowAnim,
                            loggedIn: loggedIn,
                            onStart: _onStartGame,
                            onOptions: _onOptions,
                            onProfile: _showProfileDialog,
                          ),
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
// _LoginDialog — dialog pixel art para inserir nome
// ─────────────────────────────────────────────────────────────────────────────
class _LoginDialog extends StatefulWidget {
  final Future<void> Function(String nome) onConfirm;
  const _LoginDialog({required this.onConfirm});

  @override
  State<_LoginDialog> createState() => _LoginDialogState();
}

class _LoginDialogState extends State<_LoginDialog> {
  final _ctrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final nome = _ctrl.text.trim();
    if (nome.isEmpty) {
      setState(() => _error = 'INSIRA UM NOME VÁLIDO.');
      return;
    }
    if (nome.length < 3) {
      setState(() => _error = 'MÍNIMO 3 CARACTERES.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    Navigator.of(context).pop(); // fecha este dialog
    await widget.onConfirm(nome);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xF01A1208),
          border: Border.all(color: _C.amber, width: 2),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Título
            Row(
              children: [
                const Text('👤 ', style: TextStyle(fontSize: 16)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'IDENTIFICAÇÃO',
                    style: _pixelStyle(11, color: _C.amberLight),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'INSIRA SEU NOME DE SOBREVIVENTE',
              style: _pixelStyle(7, color: _C.hud),
            ),
            const SizedBox(height: 20),

            // Campo de texto
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0D0800),
                border: Border.all(
                  color: _error != null ? _C.red : _C.btnBorder,
                  width: 1.5,
                ),
              ),
              child: TextField(
                controller: _ctrl,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                maxLength: 20,
                style: _pixelStyle(12, color: _C.amberLight),
                cursorColor: _C.amber,
                decoration: InputDecoration(
                  hintText: 'SEU NOME...',
                  hintStyle:
                      _pixelStyle(10, color: _C.hud.withValues(alpha: 0.4)),
                  counterStyle: _pixelStyle(7, color: _C.hud),
                  border: InputBorder.none,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                ),
                onSubmitted: (_) => _confirm(),
              ),
            ),

            // Erro
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: _pixelStyle(8, color: _C.red)),
            ],

            const SizedBox(height: 20),

            // Botão confirmar
            _PixelButton(
              label: _loading ? 'CONECTANDO...' : 'CONFIRMAR',
              primary: true,
              glowIntensity: 0.9,
              onTap: _loading ? () {} : _confirm,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ProfileDialog — mostra nome, fase e toggle dev mode
// ─────────────────────────────────────────────────────────────────────────────
class _ProfileDialog extends StatelessWidget {
  final PlayerProfile profile;
  final bool devMode;
  final Future<void> Function(bool) onToggleDev;
  final VoidCallback onLogout;

  const _ProfileDialog({
    required this.profile,
    required this.devMode,
    required this.onToggleDev,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final faseLabel = switch (profile.faseAtual) {
      1 => 'BLOCO H-15',
      2 => 'BIBLIOTECA CENTRAL',
      3 => 'REFEITÓRIO CENTRAL',
      4 => 'CAA',
      5 => 'REITORIA',
      _ => 'CONCLUÍDO',
    };

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xF01A1208),
          border: Border.all(color: _C.amber, width: 2),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Text('📋 PERFIL DO SOBREVIVENTE',
                style: _pixelStyle(9, color: _C.amberLight)),
            const SizedBox(height: 16),
            _Divider(),
            const SizedBox(height: 16),

            // Nome
            _ProfileRow(label: 'NOME', value: profile.nome),
            const SizedBox(height: 10),

            // Fase
            _ProfileRow(
              label: 'FASE ATUAL',
              value: '${profile.faseAtual.toString().padLeft(2, '0')}/05',
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: _C.amber.withValues(alpha: 0.3)),
                color: _C.btnFill,
              ),
              child: Text(
                faseLabel,
                style: _pixelStyle(8, color: _C.amber),
              ),
            ),

            // Itens
            if (profile.itens.isNotEmpty) ...[
              const SizedBox(height: 10),
              _ProfileRow(
                label: 'ITENS',
                value: profile.itens.join(', '),
              ),
            ],

            const SizedBox(height: 16),
            _Divider(),
            const SizedBox(height: 16),

            // Modo desenvolvedor
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('🛠 MODO DEV',
                        style: _pixelStyle(9, color: _C.devGreen)),
                    const SizedBox(height: 3),
                    Text('Ignora GPS no mapa',
                        style: _pixelStyle(7,
                            color: _C.hud.withValues(alpha: 0.6))),
                  ],
                ),
                GestureDetector(
                  onTap: () => onToggleDev(!devMode),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: devMode ? _C.devGreen : _C.btnBorder,
                        width: 1.5,
                      ),
                      color: devMode
                          ? _C.devGreen.withValues(alpha: 0.12)
                          : Colors.transparent,
                    ),
                    child: Text(
                      devMode ? 'ON' : 'OFF',
                      style: _pixelStyle(
                        10,
                        color: devMode ? _C.devGreen : _C.hud,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Botões
            _PixelButton(
              label: '< TROCAR JOGADOR',
              primary: false,
              glowIntensity: 0,
              onTap: onLogout,
            ),
            const SizedBox(height: 10),
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

// ─────────────────────────────────────────────────────────────────────────────
// _PlayerBadge — chip no topo mostrando jogador logado
// ─────────────────────────────────────────────────────────────────────────────
class _PlayerBadge extends StatelessWidget {
  final PlayerProfile profile;
  final bool devMode;
  const _PlayerBadge({required this.profile, required this.devMode});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _C.hudBg,
        border: Border.all(
          color: devMode
              ? _C.devGreen.withValues(alpha: 0.7)
              : _C.btnBorder.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(devMode ? '🛠 ' : '👤 ', style: const TextStyle(fontSize: 10)),
          Text(
            devMode ? '${profile.nome} [DEV]' : profile.nome,
            style: _pixelStyle(
              7,
              color: devMode ? _C.devGreen : _C.amberLight,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _LoadingDialog — spinner enquanto consulta o Firestore
// ─────────────────────────────────────────────────────────────────────────────
class _LoadingDialog extends StatelessWidget {
  final String message;
  const _LoadingDialog({required this.message});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xF01A1208),
          border: Border.all(color: _C.btnBorder, width: 1.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(color: _C.amber, strokeWidth: 2),
            ),
            const SizedBox(height: 16),
            Text(message, style: _pixelStyle(8, color: _C.hud)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ButtonColumn — três botões: START, OPTIONS, PROFILE
// ─────────────────────────────────────────────────────────────────────────────
class _ButtonColumn extends StatelessWidget {
  final Animation<double> glowAnim;
  final bool loggedIn;
  final VoidCallback onStart;
  final VoidCallback onOptions;
  final VoidCallback onProfile;

  const _ButtonColumn({
    required this.glowAnim,
    required this.loggedIn,
    required this.onStart,
    required this.onOptions,
    required this.onProfile,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PixelButton(
            label: loggedIn ? 'START GAME' : 'ENTRAR',
            primary: true,
            glowIntensity: glowAnim.value,
            onTap: onStart,
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
            label: 'PROFILE',
            primary: false,
            glowIntensity: 0,
            onTap: onProfile,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widgets visuais — preservados do design original
// ─────────────────────────────────────────────────────────────────────────────

class _Background extends StatelessWidget {
  const _Background();
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.black,
        image: DecorationImage(
          image: AssetImage('assets/images/start_screen.jpg'),
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}

class _Vignette extends StatelessWidget {
  const _Vignette();
  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _VignettePainter());
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
    canvas.drawRect(
      Rect.fromLTWH(0, size.height * 0.60, size.width, size.height * 0.40),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, _C.bg.withValues(alpha: 0.94)],
        ).createShader(
          Rect.fromLTWH(0, size.height * 0.60, size.width, size.height * 0.40),
        ),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}

class _ScreenFrame extends StatelessWidget {
  const _ScreenFrame();
  @override
  Widget build(BuildContext context) => CustomPaint(painter: _FramePainter());
}

class _FramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const m = 6.0;
    const r = 4.0;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(m, m, size.width - m * 2, size.height - m * 2),
        const Radius.circular(r),
      ),
      Paint()
        ..color = _C.btnBorder.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
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

    void corner(Canvas c, Offset o, double rot) {
      c.save();
      c.translate(o.dx, o.dy);
      c.rotate(rot);
      final p = Paint()
        ..color = _C.amber.withValues(alpha: 0.7)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.square;
      c.drawLine(Offset.zero, const Offset(10, 0), p);
      c.drawLine(Offset.zero, const Offset(0, 10), p);
      c.restore();
    }

    corner(canvas, Offset(m + 2, m + 2), 0);
    corner(canvas, Offset(size.width - m - 2, m + 2), pi / 2);
    corner(canvas, Offset(size.width - m - 2, size.height - m - 2), pi);
    corner(canvas, Offset(m + 2, size.height - m - 2), 3 * pi / 2);
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Text('INICIAR EXPLORAÇÃO',
              textAlign: TextAlign.center,
              style:
                  _pixelStyle(16, color: _C.amberLight, shadow: _C.amberDark)),
          const SizedBox(height: 4),
          Text('PUC CAMPINAS',
              textAlign: TextAlign.center,
              style: _pixelStyle(22, color: _C.amber, shadow: _C.btnShadow)),
        ],
      ),
    );
  }
}

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

class _Compass extends StatelessWidget {
  const _Compass();
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

    canvas.drawCircle(Offset(cx, cy), r, paint);

    canvas.drawPath(
      Path()
        ..moveTo(cx, cy - r + 3)
        ..lineTo(cx - 4, cy - 4)
        ..lineTo(cx + 4, cy - 4)
        ..close(),
      Paint()..color = _C.amberLight,
    );
    canvas.drawPath(
      Path()
        ..moveTo(cx, cy + r - 3)
        ..lineTo(cx - 4, cy + 4)
        ..lineTo(cx + 4, cy + 4)
        ..close(),
      Paint()..color = _C.hud.withValues(alpha: 0.5),
    );
    canvas.drawLine(Offset(cx - r + 3, cy), Offset(cx - 4, cy), paint);
    canvas.drawLine(Offset(cx + 4, cy), Offset(cx + r - 3, cy), paint);

    void letter(String l, double x, double y) {
      final tp = TextPainter(
        text: TextSpan(
            text: l,
            style: TextStyle(
              fontSize: 6,
              color: l == 'N' ? _C.amberLight : _C.hud,
              fontWeight: FontWeight.bold,
            )),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, y - tp.height / 2));
    }

    letter('N', cx, cy - r + 7);
    letter('S', cx, cy + r - 7);
    letter('L', cx + r - 7, cy);
    letter('O', cx - r + 7, cy);
    canvas.drawCircle(Offset(cx, cy), 2, Paint()..color = _C.amberLight);
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}

class _StarIcon extends StatelessWidget {
  const _StarIcon();
  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: const Size(20, 20), painter: _StarPainter());
}

class _StarPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final p = Paint()..color = _C.hud.withValues(alpha: 0.8);
    canvas.drawPath(
      Path()
        ..moveTo(cx, 0)
        ..lineTo(cx + 4, cy)
        ..lineTo(cx, size.height)
        ..lineTo(cx - 4, cy)
        ..close(),
      p,
    );
    canvas.drawPath(
      Path()
        ..moveTo(0, cy)
        ..lineTo(cx, cy - 4)
        ..lineTo(size.width, cy)
        ..lineTo(cx, cy + 4)
        ..close(),
      p,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// _PixelButton — botão pixel art (preservado do design original)
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
                      ? Color.lerp(_C.amberLight, Colors.white,
                          widget.glowIntensity * 0.3)!
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
    const c = 4.0;

    if (!pressed) {
      canvas.drawPath(
        Path()
          ..moveTo(c, h)
          ..lineTo(w - c, h)
          ..lineTo(w, h - c)
          ..lineTo(w, h + 4)
          ..lineTo(0, h + 4)
          ..close(),
        Paint()..color = _C.btnShadow,
      );
    }

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

    canvas.drawPath(shape, Paint()..color = fillColor);

    if (glowColor != Colors.transparent) {
      canvas.drawPath(
          shape,
          Paint()
            ..color = glowColor
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    }

    canvas.drawPath(
        shape,
        Paint()
          ..color = borderColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);

    canvas.drawPath(
      Path()
        ..moveTo(c + 2, 2)
        ..lineTo(w - c - 2, 2)
        ..lineTo(w - 2, c + 2)
        ..lineTo(w - 2, h * 0.4),
      Paint()
        ..color = borderColor.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

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
// _OptionsDialog (preservado)
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
// Helpers de UI
// ─────────────────────────────────────────────────────────────────────────────

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      color: _C.btnBorder.withValues(alpha: 0.3),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  final String label;
  final String value;
  const _ProfileRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label: ',
            style: _pixelStyle(7, color: _C.hud.withValues(alpha: 0.7))),
        Expanded(
          child: Text(value, style: _pixelStyle(8, color: _C.amberLight)),
        ),
      ],
    );
  }
}

class _PixelSnackContent extends StatelessWidget {
  final String message;
  final bool isError;
  const _PixelSnackContent({required this.message, required this.isError});

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
        style: _pixelStyle(
          8,
          color: isError ? const Color(0xFFFF7777) : _C.amberLight,
        ),
      ),
    );
  }
}

TextStyle _pixelStyle(double size, {Color color = _C.amber, Color? shadow}) {
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
