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
