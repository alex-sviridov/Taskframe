import 'dart:async';

import 'package:flutter/material.dart';
import 'package:taskframe/features/day/day_new_block.dart';
import 'package:taskframe/features/day/day_settings.dart';
import 'package:taskframe/features/day/models/time_object.dart';
import 'package:taskframe/features/day/widgets/block_view.dart';

/// The 15-minute-aligned timeline: an hour grid with [blocks] drawn on top.
///
/// Double-tapping (desktop) or long-pressing (touch) free grid space opens a
/// draft for a new block there; tapping one of [_DraftOverlay]'s two icon
/// buttons creates it via [onCreateBlock], and tapping elsewhere dismisses
/// the draft.
class DayGrid extends StatefulWidget {
  /// Creates a [DayGrid] showing [blocks] between [settings]'s day start
  /// and day end, with each 15-minute slot [slotHeight] pixels tall.
  const new({
    required this.date,
    required this.blocks,
    required this.settings,
    required this.slotHeight,
    required this.onCreateBlock,
    this.showHourLabels = true,
    this.onSwipeStart,
    this.onSwipeUpdate,
    this.onSwipeEnd,
    this.onSwipeCancel,
    super.key,
  });

  /// The date this grid shows, used to resolve tap positions into times.
  final DateTime date;

  /// The blocks to draw on the grid.
  final List<TimeObject> blocks;

  /// The grid's visible start/end hours.
  final DaySettings settings;

  /// Pixel height of a single 15-minute slot.
  final double slotHeight;

  /// Whether this grid draws its own hour-label gutter on the left.
  ///
  /// `false` in week view, where a single `HourGutter` draws the labels
  /// once for all day columns; this grid still draws its own horizontal
  /// gridlines regardless.
  final bool showHourLabels;

  /// Called when the user confirms a new block from the draft.
  final void Function({
    required DateTime start,
    required DateTime end,
    required BlockKind kind,
  })
  onCreateBlock;

  /// Forwarded from a horizontal drag that starts on free grid space (not
  /// on a block), so the caller can drive its own day-switching animation
  /// finger-tracked. `null` disables day-switching entirely.
  final GestureDragStartCallback? onSwipeStart;

  /// See [onSwipeStart].
  final GestureDragUpdateCallback? onSwipeUpdate;

  /// See [onSwipeStart].
  final GestureDragEndCallback? onSwipeEnd;

  /// See [onSwipeStart].
  final VoidCallback? onSwipeCancel;

  @override
  State<DayGrid> createState() => _DayGridState();
}

class _DayGridState extends State<DayGrid> {
  ({DateTime start, DateTime end})? _draft;
  Timer? _nowTimer;

  @override
  void initState() {
    super.initState();
    _scheduleNowTimer();
  }

  @override
  void didUpdateWidget(DayGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.date != widget.date) {
      _scheduleNowTimer();
    }
  }

  @override
  void dispose() {
    _nowTimer?.cancel();
    super.dispose();
  }

  /// Redraws once a minute while [widget.date] is today, so the
  /// current-time marker line keeps moving; does nothing otherwise.
  void _scheduleNowTimer() {
    _nowTimer?.cancel();
    _nowTimer = _isToday
        ? Timer.periodic(const Duration(minutes: 1), (_) => setState(() {}))
        : null;
  }

  bool get _isToday {
    final now = DateTime.now();
    return widget.date.year == now.year &&
        widget.date.month == now.month &&
        widget.date.day == now.day;
  }

  int get _slotCount =>
      (widget.settings.dayEndHour - widget.settings.dayStartHour) * 4;

  double get _dayStartInMinutes => widget.settings.dayStartHour * 60;

  double get _gridLeft => widget.showHourLabels ? 44 : 4;

  double _offsetFor(DateTime time) {
    final minutesFromStart = time.hour * 60 + time.minute - _dayStartInMinutes;
    return minutesFromStart / 15 * widget.slotHeight;
  }

  void _openDraftAt(double dy) {
    final start = slotStartForOffset(
      day: widget.date,
      dy: dy,
      settings: widget.settings,
      slotHeight: widget.slotHeight,
    );
    if (start == null) return;

    final duration = durationForNewBlock(
      slotStart: start,
      existingBlocks: widget.blocks,
    );
    setState(() => _draft = (start: start, end: start.add(duration)));
  }

  void _dismissDraft() {
    if (_draft != null) {
      setState(() => _draft = null);
    }
  }

  void _create(BlockKind kind) {
    final draft = _draft!;
    widget.onCreateBlock(start: draft.start, end: draft.end, kind: kind);
    setState(() => _draft = null);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final height = _slotCount * widget.slotHeight;
    final draft = _draft;
    final nowOffset = _isToday ? _offsetFor(DateTime.now()) : null;
    final nowLineY = nowOffset != null && nowOffset >= 0 && nowOffset <= height
        ? nowOffset
        : null;

    return SizedBox(
      height: height,
      child: Stack(
        children: [
          Positioned.fill(
            // Only the background layer reacts to gestures: blocks (and the
            // draft overlay) are drawn above it in this Stack and, being
            // opaque, absorb touches that start on them before they ever
            // reach this GestureDetector.
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _dismissDraft,
              onDoubleTapDown: (details) =>
                  _openDraftAt(details.localPosition.dy),
              onLongPressStart: (details) =>
                  _openDraftAt(details.localPosition.dy),
              onHorizontalDragStart: widget.onSwipeStart,
              onHorizontalDragUpdate: widget.onSwipeUpdate,
              onHorizontalDragEnd: widget.onSwipeEnd,
              onHorizontalDragCancel: widget.onSwipeCancel,
              child: CustomPaint(
                painter: _DayGridPainter(
                  settings: widget.settings,
                  slotHeight: widget.slotHeight,
                  lineColor: scheme.outlineVariant,
                  labelStyle: Theme.of(context).textTheme.labelSmall,
                  gridLeft: _gridLeft,
                  showLabels: widget.showHourLabels,
                  nowLineY: nowLineY,
                ),
              ),
            ),
          ),
          for (final block in widget.blocks)
            Positioned(
              top: _offsetFor(block.start),
              left: _gridLeft,
              right: 0,
              height: _offsetFor(block.end) - _offsetFor(block.start),
              child: BlockView(block: block),
            ),
          if (draft != null)
            Positioned(
              top: _offsetFor(draft.start),
              left: _gridLeft,
              right: 0,
              height: _offsetFor(draft.end) - _offsetFor(draft.start),
              child: _DraftOverlay(
                onCreateEvent: () => _create(BlockKind.anchor),
                onCreateFrame: () => _create(BlockKind.frame),
              ),
            ),
        ],
      ),
    );
  }
}

