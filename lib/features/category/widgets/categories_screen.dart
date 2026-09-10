import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/features/category/models/category.dart';
import 'package:taskframe/features/category/providers.dart';
import 'package:taskframe/features/category/widgets/category_edit_sheet.dart';

/// Below this viewport width, the category list fills the screen edge to
/// edge (the native mobile list look); at or above it, it's capped and
/// wrapped in a visible card so it doesn't float as bare text in a wide
/// page. Matches the edit sheet's own breakpoint.
const _narrowBreakpoint = 700.0;

/// Lists all categories and lets the user add, edit, or delete them. The
/// default category is always first and has no delete affordance.
class CategoriesScreen extends ConsumerWidget {
  /// Creates a [CategoriesScreen].
  const new({super.key});

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Category category,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this category?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (!context.mounted) return;
    if (confirmed ?? false) {
      await ref.read(categoryListProvider.notifier).deleteCategory(category);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoryListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Categories'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => showCategoryEditSheet(context: context),
          ),
        ],
      ),
      body: switch (categoriesAsync) {
        AsyncData(:final value) => LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < _narrowBreakpoint;
            final list = ListView(
              padding: isNarrow
                  ? EdgeInsets.zero
                  : const EdgeInsets.symmetric(vertical: 8),
              children: [
                for (final category in value)
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Color(category.colorValue),
                      child: category.emoji != null
                          ? Text(category.emoji!)
                          : null,
                    ),
                    title: Text(category.name),
                    onTap: () => showCategoryEditSheet(
                      context: context,
                      category: category,
                    ),
                    trailing: category.isDefault
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.delete),
                            onPressed: () =>
                                _confirmDelete(context, ref, category),
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
