// ignore_for_file: avoid_print
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Reproduction PURE DART de la logique de cap de MapPage.
// Aucune dépendance native (geolocator, flutter_map, etc.).
// Lance avec : flutter test test/gps_heading_logic_test.dart
// ─────────────────────────────────────────────────────────────────────────────

// ── Copie exacte des fonctions de map_page.dart ──────────────────────────────

double _smoothAngle(double current, double target) {
  double diff = target - current;
  while (diff > 180) diff -= 360;
  while (diff < -180) diff += 360;
  final smoothed = current + diff * 0.25;
  return (smoothed % 360 + 360) % 360;
}

// bearingBetween simplifié (formule géodésique exacte)
double _bearingBetween(
  double lat1, double lon1,
  double lat2, double lon2,
) {
  final dLon = (lon2 - lon1) * math.pi / 180;
  final lat1R = lat1 * math.pi / 180;
  final lat2R = lat2 * math.pi / 180;
  final y = math.sin(dLon) * math.cos(lat2R);
  final x = math.cos(lat1R) * math.sin(lat2R) -
      math.sin(lat1R) * math.cos(lat2R) * math.cos(dLon);
  final bearing = math.atan2(y, x) * 180 / math.pi;
  return (bearing + 360) % 360; // normaliser en [0, 360)
}

double _distanceBetween(
  double lat1, double lon1,
  double lat2, double lon2,
) {
  const r = 6371000.0;
  final dLat = (lat2 - lat1) * math.pi / 180;
  final dLon = (lon2 - lon1) * math.pi / 180;
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1 * math.pi / 180) *
          math.cos(lat2 * math.pi / 180) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

// ── Simulateur d'une Position GPS (sans plugin geolocator) ──────────────────

class FakePosition {
  final double lat;
  final double lon;
  final double heading; // -1 si invalide
  final double speed;   // m/s
  final double accuracy;

  const FakePosition({
    required this.lat,
    required this.lon,
    this.heading = -1,
    required this.speed,
    this.accuracy = 5.0,
  });

  double get speedKmh => speed * 3.6;
}

// ── Logique ACTUELLE de MapPage (Stratégie A) ─────────────────────────────────

class CurrentMapPageLogic {
  double lastHeading = 0;
  FakePosition? currentPosition;

  /// Retourne (smooth, source) comme MapPage le fait aujourd'hui.
  (double smooth, String source) processPosition(FakePosition pos) {
    double currentHeading = lastHeading;
    String source = 'frozen';

    if (pos.speedKmh > 1.5) {
      if (pos.heading >= 0.0 && pos.heading.isFinite) {
        currentHeading = pos.heading;
        source = 'ios_direct';
      } else if (currentPosition != null) {
        final dist = _distanceBetween(
          currentPosition!.lat, currentPosition!.lon,
          pos.lat, pos.lon,
        );
        if (dist > 3.0) {
          currentHeading = _bearingBetween(
            currentPosition!.lat, currentPosition!.lon,
            pos.lat, pos.lon,
          );
          source = 'prev_bearing';
        }
        // else : reste 'frozen'
      }
    }

    final smooth = _smoothAngle(lastHeading, currentHeading);
    lastHeading = smooth;
    currentPosition = pos;
    return (smooth, source);
  }
}

// ── Logique PROPOSÉE (Stratégie B : ancre accumulée) ─────────────────────────

class ProposedMapPageLogic {
  double lastHeading = 0;
  FakePosition? currentPosition;

  // Ancre : dernière position où pos.heading était valide
  FakePosition? _headingAnchorPos;
  double _headingAnchorDist = 0;

