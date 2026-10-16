import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mimo_spark/logic/fuel_calculator.dart';
import 'package:mimo_spark/data/fuel_refill_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MIMO SPARK V3.1 — Tests de Robustesse Carburant & SQLite Source de Vérité', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('Scénario 1 : Ajout de carburant avec atomisme et persistance durable', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{'last_fuel_level': 10.0});
      final calculator = FuelCalculator();
      await calculator.init();
      expect(calculator.currentLiters, closeTo(10.0, 1e-9));

      // Ajout de 12.5 L
      final newLevel = await calculator.addFuel(12.5, pricePerLiter: 50.0);
      expect(newLevel, closeTo(22.5, 1e-9));
      expect(calculator.currentLiters, closeTo(22.5, 1e-9));

      // Vérification que le cache a bien été synchronisé
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('last_fuel_level'), closeTo(22.5, 1e-9));
    });

    test('Scénario 2 : Concurrence OBD2 — trames arrivant pendant l\'enregistrement d\'un plein', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{'last_fuel_level': 10.0});
      final calculator = FuelCalculator();
      await calculator.init();

      // Simuler l'activation du verrou de plein
      // Pendant ce temps, 5 trames OBD2 de 3.6 L/h pendant 1 seconde chacune = 0.001 L chacune (total 0.005 L)
      calculator.updateVirtualFuel(3.6, 1.0); // Conso hors verrou
      expect(calculator.currentLiters, closeTo(9.999, 1e-9));

      // Ajout d'un plein avec mesure de consommation bufferisée
      // Le plein est de 10 L. Si pendant l'opération une trame de 7.2 L/h sur 2s survient (0.004 L),
      // le niveau final doit être (9.999 + 10.0) - conso = 19.999 L
      await calculator.addFuel(10.0);
      expect(calculator.currentLiters, closeTo(19.999, 1e-9));
      expect(calculator.pendingConsumptionLiters, 0.0);
      expect(calculator.isRefilling, isFalse);
    });

    test('Scénario 3 : Échec d\'opération — préservation de la consommation survenue dans le buffer', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{'last_fuel_level': 10.0});
      final calculator = FuelCalculator();
      await calculator.init();

      // Tentative d'ajout illégal (dépassement 35 L) : 30 L alors qu'on est à 10 L (total 40 L > 35 L)
      expect(
        () => calculator.addFuel(30.0),
        throwsA(isA<StateError>()),
      );

      // Le niveau doit rester intact à 10.0 L
      expect(calculator.currentLiters, closeTo(10.0, 1e-9));
      expect(calculator.isRefilling, isFalse);
      expect(calculator.pendingConsumptionLiters, 0.0);
    });

    test('Scénario 4 : Préservation absolue du niveau existant après redémarrage (zéro réinitialisation à 15L)', () async {
      // Simule un niveau utilisateur personnalisé (ex: 8.7 L)
      SharedPreferences.setMockInitialValues(<String, Object>{'last_fuel_level': 8.7});
      final calculator = FuelCalculator();
      await calculator.init();

      // Strictement 8.7 L (pas 15 L par défaut ni 35 L)
      expect(calculator.currentLiters, closeTo(8.7, 1e-9));
      expect(calculator.kmRestants, 115);
    });

    test('Scénario 5 : Migration depuis clé legacy fuel_calibration', () async {
      // Cas d'un utilisateur venant d'une ancienne V2 avec fuel_calibration = 22.0 L
      SharedPreferences.setMockInitialValues(<String, Object>{'fuel_calibration': 22.0});
      final calculator = FuelCalculator();
      await calculator.init();

      expect(calculator.currentLiters, closeTo(22.0, 1e-9));
      // Vérification que le niveau a été migré dans last_fuel_level
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('last_fuel_level'), closeTo(22.0, 1e-9));
    });

    test('Scénario 6 : Annulation de plein — cas simple avec déduction de la jauge demandée', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{'last_fuel_level': 10.0});
      final calculator = FuelCalculator();
      await calculator.init();

      await calculator.addFuel(10.0);
      expect(calculator.currentLiters, closeTo(20.0, 1e-9));

      // Annulation avec déduction autorisée
      await calculator.cancelFuelRefill(10.0, deductLiters: true);
      expect(calculator.currentLiters, closeTo(10.0, 1e-9));
    });

    test('Scénario 7 : Annulation de plein — cas par défaut sans déduction de la jauge (décoché par défaut)', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{'last_fuel_level': 10.0});
      final calculator = FuelCalculator();
      await calculator.init();

      await calculator.addFuel(10.0);
      expect(calculator.currentLiters, closeTo(20.0, 1e-9));

      // Annulation financière seule (deductLiters: false)
      await calculator.cancelFuelRefill(10.0, deductLiters: false);
      // Le niveau physique reste à 20.0 L car la jauge n'est pas modifiée par défaut
      expect(calculator.currentLiters, closeTo(20.0, 1e-9));
    });

    test('Scénario 8 : Annulation de plein après calibrage manuel ultérieur — jauge strictement protégée', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{'last_fuel_level': 10.0});
      final calculator = FuelCalculator();
      await calculator.init();

      final refillTs = DateTime.now().millisecondsSinceEpoch;
      await calculator.addFuel(10.0);
      expect(calculator.currentLiters, closeTo(20.0, 1e-9));

      // L'utilisateur effectue un calibrage manuel après le plein (ex: règle l'aiguille à 18 L)
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await calculator.calibrate(18.0);
      expect(calculator.currentLiters, closeTo(18.0, 1e-9));
      expect(calculator.lastCalibTs, greaterThan(refillTs));

      // Tentative d'annulation du plein avec deductLiters: true
      await calculator.cancelFuelRefill(
        10.0,
        deductLiters: true,
        refillTimestamp: refillTs,
      );

      // La jauge DOIT rester à 18.0 L car le calibrage manuel postérieur représente la vérité physique
      expect(calculator.currentLiters, closeTo(18.0, 1e-9));
    });

    test('Scénario 9 : Modèle FuelRefill avec statut et rétrocompatibilité des pleins annulés', () {
      final now = DateTime.now().millisecondsSinceEpoch;

      // 1. Plein normal engagé
      final refillCommitted = FuelRefill(
        id: 'refill_comm',
        timestamp: now,
        date: '2026-10-16',
        liters: 15.0,
        pricePerLiter: 50.0,
        totalAmount: 750.0,
        levelBefore: 10.0,
        levelAfter: 25.0,
      );
      expect(refillCommitted.status, 'committed');
      expect(refillCommitted.isCanceled, isFalse);

      // 2. Plein avec isCanceled = true (ancien format v4)
      final refillLegacyCanceled = FuelRefill(
        id: 'refill_old_canc',
        timestamp: now,
        date: '2026-10-16',
        liters: 15.0,
        pricePerLiter: 50.0,
        totalAmount: 750.0,
        levelBefore: 10.0,
        levelAfter: 25.0,
        isCanceled: true,
      );
      expect(refillLegacyCanceled.status, 'canceled');
      expect(refillLegacyCanceled.isCanceled, isTrue);

      // 3. Désérialisation depuis une table v4 où seul `canceled = 1` existait
      final mapV4 = {
        'id': 'v4_canc',
        'timestamp': now,
        'date': '2026-10-16',
        'liters': 10.0,
        'price_per_liter': 50.0,
        'total_amount': 500.0,
        'level_before': 10.0,
        'level_after': 20.0,
        'canceled': 1, // Ancienne colonne v4
        // 'status' absent
      };
      final fromMapV4 = FuelRefill.fromMap(mapV4);
      expect(fromMapV4.status, 'canceled');
      expect(fromMapV4.isCanceled, isTrue);
    });

    test('Scénario 10 : Écriture sérialisée — aucune collision d\'I/O pendant les sauvegardes', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{'last_fuel_level': 15.0});
      final calculator = FuelCalculator();
      await calculator.init();

      // Lancer 5 sauvegardes concurrentes quasi-simultanées
      final futures = <Future<void>>[
        calculator.save(),
        calculator.save(),
        calculator.save(),
        calculator.save(),
        calculator.save(),
      ];

      await Future.wait(futures);
      expect(calculator.currentLiters, closeTo(15.0, 1e-9));
    });
  });
}
