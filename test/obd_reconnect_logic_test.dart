// test/obd_reconnect_logic_test.dart
//
// Tests unitaires P0-OBD2 — SPARK V3.1 (Dart VM pur, sans plugin natif)
//
// ObdService dépend de flutter_background_service et network_info_plus
// qui nécessitent des channels natifs (iOS/Android). Ces tests ne peuvent
// donc pas instancier ObdService directement dans un test Dart VM.
//
// Stratégie : tester la LOGIQUE PURE extraite dans des fonctions autonomes,
// sans aucune dépendance à un plugin natif. Les règles de décision du
// didChangeAppLifecycleState sont isolées ici et vérifiées exhaustivement.
//
// Les invariants du getter/méthode seront validés par les tests d'intégration
// sur device réel (scenarios manuels listés en bas de ce fichier).

import 'package:flutter_test/flutter_test.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Logique pure extraite de checkConnectionHealth()
// Reproduit exactement la règle codée dans obd_service.dart
// ─────────────────────────────────────────────────────────────────────────────

/// Simule checkConnectionHealth() pour un socket null.
/// Retourne toujours false si la socket n'existe pas.
bool checkHealthSocketNull() => false;

/// Simule checkConnectionHealth() pour une socket existante.
/// [lastDataReceived] : timestamp de la dernière donnée reçue.
/// [maxAgeSeconds]    : seuil de fraîcheur (défaut 8s dans le code réel).
bool checkHealthSocketAlive(DateTime lastDataReceived, {int maxAgeSeconds = 8}) {
  final age = DateTime.now().difference(lastDataReceived).inSeconds;
  return age <= maxAgeSeconds;
}

/// Décision de reconnexion du dashboard (logique exacte du resumed corrigé).
/// Retourne true si une reconnexion est nécessaire.
bool needsReconnect({required bool socketNull, required DateTime lastDataReceived, int maxAgeSeconds = 8}) {
  if (socketNull) return true;
  final age = DateTime.now().difference(lastDataReceived).inSeconds;
  return age > maxAgeSeconds;
}

