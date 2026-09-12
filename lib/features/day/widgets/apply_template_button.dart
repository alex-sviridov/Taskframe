import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/features/day/widgets/apply_template_modal.dart';
import 'package:taskframe/features/template/providers.dart';

/// A day header's "apply template" icon button. Disabled while no
/// templates exist; tapping it opens [showApplyTemplateModal] for [date].
///
/// Always visible when [alwaysVisible] (single-day/mobile headers); on a
/// multi-column header (week view/desktop) pass `false` so it only shows
/// while the column is hovered, matching a desktop-only affordance.
class ApplyTemplateButton extends ConsumerWidget {
  /// Creates an [ApplyTemplateButton] for [date].
  const new({required this.date, required this.alwaysVisible, super.key});

  /// The day this button applies a template to.
  final DateTime date;

  /// Whether this button is always shown, or only on hover — see the
  /// class docs.
  final bool alwaysVisible;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasTemplates =
        (ref.watch(templateListProvider).value ?? const []).isNotEmpty;

    final button = IconButton(
      tooltip: 'Apply template',
      icon: const Icon(Icons.playlist_add, size: 18),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      onPressed: hasTemplates
          ? () =>
                unawaited(showApplyTemplateModal(context: context, date: date))
          : null,
    );

    return alwaysVisible ? button : _HoverReveal(child: button);
  }
}

/// Shows [child] only while the pointer hovers over it; hidden (and
/// non-interactive, via [IgnorePointer]) otherwise.
class _HoverReveal extends StatefulWidget {
  const new({required this.child});

  final Widget child;

  @override
  State<_HoverReveal> createState() => _HoverRevealState();
}

class _HoverRevealState extends State<_HoverReveal> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Opacity(
        opacity: _hovering ? 1 : 0,
        child: IgnorePointer(ignoring: !_hovering, child: widget.child),
      ),
    );
  }
}
