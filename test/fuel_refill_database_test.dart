import 'package:flutter_test/flutter_test.dart';
import 'package:mimo_spark/data/fuel_refill_model.dart';

void main() {
  group('FuelRefill model & business logic tests', () {
    test('FuelRefill serialization and deserialization (toMap / fromMap)', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final refill = FuelRefill(
        id: 'refill_test_123',
        timestamp: now,
        date: '2026-10-16',
        liters: 10.0,
        pricePerLiter: 50.0,
        totalAmount: 500.0,
        levelBefore: 9.3,
        levelAfter: 19.3,
        isCanceled: false,
        expenseId: 42,
      );

      final map = refill.toMap();
      expect(map['id'], 'refill_test_123');
      expect(map['timestamp'], now);
      expect(map['date'], '2026-10-16');
      expect(map['liters'], 10.0);
      expect(map['price_per_liter'], 50.0);
      expect(map['total_amount'], 500.0);
      expect(map['level_before'], 9.3);
      expect(map['level_after'], 19.3);
      expect(map['canceled'], 0);
      expect(map['expense_id'], 42);

      final deserialized = FuelRefill.fromMap(map);
      expect(deserialized.id, refill.id);
      expect(deserialized.timestamp, refill.timestamp);
      expect(deserialized.date, refill.date);
      expect(deserialized.liters, refill.liters);
      expect(deserialized.pricePerLiter, refill.pricePerLiter);
      expect(deserialized.totalAmount, refill.totalAmount);
      expect(deserialized.levelBefore, refill.levelBefore);
      expect(deserialized.levelAfter, refill.levelAfter);
      expect(deserialized.isCanceled, isFalse);
      expect(deserialized.expenseId, 42);
    });

    test('Parsing des décimales avec virgule et point (9,5 et 9.5)', () {
      double? parseDecimal(String text) {
        if (text.trim().isEmpty) return null;
        return double.tryParse(text.trim().replaceAll(',', '.'));
      }

      expect(parseDecimal('10'), 10.0);
      expect(parseDecimal('9.5'), 9.5);
      expect(parseDecimal('9,5'), 9.5);
      expect(parseDecimal(' 12,34 '), 12.34);
      expect(parseDecimal(''), isNull);
      expect(parseDecimal('abc'), isNull);
      expect(parseDecimal('-5'), -5.0);
    });

    test('Calcul exact du montant en DA et détection des dépassements de réservoir', () {
      const tankCapacity = 35.0;
      double currentLevel = 9.3;

      // Cas 1 : Ajout de 10 L à 50 DA/L
      double addedLiters1 = 10.0;
      double price1 = 50.0;
      double totalCost1 = addedLiters1 * price1;
      double projectedLevel1 = currentLevel + addedLiters1;

      expect(totalCost1, 500.0);
      expect(projectedLevel1, closeTo(19.3, 1e-9));
      expect(projectedLevel1 <= tankCapacity, isTrue);

      // Cas 2 : Tentative d'ajout excessif (30 L)
      double addedLiters2 = 30.0;
      double projectedLevel2 = currentLevel + addedLiters2;
      expect(projectedLevel2, closeTo(39.3, 1e-9));
      expect(projectedLevel2 > tankCapacity, isTrue); // Dépassement détecté
      double maxAddable = tankCapacity - currentLevel;
      expect(maxAddable, closeTo(25.7, 1e-9));
    });

    test('Annulation d\'un plein : trace d\'audit conservée avec canceled = 1', () {
      final refill = FuelRefill(
        id: 'refill_to_cancel',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        date: '2026-10-16',
        liters: 10.0,
        pricePerLiter: 50.0,
        totalAmount: 500.0,
        levelBefore: 9.3,
        levelAfter: 19.3,
        isCanceled: true, // Annulé
        expenseId: 10,
      );

      final map = refill.toMap();
      expect(map['canceled'], 1);

      final deserialized = FuelRefill.fromMap(map);
      expect(deserialized.isCanceled, isTrue);
    });
  });
}
