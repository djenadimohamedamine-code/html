import 'dart:convert';
import 'package:flutter/services.dart';

class DtcInfo {
  final String code;
  final String title;
  final String msg;
  final String severity; // 'critique', 'alerte', 'info'
  final String category;
  final String description;
  final List<String> causes;
  final List<String> symptoms;
  final List<String> checks;
  final String note;
  final String? status;
  final String? rawFrame;

  const DtcInfo({
    required this.code,
    required this.title,
    required this.msg,
    required this.severity,
    required this.category,
    required this.description,
    required this.causes,
    required this.symptoms,
    required this.checks,
    this.note = '',
    this.status,
    this.rawFrame,
  });
}

class DtcDatabase {
  static Map<String, dynamic>? _codes;
  static bool _loading = false;

  // ─── Chargement asynchrone lazy ───────────────────────────────────────────
  static Future<void> _ensureLoaded() async {
    if (_codes != null) return;
    if (_loading) {
      while (_loading) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      return;
    }
    await loadCodes();
  }

  static Future<void> loadCodes() async {
    if (_loading) return;
    _loading = true;
    try {
      final String data = await rootBundle.loadString('assets/data/dtc_codes.json');
      final decoded = jsonDecode(data);
      if (decoded is Map<String, dynamic>) {
        _codes = decoded;
      }
    } catch (e) {
      print("Erreur chargement base DTC: $e");
      _codes = {};
    } finally {
      _loading = false;
    }
  }

