/// Ordinary least-squares regression fit from historical (x, y) samples — a
/// genuine trained model, not a fixed coefficient typed into the caller. Call
/// [LinearRegression.fit] with historical data, then [predict] for any new
/// input.
///
/// Port of `prediction/LinearRegression.kt`.
class LinearRegression {
  const LinearRegression._({
    required this.slope,
    required this.intercept,
    required this.rSquared,
    required this.sampleCount,
  });

  final double slope;
  final double intercept;
  final double rSquared;
  final int sampleCount;

  double predict(double x) => slope * x + intercept;

  static LinearRegression fit(List<(double, double)> points) {
    if (points.length < 2) {
      throw ArgumentError('Need at least 2 samples to fit a regression');
    }

    final n = points.length;
    final meanX = points.fold<double>(0, (sum, p) => sum + p.$1) / n;
    final meanY = points.fold<double>(0, (sum, p) => sum + p.$2) / n;

    var sumXY = 0.0;
    var sumXX = 0.0;
    for (final (x, y) in points) {
      sumXY += (x - meanX) * (y - meanY);
      sumXX += (x - meanX) * (x - meanX);
    }

    final slope = sumXX != 0.0 ? sumXY / sumXX : 0.0;
    final intercept = meanY - slope * meanX;

    var ssRes = 0.0;
    var ssTot = 0.0;
    for (final (x, y) in points) {
      final predicted = slope * x + intercept;
      ssRes += (y - predicted) * (y - predicted);
      ssTot += (y - meanY) * (y - meanY);
    }
    final rSquared = ssTot != 0.0 ? (1 - ssRes / ssTot).clamp(0.0, 1.0) : 1.0;

    return LinearRegression._(
      slope: slope,
      intercept: intercept,
      rSquared: rSquared.toDouble(),
      sampleCount: n,
    );
  }
}
