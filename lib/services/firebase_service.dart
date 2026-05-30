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
  static const h15Weapon = 'rpg_h15_weapon'; // arma escolhida no H-15
  static const caaFinalChoice = 'rpg_caa_final_choice';
  static const reitoriaEnding = 'rpg_reitoria_ending';
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
  CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection('users');

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
    try {
      final query = await _players
          .where('nome', isEqualTo: nomeKey)
          .limit(1)
          .get()
          .timeout(const Duration(seconds: 10));

      PlayerProfile profile;

      if (query.docs.isNotEmpty) {
        // ── Jogador existente ───────────────────────────────────────────────
        final remote = PlayerProfile.fromFirestore(query.docs.first.data());
        // Take the max fase to never regress progress saved only locally
        final localPrefs = await SharedPreferences.getInstance();
        final localFase = localPrefs.getInt(PrefKeys.faseAtual) ?? 1;
        final bestFase = remote.faseAtual > localFase ? remote.faseAtual : localFase;
        profile = bestFase == remote.faseAtual
            ? remote
            : PlayerProfile(
                nome: remote.nome,
                faseAtual: bestFase,
                itens: remote.itens,
                escolhas: remote.escolhas,
                isNew: false,
              );
        // Sync the best fase back to Firestore if local was ahead
        if (bestFase > remote.faseAtual && _firebaseReady) {
          _players.doc(nomeKey).update({
            'faseAtual': bestFase,
            'updatedAt': FieldValue.serverTimestamp(),
          }).catchError((e) => debugPrint('Sync faseAtual error: $e'));
        }
      } else {
        // ── Novo jogador ────────────────────────────────────────────────────
        profile = PlayerProfile(
          nome: nomeKey,
          faseAtual: 1,
          itens: [],
          escolhas: [],
          isNew: true,
        );
        await _players.doc(nomeKey).set({
          ...profile.toFirestore(),
          'createdAt': FieldValue.serverTimestamp(),
        }).timeout(const Duration(seconds: 10));
      }

      await _saveToPrefs(profile);
      return profile;
    } on FirebaseException catch (e) {
      // Regras do Firestore bloquearam ou sem conectividade — usa perfil local
      debugPrint('Firestore bloqueado (${e.code}): ${e.message}');
      final localPrefs = await SharedPreferences.getInstance();
      final profile = PlayerProfile(
        nome: nomeKey,
        faseAtual: localPrefs.getInt(PrefKeys.faseAtual) ?? 1,
        itens: localPrefs.getStringList(PrefKeys.itens) ?? const [],
        escolhas: const [],
        isNew: false,
      );
      return profile;
    }
  }

  // ── Atualização de fase ────────────────────────────────────────────────────

  /// Incrementa a fase do jogador no Firestore e em SharedPreferences.
  Future<void> unlockNextPhase(String nome) async {
    final prefs = await SharedPreferences.getInstance();
    final faseAtual = prefs.getInt(PrefKeys.faseAtual) ?? 1;
    final nextFase = (faseAtual + 1).clamp(1, 5);

    if (nextFase == faseAtual) return;

    // Always update locally first so the player never loses progress
    await prefs.setInt(PrefKeys.faseAtual, nextFase);

    final nomeKey = nome.trim().toUpperCase();

    if (_firebaseReady) {
      try {
        await Future.wait([
          _players.doc(nomeKey).set(
          {
            'faseAtual': nextFase,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
          ).timeout(const Duration(seconds: 10)),
          _users.doc(nomeKey).set(
            {
              'currentArea': nextFase >= 2 ? 'area2' : 'area1',
              'unlockedAreas': {
                'area1': true,
                'area2': nextFase >= 2,
                'area3': false,
              },
              'completedAreas': {
                'area1': nextFase >= 2,
                'area2': false,
                'area3': false,
              },
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          ).timeout(const Duration(seconds: 10)),
        ]);
      } on FirebaseException catch (e) {
        debugPrint('Firestore unlockNextPhase error (${e.code}): ${e.message}');
      } catch (e) {
        debugPrint('unlockNextPhase error: $e');
      }
    } else {
      debugPrint('Firebase indisponível; fase atualizada apenas localmente.');
    }
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

  // ── Arma equipada no H-15 ────────────────────────────────────────────────

  Future<void> saveWeapon(String nome, String weapon) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PrefKeys.h15Weapon, weapon);
    if (_firebaseReady) {
      _players.doc(nome.trim().toUpperCase()).update({
        'h15Weapon': weapon,
        'updatedAt': FieldValue.serverTimestamp(),
      }).catchError((e) => debugPrint('Firestore saveWeapon error: $e'));
    }
  }

  Future<String?> loadWeapon() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(PrefKeys.h15Weapon);
  }

  String _progressUid(String playerName) => playerName.trim().isEmpty
      ? 'LOCAL_PLAYER'
      : playerName.trim().toUpperCase();

  Future<void> completeArea2(String playerName,
      {bool moveToArea3 = false}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('area2_mainCompleted', true);
    final faseAtual = prefs.getInt(PrefKeys.faseAtual) ?? 1;
    if (faseAtual < 3) await prefs.setInt(PrefKeys.faseAtual, 3);
    if (moveToArea3) await prefs.setString('currentArea', 'area3');

    if (!_firebaseReady) {
      debugPrint('Firebase indisponivel; Area 2 salva apenas localmente.');
      return;
    }

    final uid = _progressUid(playerName);
    await _users.doc(uid).set({
      'currentArea': moveToArea3 ? 'area3' : 'area2',
      'unlockedAreas': {
        'area1': true,
        'area2': true,
        'area3': true,
      },
      'completedAreas': {
        'area1': true,
        'area2': true,
        'area3': false,
      },
      'areaStates': {
        'area2': {'mainCompleted': true},
      },
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true)).timeout(const Duration(seconds: 10));
  }

  Future<bool> canAccessArea3(String playerName) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('area2_mainCompleted') ?? false) return true;
    if (!_firebaseReady) return false;

    try {
      final uid = _progressUid(playerName);
      final snap =
          await _users.doc(uid).get().timeout(const Duration(seconds: 10));
      final data = snap.data();
      if (data == null) return false;
      final completed = data['completedAreas'];
      final unlocked = data['unlockedAreas'];
      final area2Done = completed is Map && completed['area2'] == true;
      final area3Open = unlocked is Map && unlocked['area3'] == true;
      return area2Done || area3Open;
    } catch (e) {
      debugPrint('canAccessArea3 error: $e');
      return false;
    }
  }

  Future<void> completeArea4(
    String playerName, {
    required String finalChoice,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PrefKeys.caaFinalChoice, finalChoice);
    await prefs.setBool('area4_mainCompleted', true);
    final faseAtual = prefs.getInt(PrefKeys.faseAtual) ?? 1;
    if (faseAtual < 5) await prefs.setInt(PrefKeys.faseAtual, 5);
    await prefs.setString('currentArea', 'area5');

    final uid = _progressUid(playerName);
    final nomeKey = playerName.trim().toUpperCase();
    if (!_firebaseReady) {
      debugPrint('Firebase indisponivel; Area 4 salva apenas localmente.');
      return;
    }

    try {
      await Future.wait([
        _players.doc(nomeKey).set({
          'faseAtual': 5,
          'caaFinalChoice': finalChoice,
          'escolhas': FieldValue.arrayUnion(['caa:$finalChoice']),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true)).timeout(const Duration(seconds: 10)),
        _users.doc(uid).set({
          'currentArea': 'area5',
          'unlockedAreas': {
            'area1': true,
            'area2': true,
            'area3': true,
            'area4': true,
            'area5': true,
          },
          'completedAreas': {
            'area1': true,
            'area2': true,
            'area3': true,
            'area4': true,
            'area5': false,
          },
          'areaStates': {
            'area4': {
              'mainCompleted': true,
              'finalChoice': finalChoice,
            },
          },
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true)).timeout(const Duration(seconds: 10)),
      ]);
    } on FirebaseException catch (e) {
      debugPrint('Firestore completeArea4 error (${e.code}): ${e.message}');
    } catch (e) {
      debugPrint('completeArea4 error: $e');
    }
  }

  Future<String?> loadCaaFinalChoice() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(PrefKeys.caaFinalChoice);
  }

  Future<void> completeArea5(
    String playerName, {
    required String ending,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PrefKeys.reitoriaEnding, ending);
    await prefs.setBool('area5_mainCompleted', true);
    await prefs.setInt(PrefKeys.faseAtual, 5);
    await prefs.setString('currentArea', 'finished');

    final uid = _progressUid(playerName);
    final nomeKey = playerName.trim().toUpperCase();
    if (!_firebaseReady) {
      debugPrint('Firebase indisponivel; Area 5 salva apenas localmente.');
      return;
    }

    try {
      await Future.wait([
        _players.doc(nomeKey).set({
          'faseAtual': 5,
          'reitoriaEnding': ending,
          'escolhas': FieldValue.arrayUnion(['reitoria:$ending']),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true)).timeout(const Duration(seconds: 10)),
        _users.doc(uid).set({
          'currentArea': 'finished',
          'unlockedAreas': {
            'area1': true,
            'area2': true,
            'area3': true,
            'area4': true,
            'area5': true,
          },
          'completedAreas': {
            'area1': true,
            'area2': true,
            'area3': true,
            'area4': true,
            'area5': true,
          },
          'areaStates': {
            'area5': {
              'mainCompleted': true,
              'ending': ending,
            },
          },
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true)).timeout(const Duration(seconds: 10)),
      ]);
    } on FirebaseException catch (e) {
      debugPrint('Firestore completeArea5 error (${e.code}): ${e.message}');
    } catch (e) {
      debugPrint('completeArea5 error: $e');
    }
  }

  Future<void> updateArea2State(
    String playerName,
    Map<String, dynamic> state,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    for (final entry in state.entries) {
      final key = 'area2_${entry.key}';
      final value = entry.value;
      if (value is bool) await prefs.setBool(key, value);
      if (value is int) await prefs.setInt(key, value);
      if (value is double) await prefs.setDouble(key, value);
      if (value is String) await prefs.setString(key, value);
      if (value is List) {
        await prefs.setStringList(
          key,
          value.map((e) => e.toString()).toList(),
        );
      }
    }

    if (!_firebaseReady) return;
    final uid = _progressUid(playerName);
    await _users.doc(uid).set({
      'areaStates': {
        'area2': state,
      },
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true)).timeout(const Duration(seconds: 10));
  }

  Future<void> updateInventoryItem(
    String playerName,
    String itemKey,
    int delta,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final prefKey = 'inventory_$itemKey';
    final current = prefs.getInt(prefKey) ?? 0;
    await prefs.setInt(prefKey, (current + delta).clamp(0, 999).toInt());

    if (!_firebaseReady) return;
    final uid = _progressUid(playerName);
    await _users.doc(uid).set({
      'inventory': {
        itemKey: FieldValue.increment(delta),
      },
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true)).timeout(const Duration(seconds: 10));
  }

  Future<void> updateStats(
    String playerName, {
    int? maxHealthDelta,
    int? currentHealth,
  }) async {
    if (!_firebaseReady) return;
    final uid = _progressUid(playerName);
    await _users.doc(uid).set({
      'stats': {
        if (maxHealthDelta != null)
          'maxHealth': FieldValue.increment(maxHealthDelta),
        if (currentHealth != null) 'currentHealth': currentHealth,
      },
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true)).timeout(const Duration(seconds: 10));
  }

  Future<Map<String, int>> loadInventory(String playerName) async {
    final prefs = await SharedPreferences.getInstance();
    final inventory = <String, int>{
      'emergencyMedkit': prefs.getInt('inventory_emergencyMedkit') ?? 0,
      'stimulant': prefs.getInt('inventory_stimulant') ?? 0,
      'maxHealthBonus': prefs.getInt('inventory_maxHealthBonus') ?? 0,
    };

    if (!_firebaseReady) return inventory;

    try {
      final uid = _progressUid(playerName);
      final snap =
          await _users.doc(uid).get().timeout(const Duration(seconds: 10));
      final data = snap.data();
      final remoteInventory = data?['inventory'];
      if (remoteInventory is Map) {
        for (final key in inventory.keys) {
          final value = remoteInventory[key];
          if (value is num) {
            inventory[key] = value.toInt();
            await prefs.setInt('inventory_$key', value.toInt());
          }
        }
      }
    } catch (e) {
      debugPrint('loadInventory error: $e');
    }

    return inventory;
  }

  Future<Map<String, dynamic>> loadArea2State(String playerName) async {
    final prefs = await SharedPreferences.getInstance();
    final state = <String, dynamic>{
      'mainCompleted': prefs.getBool('area2_mainCompleted') ?? false,
      'radioQuestCompleted':
          prefs.getBool('area2_radioQuestCompleted') ?? false,
      'secretCodeCompleted':
          prefs.getBool('area2_secretCodeCompleted') ?? false,
      'vitalBoostCollected':
          prefs.getBool('area2_vitalBoostCollected') ?? false,
      'marcosTrust': prefs.getInt('area2_marcosTrust') ?? 0,
      'brokenTablesCount': prefs.getInt('area2_brokenTablesCount') ?? 0,
      'usedRevive': prefs.getBool('area2_usedRevive') ?? false,
      'areaCQuestStarted': prefs.getBool('area2_areaCQuestStarted') ?? false,
      'areaCBarricadeBroken':
          prefs.getBool('area2_areaCBarricadeBroken') ?? false,
      'radioPowered': prefs.getBool('area2_radioPowered') ?? false,
      'secretCodePieces': prefs.getStringList('area2_secretCodePieces') ?? [],
    };

    if (!_firebaseReady) return state;

    try {
      final uid = _progressUid(playerName);
      final snap =
          await _users.doc(uid).get().timeout(const Duration(seconds: 10));
      final data = snap.data();
      final areaStates = data?['areaStates'];
      final area2 = areaStates is Map ? areaStates['area2'] : null;
      if (area2 is Map) {
        for (final entry in area2.entries) {
          final key = entry.key.toString();
          final value = entry.value;
          state[key] = value;
          final prefKey = 'area2_$key';
          if (value is bool) await prefs.setBool(prefKey, value);
          if (value is int) await prefs.setInt(prefKey, value);
          if (value is double) await prefs.setDouble(prefKey, value);
          if (value is String) await prefs.setString(prefKey, value);
          if (value is List) {
            await prefs.setStringList(
              prefKey,
              value.map((e) => e.toString()).toList(),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('loadArea2State error: $e');
    }

    return state;
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
