import 'dtc_database.dart';

enum DtcMode {
  stored,    // Mode 03 (43) - Codes confirmés en mémoire
  pending,   // Mode 07 (47) - Codes en cours de validation / cycle de conduite
  permanent, // Mode 0A (4A) - Codes permanents (non effaçables manuellement)
}

enum ObdProtocolType {
  auto,   // Auto-détection structurelle
  kline,  // ISO 9141-2 / ISO 14230 (K-Line direct)
  can,    // ISO 15765-4 (CAN avec décompte NODTC et ISO-TP)
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

/// Session d'assemblage de trames multiples ISO-TP (ISO 15765-2)
class _IsoTpSession {
  final DtcMode mode;
  final String statusLabel;
  final String rawFrame;
  final int totalDtcCount;
  final List<String> dtcBytes = [];
  int nextSequence; // Index de trame consécutive attendu (1, 2, 3...)
  bool isComplete = false;
  bool isCorrupted = false;

  _IsoTpSession({
    required this.mode,
    required this.statusLabel,
    required this.rawFrame,
    required this.totalDtcCount,
    this.nextSequence = 1,
  });
}

class DtcScanner {
  // Session d'assemblage pour le flux continu (feedRawLine)
  _IsoTpSession? _streamingSession;

  /// Réinitialise l'état interne d'assemblage
  void resetSession() {
    _streamingSession = null;
  }

