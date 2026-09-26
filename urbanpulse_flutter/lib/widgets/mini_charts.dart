import 'package:flutter/material.dart';

import '../core/app_colors.dart';

/// The Dashboard's two charts, drawn with [CustomPainter].
///
/// The Kotlin app used MPAndroidChart for a seven-point cubic line and a
/// seven-bar column chart with a bottom category axis and a left value axis —
/// little enough that Flutter's own painting API covers it without a charting
/// dependency.

const _axisColor = AppColors.surfaceBorder;
const _labelColor = AppColors.textSecondary;
const _gridColor = AppColors.surfaceDark;
const _labelStyle = TextStyle(
  color: _labelColor,
  fontSize: 10,
  fontWeight: FontWeight.w600,
);

/// Cubic-bezier trend line with circular data points — the "Air Quality Trend
/// (7 Days)" card.
class TrendLineChart extends StatelessWidget {
  const TrendLineChart({
    required this.values,
    required this.labels,
    this.lineColor = AppColors.primaryBlue,
    this.height = 180,
    this.minCeiling,
    super.key,
  });

  final List<double> values;
  final List<String> labels;
  final Color lineColor;
  final double height;
  final double? minCeiling;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    width: double.infinity,
    child: CustomPaint(
      painter: _LineChartPainter(
        values: values,
        labels: labels,
        lineColor: lineColor,
        holeColor: Theme.of(context).colorScheme.surface,
        minCeiling: minCeiling,
      ),
    ),
  );
}

/// Vertical bars with a category axis — the "12h Traffic Forecast" card.
class ForecastBarChart extends StatelessWidget {
  const ForecastBarChart({
    required this.values,
    required this.labels,
    this.barColor = AppColors.primaryGreen,
    this.height = 180,
    super.key,
  });

  final List<double> values;
  final List<String> labels;
  final Color barColor;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    width: double.infinity,
    child: CustomPaint(
      painter: _BarChartPainter(
        values: values,
        labels: labels,
        barColor: barColor,
      ),
    ),
  );
}

/// Shared axis geometry: reserves gutters for the tick labels and maps values
/// into the remaining plot rectangle.
class _ChartGeometry {
  _ChartGeometry(Size size, List<double> values, {double? minCeiling})
    : plot = Rect.fromLTRB(36, 8, size.width - 4, size.height - 20) {
    final maxValue = values.isEmpty
        ? 1.0
        : values.reduce((a, b) => a > b ? a : b);
    final ceiling = minCeiling ?? 1.0;
    // Head-room above the tallest point keeps labels off the top edge.
    top = maxValue <= 0 ? ceiling : (maxValue < ceiling ? ceiling : maxValue * 1.15);
  }

  final Rect plot;
  late final double top;

  double yFor(double value) => plot.bottom - (value / top) * plot.height;
}

void _paintAxes(Canvas canvas, _ChartGeometry geo, {required bool gridLines}) {
  final axisPaint = Paint()
    ..color = _axisColor
    ..strokeWidth = 1;
  canvas.drawLine(geo.plot.bottomLeft, geo.plot.bottomRight, axisPaint);
  canvas.drawLine(geo.plot.topLeft, geo.plot.bottomLeft, axisPaint);

  if (!gridLines) return;
  final gridPaint = Paint()
    ..color = _gridColor
    ..strokeWidth = 1;
  for (var i = 1; i <= 4; i++) {
    final value = geo.top * i / 4;
    final y = geo.yFor(value);
    canvas.drawLine(
      Offset(geo.plot.left, y),
      Offset(geo.plot.right, y),
      gridPaint,
    );
    _paintText(
      canvas,
      value.round().toString(),
      Offset(geo.plot.left - 6, y),
      align: _TextAlign.right,
    );
  }
}

enum _TextAlign { left, center, right }

void _paintText(
  Canvas canvas,
  String text,
  Offset anchor, {
  _TextAlign align = _TextAlign.center,
}) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: _labelStyle),
    textDirection: TextDirection.ltr,
  )..layout();
  final dx = switch (align) {
    _TextAlign.left => anchor.dx,
    _TextAlign.center => anchor.dx - painter.width / 2,
    _TextAlign.right => anchor.dx - painter.width,
  };
  painter.paint(canvas, Offset(dx, anchor.dy - painter.height / 2));
}

