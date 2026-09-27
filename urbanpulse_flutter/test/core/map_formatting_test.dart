import 'package:flutter_test/flutter_test.dart';
import 'package:urbanpulse/core/formatting.dart';

void main() {
  test('distances read like a map', () {
    expect(distanceLabel(0), '0 m');
    expect(distanceLabel(4), '4 m');
    expect(distanceLabel(48), '50 m');
    expect(distanceLabel(452), '450 m');
    expect(distanceLabel(949), '950 m');
    expect(distanceLabel(1000), '1.0 km');
    expect(distanceLabel(2440), '2.4 km');
    expect(distanceLabel(38400), '38 km');
    expect(distanceLabel(double.nan), '');
    expect(distanceLabel(-5), '');
  });

  test('durations read like a map', () {
    expect(minutesLabel(0), '1 min');
    expect(minutesLabel(7), '7 min');
    expect(minutesLabel(60), '1 h');
    expect(minutesLabel(65), '1 h 5 min');
    expect(minutesLabel(190), '3 h 10 min');
  });
}
