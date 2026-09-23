import 'package:flutter/material.dart';

/// How far a drag must travel before release triggers a swipe action,
/// rather than snapping back with nothing happening.
const _swipeThreshold = 96.0;

/// The distance the card is allowed to travel past the threshold before
/// resisting further drag, so a long drag doesn't reveal an unbounded gap.
const _maxDragExtent = 140.0;

/// Wraps [child] in a horizontally draggable card that reveals a colored,
/// icon-labeled strip behind it as it's dragged, and fires [onSwipeLeft] or
/// [onSwipeRight] when released past the swipe threshold — then always
/// snaps back to its resting position, since this never removes [child]
/// from the tree (unlike [Dismissible]).
///
/// Passing `null` for either callback disables dragging in that direction
/// entirely, so the card doesn't move or reveal a background for it.
class SwipeActionCard extends StatefulWidget {
  /// Creates a [SwipeActionCard] around [child].
  const new({
    required this.child,
    this.onSwipeLeft,
    this.onSwipeRight,
    this.leftIcon = Icons.chevron_left,
    this.rightIcon = Icons.chevron_right,
    this.backgroundColor,
    super.key,
  });

  /// The card's content.
  final Widget child;

  /// Called when the card is swiped left past the threshold. `null`
  /// disables leftward dragging.
  final VoidCallback? onSwipeLeft;

  /// Called when the card is swiped right past the threshold. `null`
  /// disables rightward dragging.
  final VoidCallback? onSwipeRight;

  /// Icon shown in the background revealed by a leftward drag.
  final IconData leftIcon;

  /// Icon shown in the background revealed by a rightward drag.
  final IconData rightIcon;

  /// Color of the revealed background strip. Defaults to the theme's
  /// `secondaryContainer`.
  final Color? backgroundColor;

  @override
  State<SwipeActionCard> createState() => _SwipeActionCardState();
}

class _SwipeActionCardState extends State<SwipeActionCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _snapBack = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );
  double _dragExtent = 0;

  bool get _canSwipeLeft => widget.onSwipeLeft != null;
  bool get _canSwipeRight => widget.onSwipeRight != null;

  @override
  void dispose() {
    _snapBack.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    var next = _dragExtent + details.primaryDelta!;
    if (next > 0 && !_canSwipeRight) next = 0;
    if (next < 0 && !_canSwipeLeft) next = 0;
    next = next.clamp(-_maxDragExtent, _maxDragExtent);
    setState(() => _dragExtent = next);
  }

  void _onDragEnd(DragEndDetails details) {
    if (_dragExtent >= _swipeThreshold && _canSwipeRight) {
      widget.onSwipeRight!();
    } else if (_dragExtent <= -_swipeThreshold && _canSwipeLeft) {
      widget.onSwipeLeft!();
    }
    _animateBackToRest();
  }

  void _animateBackToRest() {
    final start = _dragExtent;
    _snapBack
      ..reset()
      ..addListener(() {
        setState(() => _dragExtent = start * (1 - _snapBack.value));
      })
      ..forward();
  }

  @override
  Widget build(BuildContext context) {
    if (!_canSwipeLeft && !_canSwipeRight) return widget.child;

    final theme = Theme.of(context);
    final background =
        widget.backgroundColor ?? theme.colorScheme.secondaryContainer;
    final showingRight = _dragExtent > 0;

    return GestureDetector(
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      child: Stack(
        alignment: showingRight ? Alignment.centerLeft : Alignment.centerRight,
        children: [
          if (_dragExtent != 0)
            Container(
              color: background,
              alignment: showingRight
                  ? Alignment.centerLeft
                  : Alignment.centerRight,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Icon(showingRight ? widget.rightIcon : widget.leftIcon),
            ),
          Transform.translate(
            offset: Offset(_dragExtent, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}
