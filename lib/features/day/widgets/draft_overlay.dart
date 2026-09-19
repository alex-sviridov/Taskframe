import 'package:flutter/material.dart';
import 'package:taskframe/features/day/models/time_object.dart';
import 'package:taskframe/features/day/widgets/block_kind_style.dart';
import 'package:taskframe/features/day/widgets/day_grid_painters.dart';

/// The draft prompt shown while placing a new block: a plain gray,
/// dashed-outline box sized to the block's real duration, with two
/// fixed-size icon buttons centered on it, one per kind of block it can
/// create.
///
/// The buttons stay full-size even when the box itself (a 15-minute slot,
/// say) is too short to contain them — they overflow past its edges rather
/// than shrinking or being clipped.
class DraftOverlay extends StatelessWidget {
  /// Creates a [DraftOverlay] with its two create-block callbacks.
  const new({
    required this.onCreateEvent,
    required this.onCreateFrame,
    super.key,
  });

  /// Called when the "Create Event" button is tapped.
  final VoidCallback onCreateEvent;

  /// Called when the "Create Frame" button is tapped.
  final VoidCallback onCreateFrame;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: const DashedBorderPainter(color: Colors.grey),
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
                  color: BlockKind.frame.color,
                  icon: BlockKind.frame.icon,
                  label: 'Create Frame',
                  onTap: onCreateFrame,
                ),
                const SizedBox(width: 8),
                _DraftButton(
                  color: BlockKind.anchor.color,
                  icon: BlockKind.anchor.icon,
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

/// One fixed-size, colored icon button on the [DraftOverlay].
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
