import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import '../core/gps_debug_logger.dart';

/// Écran de diagnostic GPS — accessible sans Xcode.
///
/// Accès depuis le drawer MIMO SPARK : visible uniquement quand
/// [GpsDebugLogger.enabled] est true.
///
/// Fonctions :
///   • Affiche le log en temps réel (ScrollView auto-scroll vers le bas).
///   • Bouton Partager : feuille de partage iOS → copier dans Notes, Mail, etc.
///   • Bouton Effacer : vide le fichier log et le buffer mémoire.
///   • Bouton Copier : copie tout le texte dans le presse-papier.
class GpsDebugLogPage extends StatefulWidget {
  const GpsDebugLogPage({super.key});

  @override
  State<GpsDebugLogPage> createState() => _GpsDebugLogPageState();
}

class _GpsDebugLogPageState extends State<GpsDebugLogPage> {
  final ScrollController _scroll = ScrollController();
  List<String> _lines = [];
  bool _autoScroll = true;

  @override
  void initState() {
    super.initState();
    _refresh();
    // Rafraîchit toutes les 2 secondes pour voir les nouvelles mesures
    _startPolling();
  }

  late final Stream<void> _poll = Stream.periodic(
    const Duration(seconds: 2),
  );

  void _startPolling() {
    _poll.listen((_) {
      if (mounted) _refresh();
    });
  }

  void _refresh() {
    setState(() {
      _lines = GpsDebugLogger.lines.toList();
    });
    if (_autoScroll && _scroll.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  Future<void> _share() async {
    final content = await GpsDebugLogger.readAll();
    final path = await GpsDebugLogger.filePath;
    final xFile = XFile(path, mimeType: 'text/plain', name: 'gps_debug_log.txt');
    await Share.shareXFiles(
      [xFile],
      subject: 'MIMO SPARK — Log GPS diagnostic',
      text: 'Log GPS SPARK (${_lines.length} entrées)',
    );
  }

  Future<void> _copy() async {
    final content = _lines.join('\n');
    await Clipboard.setData(ClipboardData(text: content));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Log copié dans le presse-papier'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1C24),
        title: const Text('Effacer le log ?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Le fichier de log GPS sera effacé. Cette action est irréversible.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Effacer', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await GpsDebugLogger.clear();
      _refresh();
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0C10),
      appBar: AppBar(
        backgroundColor: const Color(0xFF151820),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Log GPS — Diagnostic',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              '${_lines.length} entrées · auto-scroll: $_autoScroll',
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ],
        ),
        actions: [
          // Auto-scroll toggle
          IconButton(
            tooltip: 'Auto-scroll',
            icon: Icon(
              _autoScroll ? Icons.vertical_align_bottom : Icons.pause,
              color: _autoScroll ? Colors.greenAccent : Colors.white54,
            ),
            onPressed: () => setState(() => _autoScroll = !_autoScroll),
          ),
          // Copier
          IconButton(
            tooltip: 'Copier',
            icon: const Icon(Icons.copy, color: Colors.white70),
            onPressed: _copy,
          ),
          // Partager (iOS share sheet)
          IconButton(
            tooltip: 'Partager',
            icon: const Icon(Icons.share, color: Colors.white),
            onPressed: _share,
          ),
          // Effacer
          IconButton(
            tooltip: 'Effacer',
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            onPressed: _clear,
          ),
        ],
      ),
      body: Column(
        children: [
          // En-tête des colonnes (rappel du format)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            color: const Color(0xFF1E2030),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Text(
                'timestamp_ms | speed | h_raw | acc_m | dist_prev | dist_anchor | src | smooth | page',
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 10,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
          const Divider(height: 1, color: Colors.white12),
          // Log scroll view
          Expanded(
            child: _lines.isEmpty
                ? const Center(
                    child: Text(
                      'Aucun log.\nDémarrez MapPage pour commencer l\'enregistrement.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white38, fontSize: 14),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    itemCount: _lines.length,
                    itemBuilder: (_, i) {
                      final line = _lines[i];
                      final isMarker = line.startsWith('#');
                      final isFrozen = line.contains('frozen');
                      final isBearing = line.contains('anchor_bearing');

                      Color textColor;
                      if (isMarker) {
                        textColor = Colors.amberAccent;
                      } else if (isFrozen) {
                        textColor = const Color(0xFFFF6B6B); // rouge = cap gelé
                      } else if (isBearing) {
                        textColor = const Color(0xFF6BCB77); // vert = fallback bearing
                      } else {
                        textColor = Colors.white70; // blanc = GPS direct
                      }

                      return SelectableText(
                        line,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 11,
                          fontFamily: 'monospace',
                          height: 1.4,
                        ),
                      );
                    },
                  ),
          ),
          // Légende des couleurs
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: const Color(0xFF151820),
            child: Wrap(
              spacing: 16,
              children: const [
                _LegendItem(color: Colors.white70, label: 'ios_direct'),
                _LegendItem(color: Color(0xFF6BCB77), label: 'anchor_bearing'),
                _LegendItem(color: Color(0xFFFF6B6B), label: 'frozen (cap gelé)'),
                _LegendItem(color: Colors.amberAccent, label: 'marqueur événement'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: color, fontSize: 10)),
      ],
    );
  }
}
