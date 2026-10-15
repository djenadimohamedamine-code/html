import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimo_spark/core/vehicle_marker_heading.dart';

void main() {
  testWidgets('Real Spark photo marker has a transparent PNG background', (tester) async {
    // Prevent an opaque checkerboard JPG-in-PNG from being displayed over the map.
    final data = await rootBundle.load('assets/images/Adobe Express - file.png');
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    expect(pixels, isNotNull);

    final bytes = pixels!;
    final width = image.width;
    final height = image.height;
    // The four corners should be genuinely transparent, not a fake checkerboard.
    for (final point in <(int, int)>[
      (0, 0),
      (width - 1, 0),
      (0, height - 1),
      (width - 1, height - 1),
    ]) {
      final alpha = bytes.getUint8((point.$2 * width + point.$1) * 4 + 3);
      expect(alpha, lessThan(16), reason: 'Sprite corner must have true alpha');
    }
    image.dispose();
    codec.dispose();
  });

  group('Chevrolet Spark car marker orientation', () {
    test('car nose follows cardinal GPS headings with one sprite offset', () {
      expect(VehicleMarkerHeading.rotationDegrees(0), closeTo(65, 0.001));
      expect(VehicleMarkerHeading.rotationDegrees(90), closeTo(155, 0.001));
      expect(VehicleMarkerHeading.rotationDegrees(180), closeTo(245, 0.001));
      expect(VehicleMarkerHeading.rotationDegrees(270), closeTo(335, 0.001));
    });

    test('wrap around heading 359 to 0 without flipping 180 degrees', () {
      expect(VehicleMarkerHeading.rotationDegrees(359), closeTo(64, 0.001));
      expect(VehicleMarkerHeading.rotationDegrees(0), closeTo(65, 0.001));
      expect(VehicleMarkerHeading.rotationDegrees(360), closeTo(65, 0.001));
    });

    test('normalizes negative bearings to the same direction', () {
      expect(VehicleMarkerHeading.rotationDegrees(-10), closeTo(55, 0.001));
      expect(VehicleMarkerHeading.rotationDegrees(350), closeTo(55, 0.001));
    });

    test('returns an angle in radians for Flutter Transform.rotate', () {
      expect(
        VehicleMarkerHeading.rotationRadians(0),
        closeTo(65 * 3.141592653589793 / 180, 0.000001),
      );
    });
  });
}
