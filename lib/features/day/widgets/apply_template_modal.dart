import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/core/responsive.dart';
import 'package:taskframe/features/day/providers.dart';
import 'package:taskframe/features/day/template_apply_effects.dart';
import 'package:taskframe/features/template/models/template.dart';
import 'package:taskframe/features/template/providers.dart';

/// Opens a modal listing every template, applying the tapped one to
/// [date]. Near-fullscreen on a narrow (mobile) width, a centered
/// fixed-width dialog on a wide one — matches `showBlockEditModal`.
Future<void> showApplyTemplateModal({
  required BuildContext context,
  required DateTime date,
}) {
  if (isNarrow(context)) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.6,
        child: ApplyTemplateModal(date: date),
      ),
    );
  }
  return showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 480),
        child: ApplyTemplateModal(date: date),
      ),
    ),
  );
}

/// Lists every template; tapping one applies its blocks to [date] via
/// [DayBlocksNotifier.applyTemplate], records the outcome in
/// [templateApplyEffectsProvider] to drive the newly-added/skipped
/// animations, then closes itself.
class ApplyTemplateModal extends ConsumerWidget {
  /// Creates an [ApplyTemplateModal] for [date].
  const new({required this.date, super.key});

  /// The day the chosen template is applied to.
  final DateTime date;

  Future<void> _apply(
    BuildContext context,
    WidgetRef ref,
    Template template,
  ) async {
    final result = await ref
        .read(dayBlocksProvider(date).notifier)
        .applyTemplate(template.id);
    if (!context.mounted) return;
    Navigator.of(context).pop();

    ref.read(templateApplyEffectsProvider(date).notifier)
      ..addHighlights(result.addedIds)
      ..addGhosts(result.skipped);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templates = ref.watch(templateListProvider).value ?? const [];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Apply template',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        Flexible(
          child: templates.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No templates yet'),
                )
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final template in templates)
                      ListTile(
                        key: ValueKey('apply-template-option-${template.id}'),
                        title: Text(template.name),
                        onTap: () => unawaited(_apply(context, ref, template)),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
