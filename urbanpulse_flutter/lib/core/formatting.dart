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

/// `"Fri 25 Sep"` — no comma, for the places that count characters (the watch).
String compactDate(DateTime d) =>
    '${_weekdayNames[d.weekday - 1]} ${d.day} ${_monthNames[d.month - 1]}';

/// `"09:30"` — 24-hour, fixed width, which is what fits on a watch row.
String clock24(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

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