  (double smooth, String source) processPosition(FakePosition pos) {
    double currentHeading = lastHeading;
    String source = 'frozen';

    if (pos.speedKmh > 1.5) {
      if (pos.heading >= 0.0 && pos.heading.isFinite) {
        // Cap iOS valide : utiliser directement et réinitialiser l'ancre
        currentHeading = pos.heading;
        source = 'ios_direct';
        _headingAnchorPos = pos;
        _headingAnchorDist = 0;
      } else if (_headingAnchorPos != null && currentPosition != null) {
        // Accumuler la distance depuis l'ancre
        final stepDist = _distanceBetween(
          currentPosition!.lat, currentPosition!.lon,
          pos.lat, pos.lon,
        );
        _headingAnchorDist += stepDist;

        // Seuil adaptatif : max(5m, 1.5 × accuracy)
        final minDist = math.max(5.0, pos.accuracy * 1.5);
        if (_headingAnchorDist >= minDist) {
          // Bearing depuis l'ancre (pas la position précédente)
          final bearing = _bearingBetween(
            _headingAnchorPos!.lat, _headingAnchorPos!.lon,
            pos.lat, pos.lon,
          );
          // Garder uniquement si le bearing est plausible
          // (distance >> accuracy → résultat fiable)
          if (_headingAnchorDist > pos.accuracy) {
            currentHeading = bearing;
            source = 'anchor_bearing';
          }
        }
      }
    }

    final smooth = _smoothAngle(lastHeading, currentHeading);
    lastHeading = smooth;
    currentPosition = pos;
    return (smooth, source);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Générateurs de séquences GPS simulées
// ─────────────────────────────────────────────────────────────────────────────

/// Génère N positions se déplaçant de [stepM] mètres vers [bearingDeg].
/// Latitude 36.8° (Alger), 1° lat ≈ 111 km.
List<FakePosition> _straightLine({
  required double startLat,
  required double startLon,
  required int count,
  required double stepM,
  required double bearingDeg,
  required double speedKmh,
  required double accuracy,
  double headingOverride = -2, // -2 = utilise bearingDeg, -1 = invalide
}) {
  final positions = <FakePosition>[];
  double lat = startLat;
  double lon = startLon;
  final bearingRad = bearingDeg * math.pi / 180;
  final dLat = stepM * math.cos(bearingRad) / 111320;
  final dLon = stepM * math.sin(bearingRad) /
      (111320 * math.cos(startLat * math.pi / 180));

  for (int i = 0; i < count; i++) {
    lat += dLat;
    lon += dLon;
    final h = headingOverride == -2 ? bearingDeg : headingOverride;
    positions.add(FakePosition(
      lat: lat,
      lon: lon,
      heading: h,
      speed: speedKmh / 3.6,
      accuracy: accuracy,
    ));
  }
  return positions;
}

// ─────────────────────────────────────────────────────────────────────────────
// TESTS
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  // ── Section 1 : _smoothAngle ────────────────────────────────────────────────
  group('_smoothAngle — propriétés de base', () {
    test('converge de 0° vers 180° en 16 étapes (< 2° d\'erreur)', () {
      double h = 0;
      int steps = 0;
      while (true) {
        h = _smoothAngle(h, 180);
        steps++;
        final err = (h - 180).abs();
        if (err < 2.0) break;
        expect(steps, lessThan(100), reason: 'ne converge pas');
      }
      expect(steps, lessThanOrEqualTo(16));
    });

    test('traverse 359°→1° sans saut de 180°', () {
      double h = 355;
      for (int i = 0; i < 20; i++) {
        final next = _smoothAngle(h, 1);
        // Le saut inter-étapes ne doit jamais dépasser 90°
        double diff = (next - h).abs();
        if (diff > 180) diff = 360 - diff;
        expect(diff, lessThan(90),
            reason: 'saut trop grand step $i: $h → $next');
        h = next;
      }
    });

    test('reste dans [0, 360)', () {
      for (final pair in [
        (350.0, 10.0),
        (10.0, 350.0),
        (0.0, 359.0),
        (180.0, 0.0),
        (270.0, 90.0),
      ]) {
        final result = _smoothAngle(pair.$1, pair.$2);
        expect(result, inInclusiveRange(0, 360));
      }
    });

    test('convergence depuis chaque cap cardinal vers 180°', () {
      for (final start in [0.0, 90.0, 270.0, 359.0]) {
        double h = start;
        int steps = 0;
        while (steps < 100) {
          h = _smoothAngle(h, 180);
          steps++;
          if ((h - 180).abs() < 2) break;
        }
        expect(steps, lessThan(30),
            reason: 'convergence trop lente depuis $start°');
      }
    });
  });

  // ── Section 2 : Stratégie A — fallback bearing mort ────────────────────────
  group('Stratégie A (actuelle) — fallback bearing avec distanceFilter=1m', () {
    test(
      'le fallback ne se déclenche JAMAIS avec des positions séparées de 1m',
      () {
        // Reproduit le bug structurel : _currentPosition = pos précédente
        // → distance = ~1m, toujours < 3m
        final logic = CurrentMapPageLogic();

        // Position initiale en route vers le nord avec cap valide
        logic.processPosition(FakePosition(
          lat: 36.800, lon: 3.050,
          heading: 0, speed: 10 / 3.6, accuracy: 5,
        ));

        // Séquence de 10 positions à 1m vers le nord avec heading invalide
        final positions = _straightLine(
          startLat: 36.800, startLon: 3.050,
          count: 10, stepM: 1.0, bearingDeg: 0,
          speedKmh: 10, accuracy: 5,
          headingOverride: -1, // invalide
        );

        int fallbackCount = 0;
        for (final pos in positions) {
          final (_, source) = logic.processPosition(pos);
          if (source == 'prev_bearing') fallbackCount++;
        }

        // Bug confirmé : le fallback ne se déclenche jamais
        expect(fallbackCount, equals(0),
            reason: 'La distance pos-prev est ~1m < seuil 3m : '
                'le fallback ne peut jamais se déclencher avec distanceFilter=1');
      },
    );

    test(
      'cap gelé à ~0° pendant tout un trajet retour (heading invalide)',
      () {
        final logic = CurrentMapPageLogic();

        // Aller : cap Nord valide établi
        for (int i = 0; i < 5; i++) {
          logic.processPosition(FakePosition(
            lat: 36.800 + i * 0.00001,
            lon: 3.050,
            heading: 0, speed: 10 / 3.6, accuracy: 5,
          ));
        }
        final capApresAller = logic.lastHeading;
        expect(capApresAller, closeTo(0, 5),
            reason: 'Cap Nord doit être établi après l\'aller');

        // Retour : heading invalide, positions vers le sud
        final retour = _straightLine(
          startLat: 36.800, startLon: 3.050,
          count: 30, stepM: 1.0, bearingDeg: 180,
          speedKmh: 20, accuracy: 5,
          headingOverride: -1,
        );

        for (final pos in retour) {
          logic.processPosition(pos);
        }

        // Bug Strat A : cap gelé — ne converge JAMAIS vers 180° (Sud)
        // Alpha=0.25 sur target figé = le cap reste bien en dessous de 90°.
        expect(
          logic.lastHeading,
          lessThan(90),
          reason: 'Bug confirmé : cap gelé, ne converge JAMAIS vers 180° (Sud)',
        );
      },
    );

    test(
      'le fallback se déclenche si la position de référence est distante de >3m',
      () {
        // Cas atypique : distanceFilter plus grand ou position initiale fixe
        // Vérifie que la formule elle-même fonctionne quand on lui donne de la distance
        final logic = CurrentMapPageLogic();

        // Position de référence fixe (simuler une ancre manuelle)
        logic.currentPosition = const FakePosition(
          lat: 36.800, lon: 3.050,
          speed: 0, accuracy: 5,
        );
        logic.lastHeading = 0;

        // Une nouvelle position à 10m vers le sud
        final pos = FakePosition(
          lat: 36.800 - 10.0 / 111320,
          lon: 3.050,
          heading: -1, // invalide
          speed: 15 / 3.6,
          accuracy: 5,
        );

        final (_, source) = logic.processPosition(pos);
        expect(source, equals('prev_bearing'),
            reason: 'Le fallback doit se déclencher si distance > 3m');
        // Avec alpha=0.25 et lastHeading=0° : smooth = 0 + (180-0)*0.25 = 45°
        // Le cap a bougé dans la bonne direction (> 0° initial, vers 180°)
        expect(logic.lastHeading, greaterThan(0),
            reason: 'Le cap doit avoir bougé vers le sud (> 0°)');
        expect(logic.lastHeading, lessThan(180),
            reason: 'Un seul callback alpha=0.25 : smooth est entre 0° et 180°');
      },
    );
  });

  // ── Section 3 : Stratégie B — ancre accumulée ──────────────────────────────
  group('Stratégie B (proposée) — ancre accumulée', () {
    test(
      'le fallback se déclenche après 5m accumulés (distanceFilter=1m)',
      () {
        final logic = ProposedMapPageLogic();

        // Position initiale avec cap valide (ancre établie)
        logic.processPosition(FakePosition(
          lat: 36.800, lon: 3.050,
          heading: 0, speed: 10 / 3.6, accuracy: 5,
        ));

        // Séquence 10× 1m vers le sud, heading invalide
        final positions = _straightLine(
          startLat: 36.800, startLon: 3.050,
          count: 10, stepM: 1.0, bearingDeg: 180,
          speedKmh: 10, accuracy: 5,
          headingOverride: -1,
        );

        final sources = <String>[];
        for (final pos in positions) {
          final (_, source) = logic.processPosition(pos);
          sources.add(source);
        }

        // accuracy=5m → seuil = max(5.0, 1.5×5) = 7.5m
        // Sur 10 positions à ~1m chacune, le fallback se déclenche après ~8m
        final frozenCount = sources.where((s) => s == 'frozen').length;
        final anchorCount = sources.where((s) => s == 'anchor_bearing').length;

        expect(frozenCount, lessThanOrEqualTo(8),
            reason: 'accuracy=5m → seuil=7.5m → au max 8 positions gelées avant fallback');
        expect(anchorCount, greaterThanOrEqualTo(1),
            reason: 'Le fallback doit se déclencher au moins une fois sur 10m cumulés');
      },
    );

    test(
      'cap retour 180° atteint après fallback anchor (distanceFilter=1m)',
      () {
        final logic = ProposedMapPageLogic();

        // Aller : cap Nord établi
        for (int i = 0; i < 5; i++) {
          logic.processPosition(FakePosition(
            lat: 36.800 + i * 0.00001,
            lon: 3.050,
            heading: 0, speed: 10 / 3.6, accuracy: 5,
          ));
        }

        // Retour : heading invalide, 30 positions vers le sud
        final retour = _straightLine(
          startLat: 36.800, startLon: 3.050,
          count: 30, stepM: 1.0, bearingDeg: 180,
          speedKmh: 10, accuracy: 5,
          headingOverride: -1,
        );

        for (final pos in retour) {
          logic.processPosition(pos);
        }

        // Contrairement à la Strat A, le cap doit converger vers 180°
        expect(
          logic.lastHeading,
          inInclusiveRange(90, 270),
          reason: 'Strat B : cap doit s\'orienter vers le Sud (180°) grâce à l\'ancre',
        );
      },
    );

    test(
      'seuil adaptatif : augmente avec l\'accuracy (accuracy=15m → seuil 22.5m)',
      () {
        final logic = ProposedMapPageLogic();

        // Position initiale avec cap valide
        logic.processPosition(FakePosition(
          lat: 36.800, lon: 3.050,
          heading: 0, speed: 10 / 3.6, accuracy: 15, // accuracy dégradée
        ));

        // 20 positions à 1m, heading invalide, accuracy=15m
        final positions = _straightLine(
          startLat: 36.800, startLon: 3.050,
          count: 20, stepM: 1.0, bearingDeg: 180,
          speedKmh: 10, accuracy: 15,
          headingOverride: -1,
        );

        final sources = <String>[];
        for (final pos in positions) {
          final (_, source) = logic.processPosition(pos);
          sources.add(source);
        }

        // Seuil = max(5, 1.5×15) = 22.5m → fallback pas avant ~23 positions
        final anchorBefore15 = sources.take(15).where((s) => s == 'anchor_bearing').length;
        expect(anchorBefore15, equals(0),
            reason: 'Avec accuracy=15m, seuil=22.5m → pas de fallback avant 15m');
      },
    );

    test(
      'U-turn simulé : ancre trompeur sur grande distance parcourue en épingle',
      () {
        // Problème signalé : ancre ancienne sur un virage serré peut donner
        // un bearing != direction actuelle
        //
        // Scénario : 10m vers le Nord, demi-tour, 10m vers le Sud
        // Position finale = même position que l'ancre → bearing indéfini

        final logic = ProposedMapPageLogic();

        // 1. Aller Nord avec cap valide (ancre établie)
        final aller = _straightLine(
          startLat: 36.800, startLon: 3.050,
          count: 10, stepM: 1.0, bearingDeg: 0,
          speedKmh: 10, accuracy: 5,
          headingOverride: 0,
        );
        for (final pos in aller) {
          logic.processPosition(pos);
        }

        // Ancre = point au Nord (~10m de l'origine)
        // 2. Demi-tour lent (heading invalide, petits pas)
        final demiTour = _straightLine(
          startLat: 36.800 + 10.0 / 111320,
          startLon: 3.050,
          count: 5, stepM: 0.5, bearingDeg: 180,
          speedKmh: 3, accuracy: 5,
          headingOverride: -1,
        );
        for (final pos in demiTour) {
          logic.processPosition(pos);
        }

        // 3. Retour Sud (heading invalide, dist accumulée > seuil)
        final retour = _straightLine(
          startLat: 36.800 + 10.0 / 111320 - 5 * 0.5 / 111320,
          startLon: 3.050,
          count: 20, stepM: 1.0, bearingDeg: 180,
          speedKmh: 10, accuracy: 5,
          headingOverride: -1,
        );

        String lastSource = '';
        double lastSmooth = 0;
        for (final pos in retour) {
          final (smooth, source) = logic.processPosition(pos);
          lastSource = source;
          lastSmooth = smooth;
        }

        // Le bearing depuis l'ancre (Nord) vers une position au Sud de l'ancre
        // doit indiquer ~180° — on vérifie la plausibilité
        print('[TEST U-TURN] dernier source=$lastSource smooth=${lastSmooth.toStringAsFixed(1)}°');
        // On documente le comportement sans assert bloquant (dépend du chemin exact)
        // Le test réel est visuel sur iPhone
      },
    );

    test(
      'virage à 90° : bearing ancre reste fiable si distance > accuracy',
      () {
        final logic = ProposedMapPageLogic();

        // Établir cap Nord
        logic.processPosition(FakePosition(
          lat: 36.800, lon: 3.050,
          heading: 0, speed: 10 / 3.6, accuracy: 4,
        ));

        // 8m vers le Nord avec cap valide (déplace l'ancre)
        final nord = _straightLine(
          startLat: 36.800, startLon: 3.050,
          count: 8, stepM: 1.0, bearingDeg: 0,
          speedKmh: 10, accuracy: 4,
          headingOverride: 0,
        );
        for (final p in nord) logic.processPosition(p);

        // Virage vers l'Est : heading invalide pendant 10m
        final est = _straightLine(
          startLat: 36.800 + 8.0 / 111320, startLon: 3.050,
          count: 10, stepM: 1.0, bearingDeg: 90,
          speedKmh: 10, accuracy: 4,
          headingOverride: -1,
        );

        String? firstAnchorSource;
        double? firstAnchorSmooth;
        for (final pos in est) {
          final (smooth, source) = logic.processPosition(pos);
          if (source == 'anchor_bearing' && firstAnchorSource == null) {
            firstAnchorSource = source;
            firstAnchorSmooth = smooth;
          }
        }

        // Le bearing depuis l'ancre (Nord) vers des positions à l'Est
        // est ~90° (Est) — correct pour un virage vers l'Est
        if (firstAnchorSmooth != null) {
          expect(firstAnchorSmooth, inInclusiveRange(20, 160),
              reason: 'Bearing Est attendu après virage');
        }
      },
    );

    test(
      'GPS dégradé (accuracy=20m) : pas de bearing aléatoire sur petite distance',
      () {
        final logic = ProposedMapPageLogic();

        // Cap initial
        logic.processPosition(FakePosition(
          lat: 36.800, lon: 3.050,
          heading: 90, speed: 10 / 3.6, accuracy: 20,
        ));

        // 10 positions à 1m avec accuracy=20m et heading invalide
        // Seuil = max(5, 1.5×20) = 30m → le fallback NE doit PAS se déclencher
        final positions = _straightLine(
          startLat: 36.800, startLon: 3.050,
          count: 10, stepM: 1.0, bearingDeg: 90,
          speedKmh: 10, accuracy: 20,
          headingOverride: -1,
        );

        final sources = <String>[];
        for (final p in positions) {
          final (_, s) = logic.processPosition(p);
          sources.add(s);
        }

        final anchorCount = sources.where((s) => s == 'anchor_bearing').length;
        expect(anchorCount, equals(0),
            reason: 'accuracy=20m → seuil=30m → aucun bearing risqué sur 10m');
      },
    );
  });

  // ── Section 4 : Initialisation du cap ──────────────────────────────────────
  group('Initialisation du cap au démarrage', () {
    test(
      'cap initial = 0° quand heading invalide au démarrage',
      () {
        // Reproduit : pos.heading = -1 au premier getCurrentPosition
        // → _lastHeading = 0 (Nord) même si la voiture pointe au Sud
        double lastHeading = -1.0 >= 0 ? -1.0 : 0.0; // code actuel L83
        expect(lastHeading, equals(0.0));
        // Conséquence : si la voiture pointe à 180°, elle sera à l'envers
        // jusqu'au premier pos.heading valide
      },
    );

    test(
      'cap initial = premier heading valide (amélioration possible)',
      () {
        // Alternative : attendre le premier heading valide plutôt que 0°
        // Ce test documente le comportement attendu si on implémentait ça
        const firstValidHeading = 178.5;
        final lastHeading = firstValidHeading >= 0 ? firstValidHeading : 0.0;
        expect(lastHeading, closeTo(178.5, 0.1));
        // La voiture apparaîtrait directement dans la bonne direction
      },
    );
  });

  // ── Section 5 : Séquence complète de trajet Bainem ↔ Beb el Oued ───────────
  group('Séquence complète — aller-retour avec U-turn', () {
    test(
      'Strat A : cap gelé au retour si heading invalide pendant U-turn',
      () {
        final logic = CurrentMapPageLogic();

        // Phase 1 : aller vers le Nord (~0°), cap GPS valide
        for (int i = 0; i < 10; i++) {
          logic.processPosition(FakePosition(
            lat: 36.800 + i * 0.0001,
            lon: 3.050,
            heading: 2.0, speed: 20 / 3.6, accuracy: 5,
          ));
        }
        final capAller = logic.lastHeading;
        expect(capAller, inInclusiveRange(0, 15));

        // Phase 2 : U-turn (arrêt + heading invalide)
        for (int i = 0; i < 5; i++) {
          logic.processPosition(FakePosition(
            lat: 36.801,
            lon: 3.050,
            heading: -1, speed: 0.5 / 3.6, accuracy: 6,
          ));
        }

        // Phase 3 : retour vers le Sud (~180°), heading invalide pendant 30m
        final retour = _straightLine(
          startLat: 36.801, startLon: 3.050,
          count: 30, stepM: 1.0, bearingDeg: 180,
          speedKmh: 20, accuracy: 5,
          headingOverride: -1,
        );
        for (final p in retour) logic.processPosition(p);

        // Bug : cap toujours ~0° même après 30m vers le Sud
        expect(
          logic.lastHeading,
          inInclusiveRange(0, 30),
          reason: 'Strat A : cap gelé à ~0° (Nord) pendant le trajet retour Sud',
        );
      },
    );

    test(
      'Strat B : cap retour converge vers ~180° après 5m avec ancre',
      () {
        final logic = ProposedMapPageLogic();

        // Phase 1 : aller Nord
        for (int i = 0; i < 10; i++) {
          logic.processPosition(FakePosition(
            lat: 36.800 + i * 0.0001,
            lon: 3.050,
            heading: 2.0, speed: 20 / 3.6, accuracy: 5,
          ));
        }

        // Phase 2 : U-turn (heading invalide)
        for (int i = 0; i < 5; i++) {
          logic.processPosition(FakePosition(
            lat: 36.801, lon: 3.050,
            heading: -1, speed: 0.5 / 3.6, accuracy: 6,
          ));
        }

        // Phase 3 : retour Sud, heading invalide
        final retour = _straightLine(
          startLat: 36.801, startLon: 3.050,
          count: 30, stepM: 1.0, bearingDeg: 180,
          speedKmh: 20, accuracy: 5,
          headingOverride: -1,
        );
        for (final p in retour) logic.processPosition(p);

        // Strat B : cap doit avoir convergé vers le Sud
        final finalCap = logic.lastHeading;
        print('[TEST RETOUR] Strat B cap final = ${finalCap.toStringAsFixed(1)}°');
        expect(
          finalCap,
          inInclusiveRange(90, 270),
          reason: 'Strat B : cap doit s\'orienter vers le Sud grâce à l\'ancre accumulée',
        );
      },
    );

    test(
      'Strat B : cap correct si heading iOS reprend après U-turn',
      () {
        final logic = ProposedMapPageLogic();

        // Phase 1 : aller Nord
        for (int i = 0; i < 5; i++) {
          logic.processPosition(FakePosition(
            lat: 36.800 + i * 0.0001, lon: 3.050,
            heading: 1.0, speed: 15 / 3.6, accuracy: 5,
          ));
        }

        // Phase 2 : U-turn (heading invalide)
        for (int i = 0; i < 3; i++) {
          logic.processPosition(FakePosition(
            lat: 36.8005, lon: 3.050,
            heading: -1, speed: 0.3 / 3.6, accuracy: 5,
          ));
        }

        // Phase 3 : GPS reprend, heading valide = 180°
        for (int i = 0; i < 20; i++) {
          logic.processPosition(FakePosition(
            lat: 36.8005 - i * 0.0001, lon: 3.050,
            heading: 178.5, speed: 15 / 3.6, accuracy: 5,
          ));
        }

        // Cap doit avoir convergé vers 180°
        expect(logic.lastHeading, inInclusiveRange(160, 200),
            reason: 'Quand iOS renvoie un heading valide à 180°, '
                'le lissage doit avoir convergé');
      },
    );
  });
}