/// The draft prompt shown while placing a new block: a plain gray,
/// dashed-outline box sized to the block's real duration, with two
/// fixed-size icon buttons centered on it, one per kind of block it can
/// create.
///
/// The buttons stay full-size even when the box itself (a 15-minute slot,
/// say) is too short to contain them — they overflow past its edges rather
/// than shrinking or being clipped.
class _DraftOverlay extends StatelessWidget {
  const new({required this.onCreateEvent, required this.onCreateFrame});

  final VoidCallback onCreateEvent;
  final VoidCallback onCreateFrame;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: const _DashedBorderPainter(color: Colors.grey),
            child: ColoredBox(color: Colors.grey.withValues(alpha: 0.2)),
          ),
        ),
        Center(
          child: OverflowBox(
            minHeight: 0,
            maxHeight: double.infinity,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _DraftButton(
                  color: Colors.blue,
                  icon: Icons.crop_free,
                  label: 'Create Frame',
                  onTap: onCreateFrame,
                ),
                const SizedBox(width: 8),
                _DraftButton(
                  color: Colors.red,
                  icon: Icons.event,
                  label: 'Create Event',
                  onTap: onCreateEvent,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One fixed-size, colored icon button on the [_DraftOverlay].
class _DraftButton extends StatelessWidget {
  const new({
    required this.color,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  static const double _size = 28;

  final Color color;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: SizedBox.square(
        dimension: _size,
        child: Material(
          color: color,
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: onTap,
            child: Center(child: Icon(icon, color: Colors.white, size: 16)),
          ),
        ),
      ),
    );
  }
}

/// Paints a dashed rectangle outline around its bounds.
class _DashedBorderPainter extends CustomPainter {
  const new({required this.color});

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
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _DayGridPainter extends CustomPainter {
  const new({
    required this.settings,
    required this.slotHeight,
    required this.lineColor,
    required this.labelStyle,
    required this.gridLeft,
    required this.showLabels,
    required this.nowLineY,
  });

  final DaySettings settings;
  final double slotHeight;
  final Color lineColor;
  final TextStyle? labelStyle;
  final double gridLeft;
  final bool showLabels;

  /// Pixel y-offset of the current-time marker line, or `null` to hide it
  /// (not today, or the current time falls outside the visible hours).
  final double? nowLineY;

  static const double _labelLeft = 4;
  static const Color _nowLineColor = Color(0xFF8B0000);

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

    final markerY = nowLineY;
    if (markerY != null) {
      final nowPaint = Paint()
        ..color = _nowLineColor
        ..strokeWidth = 2;
      canvas
        ..drawLine(Offset(0, markerY), Offset(size.width, markerY), nowPaint)
        ..drawCircle(Offset(0, markerY), 3, nowPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _DayGridPainter oldDelegate) =>
      oldDelegate.settings != settings ||
      oldDelegate.slotHeight != slotHeight ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.labelStyle != labelStyle ||
      oldDelegate.gridLeft != gridLeft ||
      oldDelegate.showLabels != showLabels ||
      oldDelegate.nowLineY != nowLineY;
}
