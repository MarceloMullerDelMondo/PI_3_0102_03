import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Chaves SharedPreferences — compartilhadas com map_selection_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
abstract class PrefKeys {
  static const playerName = 'rpg_player_name';
  static const faseAtual = 'rpg_puc_fase_atual';
  static const itens = 'rpg_player_itens';
  static const devMode = 'rpg_dev_mode';
}

// ─────────────────────────────────────────────────────────────────────────────
// Modelo do jogador
// ─────────────────────────────────────────────────────────────────────────────
class PlayerProfile {
  final String nome;
  final int faseAtual;
  final List<String> itens;
  final List<String> escolhas;
  final bool isNew; // true quando criado agora

  const PlayerProfile({
    required this.nome,
    required this.faseAtual,
    required this.itens,
    required this.escolhas,
    required this.isNew,
  });

  factory PlayerProfile.fromFirestore(Map<String, dynamic> data) {
    return PlayerProfile(
      nome: data['nome'] as String? ?? '',
      faseAtual: data['faseAtual'] as int? ?? 1,
      itens: List<String>.from(data['itens'] ?? []),
      escolhas: List<String>.from(data['escolhas'] ?? []),
      isNew: false,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'nome': nome,
        'faseAtual': faseAtual,
        'itens': itens,
        'escolhas': escolhas,
        'updatedAt': FieldValue.serverTimestamp(),
      };
}

// ─────────────────────────────────────────────────────────────────────────────
// FirebaseService — singleton
// ─────────────────────────────────────────────────────────────────────────────
class FirebaseService {
  FirebaseService._();
  static final FirebaseService instance = FirebaseService._();

  FirebaseFirestore get _db => FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _players =>
      _db.collection('players');

  bool get _firebaseReady => Firebase.apps.isNotEmpty;

  // ── Login / criação de perfil ──────────────────────────────────────────────

  /// Busca o jogador pelo nome.
  /// - Se existe: baixa o perfil e sincroniza com SharedPreferences.
  /// - Se não existe: cria documento novo com fase 1.
  /// Retorna o [PlayerProfile] resultante.
  Future<PlayerProfile> loginOrCreate(String nome) async {
    final nomeKey = nome.trim().toUpperCase();

    if (!_firebaseReady) {
      debugPrint(
        'Firebase indisponível${kIsWeb ? ' no Web' : ''}; usando perfil local.',
      );
      final profile = PlayerProfile(
        nome: nomeKey,
        faseAtual: 1,
        itens: const [],
        escolhas: const [],
        isNew: true,
      );
      await _saveToPrefs(profile);
      return profile;
    }

    // 1. Tenta buscar pelo nome (campo indexado)
    final query = await _players
        .where('nome', isEqualTo: nomeKey)
        .limit(1)
        .get()
        .timeout(const Duration(seconds: 10));

    PlayerProfile profile;

    if (query.docs.isNotEmpty) {
      // ── Jogador existente ─────────────────────────────────────────────────
      final doc = query.docs.first;
      profile = PlayerProfile.fromFirestore(doc.data());
    } else {
      // ── Novo jogador ──────────────────────────────────────────────────────
      profile = PlayerProfile(
        nome: nomeKey,
        faseAtual: 1,
        itens: [],
        escolhas: [],
        isNew: true,
      );
      // Usa o nome como ID do documento para facilitar lookups futuros
      await _players.doc(nomeKey).set({
        ...profile.toFirestore(),
        'createdAt': FieldValue.serverTimestamp(),
      }).timeout(const Duration(seconds: 10));
    }

    // 2. Sincroniza com SharedPreferences
    await _saveToPrefs(profile);
    return profile;
  }

  // ── Atualização de fase ────────────────────────────────────────────────────

  /// Incrementa a fase do jogador no Firestore e em SharedPreferences.
  Future<void> unlockNextPhase(String nome) async {
    final prefs = await SharedPreferences.getInstance();
    final faseAtual = prefs.getInt(PrefKeys.faseAtual) ?? 1;
    final nextFase = (faseAtual + 1).clamp(1, 5);

    if (nextFase == faseAtual) return;

    final nomeKey = nome.trim().toUpperCase();

    if (_firebaseReady) {
      // Atualiza Firestore
      await _players.doc(nomeKey).update({
        'faseAtual': nextFase,
        'updatedAt': FieldValue.serverTimestamp(),
      }).timeout(const Duration(seconds: 10));
    } else {
      debugPrint('Firebase indisponível; fase atualizada apenas localmente.');
    }

    // Atualiza local
    await prefs.setInt(PrefKeys.faseAtual, nextFase);
  }

  // ── Atualização de itens / escolhas ───────────────────────────────────────

  Future<void> addItem(String nome, String item) async {
    final nomeKey = nome.trim().toUpperCase();
    if (_firebaseReady) {
      await _players.doc(nomeKey).update({
        'itens': FieldValue.arrayUnion([item]),
        'updatedAt': FieldValue.serverTimestamp(),
      }).timeout(const Duration(seconds: 10));
    } else {
      debugPrint('Firebase indisponível; item adicionado apenas localmente.');
    }
    final prefs = await SharedPreferences.getInstance();
    final itens = prefs.getStringList(PrefKeys.itens) ?? [];
    itens.add(item);
    await prefs.setStringList(PrefKeys.itens, itens);
  }

  // ── Leitura local (sem network) ───────────────────────────────────────────

  Future<PlayerProfile?> loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final nome = prefs.getString(PrefKeys.playerName);
    if (nome == null || nome.isEmpty) return null;

    return PlayerProfile(
      nome: nome,
      faseAtual: prefs.getInt(PrefKeys.faseAtual) ?? 1,
      itens: prefs.getStringList(PrefKeys.itens) ?? [],
      escolhas: [],
      isNew: false,
    );
  }

  // ── Helpers internos ──────────────────────────────────────────────────────

  Future<void> _saveToPrefs(PlayerProfile p) async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setString(PrefKeys.playerName, p.nome),
      prefs.setInt(PrefKeys.faseAtual, p.faseAtual),
      prefs.setStringList(PrefKeys.itens, p.itens),
    ]);
  }
}
