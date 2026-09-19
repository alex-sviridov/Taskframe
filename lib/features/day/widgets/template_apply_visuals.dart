import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:taskframe/features/day/template_apply_effects.dart';
import 'package:taskframe/features/day/widgets/day_grid_painters.dart';

/// A short border-color pulse shown around a block just added by applying
/// a template — fades from [ColorScheme.primary] back to nothing over
/// [templateApplyHighlightDuration], then calls [onDone].
class TemplateHighlightPulse extends StatefulWidget {
  /// Creates a [TemplateHighlightPulse] wrapping [child], calling [onDone]
  /// once the pulse finishes.
  const new({required this.onDone, required this.child, super.key});

  /// Called once the pulse animation finishes.
  final VoidCallback onDone;

  /// The block content the pulse is drawn around.
  final Widget child;

  @override
  State<TemplateHighlightPulse> createState() => _TemplateHighlightPulseState();
}

class _TemplateHighlightPulseState extends State<TemplateHighlightPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(
            vsync: this,
            duration: templateApplyHighlightDuration,
          )
          ..addStatusListener(_handleStatus)
          ..forward();
  }

  void _handleStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) widget.onDone();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final opacity = 1 - _controller.value;
        return DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(
              color: color.withValues(alpha: opacity),
              width: 2,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// A brief fading, side-to-side-shaking dashed outline shown at a template
/// event's would-be slot when it was skipped for overlapping an existing
/// block — plays for [templateApplyGhostDuration], then calls [onDone].
class TemplateGhostOverlay extends StatefulWidget {
  /// Creates a [TemplateGhostOverlay], calling [onDone] once its ghost
  /// animation finishes.
  const new({required this.onDone, super.key});

  /// Called once the ghost animation finishes.
  final VoidCallback onDone;

  @override
  State<TemplateGhostOverlay> createState() => _TemplateGhostOverlayState();
}

class _TemplateGhostOverlayState extends State<TemplateGhostOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: templateApplyGhostDuration)
          ..addStatusListener(_handleStatus)
          ..forward();
  }

  void _handleStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) widget.onDone();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.error;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        final opacity = (t < 0.5 ? t * 2 : (1 - t) * 2).clamp(0.0, 1.0);
        final dx = math.sin(t * math.pi * 6) * 4 * (1 - t);
        return Opacity(
          opacity: opacity,
          child: Transform.translate(
            offset: Offset(dx, 0),
            child: CustomPaint(painter: DashedBorderPainter(color: color)),
          ),
        );
      },
    );
  }
}
