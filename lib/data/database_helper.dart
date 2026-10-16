import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'ride_model.dart';
import 'fuel_refill_model.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  Database? _db;

  Future<Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  /// Permet d'injecter une base SQLite isolée (ex: inMemoryDatabasePath) pour les tests unitaires.
  void setDatabaseForTesting(Database? db) {
    _db = db;
  }

  Future<Database> _initDb() async {
    final path = join(await getDatabasesPath(), 'mimo_spark.db');
    return openDatabase(
      path,
      version: 5, // Montée en version 5 pour la persistance durable du carburant (fuel_state)
      onCreate: createTables,
      onUpgrade: upgradeTables,
    );
  }

  static Future<void> createTables(Database db, int version) async {
    await db.execute('''
      CREATE TABLE sessions (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        start_timestamp INTEGER NOT NULL,
        end_timestamp   INTEGER NOT NULL,
        total_earned    REAL NOT NULL,
        total_spent     REAL NOT NULL,
        total_km        REAL NOT NULL,
        total_fuel      REAL NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE rides (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        date         TEXT NOT NULL,
        start_time   INTEGER NOT NULL,
        end_time     INTEGER NOT NULL,
        fuel_liters  REAL NOT NULL,
        fuel_cost_da REAL NOT NULL,
        earned_da    REAL NOT NULL,
        profit_da    REAL NOT NULL,
        distance_km  REAL NOT NULL,
        session_id   INTEGER -- Pour l'archivage
      )
    ''');
    await db.execute('''
      CREATE TABLE expenses (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        date         TEXT NOT NULL,
        type         TEXT NOT NULL,
        amount_da    REAL NOT NULL,
        timestamp    INTEGER NOT NULL,
        session_id   INTEGER -- Pour l'archivage
      )
    ''');
    await db.execute('''
      CREATE TABLE fuel_refills (
        id              TEXT PRIMARY KEY,
        timestamp       INTEGER NOT NULL,
        date            TEXT NOT NULL,
        liters          REAL NOT NULL,
        price_per_liter REAL NOT NULL,
        total_amount    REAL NOT NULL,
        level_before    REAL NOT NULL,
        level_after     REAL NOT NULL,
        status          TEXT NOT NULL DEFAULT 'committed',
        canceled        INTEGER NOT NULL DEFAULT 0,
        expense_id      INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE fuel_state (
        id            INTEGER PRIMARY KEY CHECK (id = 1),
        liters        REAL NOT NULL,
        updated_at    INTEGER NOT NULL,
        event_type    TEXT NOT NULL,
        reference_id  TEXT,
        last_calib_ts INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  static Future<void> upgradeTables(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('CREATE TABLE expenses (id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT NOT NULL, type TEXT NOT NULL, amount_da REAL NOT NULL, timestamp INTEGER NOT NULL)');
    }
    if (oldVersion < 3) {
      await db.execute('CREATE TABLE sessions (id INTEGER PRIMARY KEY AUTOINCREMENT, start_timestamp INTEGER NOT NULL, end_timestamp INTEGER NOT NULL, total_earned REAL NOT NULL, total_spent REAL NOT NULL, total_km REAL NOT NULL, total_fuel REAL NOT NULL)');
      await db.execute('ALTER TABLE rides ADD COLUMN session_id INTEGER');
      await db.execute('ALTER TABLE expenses ADD COLUMN session_id INTEGER');
    }
    if (oldVersion < 4) {
      await db.execute('''
        CREATE TABLE fuel_refills (
          id              TEXT PRIMARY KEY,
          timestamp       INTEGER NOT NULL,
          date            TEXT NOT NULL,
          liters          REAL NOT NULL,
          price_per_liter REAL NOT NULL,
          total_amount    REAL NOT NULL,
          level_before    REAL NOT NULL,
          level_after     REAL NOT NULL,
          status          TEXT NOT NULL DEFAULT 'committed',
          canceled        INTEGER NOT NULL DEFAULT 0,
          expense_id      INTEGER
        )
      ''');
    }
    if (oldVersion < 5) {
      // Si fuel_refills existe déjà (v4), vérifier si la colonne status est présente
      final columns = await db.rawQuery('PRAGMA table_info(fuel_refills)');
      final hasStatus = columns.any((c) => c['name'] == 'status');
      if (!hasStatus) {
        await db.execute("ALTER TABLE fuel_refills ADD COLUMN status TEXT NOT NULL DEFAULT 'committed'");
      }
      // Si une ancienne ligne est annulée, son statut doit être 'canceled' et non 'committed'
      await db.execute("UPDATE fuel_refills SET status = 'canceled' WHERE canceled = 1");

      // Création de fuel_state pour la source de vérité SQLite du carburant
      await db.execute('''
        CREATE TABLE IF NOT EXISTS fuel_state (
          id            INTEGER PRIMARY KEY CHECK (id = 1),
          liters        REAL NOT NULL,
          updated_at    INTEGER NOT NULL,
          event_type    TEXT NOT NULL,
          reference_id  TEXT,
          last_calib_ts INTEGER NOT NULL DEFAULT 0
        )
      ''');
    }
  }

  Future<int> insertRide(Ride ride) async {
    final db = await database;
    return db.insert('rides', ride.toMap());
  }

  Future<List<Ride>> getActiveRides() async {
    final db = await database;
    final maps = await db.query('rides', where: 'session_id IS NULL', orderBy: 'start_time ASC');
    return maps.map((m) => Ride.fromMap(m)).toList();
  }

  Future<List<Ride>> getRidesForDate(String date) async {
    final db = await database;
    final maps = await db.query('rides', where: 'date = ?', whereArgs: [date], orderBy: 'start_time ASC');
    return maps.map((m) => Ride.fromMap(m)).toList();
  }

  Future<List<Ride>> getAllRides() async {
    final db = await database;
    final maps = await db.query('rides', orderBy: 'start_time DESC');
    return maps.map((m) => Ride.fromMap(m)).toList();
  }

  Future<void> deleteRide(int id) async {
    final db = await database;
    await db.delete('rides', where: 'id = ?', whereArgs: [id]);
  }

  // ── Gestion des dépenses ────────────────────────────────────────────────
  Future<int> insertExpense(String type, double amount) async {
    final db = await database;
    final now = DateTime.now();
    final dateStr = '${now.year}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')}';
    return db.insert('expenses', {
      'date': dateStr,
      'type': type,
      'amount_da': amount,
      'timestamp': now.millisecondsSinceEpoch,
    });
  }

  Future<List<Map<String, dynamic>>> getActiveExpenses() async {
    final db = await database;
    return db.query('expenses', where: 'session_id IS NULL', orderBy: 'timestamp ASC');
  }

  Future<List<Map<String, dynamic>>> getExpensesForDate(String date) async {
    final db = await database;
    return db.query('expenses', where: 'date = ?', whereArgs: [date]);
  }

  // ── Session Archiving ───────────────────────────────────────────────────
  Future<int?> closeCurrentSession() async {
    final db = await database;
    return await db.transaction<int?>((txn) async {
      // 1. Lire atomiquement les trajets et dépenses de la session active
      final activeRides = await txn.query('rides', where: 'session_id IS NULL', orderBy: 'start_time ASC');
      final activeExpenses = await txn.query('expenses', where: 'session_id IS NULL', orderBy: 'timestamp ASC');

      if (activeRides.isEmpty && activeExpenses.isEmpty) return null; // Rien à clôturer

      double totalEarned = 0.0;
      double totalKm = 0.0;
      double totalFuel = 0.0;
      for (var r in activeRides) {
        totalEarned += (r['earned_da'] as num).toDouble();
        totalKm += (r['distance_km'] as num).toDouble();
        totalFuel += (r['fuel_liters'] as num).toDouble();
      }

      double totalSpent = 0.0;
      for (var e in activeExpenses) {
        totalSpent += (e['amount_da'] as num).toDouble();
      }

      int startTs = activeRides.isNotEmpty
          ? (activeRides.first['start_time'] as int)
          : (activeExpenses.first['timestamp'] as int);
      int endTs = DateTime.now().millisecondsSinceEpoch;

      // 2. Créer l'entrée de session
      int sessionId = await txn.insert('sessions', {
        'start_timestamp': startTs,
        'end_timestamp': endTs,
        'total_earned': totalEarned,
        'total_spent': totalSpent,
        'total_km': totalKm,
        'total_fuel': totalFuel,
      });

      // 3. Lier les records à cette session de façon indivisible
      await txn.update('rides', {'session_id': sessionId}, where: 'session_id IS NULL');
      await txn.update('expenses', {'session_id': sessionId}, where: 'session_id IS NULL');

      return sessionId;
    });
  }

  Future<List<Map<String, dynamic>>> getAllSessions() async {
    final db = await database;
    return db.query('sessions', orderBy: 'end_timestamp DESC');
  }

  Future<List<Ride>> getRidesForSession(int sessionId) async {
    final db = await database;
    final maps = await db.query('rides', where: 'session_id = ?', whereArgs: [sessionId]);
    return maps.map((m) => Ride.fromMap(m)).toList();
  }

  Future<List<Map<String, dynamic>>> getExpensesForSession(int sessionId) async {
    final db = await database;
    return db.query('expenses', where: 'session_id = ?', whereArgs: [sessionId]);
  }

  Future<void> deleteExpense(int id) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.update('fuel_refills', {'canceled': 1, 'status': 'canceled'}, where: 'expense_id = ?', whereArgs: [id]);
      await txn.delete('expenses', where: 'id = ?', whereArgs: [id]);
    });
  }

  // ── Source de vérité durable du carburant (fuel_state) ───────────────────

  /// Récupère l'état courant durable du carburant dans SQLite (id = 1).
  Future<Map<String, dynamic>?> getFuelState() async {
    final db = await database;
    final res = await db.query('fuel_state', where: 'id = 1', limit: 1);
    if (res.isEmpty) return null;
    return res.first;
  }

  /// Met à jour l'état persistant du carburant de manière durable.
  /// Protège contre l'écrasement par des écritures asynchrones obsolètes (now < updated_at).
  Future<bool> setFuelState({
    required double liters,
    required String eventType,
    String? referenceId,
    int? lastCalibTs,
    int? updatedAt,
  }) async {
    final db = await database;
    final now = updatedAt ?? DateTime.now().millisecondsSinceEpoch;
    final existing = await getFuelState();
    if (existing != null) {
      final existingTs = existing['updated_at'] as int? ?? 0;
      // Protection anti-écrasement chronologique :
      // Si l'écriture est strictement plus ancienne que l'état persistant existant, elle est rejetée
      if (now < existingTs) {
        return false;
      }
    }
    await db.insert('fuel_state', {
      'id': 1,
      'liters': liters,
      'updated_at': now,
      'event_type': eventType,
      'reference_id': referenceId,
      'last_calib_ts': lastCalibTs ?? (existing != null ? (existing['last_calib_ts'] as int? ?? 0) : 0),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return true;
  }

  /// Sauvegarde périodique de la consommation OBD2 dans fuel_state en préservant le timestamp de calibrage
  /// et en rejetant toute écriture obsolète vis-à-vis d'un plein ou calibrage plus récent.
  Future<bool> updateFuelLevelFromObd(double currentLiters, {int? timestamp}) async {
    final now = timestamp ?? DateTime.now().millisecondsSinceEpoch;
    return setFuelState(
      liters: currentLiters,
      eventType: 'OBD_SYNC',
      updatedAt: now,
    );
  }

  // ── Pleins de carburant (fuel_refills) ───────────────────────────────────

  /// Enregistre un plein de carburant de manière atomique et indivisible dans SQLite :
  /// 1. Crée la dépense dans `expenses` (`type = 'FUEL'`).
  /// 2. Enregistre le plein dans `fuel_refills` (`status = 'committed'`).
  /// 3. Met à jour la source de vérité `fuel_state` avec `levelAfter`.
  Future<FuelRefill> recordFuelRefill({
    required double liters,
    required double pricePerLiter,
    required double levelBefore,
    required double levelAfter,
    int? lastCalibTs,
    String? customId,
  }) async {
    final db = await database;
    final now = DateTime.now();
    final nowMs = now.millisecondsSinceEpoch;
    final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final totalAmount = liters * pricePerLiter;
    final refillId = customId ?? 'refill_$nowMs';

    int? expenseId;

    await db.transaction((txn) async {
      // 1. Enregistrement unique de la dépense
      expenseId = await txn.insert('expenses', {
        'date': dateStr,
        'type': 'FUEL',
        'amount_da': totalAmount,
        'timestamp': nowMs,
      });

      // 2. Enregistrement dans l'historique des pleins avec status = committed
      await txn.insert('fuel_refills', {
        'id': refillId,
        'timestamp': nowMs,
        'date': dateStr,
        'liters': liters,
        'price_per_liter': pricePerLiter,
        'total_amount': totalAmount,
        'level_before': levelBefore,
        'level_after': levelAfter,
        'status': 'committed',
        'canceled': 0,
        'expense_id': expenseId,
      });

      // 3. Mise à jour atomique de l'état du carburant dans fuel_state avec garantie d'horodatage monotone
      final existingState = await txn.query('fuel_state', where: 'id = 1', limit: 1);
      final currentCalibTs = lastCalibTs ?? (existingState.isNotEmpty ? (existingState.first['last_calib_ts'] as int? ?? 0) : 0);
      int refillCommitTs = nowMs;
      if (existingState.isNotEmpty) {
        final existingTs = existingState.first['updated_at'] as int? ?? 0;
        if (refillCommitTs <= existingTs) {
          refillCommitTs = existingTs + 1;
        }
      }

      await txn.insert('fuel_state', {
        'id': 1,
        'liters': levelAfter,
        'updated_at': refillCommitTs,
        'event_type': 'REFILL',
        'reference_id': refillId,
        'last_calib_ts': currentCalibTs,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });

    return FuelRefill(
      id: refillId,
      timestamp: nowMs,
      date: dateStr,
      liters: liters,
      pricePerLiter: pricePerLiter,
      totalAmount: totalAmount,
      levelBefore: levelBefore,
      levelAfter: levelAfter,
      isCanceled: false,
      status: 'committed',
      expenseId: expenseId,
    );
  }

  /// Annule un plein enregistré de manière atomique et sécurisée :
  /// - Opération idempotente garantie par `WHERE id = ? AND canceled = 0`.
  /// - Si la session associée est active : suppression de la dépense dans `expenses`.
  /// - Si la session associée est archivée : contre-passation traçable dans `expenses` (`type = 'FUEL_CANCEL'`, `amount_da = -totalAmount`)
  ///   et ajustement arithmétique rigoureux de `sessions.total_spent = total_spent - totalAmount`.
  /// - Si `deductLiters == true` et qu'aucun calibrage manuel n'a eu lieu après le plein, ajuste également `fuel_state`.
  Future<bool> cancelFuelRefill(
    String refillId, {
    bool deductLiters = false,
  }) async {
    final db = await database;
    final now = DateTime.now();
    final nowMs = now.millisecondsSinceEpoch;
    final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    return await db.transaction<bool>((txn) async {
      // 1. Verrouillage atomique anti-double annulation (WHERE id = ? AND canceled = 0)
      final rowsAffected = await txn.update(
        'fuel_refills',
        {'canceled': 1, 'status': 'canceled'},
        where: 'id = ? AND canceled = 0',
        whereArgs: [refillId],
      );
      if (rowsAffected == 0) return false; // Déjà annulé ou inexistant (idempotent)

      final maps = await txn.query('fuel_refills', where: 'id = ?', whereArgs: [refillId], limit: 1);
      if (maps.isEmpty) return false;
      final refill = FuelRefill.fromMap(maps.first);

      // 2. Traitement de la dépense financière
      if (refill.expenseId != null) {
        final expenseRows = await txn.query('expenses', where: 'id = ?', whereArgs: [refill.expenseId], limit: 1);
        if (expenseRows.isNotEmpty) {
          final expense = expenseRows.first;
          final sessionId = expense['session_id'] as int?;

          if (sessionId == null) {
            // Session active en cours : suppression directe de la dépense
            await txn.delete('expenses', where: 'id = ?', whereArgs: [refill.expenseId]);
          } else {
            // Session archivée : conservation de la trace et insertion d'une contre-passation
            await txn.insert('expenses', {
              'date': dateStr,
              'type': 'FUEL_CANCEL',
              'amount_da': -refill.totalAmount, // Montant négatif traçable
              'timestamp': nowMs,
              'session_id': sessionId,
            });

            // Ajustement rigoureusement exact de la session archivée (sans artifice max(0, ...))
            await txn.rawUpdate(
              'UPDATE sessions SET total_spent = total_spent - ? WHERE id = ?',
              [refill.totalAmount, sessionId],
            );
          }
        }
      }

      // 3. Traitement de la jauge physique si explicitement demandé
      if (deductLiters) {
        final stateRows = await txn.query('fuel_state', where: 'id = 1', limit: 1);
        if (stateRows.isNotEmpty) {
          final state = stateRows.first;
          final lastCalibTs = state['last_calib_ts'] as int? ?? 0;
          // Si un calibrage manuel a eu lieu après le plein, la vérité physique observée prime : interdiction de toucher à la jauge
          if (lastCalibTs <= refill.timestamp) {
            final currentLiters = (state['liters'] as num).toDouble();
            final newLiters = (currentLiters - refill.liters).clamp(0.0, 35.0);
            int cancelCommitTs = nowMs;
            final existingTs = state['updated_at'] as int? ?? 0;
            if (cancelCommitTs <= existingTs) {
              cancelCommitTs = existingTs + 1;
            }
            await txn.insert('fuel_state', {
              'id': 1,
              'liters': newLiters,
              'updated_at': cancelCommitTs,
              'event_type': 'REFILL_CANCEL',
              'reference_id': refillId,
              'last_calib_ts': lastCalibTs,
            }, conflictAlgorithm: ConflictAlgorithm.replace);
          }
        }
      }

      return true;
    });
  }

  /// Récupère l'ensemble des pleins enregistrés par ordre chronologique décroissant.
  Future<List<FuelRefill>> getAllFuelRefills() async {
    final db = await database;
    final maps = await db.query('fuel_refills', orderBy: 'timestamp DESC');
    return maps.map((m) => FuelRefill.fromMap(m)).toList();
  }

  /// Récupère les pleins actifs (non annulés).
  Future<List<FuelRefill>> getActiveFuelRefills() async {
    final db = await database;
    final maps = await db.query('fuel_refills', where: 'canceled = 0', orderBy: 'timestamp DESC');
    return maps.map((m) => FuelRefill.fromMap(m)).toList();
  }

  /// Récupère un plein par son identifiant unique.
  Future<FuelRefill?> getFuelRefillById(String refillId) async {
    final db = await database;
    final maps = await db.query('fuel_refills', where: 'id = ?', whereArgs: [refillId]);
    if (maps.isEmpty) return null;
    return FuelRefill.fromMap(maps.first);
  }
}
