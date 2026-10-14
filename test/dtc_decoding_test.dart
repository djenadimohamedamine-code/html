import 'package:flutter_test/flutter_test.dart';
import 'package:mimo_spark/core/dtc_scanner.dart';

void main() {
  group('OBD-II DTC Frame Decoding Tests (SAE J1979 / ISO 15031-5)', () {
    final scanner = DtcScanner();

    test('Chevrolet Spark 0.8: Décode fidèlement la trame MAP P0107 avec octet de compte', () {
      // Trame réelle envoyée par l'ECU GM/Daewoo : 43 (Mode 03), 01 (1 code), 01 07 (P0107), bourrage 00
      const raw = '43 01 01 07 00 00 00';
      final results = scanner.parseRawFrames(raw);

      expect(results.length, 1);
      expect(results[0].code, 'P0107');
      expect(results[0].mode, DtcMode.stored);
      expect(results[0].statusLabel, contains('Confirmé'));
    });

    test('Décodage K-Line sans octet de compte (paires directes)', () {
      const raw = '43 01 07';
      final results = scanner.parseRawFrames(raw);

      expect(results.length, 1);
      expect(results[0].code, 'P0107');
    });

    test('Décodage CAN pour code P0700 avec octet de compte 01 et padding zéros', () {
      const raw = '43 01 07 00 00 00 00';
      final results = scanner.parseRawFrames(raw);

      expect(results.length, 1);
      expect(results[0].code, 'P0700');
    });

    test('Décodage K-Line multiple codes sans octet de compte (paires directes)', () {
      const raw = '43 01 07 01 08';
      final results = scanner.parseRawFrames(raw);

      expect(results.length, 2);
      expect(results[0].code, 'P0107');
      expect(results[1].code, 'P0108');
    });

    test('Décodage multiple codes (P0107 et P0108) sur CAN ISO 15765-4', () {
      const raw = '43 02 01 07 01 08 00';
      final results = scanner.parseRawFrames(raw);

      expect(results.length, 2);
      expect(results[0].code, 'P0107');
      expect(results[1].code, 'P0108');
    });

    test('Décodage Mode 07 (En attente / Pending)', () {
      const raw = '47 01 01 07 00 00 00';
      final results = scanner.parseRawFrames(raw);

      expect(results.length, 1);
      expect(results[0].code, 'P0107');
      expect(results[0].mode, DtcMode.pending);
      expect(results[0].statusLabel, contains('En attente'));
    });

    test('Décodage Mode 0A (Permanent)', () {
      const raw = '4A 01 01 07 00 00 00';
      final results = scanner.parseRawFrames(raw);

      expect(results.length, 1);
      expect(results[0].code, 'P0107');
      expect(results[0].mode, DtcMode.permanent);
      expect(results[0].statusLabel, contains('Permanent'));
    });

    test('Décodage correct des 4 familles P, C, B, U via bits 7-6', () {
      // 00 -> P (Powertrain) : 01 07 -> P0107
      expect(DtcScanner.decodeDtcBytes('01', '07'), 'P0107');

      // 01 -> C (Chassis) : 41 23 -> C0123
      expect(DtcScanner.decodeDtcBytes('41', '23'), 'C0123');

      // 10 -> B (Body) : 81 00 -> B0100
      expect(DtcScanner.decodeDtcBytes('81', '00'), 'B0100');

      // 11 -> U (Network) : C1 55 -> U0155
      expect(DtcScanner.decodeDtcBytes('C1', '55'), 'U0155');
    });

    test('Décodage des codes spécifiques constructeur (bit 5-4 = 01 -> P1xxx)', () {
      // High byte 0x11 = 0001 0001 (P + 1 + 1) + 0x06 -> P1106
      expect(DtcScanner.decodeDtcBytes('11', '06'), 'P1106');
    });

    test('Suppression des préfixes de trames multiples ISO-TP (0:, 1:)', () {
      const raw = '0: 43 02 01 07 01 08\n1: 00 00 00 00 00 00';
      final results = scanner.parseRawFrames(raw);

      expect(results.length, 2);
      expect(results[0].code, 'P0107');
      expect(results[1].code, 'P0108');
    });

    test('Aucun code fantôme sur 43 00 ou NO DATA', () {
      expect(scanner.parseRawFrames('43 00'), isEmpty);
      expect(scanner.parseRawFrames('43 00 00 00 00 00 00'), isEmpty);
      expect(scanner.parseRawFrames('NO DATA'), isEmpty);
      expect(scanner.parseRawFrames('UNABLE TO CONNECT'), isEmpty);
    });

    test('Rétrocompatibilité parseRawDtcFrame()', () {
      final list = scanner.parseRawDtcFrame('43 01 01 07 00 00 00');
      expect(list, ['P0107']);
    });
  });
}
