import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/core/responsive.dart';
import 'package:taskframe/core/widgets/colored_list_card.dart';
import 'package:taskframe/features/category/providers.dart';
import 'package:taskframe/features/category/widgets/category_edit_sheet.dart';

/// Lists all categories and lets the user add or edit them — deleting a
/// non-default category happens inside its edit sheet, matching
/// `TasksScreen`/`TaskEditModal`. The default category is always first.
class CategoriesScreen extends ConsumerWidget {
  /// Creates a [CategoriesScreen].
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoryListProvider);

    return Scaffold(
      appBar: AppBar(
        // Reserves the leading slot so AppShell's floating hamburger button
        // (narrow widths only) has room without covering the title.
        leading: const SizedBox(),
        title: const Text('Categories'),
        actions: [
          IconButton(
            tooltip: 'Add category',
            icon: const Icon(Icons.add),
            onPressed: () => showCategoryEditSheet(context: context),
          ),
        ],
      ),
      body: switch (categoriesAsync) {
        AsyncData(:final value) => LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < narrowBreakpoint;
            final list = ListView(
              padding: isNarrow
                  ? EdgeInsets.zero
                  : const EdgeInsets.symmetric(vertical: 8),
              children: [
                for (final category in value)
                  ColoredListCard(
                    color: Color(category.colorValue),
                    leading: category.emoji != null
                        ? CircleAvatar(child: Text(category.emoji!))
                        : null,
                    title: Text(category.name),
                    onTap: () => showCategoryEditSheet(
                      context: context,
                      category: category,
                    ),
                  ),
              ],
            );
            if (isNarrow) return list;
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Card(
                  margin: const EdgeInsets.symmetric(vertical: 24),
                  child: list,
                ),
              ),
            );
          },
        ),
        AsyncError() => const Center(child: Text('Failed to load categories')),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}
