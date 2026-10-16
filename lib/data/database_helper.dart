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

  Future<Database> _initDb() async {
    final path = join(await getDatabasesPath(), 'mimo_spark.db');
    return openDatabase(
      path,
      version: 4, // Montée en version 4 pour les pleins de carburant (fuel_refills)
      onCreate: (db, version) async {
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
            canceled        INTEGER NOT NULL DEFAULT 0,
            expense_id      INTEGER
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
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
              canceled        INTEGER NOT NULL DEFAULT 0,
              expense_id      INTEGER
            )
          ''');
        }
      },
    );
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
  Future<void> closeCurrentSession() async {
    final db = await database;
    
    // 1. Calculer les totaux de la session active
    final rides = await getActiveRides();
    final expenses = await getActiveExpenses();
    
    if (rides.isEmpty && expenses.isEmpty) return; // Rien à clôturer
    
    double totalEarned = 0;
    double totalKm = 0;
    double totalFuel = 0;
    for (var r in rides) {
      totalEarned += r.earnedDa;
      totalKm += r.distanceKm;
      totalFuel += r.fuelLiters;
    }
    
    double totalSpent = 0;
    for (var e in expenses) {
      totalSpent += e['amount_da'];
    }
    
    int startTs = rides.isNotEmpty ? rides.first.startTime : (expenses.isNotEmpty ? expenses.first['timestamp'] : DateTime.now().millisecondsSinceEpoch);
    int endTs = DateTime.now().millisecondsSinceEpoch;

    // 2. Créer l'entrée de session
    int sessionId = await db.insert('sessions', {
      'start_timestamp': startTs,
      'end_timestamp': endTs,
      'total_earned': totalEarned,
      'total_spent': totalSpent,
      'total_km': totalKm,
      'total_fuel': totalFuel,
    });

    // 3. Lier les records à cette session
    await db.update('rides', {'session_id': sessionId}, where: 'session_id IS NULL');
    await db.update('expenses', {'session_id': sessionId}, where: 'session_id IS NULL');
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
    await db.update('fuel_refills', {'canceled': 1}, where: 'expense_id = ?', whereArgs: [id]);
    await db.delete('expenses', where: 'id = ?', whereArgs: [id]);
  }

  // ── Pleins de carburant (fuel_refills) ───────────────────────────────────

  /// Enregistre un plein de carburant de manière atomique.
  /// Crée également une entrée unique dans la table `expenses` pour que la dépense
  /// apparaisse dans le bilan du jour sans risque de doublon.
  Future<FuelRefill> recordFuelRefill({
    required double liters,
    required double pricePerLiter,
    required double levelBefore,
    required double levelAfter,
    String? customId,
  }) async {
    final db = await database;
    final now = DateTime.now();
    final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final totalAmount = liters * pricePerLiter;
    final refillId = customId ?? 'refill_${now.millisecondsSinceEpoch}';

    int? expenseId;

    await db.transaction((txn) async {
      // 1. Enregistrement unique de la dépense
      expenseId = await txn.insert('expenses', {
        'date': dateStr,
        'type': 'FUEL',
        'amount_da': totalAmount,
        'timestamp': now.millisecondsSinceEpoch,
      });

      // 2. Enregistrement dans l'historique des pleins avec la clé de dépense
      await txn.insert('fuel_refills', {
        'id': refillId,
        'timestamp': now.millisecondsSinceEpoch,
        'date': dateStr,
        'liters': liters,
        'price_per_liter': pricePerLiter,
        'total_amount': totalAmount,
        'level_before': levelBefore,
        'level_after': levelAfter,
        'canceled': 0,
        'expense_id': expenseId,
      });
    });

    return FuelRefill(
      id: refillId,
      timestamp: now.millisecondsSinceEpoch,
      date: dateStr,
      liters: liters,
      pricePerLiter: pricePerLiter,
      totalAmount: totalAmount,
      levelBefore: levelBefore,
      levelAfter: levelAfter,
      isCanceled: false,
      expenseId: expenseId,
    );
  }

  /// Annule un plein enregistré (canceled = 1) et retire la dépense associée.
  /// Conserve l'historique d'audit du plein sans double comptage.
  Future<bool> cancelFuelRefill(String refillId) async {
    final db = await database;
    final maps = await db.query('fuel_refills', where: 'id = ?', whereArgs: [refillId]);
    if (maps.isEmpty) return false;

    final refill = FuelRefill.fromMap(maps.first);
    if (refill.isCanceled) return false; // Déjà annulé

    await db.transaction((txn) async {
      // 1. Marquer le plein comme annulé
      await txn.update(
        'fuel_refills',
        {'canceled': 1},
        where: 'id = ?',
        whereArgs: [refillId],
      );

      // 2. Retirer la dépense correspondante si liée
      if (refill.expenseId != null) {
        await txn.delete(
          'expenses',
          where: 'id = ?',
          whereArgs: [refill.expenseId],
        );
      }
    });

    return true;
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

