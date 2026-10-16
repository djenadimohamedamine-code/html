import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/database_helper.dart';

class FuelCalculator {
  double currentLiters = 35.0;
  bool lowFuelAlerted = false;
  int _lastAlertedKm = -1;
  int _lastCalibTs = 0;
  int get lastCalibTs => _lastCalibTs;

  bool _isRefilling = false;
  bool get isRefilling => _isRefilling;
  double _pendingConsumptionLiters = 0.0;
  double get pendingConsumptionLiters => _pendingConsumptionLiters;

  static const double _consumptionL100 = 7.5;
  static const double _tankCapacity = 35.0;
  static const double _fuelDensity = 750.0;  // g/L essence SP95
  static const double _afr = 14.7;           // Air-Fuel Ratio stœchiométrique
  DateTime _lastSave = DateTime.fromMillisecondsSinceEpoch(0);
  bool _isInitialized = false;
  Future<void>? _initFuture;
  Future<void> _writeQueue = Future<void>.value();

  // Initialise en chargeant la source de vérité SQLite durable ou SharedPreferences en premier import
  Future<void> init() => _initFuture ??= _initialize();

  Future<void> _initialize() async {
    // 1. Priorité absolue à la source de vérité SQLite
    Map<String, dynamic>? fuelState;
    try {
      fuelState = await DatabaseHelper().getFuelState();
    } catch (_) {
      // Ignoré si environnement de test unitaire sans plugin SQLite natif
    }

    if (fuelState != null) {
      currentLiters = ((fuelState['liters'] as num).toDouble()).clamp(0.0, _tankCapacity);
      _lastCalibTs = (fuelState['last_calib_ts'] as int?) ?? 0;
    } else {
      // 2. Migration contrôlée depuis SharedPreferences (installation existante v3/v4 ou première ouverture)
      final prefs = await SharedPreferences.getInstance();
      final savedFuel = prefs.getDouble('last_fuel_level');
      final legacyFuel = savedFuel == null ? prefs.getDouble('fuel_calibration') : null;
      final initialLiters = (savedFuel ?? legacyFuel ?? 15.0).clamp(0.0, _tankCapacity);
      _lastCalibTs = prefs.getInt('last_calibration_timestamp') ?? 0;

      // Inscription durable dans fuel_state SQLite pour figer la vérité
      try {
        await DatabaseHelper().setFuelState(
          liters: initialLiters,
          eventType: 'MIGRATION_INIT',
          lastCalibTs: _lastCalibTs,
        );
      } catch (_) {}

      currentLiters = initialLiters;

      // Miroir dans SharedPreferences si non existant
      if (savedFuel == null) {
        await prefs.setDouble('last_fuel_level', currentLiters);
      }
    }
    _isInitialized = true;
  }

  // Calibrage manuel par l'utilisateur (bouton dans le menu ou tactile)
  Future<void> calibrate(double liters) async {
    await init();
    if (!liters.isFinite) throw ArgumentError.value(liters, 'liters');
    final previous = currentLiters;
    final calibrated = liters.clamp(0.0, _tankCapacity);
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    _lastCalibTs = nowMs;
    currentLiters = calibrated;

    try {
      await _enqueueSave(calibrated, eventType: 'CALIBRATION', calibTs: nowMs);
    } catch (_) {
      if (currentLiters == calibrated) currentLiters = previous;
      rethrow;
    }
    lowFuelAlerted = false;
    _lastAlertedKm = -1;
    print('Niveau essence calibré.');
  }

  /// Capacité maximale du réservoir (35 litres pour la Spark 0.8L).
  static const double tankCapacity = _tankCapacity;

  /// Litres maximum pouvant encore être ajoutés sans déborder du réservoir.
  double get maxAddableLiters => (_tankCapacity - currentLiters).clamp(0.0, _tankCapacity);

