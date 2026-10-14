import 'dtc_database.dart';

enum DtcMode {
  stored,    // Mode 03 (43) - Codes confirmés en mémoire
  pending,   // Mode 07 (47) - Codes en cours de validation / cycle de conduite
  permanent, // Mode 0A (4A) - Codes permanents (non effaçables manuellement)
}

class DecodedDtc {
  final String code;
  final DtcMode mode;
  final String statusLabel;
  final String rawFrame;

  const DecodedDtc({
    required this.code,
    required this.mode,
    required this.statusLabel,
    required this.rawFrame,
  });

  @override
  String toString() => '$code ($statusLabel)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DecodedDtc && runtimeType == other.runtimeType && code == other.code && mode == other.mode;

  @override
  int get hashCode => code.hashCode ^ mode.hashCode;
}

class DtcScanner {
  /// Décode une réponse brute OBD2 (pouvant contenir plusieurs lignes ou trames).
  /// Gère :
  /// - Mode 03 (réponse 43 : confirmés)
  /// - Mode 07 (réponse 47 : en attente)
  /// - Mode 0A (réponse 4A : permanents)
  /// - Format CAN ISO 15765-4 avec octet de décompte (NODTC)
  /// - Format K-Line ISO 9141-2 / ISO 14230 (paires directes sans octet de décompte)
  /// - Décodage des familles standard P (00), C (01), B (10), U (11) via bits 7-6
  /// - Suppression des en-têtes CAN (ex: 0:, 1:, 7E8...) et des octets de bourrage (00 00, FF FF)
  List<DecodedDtc> parseRawFrames(String rawOutput) {
    List<DecodedDtc> results = [];
    final lines = rawOutput.replaceAll('\r', '\n').split('\n');

    for (String line in lines) {
      final trimmed = line.trim().toUpperCase();
      if (trimmed.isEmpty ||
          trimmed.contains('NO DATA') ||
          trimmed.contains('UNABLE TO CONNECT') ||
          trimmed.contains('ERROR') ||
          trimmed.startsWith('AT') ||
          trimmed.startsWith('OK') ||
          trimmed.startsWith('ELM327')) {
        continue;
      }

      // Nettoyage des index de trames multiples (ex: "0: 43 02 ...", "1: ...")
      String cleanLine = trimmed.replaceAll(RegExp(r'^[0-9A-F]{1,3}:\s*'), '');

      // Découpage en octets hexadécimaux stricts (2 caractères)
      List<String> tokens = cleanLine
          .replaceAll(RegExp(r'[^0-9A-F\s]'), '')
          .split(RegExp(r'\s+'))
          .where((t) => t.length == 2)
          .toList();

      if (tokens.isEmpty) continue;

      // Recherche des octets de réponse diagnostic OBD
      final modeMap = {
        '43': (DtcMode.stored, 'Confirmé (Mode 03)'),
        '47': (DtcMode.pending, 'En attente (Mode 07)'),
        '4A': (DtcMode.permanent, 'Permanent (Mode 0A)'),
      };

      for (var entry in modeMap.entries) {
        final modeHex = entry.key;
        final modeEnum = entry.value.$1;
        final statusLabel = entry.value.$2;

        int modeIndex = tokens.indexOf(modeHex);
        if (modeIndex == -1) continue;

        List<String> payload = tokens.sublist(modeIndex + 1);
        if (payload.isEmpty) continue;

        // Si le premier octet après le mode est '00', aucun code n'est présent
        if (payload[0] == '00' && (payload.length == 1 || payload.every((b) => b == '00'))) {
          continue;
        }

        int? firstByteVal = int.tryParse(payload[0], radix: 16);
        bool hasCountByte = false;

        // Détection intelligente du format ISO 15765-4 (CAN avec octet de compte NODTC)
        // Si le premier octet vaut N (1 à 16) et qu'il y a au moins 2*N octets qui suivent :
        if (firstByteVal != null && firstByteVal >= 1 && firstByteVal <= 16) {
          int expectedDtcBytes = 2 * firstByteVal;
          if (payload.length == 1 + expectedDtcBytes) {
            hasCountByte = true;
          } else if (payload.length > 1 + expectedDtcBytes) {
            final tail = payload.sublist(1 + expectedDtcBytes);
            if (tail.every((b) => b == '00')) {
              hasCountByte = true;
            }
          }
        }

        if (hasCountByte && firstByteVal != null) {
          // Format standard avec octet de compte : on extrait exactement N codes
          for (int i = 0; i < firstByteVal; i++) {
            int highIdx = 1 + (2 * i);
            int lowIdx = 2 + (2 * i);
            if (lowIdx < payload.length) {
              String? dtc = decodeDtcBytes(payload[highIdx], payload[lowIdx]);
              if (dtc != null) {
                results.add(DecodedDtc(
                  code: dtc,
                  mode: modeEnum,
                  statusLabel: statusLabel,
                  rawFrame: trimmed,
                ));
              }
            }
          }
        } else {
          // Format sans octet de compte (K-Line direct ou trame tronquée)
          for (int i = 0; i + 1 < payload.length; i += 2) {
            String? dtc = decodeDtcBytes(payload[i], payload[i + 1]);
            if (dtc != null) {
              results.add(DecodedDtc(
                code: dtc,
                mode: modeEnum,
                statusLabel: statusLabel,
                rawFrame: trimmed,
              ));
            }
          }
        }
      }
    }

    // Déduplication tout en préservant l'ordre d'apparition
    final seen = <String>{};
    final uniqueResults = <DecodedDtc>[];
    for (var item in results) {
      final key = '${item.code}_${item.mode}';
      if (seen.add(key)) {
        uniqueResults.add(item);
      }
    }

    return uniqueResults;
  }

