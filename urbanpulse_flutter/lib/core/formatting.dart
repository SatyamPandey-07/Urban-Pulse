// Small formatting helpers that stand in for the `String.format(Locale.US, …)`
// patterns used throughout the Kotlin source. Kept here (rather than pulling in
// `intl`) because the app only needs grouped integers and fixed decimals.

/// `1234567` -> `"1,234,567"`, matching Kotlin's `%,d`.
String grouped(num value) {
  final negative = value < 0;
  final digits = value.abs().round().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return negative ? '-$buffer' : buffer.toString();
}

/// `"₹4,200"` — the rupee amounts rendered all over the original UI.
String rupees(num value) => '₹${grouped(value)}';

/// Kotlin's `%.<n>f`.
String fixed(num value, [int digits = 1]) => value.toStringAsFixed(digits);

extension NumClamp on double {
  double coerceAtLeast(double min) => this < min ? min : this;

  double coerceAtMost(double max) => this > max ? max : this;
}

extension IntClamp on int {
  int coerceAtLeast(int min) => this < min ? min : this;
}

const _monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', //
  'Dec',
];
const _weekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// `"Sat, 12 Oct"`.
String shortDate(DateTime d) =>
    '${_weekdayNames[d.weekday - 1]}, ${d.day} ${_monthNames[d.month - 1]}';

/// `"9:30 AM"`.
String clock12(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  return '$h:$m ${d.hour < 12 ? 'AM' : 'PM'}';
}

/// `"12 Oct – 15 Oct 2026"` for trip cards.
String dateRangeLabel(DateTime a, DateTime b) {
  String d(DateTime x) => '${x.day} ${_monthNames[x.month - 1]}';
  return a.year == b.year
      ? '${d(a)} – ${d(b)} ${b.year}'
      : '${d(a)} ${a.year} – ${d(b)} ${b.year}';
}

/// `"450 m"`, `"2.4 km"`, `"38 km"`: a distance a person reads on a map.
String distanceLabel(num meters) {
  if (!meters.isFinite || meters < 0) return '';
  if (meters < 950) {
    final tens = (meters / 10).round() * 10;
    return '${tens == 0 ? meters.round() : tens} m';
  }
  final km = meters / 1000;
  return km < 10 ? '${km.toStringAsFixed(1)} km' : '${km.round()} km';
}

/// `"7 min"`, `"1 h 5 min"`, `"2 h"`.
String minutesLabel(int minutes) {
  if (minutes < 1) return '1 min';
  if (minutes < 60) return '$minutes min';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '$h h' : '$h h $m min';
}