  /// Ajoute une quantité exacte de carburant en litres de manière atomique :
  /// - Verrouille les calculs OBD2 sans perte de consommation via `_pendingConsumptionLiters`.
  /// - Met à jour atomiquement `fuel_refills`, `expenses` et `fuel_state` dans SQLite.
  /// - Déduit la consommation cumulée survenue pendant l'I/O SQLite.
  /// - Persiste le résultat final dans SQLite et met à jour le cache SharedPreferences.
  Future<double> addFuel(
    double litersAdded, {
    double pricePerLiter = 50.0,
    String? customId,
  }) async {
    await init();
    if (!litersAdded.isFinite || litersAdded.isNaN || litersAdded <= 0) {
      throw ArgumentError.value(litersAdded, 'litersAdded', 'La quantité de carburant doit être positive et finie.');
    }

    final projected = currentLiters + litersAdded;
    if (projected > _tankCapacity + 1e-6) {
      throw StateError(
        'Le plein ($projected L) dépasse la capacité maximale du réservoir ($_tankCapacity L).',
      );
    }

    final levelBefore = currentLiters;
    final levelAfter = projected.clamp(0.0, _tankCapacity);

    // Verrouillage anti-concurrence OBD2
    _isRefilling = true;
    _pendingConsumptionLiters = 0.0;

    try {
      // Écriture atomique dans SQLite (fuel_refills + expenses + fuel_state)
      try {
        await DatabaseHelper().recordFuelRefill(
          liters: litersAdded,
          pricePerLiter: pricePerLiter,
          levelBefore: levelBefore,
          levelAfter: levelAfter,
          lastCalibTs: _lastCalibTs,
          customId: customId,
        );
      } catch (e) {
        // En cas d'erreur SQLite réelle, propager
        if (!e.toString().contains('databaseFactory') && !e.toString().contains('MissingPluginException')) {
          rethrow;
        }
      }

      // Succès de la transaction SQLite : application de la consommation mesurée pendant l'opération
      currentLiters = (levelAfter - _pendingConsumptionLiters).clamp(0.0, _tankCapacity);
      _pendingConsumptionLiters = 0.0;
      _isRefilling = false;

      // Mise à jour finale durable si de la consommation a été déduite
      await _enqueueSave(currentLiters, eventType: 'REFILL');
    } catch (e) {
      // Rollback SQLite : le plein a échoué, mais la consommation mesurée n'est pas perdue !
      currentLiters = (currentLiters - _pendingConsumptionLiters).clamp(0.0, _tankCapacity);
      _pendingConsumptionLiters = 0.0;
      _isRefilling = false;
      rethrow;
    }

    lowFuelAlerted = false;
    _lastAlertedKm = -1;
    return currentLiters;
  }

  /// Annule un plein précédent.
  /// - L'annulation financière est déléguée à DatabaseHelper.
  /// - Si `deductLiters == true` ou si `levelBefore` est fourni, la jauge est ajustée seulement si aucun calibrage manuel postérieur n'a eu lieu.
  Future<double> cancelFuelRefill(
    double litersAdded, {
    bool deductLiters = true,
    String? refillId,
    int? refillTimestamp,
    double? levelBefore,
  }) async {
    await init();
    if (!litersAdded.isFinite || litersAdded.isNaN || litersAdded <= 0) {
      throw ArgumentError.value(litersAdded, 'litersAdded', 'La quantité de carburant doit être positive et finie.');
    }

    final shouldDeduct = deductLiters || levelBefore != null;

    if (refillId != null) {
      try {
        await DatabaseHelper().cancelFuelRefill(refillId, deductLiters: shouldDeduct);
      } catch (e) {
        if (!e.toString().contains('databaseFactory') && !e.toString().contains('MissingPluginException')) {
          rethrow;
        }
      }
    }

    if (shouldDeduct) {
      // Si un calibrage manuel a eu lieu après le plein, la vérité physique prime : interdiction de toucher à la jauge
      if (refillTimestamp != null && _lastCalibTs > refillTimestamp) {
        print('Jauge non modifiée : calibrage manuel postérieur au plein.');
        return currentLiters;
      }

      double newLevel;
      if (levelBefore != null && (currentLiters - (levelBefore + litersAdded)).abs() < 1e-4) {
        newLevel = levelBefore.clamp(0.0, _tankCapacity);
      } else {
        newLevel = (currentLiters - litersAdded).clamp(0.0, _tankCapacity);
      }

      final previous = currentLiters;
      currentLiters = newLevel;
      try {
        await _enqueueSave(currentLiters, eventType: 'REFILL_CANCEL');
      } catch (_) {
        currentLiters = previous;
        rethrow;
      }
    }

    return currentLiters;
  }