  /// Récupère la fiche détaillée d'un code défaut avec toutes ses informations
  static Future<DtcInfo> getInfo(String code, {String? status, String? rawFrame}) async {
    await _ensureLoaded();
    final cleanCode = code.toUpperCase().trim();
    final entry = _codes?[cleanCode];

    if (entry != null && entry is Map<String, dynamic>) {
      final title = entry['title'] as String? ?? entry['msg'] as String? ?? cleanCode;
      final msg = entry['msg'] as String? ?? title;
      final sev = entry['sev'] as String? ?? 'info';
      final cat = entry['cat'] as String? ?? _categorize(cleanCode);
      final desc = entry['desc'] as String? ?? _generateDefaultDesc(cleanCode, title);
      final causes = (entry['causes'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? _generateDefaultCauses(cleanCode);
      final symptoms = (entry['symptoms'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? _generateDefaultSymptoms(cleanCode);
      final checks = (entry['checks'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? _generateDefaultChecks(cleanCode);
      final note = entry['note'] as String? ?? '';

      return DtcInfo(
        code: cleanCode,
        title: title,
        msg: msg,
        severity: sev,
        category: cat,
        description: desc,
        causes: causes,
        symptoms: symptoms,
        checks: checks,
        note: note,
        status: status,
        rawFrame: rawFrame,
      );
    }

    // Code non présent explicitement dans le JSON (ex: code constructeur P1xxx)
    return _synthesizeInfo(cleanCode, status: status, rawFrame: rawFrame);
  }

  /// Synthèse dynamique pour les codes constructeurs ou non répertoriés selon SAE J2012
  static DtcInfo _synthesizeInfo(String code, {String? status, String? rawFrame}) {
    final cat = _categorize(code);
    final isManufacturer = code.length >= 2 && code[1] == '1';
    final String title = isManufacturer
        ? 'Défaut spécifique constructeur ($cat)'
        : 'Code de diagnostic normalisé ($cat)';
    final String msg = isManufacturer
        ? 'Code constructeur spécifique (GM / Daewoo / Chevrolet). Consultez la documentation d\'atelier pour le détail de ce circuit.'
        : 'Anomalie de fonctionnement enregistrée sur le système $cat.';

    return DtcInfo(
      code: code,
      title: title,
      msg: msg,
      severity: isManufacturer ? 'alerte' : 'info',
      category: cat,
      description: 'Ce code a été remonté par le calculateur du véhicule. ' +
          (isManufacturer
              ? 'Il s\'agit d\'un code propre au groupe General Motors / Daewoo régissant le sous-système $cat.'
              : 'Ce code correspond à la famille standard SAE J2012 pour le système $cat.'),
      causes: _generateDefaultCauses(code),
      symptoms: _generateDefaultSymptoms(code),
      checks: _generateDefaultChecks(code),
      note: 'Pour les codes constructeurs spécifiques, vérifiez les paramètres en direct correspondants sur la page Données Moteur.',
      status: status,
      rawFrame: rawFrame,
    );
  }

  static String _categorize(String code) {
    if (code.isEmpty) return 'Système indéterminé';
    final family = code[0].toUpperCase();
    if (family == 'P') {
      if (code.length >= 3) {
        final sub = code.substring(1, 3);
        if (sub == '00' || sub == '01' || sub == '02' || sub == '11' || sub == '12') {
          return 'Alimentation air et carburant';
        } else if (sub == '03' || sub == '13') {
          return 'Système d\'allumage et ratés';
        } else if (sub == '04' || sub == '14') {
          return 'Dépollution et émissions (EVAP / Catalyseur)';
        } else if (sub == '05' || sub == '15') {
          return 'Vitesse véhicule et ralenti';
        } else if (sub == '06' || sub == '16') {
          return 'Calculateur (ECU/ECM) et mémoire';
        } else if (sub == '07' || sub == '08' || sub == '09' || sub == '17' || sub == '18') {
          return 'Boîte de vitesses et transmission';
        }
      }
      return 'Groupe motopropulseur (Moteur)';
    } else if (family == 'C') {
      return 'Châssis, Freinage ABS et Direction';
    } else if (family == 'B') {
      return 'Carrosserie, Habitacle et Airbags';
    } else if (family == 'U') {
      return 'Réseau et Communication bus CAN';
    }
    return 'Système auxiliaire';
  }

  static String _generateDefaultDesc(String code, String title) {
    return 'Le calculateur a détecté une valeur anormale sur ce circuit : $title.';
  }

  static List<String> _generateDefaultCauses(String code) {
    return [
      'Connecteur du composant desserré, oxydé ou broches endommagées',
      'Faisceau électrique pincé, coupé ou en court-circuit',
      'Composant ou capteur défectueux ou encrassé',
      'Tension de référence électrique instable ou mauvaise masse',
    ];
  }

  static List<String> _generateDefaultSymptoms(String code) {
    return [
      'Allumage du voyant d\'avertissement au tableau de bord',
      'Comportement moteur potentiellement altéré ou mode dégradé',
      'Données de télémétrie associées figées ou erronées',
    ];
  }

  static List<String> _generateDefaultChecks(String code) {
    return [
      '1. Vérifier la fixation et l\'état des connecteurs du sous-système concerné.',
      '2. Contrôler au multimètre l\'alimentation électrique (12V ou 5V) et la masse.',
      '3. Inspecter le faisceau électrique pour détecter d\'éventuels frottements ou câbles dénudés.',
      '4. Effacer le code après vérification physique et faire un essai routier pour confirmer.',
    ];
  }

  // ─── API Legacy (rétro-compatibilité intégrale) ───────────────────────────
  static Future<String> getDescription(String code) async {
    await _ensureLoaded();
    final entry = _codes?[code.toUpperCase().trim()];
    if (entry == null) return "Code de diagnostic ($code)";
    if (entry is String) return entry;
    return entry['msg'] as String? ?? entry['title'] as String? ?? "Dysfonctionnement spécifique.";
  }

  static Future<String> getSeverity(String code) async {
    await _ensureLoaded();
    final entry = _codes?[code.toUpperCase().trim()];
    if (entry is Map) return entry['sev'] as String? ?? 'info';
    return 'info';
  }

  static Future<List<Map<String, String>>> resolveAll(List<String> codes) async {
    await _ensureLoaded();
    final List<Map<String, String>> list = [];
    for (var code in codes) {
      final info = await getInfo(code);
      list.add({
        'code': info.code,
        'msg': info.msg,
        'sev': info.severity,
        'cat': info.category,
        'title': info.title,
      });
    }
    return list;
  }
}