  /// Décode une réponse brute OBD2 (pouvant contenir plusieurs lignes ou trames).
  /// Gère :
  /// - Mode 03 (réponse 43 : confirmés)
  /// - Mode 07 (réponse 47 : en attente)
  /// - Mode 0A (réponse 4A : permanents)
  /// - Reconstitution des trames multiples ISO-TP (0: First Frame, 1: 2: Consecutive Frames)
  /// - Format CAN ISO 15765-4 Single Frame avec octet de décompte (NODTC) et bourrage 16-bit
  /// - Format K-Line ISO 9141-2 / ISO 14230 (paires directes sans octet de décompte)
  /// - Prise en charge des informations de protocole (CAN vs K-Line)
  /// - Décodage strict des 4 familles SAE P (00), C (01), B (10), U (11) via bits 7-6
  /// - Suppression des en-têtes CAN (ex: 7E8, 7EA, 18DAF110...) et rejet des séquences corrompues
  List<DecodedDtc> parseRawFrames(String rawOutput, {ObdProtocolType protocol = ObdProtocolType.auto}) {
    List<DecodedDtc> results = [];
    final lines = rawOutput.replaceAll('\r', '\n').split('\n');

    _IsoTpSession? activeSession;

    for (String rawLine in lines) {
      final trimmed = rawLine.trim().toUpperCase();
      if (trimmed.isEmpty ||
          trimmed.contains('NO DATA') ||
          trimmed.contains('UNABLE TO CONNECT') ||
          trimmed.contains('ERROR') ||
          trimmed.contains('SEARCHING') ||
          trimmed.contains('BUS INIT') ||
          trimmed.startsWith('AT') ||
          trimmed.startsWith('OK') ||
          trimmed.startsWith('ELM327')) {
        continue;
      }

      // 1. Suppression des en-têtes CAN d'adresses ECU (ex: 7E8, 7E9, 7EA, 18DAF110...)
      String cleanLine = trimmed.replaceFirst(RegExp(r'^(7E[0-9A-F]|[0-9A-F]{8})\s+'), '');

      // 2. Détection du préfixe d'index de trame ISO-TP ELM327 (ex: "0: ...", "1: ...")
      int? frameIndex;
      final matchIndex = RegExp(r'^([0-9A-F]{1,3}):\s*(.*)$').firstMatch(cleanLine);
      if (matchIndex != null) {
        frameIndex = int.tryParse(matchIndex.group(1)!, radix: 16);
        cleanLine = matchIndex.group(2)!.trim();
      }

      // 3. Découpage en octets hexadécimaux stricts (2 caractères)
      List<String> tokens = cleanLine
          .replaceAll(RegExp(r'[^0-9A-F\s]'), '')
          .split(RegExp(r'\s+'))
          .where((t) => t.length == 2)
          .toList();

      if (tokens.isEmpty) continue;

      // 4. Détection des octets de PCI ISO-TP bruts si présents (10 xx = First Frame, 2x = Consecutive Frame)
      bool isRawIsoTpFF = false;
      bool isRawIsoTpCF = false;
      int? rawSeqNumber;

      if (tokens.length >= 2 && tokens[0].startsWith('1')) {
        isRawIsoTpFF = true;
      } else if (tokens.isNotEmpty && tokens[0].startsWith('2')) {
        isRawIsoTpCF = true;
        rawSeqNumber = int.tryParse(tokens[0][1], radix: 16);
      }

      // Modes diagnostic OBD
      final modeMap = {
        '43': (DtcMode.stored, 'Confirmé (Mode 03)'),
        '47': (DtcMode.pending, 'En attente (Mode 07)'),
        '4A': (DtcMode.permanent, 'Permanent (Mode 0A)'),
      };

      // ───────────────────────────────────────────────────────────────────────
      // A. GESTION DES TRAMES CONSÉCUTIVES ISO-TP (CF)
      // ───────────────────────────────────────────────────────────────────────
      if (activeSession != null && !activeSession.isComplete) {
        bool isConsecutive = false;
        List<String> chunkBytes = [];

        if (frameIndex != null) {
          // Format ELM327 indexé (0:, 1:, 2:...)
          if (frameIndex == activeSession.nextSequence) {
            isConsecutive = true;
            // Si la trame contient un octet PCI brut 2x au début, le retirer
            if (tokens.isNotEmpty && tokens[0].startsWith('2') && tokens[0].length == 2) {
              chunkBytes = tokens.sublist(1);
            } else {
              chunkBytes = tokens;
            }
          } else {
            // Mauvais compteur de séquence -> trame désynchronisée ou hors ordre !
            activeSession.isCorrupted = true;
          }
        } else if (isRawIsoTpCF && rawSeqNumber != null) {
          // Format PCI brut ISO 15765-2 (21, 22...)
          int expectedPciSeq = activeSession.nextSequence & 0x0F;
          if (rawSeqNumber == expectedPciSeq) {
            isConsecutive = true;
            chunkBytes = tokens.sublist(1);
          } else {
            activeSession.isCorrupted = true;
          }
        }

        if (isConsecutive && !activeSession.isCorrupted) {
          activeSession.dtcBytes.addAll(chunkBytes);
          activeSession.nextSequence++;
          if (activeSession.dtcBytes.length >= activeSession.totalDtcCount * 2) {
            activeSession.isComplete = true;
          }
          continue; // Cette ligne a été absorbée par l'assemblage ISO-TP
        }
      }

      // Si une session active précédente s'est terminée ou a été interrompue :
      if (activeSession != null) {
        _finalizeSession(activeSession, results);
        activeSession = null;
      }

      // ───────────────────────────────────────────────────────────────────────
      // B. RECHERCHE DE DÉBUT DE TRAME (Single Frame ou First Frame)
      // ───────────────────────────────────────────────────────────────────────
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

        // 1. Détection FIRST FRAME (ISO-TP multi-trames)
        bool isFirstFrame = (frameIndex == 0 || isRawIsoTpFF) && firstByteVal != null && firstByteVal >= 1 && firstByteVal <= 16;
        if (!isFirstFrame && protocol == ObdProtocolType.can && firstByteVal != null && firstByteVal > 3) {
          isFirstFrame = true;
        }

        if (isFirstFrame && firstByteVal != null) {
          activeSession = _IsoTpSession(
            mode: modeEnum,
            statusLabel: statusLabel,
            rawFrame: trimmed,
            totalDtcCount: firstByteVal,
            nextSequence: 1,
          );
          // Octets initiaux dans la First Frame (après l'octet de décompte NODTC)
          if (payload.length > 1) {
            activeSession.dtcBytes.addAll(payload.sublist(1));
          }
          if (activeSession.dtcBytes.length >= activeSession.totalDtcCount * 2) {
            activeSession.isComplete = true;
          }
          break; // Traité comme début d'assemblage ISO-TP
        }

        // 2. Détection SINGLE FRAME (CAN ou K-Line)
        bool isCanFormat = false;

        if (protocol == ObdProtocolType.kline) {
          // Protocole forcé K-Line : paires directes garanties, aucun octet de compte
          isCanFormat = false;
        } else if (protocol == ObdProtocolType.can) {
          // Protocole forcé CAN : le premier octet est un compte
          isCanFormat = (firstByteVal != null && firstByteVal >= 1 && firstByteVal <= 16);
        } else {
          // Auto-détection structurelle formelle :
          if (firstByteVal != null && firstByteVal >= 1 && firstByteVal <= 16) {
            int expectedDtcBytes = 2 * firstByteVal;
            if ((payload.length == 6 || payload.length == 7) && firstByteVal <= 3) {
              // Standard CAN Single Frame (DLC = 8 avec SID + NODTC + 3 slots)
              final tail = payload.sublist(1 + expectedDtcBytes);
              if (tail.isNotEmpty && tail.every((b) => b == '00')) {
                isCanFormat = true;
              }
            } else if (payload.length == 1 + expectedDtcBytes) {
              // CAN exact sans bourrage (longueur impaire : 3 pour N=1, 5 pour N=2...)
              isCanFormat = true;
            }
          }
        }

        if (isCanFormat && firstByteVal != null) {
          // Format CAN avec octet de décompte (NODTC)
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
          // Format K-Line ISO 9141-2 / ISO 14230 (paires directes de 2 octets sans octet de décompte)
          // Tout octet de bourrage 00 00 est automatiquement ignoré par decodeDtcBytes
          // Les octets tronqués isolés (i + 1 >= length) sont ignorés sans inventer de code
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

    // Finaliser toute session ISO-TP active restante
    if (activeSession != null) {
      _finalizeSession(activeSession, results);
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

  /// Décode les codes accumulés dans une session ISO-TP assemblée
  static void _finalizeSession(_IsoTpSession session, List<DecodedDtc> results) {
    // Rejet strict des sessions corrompues (désynchronisation ou index hors-séquence)
    // ou incomplètes (First Frame reçue mais Consecutive Frames manquantes)
    if (session.isCorrupted || !session.isComplete) return;

    int maxPairs = session.totalDtcCount;
    int availablePairs = session.dtcBytes.length ~/ 2;
    int countToDecode = availablePairs < maxPairs ? availablePairs : maxPairs;

    for (int i = 0; i < countToDecode; i++) {
      int highIdx = 2 * i;
      int lowIdx = (2 * i) + 1;
      if (lowIdx < session.dtcBytes.length) {
        String? dtc = decodeDtcBytes(session.dtcBytes[highIdx], session.dtcBytes[lowIdx]);
        if (dtc != null) {
          results.add(DecodedDtc(
            code: dtc,
            mode: session.mode,
            statusLabel: session.statusLabel,
            rawFrame: session.rawFrame,
          ));
        }
      }
    }
  }

  /// Traitement continu ligne par ligne pour flux réseau temps réel.
  /// Maintient l'état interne pour reconstituer les trames multiples ISO-TP arrivant ligne par ligne.
  List<DecodedDtc> feedRawLine(String rawLine, {ObdProtocolType protocol = ObdProtocolType.auto}) {
    // Si la ligne contient plusieurs sauts de ligne, déléguer à parseRawFrames
    if (rawLine.contains('\n') || rawLine.contains('\r')) {
      return parseRawFrames(rawLine, protocol: protocol);
    }

    final trimmed = rawLine.trim().toUpperCase();
    if (trimmed.isEmpty ||
        trimmed.contains('NO DATA') ||
        trimmed.contains('UNABLE TO CONNECT') ||
        trimmed.contains('ERROR') ||
        trimmed.contains('SEARCHING') ||
        trimmed.contains('BUS INIT') ||
        trimmed.startsWith('AT') ||
        trimmed.startsWith('OK') ||
        trimmed.startsWith('ELM327')) {
      return [];
    }

    // 1. Suppression des en-têtes CAN (7E8, etc.)
    String cleanLine = trimmed.replaceFirst(RegExp(r'^(7E[0-9A-F]|[0-9A-F]{8})\s+'), '');

    // 2. Préfixe d'index de trame ELM327 (ex: "0: ...", "1: ...")
    int? frameIndex;
    final matchIndex = RegExp(r'^([0-9A-F]{1,3}):\s*(.*)$').firstMatch(cleanLine);
    if (matchIndex != null) {
      frameIndex = int.tryParse(matchIndex.group(1)!, radix: 16);
      cleanLine = matchIndex.group(2)!.trim();
    }

    // 3. Découpage en octets hexadécimaux
    List<String> tokens = cleanLine
        .replaceAll(RegExp(r'[^0-9A-F\s]'), '')
        .split(RegExp(r'\s+'))
        .where((t) => t.length == 2)
        .toList();

    if (tokens.isEmpty) return [];

    bool isRawIsoTpCF = false;
    int? rawSeqNumber;
    if (tokens.isNotEmpty && tokens[0].startsWith('2') && tokens[0].length == 2) {
      isRawIsoTpCF = true;
      rawSeqNumber = int.tryParse(tokens[0][1], radix: 16);
    }

    // A. Si session ISO-TP en cours d'assemblage
    if (_streamingSession != null && !_streamingSession!.isComplete) {
      bool isConsecutive = false;
      List<String> chunkBytes = [];

      if (frameIndex != null) {
        if (frameIndex == _streamingSession!.nextSequence) {
          isConsecutive = true;
          if (tokens.isNotEmpty && tokens[0].startsWith('2') && tokens[0].length == 2) {
            chunkBytes = tokens.sublist(1);
          } else {
            chunkBytes = tokens;
          }
        } else {
          _streamingSession!.isCorrupted = true;
        }
      } else if (isRawIsoTpCF && rawSeqNumber != null) {
        int expectedPciSeq = _streamingSession!.nextSequence & 0x0F;
        if (rawSeqNumber == expectedPciSeq) {
          isConsecutive = true;
          chunkBytes = tokens.sublist(1);
        } else {
          _streamingSession!.isCorrupted = true;
        }
      }

      if (isConsecutive && !_streamingSession!.isCorrupted) {
        _streamingSession!.dtcBytes.addAll(chunkBytes);
        _streamingSession!.nextSequence++;
        if (_streamingSession!.dtcBytes.length >= _streamingSession!.totalDtcCount * 2) {
          _streamingSession!.isComplete = true;
          final res = <DecodedDtc>[];
          _finalizeSession(_streamingSession!, res);
          _streamingSession = null;
          return res;
        }
        return []; // En cours d'accumulation
      } else {
        // Mauvaise séquence -> rejet immédiat
        _streamingSession = null;
      }
    }

    // B. Nouvelle trame (Single Frame ou First Frame)
    final modeMap = {
      '43': (DtcMode.stored, 'Confirmé (Mode 03)'),
      '47': (DtcMode.pending, 'En attente (Mode 07)'),
      '4A': (DtcMode.permanent, 'Permanent (Mode 0A)'),
    };

    bool isRawIsoTpFF = tokens.length >= 2 && tokens[0].startsWith('1');

    for (var entry in modeMap.entries) {
      int modeIdx = tokens.indexOf(entry.key);
      if (modeIdx == -1) continue;
      List<String> payload = tokens.sublist(modeIdx + 1);
      if (payload.isEmpty) continue;
      if (payload[0] == '00' && (payload.length == 1 || payload.every((b) => b == '00'))) continue;

      int? firstByteVal = int.tryParse(payload[0], radix: 16);
      bool isFirstFrame = (frameIndex == 0 || isRawIsoTpFF) && firstByteVal != null && firstByteVal >= 1 && firstByteVal <= 16;
      if (!isFirstFrame && protocol == ObdProtocolType.can && firstByteVal != null && firstByteVal > 3) {
        isFirstFrame = true;
      }

      if (isFirstFrame && firstByteVal != null) {
        _streamingSession = _IsoTpSession(
          mode: entry.value.$1,
          statusLabel: entry.value.$2,
          rawFrame: trimmed,
          totalDtcCount: firstByteVal,
          nextSequence: 1,
        );
        if (payload.length > 1) {
          _streamingSession!.dtcBytes.addAll(payload.sublist(1));
        }
        if (_streamingSession!.dtcBytes.length >= _streamingSession!.totalDtcCount * 2) {
          _streamingSession!.isComplete = true;
          final res = <DecodedDtc>[];
          _finalizeSession(_streamingSession!, res);
          _streamingSession = null;
          return res;
        }
        return []; // En attente des trames consécutives
      }
    }

    // Trame unique standard (Single Frame CAN ou K-Line)
    return parseRawFrames(rawLine, protocol: protocol);
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
  List<String> parseRawDtcFrame(String rawFrame, {ObdProtocolType protocol = ObdProtocolType.auto}) {
    return parseRawFrames(rawFrame, protocol: protocol).map((d) => d.code).toSet().toList();
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