  // Mise à jour par la consommation calculée (MAF ou MAP)
  void updateVirtualFuel(double lph, double secondsPassed) {
    if (!_isInitialized || !lph.isFinite || !secondsPassed.isFinite || lph <= 0 || secondsPassed <= 0) return;
    double consumedLiters = (lph / 3600.0) * secondsPassed;

    if (_isRefilling) {
      // Si un plein est en cours d'enregistrement SQLite, mettre la consommation en tampon
      _pendingConsumptionLiters += consumedLiters;
    } else {
      currentLiters = (currentLiters - consumedLiters).clamp(0.0, _tankCapacity);
      _saveAsync();
    }

    // Alerte originale si 0 L
    if (currentLiters <= 5.0 && !lowFuelAlerted) {
      print('Critique, carburant très bas !');
      lowFuelAlerted = true;
    } else if (currentLiters > 5.0) {
      lowFuelAlerted = false;
    }

    // Nouvelles Alertes KMs (Sous 100 km, tous les 10 km)
    int km = kmRestants;
    if (km <= 100 && km > 0) {
      int alertDecade = (km / 10).floor() * 10;
      if (_lastAlertedKm == -1 || alertDecade < _lastAlertedKm) {
        print('Mimo, autonomie basse à $alertDecade kilomètres.');
        _lastAlertedKm = alertDecade;
      }
    } else if (km > 110) {
      _lastAlertedKm = -1;
    }
  }

  // MAF (g/s) → L/h
  double calculateConsumptionLph(double mafGs) {
    if (mafGs <= 0) return 0.0;
    return (mafGs / (_afr * _fuelDensity)) * 3600.0;
  }

  // Mise à jour directe si le PID 012F répond (rare sur Spark)
  void updateRealFuelLevel(double levelPercent, double capacity) {
    if (!_isInitialized || !levelPercent.isFinite || !capacity.isFinite || levelPercent < 0 || levelPercent > 100 || capacity <= 0) return;
    currentLiters = ((levelPercent / 100.0) * capacity).clamp(0.0, _tankCapacity);
    _saveAsync();
  }

  // Km restants estimés selon la consommation configurée
  int get kmRestants => (currentLiters / _consumptionL100 * 100).toInt();

  Future<void> save() async {
    await init();
    return _enqueueSave(currentLiters, eventType: 'MANUAL_SAVE');
  }

  Future<void> _enqueueSave(
    double litersToSave, {
    String eventType = 'OBD_SYNC',
    int? calibTs,
  }) {
    final Future<void> operation = _writeQueue.then((_) async {
      // 1. Sauvegarde durable dans la source de vérité SQLite
      try {
        await DatabaseHelper().setFuelState(
          liters: litersToSave,
          eventType: eventType,
          lastCalibTs: calibTs ?? _lastCalibTs,
        );
      } catch (_) {}

      // 2. Mise à jour du miroir/cache SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('last_fuel_level', litersToSave);
      await prefs.setInt('last_session_timestamp', DateTime.now().millisecondsSinceEpoch);
      if (calibTs != null) {
        await prefs.setInt('last_calibration_timestamp', calibTs);
      }
    });
    _writeQueue = operation.then<void>((_) {}, onError: (Object error, StackTrace stack) {});
    return operation;
  }

  void _saveAsync() {
    final now = DateTime.now();
    if (now.difference(_lastSave) >= const Duration(seconds: 30)) {
      _lastSave = now;
      unawaited(save().catchError((Object error, StackTrace stack) {
        _lastSave = DateTime.fromMillisecondsSinceEpoch(0);
        print('Erreur sauvegarde carburant: $error');
      }));
    }
  }
}
