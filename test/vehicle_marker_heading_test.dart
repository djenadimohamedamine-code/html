import 'package:flutter_test/flutter_test.dart';
import 'package:mimo_spark/core/vehicle_marker_heading.dart';

void main() {
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
