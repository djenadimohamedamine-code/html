import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';

/// Widget réutilisable de jauge de carburant Spark
/// Fonctionne en 2 modes :
/// 1. Mode Display (Dashboard principal) : Lecture seule, aiguille animée avec la valeur réelle
/// 2. Mode Calibration (Sous-menu calibrage) : Aiguille déplaçable (draggable) pour ajuster manuellement
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
          color: isDraggable ? Colors.orangeAccent.withOpacity(0.6) : Colors.white24,
          width: isDraggable ? 2.5 : 1.5,
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
        image: const DecorationImage(
          image: AssetImage('assets/images/ta.jpeg'),
          fit: BoxFit.cover,
        ),
      ),
      child: SfRadialGauge(
        axes: <RadialAxis>[
          RadialAxis(
            minimum: 0,
            maximum: 35,
            startAngle: 215,
            endAngle: 315, // Calibrage optimal pour Spark : E = 215° / F = 315°
            showLabels: false,
            showTicks: false,
            axisLineStyle: const AxisLineStyle(thickness: 0, color: Colors.transparent),
            pointers: <GaugePointer>[
              NeedlePointer(
                value: clampedFuel,
                needleColor: Colors.orangeAccent,
                tailStyle: TailStyle(
                  width: (8 * scale).clamp(3.0, 8.0),
                  color: Colors.orangeAccent,
                ),
                needleStartWidth: (1 * scale).clamp(0.8, 1.5),
                needleEndWidth: (7 * scale).clamp(3.0, 7.0),
                needleLength: 0.85,
                knobStyle: KnobStyle(
                  color: Colors.white,
                  knobRadius: 0.12,
                  borderColor: Colors.black45,
                  borderWidth: (2 * scale).clamp(1.0, 2.0),
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