/// Places one tick label per category. [slotCentred] aligns them to bar centres
/// (bar chart) rather than to the points themselves (line chart).
void _paintCategoryLabels(
  Canvas canvas,
  _ChartGeometry geo,
  List<String> labels, {
  bool slotCentred = false,
}) {
  if (labels.isEmpty) return;
  for (var i = 0; i < labels.length; i++) {
    final double dx;
    if (slotCentred) {
      dx = geo.plot.left + (geo.plot.width / labels.length) * (i + 0.5);
    } else if (labels.length == 1) {
      dx = geo.plot.center.dx;
    } else {
      dx = geo.plot.left + (geo.plot.width / (labels.length - 1)) * i;
    }
    _paintText(canvas, labels[i], Offset(dx, geo.plot.bottom + 10));
  }
}

class _LineChartPainter extends CustomPainter {
  _LineChartPainter({
    required this.values,
    required this.labels,
    required this.lineColor,
    required this.holeColor,
    this.minCeiling,
  });

  final List<double> values;
  final List<String> labels;
  final Color lineColor;
  final Color holeColor;
  final double? minCeiling;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final geo = _ChartGeometry(size, values, minCeiling: minCeiling);
    _paintAxes(canvas, geo, gridLines: true);
    _paintCategoryLabels(canvas, geo, labels);

    final step = values.length == 1
        ? 0.0
        : geo.plot.width / (values.length - 1);
    final points = <Offset>[
      for (var i = 0; i < values.length; i++)
        Offset(
          values.length == 1 ? geo.plot.center.dx : geo.plot.left + step * i,
          geo.yFor(values[i]),
        ),
    ];

    final linePath = _cubicThrough(points);

    // Draw gradient area under the curve
    final fillPath = Path.from(linePath)
      ..lineTo(points.last.dx, geo.plot.bottom)
      ..lineTo(points.first.dx, geo.plot.bottom)
      ..close();
    final areaPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          lineColor.withValues(alpha: 0.28),
          lineColor.withValues(alpha: 0.02),
        ],
      ).createShader(geo.plot);
    canvas.drawPath(fillPath, areaPaint);

    canvas.drawPath(
      linePath,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );

    final fillPaint = Paint()..color = lineColor;
    final holePaint = Paint()..color = holeColor;
    for (final point in points) {
      canvas.drawCircle(point, 4.5, fillPaint);
      canvas.drawCircle(point, 2.0, holePaint);
    }
  }

  /// Catmull-Rom style smoothing, matching MPAndroidChart's `CUBIC_BEZIER` mode.
  static Path _cubicThrough(List<Offset> points) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    if (points.length < 3) {
      for (final point in points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      return path;
    }
    for (var i = 0; i < points.length - 1; i++) {
      final p0 = i == 0 ? points[i] : points[i - 1];
      final p1 = points[i];
      final p2 = points[i + 1];
      final p3 = i + 2 < points.length ? points[i + 2] : p2;
      path.cubicTo(
        p1.dx + (p2.dx - p0.dx) / 6,
        p1.dy + (p2.dy - p0.dy) / 6,
        p2.dx - (p3.dx - p1.dx) / 6,
        p2.dy - (p3.dy - p1.dy) / 6,
        p2.dx,
        p2.dy,
      );
    }
    return path;
  }

  @override
  bool shouldRepaint(_LineChartPainter old) =>
      old.values != values ||
      old.labels != labels ||
      old.lineColor != lineColor;
}

class _BarChartPainter extends CustomPainter {
  _BarChartPainter({
    required this.values,
    required this.labels,
    required this.barColor,
  });

  final List<double> values;
  final List<String> labels;
  final Color barColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final geo = _ChartGeometry(size, values, minCeiling: 100.0);
    _paintAxes(canvas, geo, gridLines: true);
    _paintCategoryLabels(canvas, geo, labels, slotCentred: true);

    final slot = geo.plot.width / values.length;
    final barWidth = slot * 0.55;

    for (var i = 0; i < values.length; i++) {
      final center = geo.plot.left + slot * (i + 0.5);
      final val = values[i].clamp(0.0, 100.0);
      final rawTop = geo.yFor(val);
      // Give a minimum 12px pill so low congestion / free flow is cleanly visible as healthy flow
      const minHeight = 12.0;
      final top = (geo.plot.bottom - rawTop < minHeight) ? geo.plot.bottom - minHeight : rawTop;
      final rect = Rect.fromLTRB(
        center - barWidth / 2,
        top,
        center + barWidth / 2,
        geo.plot.bottom,
      );

      final barGradient = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            barColor,
            barColor.withValues(alpha: 0.5),
          ],
        ).createShader(rect);

      canvas.drawRRect(
        RRect.fromRectAndCorners(
          rect,
          topLeft: const Radius.circular(5),
          topRight: const Radius.circular(5),
        ),
        barGradient,
      );
    }
  }

  @override
  bool shouldRepaint(_BarChartPainter old) =>
      old.values != values || old.labels != labels || old.barColor != barColor;
}
