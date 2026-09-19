import 'package:flutter/material.dart';
import 'package:taskframe/features/day/day_settings.dart';

/// Paints a dashed rectangle outline around its bounds.
class DashedBorderPainter extends CustomPainter {
  /// Creates a [DashedBorderPainter] drawing its dashes in [color].
  const new({required this.color});

  /// The dashed outline's stroke color.
  final Color color;

  static const double _dashWidth = 4;
  static const double _dashGap = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final outline = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    for (final metric in outline.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + _dashWidth;
        canvas.drawPath(
          metric.extractPath(distance, next.clamp(0, metric.length)),
          paint,
        );
        distance = next + _dashGap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Paints the day grid's hour/quarter-hour lines and (when [showLabels] is
/// true) the hour labels down the left gutter.
class DayGridPainter extends CustomPainter {
  /// Creates a [DayGridPainter] for a day running [settings]'s start/end
  /// hours, each 15-minute slot [slotHeight] pixels tall.
  const new({
    required this.settings,
    required this.slotHeight,
    required this.lineColor,
    required this.labelStyle,
    required this.gridLeft,
    required this.showLabels,
  });

  /// The grid's visible start/end hours.
  final DaySettings settings;

  /// Pixel height of a single 15-minute slot.
  final double slotHeight;

  /// Color of the hour and quarter-hour gridlines.
  final Color lineColor;

  /// Text style for the hour labels, when [showLabels] is true.
  final TextStyle? labelStyle;

  /// Left edge (in local coordinates) the gridlines start drawing from.
  final double gridLeft;

  /// Whether to draw the hour labels down the left gutter.
  final bool showLabels;

  static const double _labelLeft = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final hourPaint = Paint()
      ..color = lineColor
      ..strokeWidth = 1.5;
    final quarterPaint = Paint()
      ..color = lineColor.withValues(alpha: lineColor.a * 0.5)
      ..strokeWidth = 1;

    final totalHours = settings.dayEndHour - settings.dayStartHour;
    for (var hour = 0; hour <= totalHours; hour++) {
      final y = hour * 4 * slotHeight;
      canvas.drawLine(Offset(gridLeft, y), Offset(size.width, y), hourPaint);

      if (hour < totalHours) {
        for (var quarter = 1; quarter < 4; quarter++) {
          final qy = y + quarter * slotHeight;
          canvas.drawLine(
            Offset(gridLeft, qy),
            Offset(size.width, qy),
            quarterPaint,
          );
        }
      }

      if (!showLabels) continue;

      final labelHour = settings.dayStartHour + hour;
      if (labelHour.isEven) {
        final painter = TextPainter(
          text: TextSpan(
            text: '${labelHour.toString().padLeft(2, '0')}:00',
            style: labelStyle,
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final labelY = (y - painter.height / 2).clamp(
          0.0,
          size.height - painter.height,
        );
        painter.paint(canvas, Offset(_labelLeft, labelY));
      }
    }
  }

  @override
  bool shouldRepaint(covariant DayGridPainter oldDelegate) =>
      oldDelegate.settings != settings ||
      oldDelegate.slotHeight != slotHeight ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.labelStyle != labelStyle ||
      oldDelegate.gridLeft != gridLeft ||
      oldDelegate.showLabels != showLabels;
}

/// Draws the current-time marker line above the blocks, so it stays visible
/// even where a block's opaque background would otherwise hide it.
class NowLinePainter extends CustomPainter {
  /// Creates a [NowLinePainter] drawing the marker at vertical offset [y].
  const new({required this.y});

  /// Vertical offset (in local coordinates) of the current-time marker.
  final double y;

  static const Color _color = Color(0xFF8B0000);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _color
      ..strokeWidth = 2;
    canvas
      ..drawLine(Offset(0, y), Offset(size.width, y), paint)
      ..drawCircle(Offset(0, y), 3, paint);
  }

  @override
  bool shouldRepaint(covariant NowLinePainter oldDelegate) =>
      oldDelegate.y != y;
}