  /// Décode une paire de 2 octets selon la norme SAE J1979 / ISO 15031-5.
  /// Exemple :
  /// high = '01', low = '07' -> P0107
  /// high = '41', low = '23' -> C0123
  /// high = '81', low = '00' -> B0100
  /// high = 'C1', low = '55' -> U0155
  static String? decodeDtcBytes(String highHex, String lowHex) {
    if (highHex == '00' && lowHex == '00') return null; // Bourrage zéro
    if (highHex == 'FF' && lowHex == 'FF') return null; // Mémoire non initialisée

    int? highVal = int.tryParse(highHex, radix: 16);
    int? lowVal = int.tryParse(lowHex, radix: 16);
    if (highVal == null || lowVal == null) return null;

    // Bit 7 et 6 : Famille du système (P, C, B, U)
    int categoryBits = (highVal >> 6) & 0x03;
    String prefix;
    switch (categoryBits) {
      case 0: prefix = 'P'; break; // Powertrain (Moteur / Boîte)
      case 1: prefix = 'C'; break; // Chassis (Freins / ABS / Direction)
      case 2: prefix = 'B'; break; // Body (Carrosserie / Habitacle / Airbags)
      case 3: prefix = 'U'; break; // Network (Réseau CAN / Liaisons calculateurs)
      default: prefix = 'P';
    }

    // Bit 5 et 4 : Deuxième chiffre (0 = standard ISO/SAE, 1 = constructeur, 2 = SAE/constructeur, 3 = réservé)
    int secondDigit = (highVal >> 4) & 0x03;

    // Bit 3 à 0 : Troisième chiffre (0 à F en hexa)
    int thirdDigit = highVal & 0x0F;
    String thirdHex = thirdDigit.toRadixString(16).toUpperCase();

    // 4ème et 5ème chiffres : octet bas en hexa (2 caractères)
    String lowFormatted = lowHex.toUpperCase().padLeft(2, '0');

    return '$prefix$secondDigit$thirdHex$lowFormatted';
  }

  // ─── API Legacy (rétro-compatibilité intégrale) ───────────────────────────
  List<String> parseRawDtcFrame(String rawFrame) {
    return parseRawFrames(rawFrame).map((d) => d.code).toSet().toList();
  }

  Future<void> announceCodes(List<String> codes) async {
    if (codes.isEmpty) {
      print('Mimo, aucun code erreur détecté. Tout est propre.');
      return;
    }

    List<Map<String, String>> resolved = await DtcDatabase.resolveAll(codes);
    resolved.sort((a, b) {
      int weight(String? s) => s == 'critique' ? 3 : (s == 'alerte' ? 2 : 1);
      return weight(b['sev']).compareTo(weight(a['sev']));
    });

    for (var item in resolved) {
      String prefix = item['sev'] == 'critique' ? 'Alerte critique Mimo ! ' : 'Mimo, ';
      print('$prefix${item['msg']}');
    }
  }

  void scanDtc(String dtcCode) async {
    String msg = await DtcDatabase.getDescription(dtcCode);
    print(msg);
  }
}
