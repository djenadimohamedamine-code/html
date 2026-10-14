import 'package:flutter_test/flutter_test.dart';
import 'package:mimo_spark/core/dtc_scanner.dart';

void main() {
  group('OBD-II DTC Frame Decoding Tests (SAE J1979 / ISO 15031-5)', () {
    final scanner = DtcScanner();

    test('Chevrolet Spark K-Line (sans comptage + bourrage) : 43 01 07 00 00 donne P0107 (JAMAIS P0700)', () {
      const raw = '43 01 07 00 00';
      final results = scanner.parseRawFrames(raw);

      expect(results.length, 1);
      expect(results[0].code, 'P0107', reason: 'Doit décoder le code MAP P0107 et ne pas le transformer en P0700');
      expect(results[0].mode, DtcMode.stored);
    });

    test('K-Line (sans comptage, sans bourrage) : 43 01 07 donne P0107', () {
      const raw = '43 01 07';
      final results = scanner.parseRawFrames(raw);

      expect(results.length, 1);
      expect(results[0].code, 'P0107');
    });

    test('CAN ISO 15765-4 (avec comptage 01 + bourrage) : 43 01 01 07 00 00 00 donne P0107', () {
      const raw = '43 01 01 07 00 00 00';
      final results = scanner.parseRawFrames(raw);

      expect(results.length, 1);
      expect(results[0].code, 'P0107');
      expect(results[0].statusLabel, contains('Confirmé'));
    });

    test('CAN ISO 15765-4 (avec comptage 01 + code P0700 + bourrage) : 43 01 07 00 00 00 00 donne P0700', () {
      const raw = '43 01 07 00 00 00 00';
      final results = scanner.parseRawFrames(raw);

      expect(results.length, 1);
      expect(results[0].code, 'P0700');
    });

    test('K-Line (sans comptage + code P0700 direct + bourrage) : 43 07 00 00 00 donne P0700', () {
      const raw = '43 07 00 00 00';
      final results = scanner.parseRawFrames(raw);

      expect(results.length, 1);
      expect(results[0].code, 'P0700');
    });

    test('K-Line (sans comptage + code P0700 direct sans bourrage) : 43 07 00 donne P0700', () {
      const raw = '43 07 00';
      final results = scanner.parseRawFrames(raw);

      expect(results.length, 1);
      expect(results[0].code, 'P0700');
    });

    test('K-Line multiples codes sans comptage (paires directes) : 43 01 07 01 08', () {
      const raw = '43 01 07 01 08';
      final results = scanner.parseRawFrames(raw);

      expect(results.length, 2);
      expect(results[0].code, 'P0107');
      expect(results[1].code, 'P0108');
    });

    test('K-Line multiples codes avec bourrage 00 00 : 43 01 07 01 08 00 00', () {
      const raw = '43 01 07 01 08 00 00';
      final results = scanner.parseRawFrames(raw);

      expect(results.length, 2);
      expect(results[0].code, 'P0107');
      expect(results[1].code, 'P0108');
    });

    test('CAN ISO 15765-4 avec comptage 02 et bourrage : 43 02 01 07 01 08 00 00', () {
      const raw = '43 02 01 07 01 08 00 00';
      final results = scanner.parseRawFrames(raw);

      expect(results.length, 2);
      expect(results[0].code, 'P0107');
      expect(results[1].code, 'P0108');
    });

    test('CAN exact sans bourrage (5 octets après 43) : 43 02 01 07 01 08', () {
      const raw = '43 02 01 07 01 08';
      final results = scanner.parseRawFrames(raw);

      expect(results.length, 2);
      expect(results[0].code, 'P0107');
      expect(results[1].code, 'P0108');
    });

    test('CAN ISO-TP trames multiples avec index (0: 43 02 ...)', () {
      const raw = '0: 43 02 01 07 01 08\n1: 00 00 00 00 00 00';
      final results = scanner.parseRawFrames(raw);

      expect(results.length, 2);
      expect(results[0].code, 'P0107');
      expect(results[1].code, 'P0108');
    });

    test('Décodage Mode 07 (En attente / Pending) sur K-Line sans comptage', () {
      const raw = '47 01 07 00 00';
      final results = scanner.parseRawFrames(raw);

      expect(results.length, 1);
      expect(results[0].code, 'P0107');
      expect(results[0].mode, DtcMode.pending);
      expect(results[0].statusLabel, contains('En attente'));
    });

    test('Décodage Mode 07 (En attente / Pending) sur CAN avec comptage', () {
      const raw = '47 01 01 07 00 00 00';
      final results = scanner.parseRawFrames(raw);

      expect(results.length, 1);
      expect(results[0].code, 'P0107');
      expect(results[0].mode, DtcMode.pending);
      expect(results[0].statusLabel, contains('En attente'));
    });

    test('Décodage Mode 0A (Permanent) sur K-Line sans comptage', () {
      const raw = '4A 01 07';
      final results = scanner.parseRawFrames(raw);

      expect(results.length, 1);
      expect(results[0].code, 'P0107');
      expect(results[0].mode, DtcMode.permanent);
      expect(results[0].statusLabel, contains('Permanent'));
    });

    test('Décodage Mode 0A (Permanent) sur CAN avec comptage', () {
      const raw = '4A 01 01 07 00 00 00';
      final results = scanner.parseRawFrames(raw);

      expect(results.length, 1);
      expect(results[0].code, 'P0107');
      expect(results[0].mode, DtcMode.permanent);
      expect(results[0].statusLabel, contains('Permanent'));
    });

    test('Décodage correct des 4 familles P, C, B, U via bits 7-6', () {
      expect(DtcScanner.decodeDtcBytes('01', '07'), 'P0107');
      expect(DtcScanner.decodeDtcBytes('41', '23'), 'C0123');
      expect(DtcScanner.decodeDtcBytes('81', '00'), 'B0100');
      expect(DtcScanner.decodeDtcBytes('C1', '55'), 'U0155');
    });

    test('Décodage des codes spécifiques constructeur (bit 5-4 = 01 -> P1xxx)', () {
      expect(DtcScanner.decodeDtcBytes('11', '06'), 'P1106');
    });

    test('Aucun code fantôme sur 43 00 ou NO DATA ou UNABLE TO CONNECT', () {
      expect(scanner.parseRawFrames('43 00'), isEmpty);
      expect(scanner.parseRawFrames('43 00 00 00 00 00 00'), isEmpty);
      expect(scanner.parseRawFrames('NO DATA'), isEmpty);
      expect(scanner.parseRawFrames('UNABLE TO CONNECT'), isEmpty);
      expect(scanner.parseRawFrames('SEARCHING...'), isEmpty);
    });

    test('Rétrocompatibilité parseRawDtcFrame()', () {
      final list = scanner.parseRawDtcFrame('43 01 01 07 00 00 00');
      expect(list, ['P0107']);
    });
  });
}
