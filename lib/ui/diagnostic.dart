import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import '../core/dtc_database.dart';
import '../core/dtc_scanner.dart';
import '../core/obd_service.dart';
import 'package:share_plus/share_plus.dart';

class DiagnosticPage extends StatefulWidget {
  /// L'instance ObdService partagée avec le Dashboard (déjà connectée)
  final ObdService obdService;
  const DiagnosticPage({super.key, required this.obdService});

  @override
  State<DiagnosticPage> createState() => _DiagnosticPageState();
}

class _DiagnosticPageState extends State<DiagnosticPage> {
  ObdService get _obdService => widget.obdService;
  final DtcScanner _dtcScanner = DtcScanner();

  final List<DecodedDtc> _rawDecodedList = [];
  List<DtcInfo> _detailedErrors = [];
  bool _isLoading = false;

  StreamSubscription? _dtcSubscription;

  @override
  void initState() {
    super.initState();
    _loadDtcDb();
    // On écoute le flux DTC dédié alimenté par les réponses de scan OBD
    _dtcSubscription = _obdService.dtcStream.listen((data) {
      if (_isLoading) _parseDiagnosticData(data);
    });
  }

  @override
  void dispose() {
    _dtcSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadDtcDb() async {
    await DtcDatabase.loadCodes();
  }

  void _parseDiagnosticData(String raw) {
    try {
      final decoded = _dtcScanner.parseRawFrames(raw, protocol: _obdService.detectedProtocol);
      if (decoded.isNotEmpty) {
        for (var item in decoded) {
          if (!_rawDecodedList.any((e) => e.code == item.code && e.mode == item.mode)) {
            _rawDecodedList.add(item);
          }
        }
      }
    } catch (e) {
      debugPrint("Parser DTC Error: $e");
    }
  }

  void _scanDtc() async {
    _dtcScanner.resetSession();
    setState(() {
      _isLoading = true;
      _rawDecodedList.clear();
      _detailedErrors.clear();
    });

    try {
      // Envoie successivement Mode 03, Mode 07, Mode 0A avec attentes dynamiques
      await _obdService.scanTroubleCodes();

      // Résolution des informations détaillées pour chaque code détecté
      final List<DtcInfo> resolved = [];
      for (var decoded in _rawDecodedList) {
        final info = await DtcDatabase.getInfo(
          decoded.code,
          status: decoded.statusLabel,
          rawFrame: decoded.rawFrame,
        );
        resolved.add(info);
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
          _detailedErrors = resolved;
        });

        if (_detailedErrors.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Diagnostic terminé : Aucun code défaut présent."),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          _showClearConfirmDialog();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Erreur durant le scan : $e"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _showClearConfirmDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 28),
            SizedBox(width: 10),
            Text('Codes Panne Détectés', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_detailedErrors.length} code(s) défaut enregistré(s) par le calculateur.',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 12),
            const Text('⚠️  EFFACER = Réinitialise la mémoire et éteint le voyant moteur.', style: TextStyle(color: Colors.orangeAccent, fontSize: 12)),
            const SizedBox(height: 6),
            const Text('📋  CONSERVER = Permet de consulter les contrôles et montrer au mécanicien.', style: TextStyle(color: Colors.lightBlueAccent, fontSize: 12)),
          ],
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
            label: const Text('EFFACER CODES', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
            onPressed: () {
              Navigator.pop(ctx);
              _clearDtc();
            },
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.visibility, color: Colors.black),
            label: const Text('CONSERVER', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent),
            onPressed: () => Navigator.pop(ctx),
          ),
        ],
      ),
    );
  }

  void _clearDtc() async {
    setState(() => _isLoading = true);
    bool success = await _obdService.clearCodes();
    if (mounted) {
      setState(() {
        _isLoading = false;
        if (success) {
          _detailedErrors.clear();
          _rawDecodedList.clear();
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? "Mémoire effacée avec succès. Le voyant Check Engine devrait s'éteindre."
                : "Échec de l'effacement. Vérifiez que le contact est mis moteur arrêté.",
          ),
          backgroundColor: success ? Colors.green : Colors.redAccent,
        ),
      );
    }
  }

  void _showDtcDetailSheet(DtcInfo info) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF141414),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (ctx, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Poignée de drag
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // En-tête : Code + Badges
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: _getSeverityColor(info.severity).withOpacity(0.18),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _getSeverityColor(info.severity), width: 1.5),
                    ),
                    child: Text(
                      info.code,
                      style: TextStyle(
                        color: _getSeverityColor(info.severity),
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          info.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (info.titleEn != null && info.titleEn!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            info.titleEn!,
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            if (info.status != null)
                              Container(
                                margin: const EdgeInsets.only(right: 6),
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.white10,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  info.status!,
                                  style: const TextStyle(color: Colors.white70, fontSize: 10),
                                ),
                              ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: _getSeverityColor(info.severity).withOpacity(0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                info.severity.toUpperCase(),
                                style: TextStyle(
                                  color: _getSeverityColor(info.severity),
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Catégorie
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.category_outlined, color: Colors.white60, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      info.category,
                      style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Avertissement / Note Expert (Ex: pour capteur MAP)
              if (info.note.isNotEmpty) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orangeAccent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orangeAccent.withOpacity(0.4)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.lightbulb_outline, color: Colors.orangeAccent, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          info.note,
                          style: const TextStyle(color: Colors.orangeAccent, fontSize: 12, height: 1.35),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Explication claire
              const Text(
                "EXPLICATION DU DÉFAUT",
                style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2),
              ),
              const SizedBox(height: 6),
              Text(
                info.description,
                style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
              ),
              // Information si fiche non indexée
              if (info.causes.isEmpty) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, color: Colors.white60, size: 18),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          "Fiche atelier détaillée non indexée pour ce code spécifique. Référez-vous à la documentation technique constructeur GM Daewoo pour la procédure officielle de test au multimètre.",
                          style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.35),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Causes probables
              if (info.causes.isNotEmpty) ...[
                const Text(
                  "CAUSES POSSIBLES",
                  style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                ),
                const SizedBox(height: 8),
                ...info.causes.map((c) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("• ", style: TextStyle(color: Colors.orangeAccent, fontSize: 14)),
                          Expanded(
                            child: Text(c, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                          ),
                        ],
                      ),
                    )),
                const SizedBox(height: 20),
              ],

              // Symptômes
              if (info.symptoms.isNotEmpty) ...[
                const Text(
                  "SYMPTÔMES CONSTATÉS AU VOLANT",
                  style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                ),
                const SizedBox(height: 8),
                ...info.symptoms.map((s) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("• ", style: TextStyle(color: Colors.lightBlueAccent, fontSize: 14)),
                          Expanded(
                            child: Text(s, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                          ),
                        ],
                      ),
                    )),
                const SizedBox(height: 20),
              ],

              // Premiers contrôles recommandés
              if (info.checks.isNotEmpty) ...[
                const Text(
                  "PREMIERS CONTRÔLES RECOMMANDÉS",
                  style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                ),
                const SizedBox(height: 8),
                ...info.checks.map((chk) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.04),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.check_circle_outline, color: Colors.greenAccent, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(chk, style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.35)),
                          ),
                        ],
                      ),
                    )),
                const SizedBox(height: 16),
              ],

              // Trames brutes (Diagnostic atelier)
              if (info.rawFrame != null && info.rawFrame!.isNotEmpty) ...[
                const Text(
                  "TRAME BRUTE OBD-II (REÇUE DU VÉHICULE)",
                  style: TextStyle(color: Colors.white24, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.1),
                ),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Text(
                    info.rawFrame!,
                    style: const TextStyle(fontFamily: 'monospace', color: Colors.greenAccent, fontSize: 11),
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // Bouton Fermer
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white10,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("FERMER", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  Color _getSeverityColor(String severity) {
    switch (severity.toLowerCase()) {
      case 'critique':
        return Colors.redAccent;
      case 'alerte':
        return Colors.orangeAccent;
      case 'info':
      default:
        return Colors.lightBlueAccent;
    }
  }

  void _lireBoiteNoire() async {
    try {
      File? file = await _obdService.getLogFile();
      if (file != null && await file.exists()) {
        String contenu = await file.readAsString();
        List<String> lignes = contenu.split('\n');
        String finDuLog = lignes.length > 30 ? lignes.sublist(lignes.length - 30).join('\n') : contenu;

        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              backgroundColor: const Color(0xFF1A1A1A),
              title: const Text('Journal Boîte Noire MIMO_OBD', style: TextStyle(color: Colors.greenAccent, fontSize: 13)),
              content: SingleChildScrollView(
                child: Text(finDuLog, style: const TextStyle(fontSize: 10, color: Colors.greenAccent, fontFamily: 'monospace')),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('FERMER', style: TextStyle(color: Colors.white)),
                )
              ],
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Le journal de bord est actuellement vide.')),
        );
      }
    } catch (e) {
      debugPrint('Erreur lecture log: $e');
    }
  }

  void _shareLog() async {
    File? logFile = await _obdService.getLogFile();
    if (logFile != null && await logFile.exists()) {
      await Share.shareXFiles([XFile(logFile.path)], text: 'Journal de bord MIMO_OBD');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucun journal de bord disponible.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostic OBD-II — MIMO_OBD'),
        backgroundColor: Colors.black,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.share, color: Colors.lightBlueAccent),
            onPressed: _shareLog,
            tooltip: 'Exporter le journal',
          )
        ],
      ),
      backgroundColor: Colors.black,
      body: Column(
        children: [
          // Barre d'actions
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ElevatedButton.icon(
                    icon: _isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2),
                          )
                        : const Icon(Icons.search, color: Colors.black),
                    label: Text(
                      _isLoading ? 'SCAN EN COURS...' : 'SCANNER DTC',
                      style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orangeAccent,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _isLoading ? null : _scanDtc,
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.history, color: Colors.white70, size: 18),
                    label: const Text('JOURNAL LOG', style: TextStyle(color: Colors.white70)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white24),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _lireBoiteNoire,
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.delete_outline, color: Colors.white, size: 18),
                    label: const Text('EFFACER', style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red[900],
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _detailedErrors.isEmpty ? null : _showClearConfirmDialog,
                  ),
                ],
              ),
            ),
          ),

          // Zone principale
          Expanded(
            child: _detailedErrors.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_isLoading) ...[
                            const CircularProgressIndicator(color: Colors.orangeAccent),
                            const SizedBox(height: 20),
                            const Text(
                              'Interrogation des calculateurs en cours…\nModes 03, 07 et 0A',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                            ),
                          ] else ...[
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.greenAccent.withOpacity(0.1),
                              ),
                              child: const Icon(Icons.check_circle_outline, color: Colors.greenAccent, size: 54),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Aucun code défaut présent',
                              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Le calculateur ne signale aucune anomalie active.\nAppuyez sur SCANNER DTC pour relancer une analyse.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.4),
                            ),
                          ],
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    itemCount: _detailedErrors.length,
                    itemBuilder: (context, index) {
                      final info = _detailedErrors[index];
                      final color = _getSeverityColor(info.severity);

                      return Container(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF141414),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: color.withOpacity(0.4), width: 1.2),
                          boxShadow: [
                            BoxShadow(color: color.withOpacity(0.08), blurRadius: 10, spreadRadius: 0),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => _showDtcDetailSheet(info),
                            child: Padding(
                              padding: const EdgeInsets.all(14.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: color.withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          info.code,
                                          style: TextStyle(
                                            color: color,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 15,
                                            letterSpacing: 1.2,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      if (info.status != null)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: Colors.white10,
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            info.status!,
                                            style: const TextStyle(color: Colors.white70, fontSize: 10),
                                          ),
                                        ),
                                      const Spacer(),
                                      const Icon(Icons.arrow_forward_ios, color: Colors.white38, size: 14),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    info.title,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      height: 1.3,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    info.category,
                                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Icon(Icons.touch_app_outlined, color: Colors.orangeAccent.withOpacity(0.8), size: 13),
                                      const SizedBox(width: 4),
                                      Text(
                                        "Toucher pour voir les causes et contrôles",
                                        style: TextStyle(color: Colors.orangeAccent.withOpacity(0.85), fontSize: 11, fontWeight: FontWeight.w500),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