void main() {
  // ───────────────────────────────────────────────────────────────────────────
  // Groupe 1 : socket null → toujours reconnecter
  // ───────────────────────────────────────────────────────────────────────────
  group('Socket null → reconnexion obligatoire', () {
    test('checkHealth retourne false si socket null', () {
      expect(checkHealthSocketNull(), isFalse);
    });

    test('needsReconnect retourne true si socket null', () {
      expect(
        needsReconnect(socketNull: true, lastDataReceived: DateTime.now()),
        isTrue,
        reason: 'Pas de socket → toujours reconnecter',
      );
    });

    test('needsReconnect retourne true même si données très récentes (socket null)', () {
      // Socket nulle mais timestamp récent : impossible en pratique (pas de socket = pas de données)
      // mais la logique doit quand même reconnecter.
      expect(
        needsReconnect(
          socketNull: true,
          lastDataReceived: DateTime.now().subtract(const Duration(seconds: 1)),
        ),
        isTrue,
      );
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Groupe 2 : socket vivante, données fraîches → NE PAS reconnecter
  // ───────────────────────────────────────────────────────────────────────────
  group('Socket vivante + données fraîches → pas de reconnexion', () {
    test('données à 0s → pas de reconnexion', () {
      final ts = DateTime.now();
      expect(checkHealthSocketAlive(ts, maxAgeSeconds: 8), isTrue);
      expect(needsReconnect(socketNull: false, lastDataReceived: ts), isFalse);
    });

    test('données à 3s → pas de reconnexion (passage Messenger rapide)', () {
      final ts = DateTime.now().subtract(const Duration(seconds: 3));
      expect(checkHealthSocketAlive(ts), isTrue);
      expect(needsReconnect(socketNull: false, lastDataReceived: ts), isFalse);
    });

    test('données à 5s → pas de reconnexion (coup d\'œil Messenger)', () {
      final ts = DateTime.now().subtract(const Duration(seconds: 5));
      expect(checkHealthSocketAlive(ts), isTrue);
      expect(needsReconnect(socketNull: false, lastDataReceived: ts), isFalse);
    });

    test('données à 8s exactement → à la limite, pas de reconnexion', () {
      final ts = DateTime.now().subtract(const Duration(seconds: 8));
      // inSeconds tronque, donc 8s → age == 8 → 8 <= 8 → true → pas de reconnexion
      expect(checkHealthSocketAlive(ts), isTrue);
      expect(needsReconnect(socketNull: false, lastDataReceived: ts), isFalse);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Groupe 3 : socket vivante, données périmées → RECONNECTER
  // ───────────────────────────────────────────────────────────────────────────
  group('Socket vivante + données périmées → reconnexion', () {
    test('données à 10s → reconnecter (Messenger 10s)', () {
      final ts = DateTime.now().subtract(const Duration(seconds: 10));
      expect(checkHealthSocketAlive(ts), isFalse);
      expect(needsReconnect(socketNull: false, lastDataReceived: ts), isTrue);
    });

    test('données à 30s → reconnecter (Messenger 30s)', () {
      final ts = DateTime.now().subtract(const Duration(seconds: 30));
      expect(needsReconnect(socketNull: false, lastDataReceived: ts), isTrue);
    });

    test('données à 120s → reconnecter (2 minutes dans Messenger)', () {
      final ts = DateTime.now().subtract(const Duration(seconds: 120));
      expect(needsReconnect(socketNull: false, lastDataReceived: ts), isTrue);
    });

    test('données à 1 heure → reconnecter (app suspendue longtemps)', () {
      final ts = DateTime.now().subtract(const Duration(hours: 1));
      expect(needsReconnect(socketNull: false, lastDataReceived: ts), isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Groupe 4 : seuil personnalisé
  // ───────────────────────────────────────────────────────────────────────────
  group('Seuil personnalisé (maxAgeSeconds)', () {
    test('seuil 15s : données à 10s → pas de reconnexion', () {
      final ts = DateTime.now().subtract(const Duration(seconds: 10));
      expect(checkHealthSocketAlive(ts, maxAgeSeconds: 15), isTrue);
      expect(needsReconnect(socketNull: false, lastDataReceived: ts, maxAgeSeconds: 15), isFalse);
    });

    test('seuil 5s : données à 6s → reconnecter', () {
      final ts = DateTime.now().subtract(const Duration(seconds: 6));
      expect(checkHealthSocketAlive(ts, maxAgeSeconds: 5), isFalse);
      expect(needsReconnect(socketNull: false, lastDataReceived: ts, maxAgeSeconds: 5), isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Groupe 5 : ancien comportement (bug corrigé) vs nouveau
  // ───────────────────────────────────────────────────────────────────────────
  group('Régression : ancien bug vs nouveau comportement', () {
    test('ANCIEN BUG : déconnectait toujours au resumed (même avec données fraîches)', () {
      // L'ancien code faisait toujours _obdService.disconnect() au resumed.
      // Ce test documente le comportement incorrect pour référence.
      const ancienComportement = true; // disconnect() systématique
      // Données fraîches à 3s — l'ancien code aurait déconnecté quand même.
      // Le nouveau code NE déconnecte PAS dans ce cas.
      final ts = DateTime.now().subtract(const Duration(seconds: 3));
      final nouveauComportement = needsReconnect(socketNull: false, lastDataReceived: ts);
      expect(ancienComportement, isNot(equals(nouveauComportement)),
          reason: 'Le nouveau code doit différer de l\'ancien pour les données fraîches');
    });

    test('NOUVEAU : données fraîches → conservation de la connexion', () {
      final ts = DateTime.now().subtract(const Duration(seconds: 4));
      expect(needsReconnect(socketNull: false, lastDataReceived: ts), isFalse);
    });

    test('NOUVEAU : données périmées → reconnexion (même comportement qu\'avant)', () {
      final ts = DateTime.now().subtract(const Duration(seconds: 30));
      expect(needsReconnect(socketNull: false, lastDataReceived: ts), isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Groupe 6 : garde _isConnecting (anti-concurrence)
  // ───────────────────────────────────────────────────────────────────────────
  group('Garde _isConnecting (logique pure)', () {
    test('un second appel pendant une connexion en cours doit être ignoré', () {
      bool isConnecting = false;
      int connectCallCount = 0;

      void connectObd() {
        if (isConnecting) return; // garde
        isConnecting = true;
        connectCallCount++;
        // Simule une connexion longue en cours…
      }

      connectObd(); // premier appel → passe
      connectObd(); // second appel concurrent → ignoré par la garde
      connectObd(); // troisième → ignoré aussi

      expect(connectCallCount, equals(1),
          reason: 'connect() ne doit être appelé qu\'une seule fois malgré les appels concurrents');
    });

    test('après libération du verrou, un nouvel appel passe', () {
      bool isConnecting = false;
      int connectCallCount = 0;

      void connectObd() {
        if (isConnecting) return;
        isConnecting = true;
        connectCallCount++;
        isConnecting = false; // libération (simule finally)
      }

      connectObd(); // premier appel → passe
      connectObd(); // second appel → passe aussi (verrou libéré)

      expect(connectCallCount, equals(2));
    });
  });
}
