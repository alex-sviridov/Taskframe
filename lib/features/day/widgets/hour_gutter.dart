import 'package:flutter/material.dart';
import 'package:taskframe/features/day/day_settings.dart';

/// The hour-label column shown once, to the left of every day column, when
/// multiple days share one page (week view). Draws only the hour labels
/// that `DayGrid` would otherwise draw itself in single-day mode.
class HourGutter extends StatelessWidget {
  const new({required this.settings, required this.slotHeight, super.key});

  /// Matches `DayGrid`'s own label-gutter width, so day columns' grid
  /// lines still start at the same x whether or not they draw their own
  /// labels.
  static const double width = 34.0;

  final DaySettings settings;
  final double slotHeight;

  @override
  Widget build(BuildContext context) {
    final slotCount = (settings.dayEndHour - settings.dayStartHour) * 4;
    return SizedBox(
      width: width,
      height: slotCount * slotHeight,
      child: CustomPaint(
        painter: _HourGutterPainter(
          settings: settings,
          slotHeight: slotHeight,
          labelStyle: Theme.of(context).textTheme.labelSmall,
        ),
      ),
    );
  }
}

class _HourGutterPainter extends CustomPainter {
  const new({
    required this.settings,
    required this.slotHeight,
    required this.labelStyle,
  });

  final DaySettings settings;
  final double slotHeight;
  final TextStyle? labelStyle;

  static const double _labelLeft = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final totalHours = settings.dayEndHour - settings.dayStartHour;
    for (var hour = 0; hour <= totalHours; hour++) {
      final labelHour = settings.dayStartHour + hour;
      if (!labelHour.isEven) continue;

      final y = hour * 4 * slotHeight;
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

  @override
  bool shouldRepaint(covariant _HourGutterPainter oldDelegate) =>
      oldDelegate.settings != settings ||
      oldDelegate.slotHeight != slotHeight ||
      oldDelegate.labelStyle != labelStyle;
}
