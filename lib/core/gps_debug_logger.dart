import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Journalisation temporaire du cap GPS pour diagnostic P0-GPS.
///
/// Activée par le flag [enabled]. Ne jamais pousser avec [enabled = true]
/// en production. Ne stocke aucune coordonnée géographique.
///
/// Accès sans Xcode : [GpsDebugLogPage] lit ce fichier et propose
/// le partage via la feuille de partage iOS (share_plus).
class GpsDebugLogger {
  GpsDebugLogger._();

  /// Mettre à true uniquement pendant une session de diagnostic terrain.
  /// Remettre à false avant tout push ou build release.
  static const bool enabled = true;

  static const String _filename = 'gps_debug_log.txt';
  static const int _maxLines = 2000; // ~200 Ko — ne sature pas l'iPhone

  // Buffer mémoire pour affichage in-app immédiat
  static final List<String> _buffer = [];
  static IOSink? _sink;
  static bool _initialized = false;

  // ------------------------------------------------------------------ init

  static Future<void> init() async {
    if (!enabled) return;
    if (_initialized) return;
    _initialized = true;
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$_filename');
    _sink = file.openWrite(mode: FileMode.append);
    final header = _buildHeader();
    _sink!.writeln(header);
    _buffer.add(header);
  }

  static String _buildHeader() {
    final now = DateTime.now();
    return '\n# GPS debug session — ${now.toIso8601String()}\n'
        '# timestamp_ms | speed_kmh | heading_raw | accuracy_m '
        '| dist_prev_m | dist_anchor_m | source | smooth_deg | page';
  }

  // ------------------------------------------------------------------ log

  /// Enregistre une mesure GPS.
  ///
  /// [timestampMs]   : DateTime.now().millisecondsSinceEpoch
  /// [speedKmh]      : vitesse en km/h
  /// [headingRaw]    : pos.heading brut (-1 si invalide)
  /// [accuracyM]     : pos.accuracy en mètres
  /// [distPrevM]     : distance depuis la position précédente (m)
  /// [distAnchorM]   : distance accumulée depuis la dernière ancre fiable (m)
  /// [source]        : "ios_direct" | "anchor_bearing" | "frozen"
  /// [smoothedDeg]   : cap final après lissage
  /// [page]          : "MapPage" | "ExpertMapPage"
  static void log({
    required int timestampMs,
    required double speedKmh,
    required double headingRaw,
    required double accuracyM,
    required double distPrevM,
    required double distAnchorM,
    required String source,
    required double smoothedDeg,
    required String page,
  }) {
    if (!enabled) return;

    final line = '$timestampMs'
        ' | ${speedKmh.toStringAsFixed(1)}'
        ' | ${headingRaw.toStringAsFixed(1)}'
        ' | ${accuracyM.toStringAsFixed(1)}'
        ' | ${distPrevM.toStringAsFixed(1)}'
        ' | ${distAnchorM.toStringAsFixed(1)}'
        ' | $source'
        ' | ${smoothedDeg.toStringAsFixed(1)}'
        ' | $page';

    _buffer.add(line);
    if (_buffer.length > _maxLines) _buffer.removeAt(0);

    _sink?.writeln(line);
  }

  // ------------------------------------------------------------------ event markers

  /// Insère un marqueur textuel dans les logs (ex: "UTURN_START").
  static void mark(String label) {
    if (!enabled) return;
    final line = '# ${DateTime.now().toIso8601String()} [$label]';
    _buffer.add(line);
    _sink?.writeln(line);
  }

  // ------------------------------------------------------------------ access

  /// Contenu du buffer mémoire, plus récent en dernier.
  static List<String> get lines => List.unmodifiable(_buffer);

  /// Chemin absolu du fichier log sur le device.
  static Future<String> get filePath async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/$_filename';
  }

  /// Contenu complet du fichier log (pour partage).
  static Future<String> readAll() async {
    final path = await filePath;
    final file = File(path);
    if (!await file.exists()) return '(aucun log enregistré)';
    return file.readAsString();
  }

  /// Efface le fichier log et réinitialise le buffer.
  static Future<void> clear() async {
    _buffer.clear();
    final path = await filePath;
    final file = File(path);
    if (await file.exists()) await file.writeAsString('');
    _initialized = false;
    _sink = null;
    await init();
  }

  /// Ferme le sink proprement (appeler dans dispose).
  static Future<void> close() async {
    await _sink?.flush();
    await _sink?.close();
    _sink = null;
    _initialized = false;
  }
}
