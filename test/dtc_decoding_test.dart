import 'package:flutter_test/flutter_test.dart';
import 'package:mimo_spark/core/dtc_scanner.dart';

void main() {
  group('OBD-II DTC Frame Decoding Tests (SAE J1979 / ISO 15031-5)', () {
    final scanner = DtcScanner();

    // ─────────────────────────────────────────────────────────────────────────
    // Tests cruciaux : Levée d'ambiguïté P0107 vs P0700 & Octets de comptage
    // ─────────────────────────────────────────────────────────────────────────

    test('Chevrolet Spark K-Line (sans comptage + bourrage) : 43 01 07 00 00 donne P0107 (JAMAIS P0700)', () {
      // Cas réel du véhicule : Trame K-Line ISO 9141-2 / ISO 14230 avec 1 code (01 07) et bourrage (00 00)
      // L'octet 01 ne DOIT PAS être confondu avec un octet de décompte !
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
      // 7 octets après 43 : 01 (compte = 1), 01 07 (P0107), 00 00 00 00 (bourrage CAN 16-bit)
      const raw = '43 01 01 07 00 00 00';
      final results = scanner.parseRawFrames(raw);

      expect(results.length, 1);
      expect(results[0].code, 'P0107');
      expect(results[0].statusLabel, contains('Confirmé'));
    });

    test('CAN ISO 15765-4 (avec comptage 01 + code P0700 + bourrage) : 43 01 07 00 00 00 00 donne P0700', () {
      // 7 octets après 43 : 01 (compte = 1), 07 00 (P0700), 00 00 00 00 (bourrage CAN)
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
      // 7 octets après 43 : 02 (compte = 2), 01 07 (P0107), 01 08 (P0108), 00 00 (bourrage)
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

    // ─────────────────────────────────────────────────────────────────────────
    // Modes SAE J1979 : Mode 07 (Pending) et Mode 0A (Permanent)
    // ─────────────────────────────────────────────────────────────────────────

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

    // ─────────────────────────────────────────────────────────────────────────
    // Décodage des familles P, C, B, U et codes constructeur
    // ─────────────────────────────────────────────────────────────────────────

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

    // ─────────────────────────────────────────────────────────────────────────
    // Robustesse et élimination des faux positifs
    // ─────────────────────────────────────────────────────────────────────────

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

    // ─────────────────────────────────────────────────────────────────────────
    // Reconstitution des trames multiples ISO-TP (ISO 15765-2 / ELM327)
    // ─────────────────────────────────────────────────────────────────────────

    test('ISO-TP multi-trames 4 codes (0: First Frame + 1: Consecutive Frame)', () {
      const raw = '0: 43 04 01 07 01 08\n1: 01 09 02 01 00 00';
      final results = scanner.parseRawFrames(raw);

      expect(results.length, 4);
      expect(results[0].code, 'P0107');
      expect(results[1].code, 'P0108');
      expect(results[2].code, 'P0109');
      expect(results[3].code, 'P0201');
    });

    test('ISO-TP multi-trames 5 codes (MAP P0105 à P0109)', () {
      const raw = '0: 43 05 01 05 01 06\n1: 01 07 01 08 01 09';
      final results = scanner.parseRawFrames(raw);

      expect(results.length, 5);
      expect(results.map((e) => e.code).toList(), ['P0105', 'P0106', 'P0107', 'P0108', 'P0109']);
    });

    test('ISO-TP avec en-tête d\'adresse CAN ECU (7E8) et PCI brut (10 / 21)', () {
      const raw = '7E8 10 0B 43 04 01 07 01 08\n7E8 21 01 09 02 01 00 00 00';
      final results = scanner.parseRawFrames(raw);

      expect(results.length, 4);
      expect(results.map((e) => e.code).toList(), ['P0107', 'P0108', 'P0109', 'P0201']);
    });

    test('ISO-TP rejet strict en cas de désynchronisation de séquence (0: puis 3:)', () {
      // Mauvais index consécutif (3: au lieu de 1:) -> trame corrompue, zéro code fantôme
      const raw = '0: 43 04 01 07 01 08\n3: 01 09 02 01 00 00';
      final results = scanner.parseRawFrames(raw);

      expect(results, isEmpty, reason: 'Une séquence ISO-TP désynchronisée ne doit produire aucun code fantôme');
    });

    test('ISO-TP rejet strict en cas de réponse tronquée (First Frame seule reçue)', () {
      // Annonce 4 codes (04) mais la Consecutive Frame n'arrive jamais
      const raw = '0: 43 04 01 07 01 08';
      final results = scanner.parseRawFrames(raw);

      expect(results, isEmpty, reason: 'Une réponse incomplète ne doit pas inventer de codes');
    });

    test('Prise en compte du protocole détecté (K-Line forcé vs CAN forcé)', () {
      // En K-Line forcé, 43 01 07 00 00 est décodé en paires directes sans ambiguïté
      final klineResults = scanner.parseRawFrames('43 01 07 00 00', protocol: ObdProtocolType.kline);
      expect(klineResults.length, 1);
      expect(klineResults[0].code, 'P0107');

      // En CAN forcé, 43 01 01 07 00 00 00 décode avec l'octet de décompte 01
      final canResults = scanner.parseRawFrames('43 01 01 07 00 00 00', protocol: ObdProtocolType.can);
      expect(canResults.length, 1);
      expect(canResults[0].code, 'P0107');
    });

    test('Streaming ligne par ligne via feedRawLine() avec assemblage ISO-TP', () {
      scanner.resetSession();

      // Ligne 1 : First Frame (4 codes annoncés, 2 reçus pour l'instant)
      final r1 = scanner.feedRawLine('0: 43 04 01 07 01 08');
      expect(r1, isEmpty, reason: 'En attente de la suite de la trame multi-lignes');

      // Ligne 2 : Consecutive Frame (reçoit les 2 codes restants)
      final r2 = scanner.feedRawLine('1: 01 09 02 01 00 00');
      expect(r2.length, 4);
      expect(r2.map((e) => e.code).toList(), ['P0107', 'P0108', 'P0109', 'P0201']);
    });
  });
}
