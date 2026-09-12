import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/core/responsive.dart';
import 'package:taskframe/features/category/models/category.dart';
import 'package:taskframe/features/category/providers.dart';

/// A small color dot for [category] followed by its emoji-prefixed name,
/// used for every row of [BlockCategoryPicker] — the closed field, its
/// dropdown menu items, and its wheel entries alike — so they never drift
/// out of visual sync with each other. Color is an accent (a swatch), not
/// the row's whole background, so it reads as a standard field/menu row
/// rather than a colored block.
class _CategoryRow extends StatelessWidget {
  const new({required this.category});

  final Category category;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(radius: 8, backgroundColor: Color(category.colorValue)),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            category.formatTitle(category.name),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// The shared field chrome (outline + "Category" label) both the wide
/// dropdown and the narrow wheel-picker trigger sit inside, so the two
/// read as the same kind of control regardless of width.
const _fieldDecoration = InputDecoration(
  labelText: 'Category',
  border: OutlineInputBorder(),
  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
);

/// Lets the user assign a category to the thing being edited: a standard
/// [DropdownButtonFormField] on a wide width, or — since a dropdown menu
/// is awkward to operate with a finger — the same field chrome wrapping a
/// tappable row that opens a [CupertinoPicker] wheel on a narrow one.
/// Either way every row is a [_CategoryRow], and picking one calls
/// [onSelected] immediately, no separate confirm step.
class BlockCategoryPicker extends ConsumerWidget {
  /// Creates a [BlockCategoryPicker].
  const new({
    required this.selectedCategoryId,
    required this.onSelected,
    super.key,
  });

  /// The id of the category currently assigned to the thing being edited.
  final String selectedCategoryId;

  /// Called with a category's id when a new one is picked.
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoryListProvider).value ?? const [];
    if (categories.isEmpty) return const SizedBox.shrink();
    final selected = categoryById(categories, selectedCategoryId);

    if (isNarrow(context)) {
      return InputDecorator(
        decoration: _fieldDecoration,
        child: GestureDetector(
          onTap: () => _showWheelPicker(context, categories, selected.id),
          child: _CategoryRow(category: selected),
        ),
      );
    }

    return DropdownButtonFormField<String>(
      // Forces the field to reset to [selected.id] whenever it changes
      // for a reason other than this field's own [onChanged] — e.g. the
      // item being edited changes underneath it — since a FormField
      // otherwise only reads [initialValue] on its very first build.
      key: ValueKey(selected.id),
      initialValue: selected.id,
      decoration: _fieldDecoration,
      selectedItemBuilder: (context) => [
        for (final category in categories) _CategoryRow(category: category),
      ],
      items: [
        for (final category in categories)
          DropdownMenuItem(
            value: category.id,
            child: _CategoryRow(category: category),
          ),
      ],
      onChanged: (id) {
        if (id != null) onSelected(id);
      },
    );
  }

  /// Opens a bottom sheet containing a [CupertinoPicker] wheel of every
  /// category, initially centered on [selectedId]. Applies [onSelected]
  /// on every settle — there's no separate Done/confirm action.
  Future<void> _showWheelPicker(
    BuildContext context,
    List<Category> categories,
    String selectedId,
  ) {
    final initialItem = categories.indexWhere((c) => c.id == selectedId);
    return showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: 216,
          child: CupertinoPicker(
            itemExtent: 48,
            scrollController: FixedExtentScrollController(
              initialItem: initialItem < 0 ? 0 : initialItem,
            ),
            onSelectedItemChanged: (index) => onSelected(categories[index].id),
            children: [
              for (final category in categories)
                Center(child: _CategoryRow(category: category)),
            ],
          ),
        ),
      ),
    );
  }
}
