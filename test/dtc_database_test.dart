import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DTC Database Validation Tests', () {
    late Map<String, dynamic> codes;

    setUpAll(() async {
      final file = File('assets/data/dtc_codes.json');
      expect(await file.exists(), isTrue, reason: 'dtc_codes.json must exist');
      final content = await file.readAsString();
      codes = jsonDecode(content) as Map<String, dynamic>;
    });

    test('Base volumétrie : Contient au moins 9000 codes', () {
      expect(codes.length, greaterThanOrEqualTo(9000));
    });

    test('Priorité MAP P0107 (Panne réelle constatée)', () {
      expect(codes.containsKey('P0107'), isTrue);
      final p0107 = codes['P0107'] as Map<String, dynamic>;

      expect(p0107['msg'], contains('Capteur de pression d\'admission (MAP)'));
      expect(p0107['msg'], contains('Circuit Low'));
      expect(p0107['sev'], 'critique');
      expect(p0107['causes'], isNotEmpty);
      expect((p0107['causes'] as List).length, greaterThanOrEqualTo(4));
      expect(p0107['symptoms'], isNotEmpty);
      expect(p0107['checks'], isNotEmpty);
      expect(p0107['note'], contains('Ne remplacez pas'));
    });

    test('Tous les défauts MAP (P0105, P0106, P0107, P0108, P0109) sont documentés en profondeur', () {
      final mapCodes = ['P0105', 'P0106', 'P0107', 'P0108', 'P0109'];
      for (var code in mapCodes) {
        expect(codes.containsKey(code), isTrue, reason: '$code must be in database');
        final entry = codes[code] as Map<String, dynamic>;
        expect(entry['title'] ?? entry['msg'], isNotEmpty);
        expect(entry['desc'], isNotEmpty);
        expect((entry['causes'] as List).length, greaterThanOrEqualTo(3));
        expect((entry['symptoms'] as List).length, greaterThanOrEqualTo(3));
        expect((entry['checks'] as List).length, greaterThanOrEqualTo(3));
        expect(entry['note'], isNotEmpty, reason: '$code must have expert caution note');
      }
    });

    test('Présence des codes majeurs moteur, allumage et réseau', () {
      final checkList = ['P0300', 'P0301', 'P0302', 'P0303', 'P0335', 'P0420', 'P0500', 'U0100', 'U0155'];
      for (var code in checkList) {
        expect(codes.containsKey(code), isTrue, reason: '$code should exist');
        final entry = codes[code] as Map<String, dynamic>;
        expect(entry['msg'], isNotEmpty);
        expect(entry['sev'], isNotNull);
      }
    });
  });
}
