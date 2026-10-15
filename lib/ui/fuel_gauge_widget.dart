import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';

/// Widget réutilisable de jauge de carburant Spark
/// Fonctionne en 2 modes :
/// 1. Mode Display (Dashboard principal) : Lecture seule, aiguille animée avec la valeur réelle
/// 2. Mode Calibration (Sous-menu calibrage) : Aiguille déplaçable (draggable) pour ajuster manuellement
///
/// Image source : 04.png (1254x1254 px, jauge isolée sur fond noir)
/// Analyse géométrique (pixel) :
///   Hub mécanique  : (647, 688) px → centerX=0.516, centerY=0.549
///   Repère E       : startAngle=226° (SfRadialGauge, 0=droite, CW)
///   Repère F       : endAngle=308°
///   needleLength   : 0.75 (calibré visuellement sur l'arc photographié)
class FuelGaugeWidget extends StatelessWidget {
  final double fuelLiters;
  final bool isDraggable;
  final double size;
  final ValueChanged<double>? onValueChanged;
  final VoidCallback? onTap;
  final bool showGlow;

  const FuelGaugeWidget({
    super.key,
    required this.fuelLiters,
    this.isDraggable = false,
    this.size = 240,
    this.onValueChanged,
    this.onTap,
    this.showGlow = true,
  });

  @override
  Widget build(BuildContext context) {
    final double clampedFuel = fuelLiters.clamp(0.0, 35.0);
    // Facteur d'échelle pour adapter la largeur des traits de l'aiguille à la taille du widget
    final double scale = size / 240.0;

    Widget gauge = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isDraggable ? Colors.orangeAccent.withOpacity(0.7) : Colors.transparent,
          width: isDraggable ? 2.5 : 0,
        ),
        boxShadow: showGlow
            ? [
                BoxShadow(
                  color: Colors.orangeAccent.withOpacity(0.18),
                  blurRadius: 18 * scale,
                  spreadRadius: 2 * scale,
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.6),
                  blurRadius: 10 * scale,
                ),
              ]
            : null,
        // Image 04.png : jauge carburant Chevrolet Spark, 1254x1254px,
        // parfaitement circulaire sur fond noir. BoxFit.cover remplit le
        // cercle Flutter sans déformer l'image (carré → cercle = clip naturel).
        image: const DecorationImage(
          image: AssetImage('assets/images/ta.png'),
          fit: BoxFit.cover,
        ),
      ),
      child: SfRadialGauge(
        axes: <RadialAxis>[
          RadialAxis(
            minimum: 0,
            maximum: 35,
            // Angles mesurés depuis le pixel-hub sur 04.png :
            //   E (repère rouge) → startAngle ≈ 226°
            //   F (plein)        → endAngle   ≈ 308°
            // Convention SfRadialGauge : 0° = droite (3h), positif = horaire (CW)
            startAngle: 226,
            endAngle: 308,
            showLabels: false,
            showTicks: false,
            // Hub mesuré en pixels : (647, 688) sur image 1254x1254
            //   centerX = 647/1254 = 0.516
            //   centerY = 688/1254 = 0.549
            centerX: 0.516,
            centerY: 0.549,
            axisLineStyle: const AxisLineStyle(thickness: 0, color: Colors.transparent),
            pointers: <GaugePointer>[
              NeedlePointer(
                value: clampedFuel,
                needleColor: const Color(0xFFFF7700),
                tailStyle: const TailStyle(length: 0, width: 0),
                needleStartWidth: (1.2 * scale).clamp(1.0, 2.0),
                needleEndWidth: (5.5 * scale).clamp(2.5, 5.5),
                // needleLength calibré pour que la pointe atteigne les tirets de l'arc
                needleLength: 0.75,
                // knobRadius = 0 : le vrai moyeu photographié est visible dans 04.png,
                // aucun disque artificiel ne doit le masquer.
                knobStyle: const KnobStyle(
                  color: Colors.transparent,
                  knobRadius: 0,
                  borderWidth: 0,
                  borderColor: Colors.transparent,
                ),
                enableAnimation: !isDraggable,
                animationDuration: 1000,
                animationType: AnimationType.easeOutBack,
                enableDragging: isDraggable,
                onValueChanged: (val) {
                  if (isDraggable && onValueChanged != null) {
                    onValueChanged!(val.clamp(0.0, 35.0));
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );

    if (onTap != null && !isDraggable) {
      return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: gauge,
      );
    }

    return gauge;
  }
}
