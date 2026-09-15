import 'package:emoji_picker_flutter/emoji_picker_flutter.dart' hide Category;
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/core/responsive.dart';
import 'package:taskframe/features/category/models/category.dart';
import 'package:taskframe/features/category/providers.dart';

/// Opens the edit sheet for [category] (edit mode) or, when [category] is
/// `null`, for creating a new category (create mode). Near-fullscreen on a
/// narrow (mobile) width, a centered fixed-width dialog on a wide one.
Future<void> showCategoryEditSheet({
  required BuildContext context,
  Category? category,
}) {
  if (isNarrow(context)) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _CategoryEditSheetContent(category: category),
    );
  }
  return showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 640),
        child: _CategoryEditSheetContent(category: category),
      ),
    ),
  );
}

class _CategoryEditSheetContent extends ConsumerStatefulWidget {
  const new({this.category});

  final Category? category;

  @override
  ConsumerState<_CategoryEditSheetContent> createState() =>
      _CategoryEditSheetContentState();
}

class _CategoryEditSheetContentState
    extends ConsumerState<_CategoryEditSheetContent> {
  late final TextEditingController _nameController;
  late Color _color;
  String? _emoji;

  /// The category backing this sheet. Starts as `null` in create mode
  /// until [_onNameChanged] creates it on the first non-empty keystroke —
  /// from then on (and always, in edit mode) every field edit applies
  /// live via this category, with no separate Save step.
  Category? _category;

  /// The in-flight creation triggered by the first keystroke, set
  /// synchronously (before awaiting it) so a keystroke arriving while
  /// it's still pending waits on the same category instead of creating a
  /// second one — mirrors `TaskEditModal`'s `_pendingCreate`.
  Future<Category>? _pendingCreate;

  bool get _isDefault => widget.category?.isDefault ?? false;

  @override
  void initState() {
    super.initState();
    _category = widget.category;
    _nameController = TextEditingController(text: widget.category?.name ?? '');
    _color = Color(widget.category?.colorValue ?? 0xFF009688);
    _emoji = widget.category?.emoji;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// Applies every keystroke immediately. In create mode, the category
  /// doesn't exist yet — the first non-empty value creates it (carrying
  /// along whatever color/emoji were already picked before typing); every
  /// edit after that, in either mode, updates the existing category.
  Future<void> _onNameChanged(String name) async {
    final notifier = ref.read(categoryListProvider.notifier);
    if (_category != null) {
      await notifier.updateCategory(_category!, name: name);
      return;
    }
    if (_pendingCreate != null) {
      final created = await _pendingCreate!;
      if (!mounted) return;
      await notifier.updateCategory(created, name: name);
      return;
    }
    if (name.isEmpty) return;
    final future = notifier.addCategory(
      name: name,
      colorValue: _color.toARGB32(),
      emoji: _emoji,
    );
    _pendingCreate = future;
    final created = await future;
    if (!mounted) return;
    setState(() {
      _category = created;
      _pendingCreate = null;
    });
  }

  Future<void> _pickColor() async {
    final picked = await showDialog<Color>(
      context: context,
      builder: (context) {
        var dialogColor = _color;
        return AlertDialog(
          content: BlockPicker(
            pickerColor: _color,
            onColorChanged: (color) => dialogColor = color,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(dialogColor),
              child: const Text('Done'),
            ),
          ],
        );
      },
    );
    if (picked == null) return;
    setState(() => _color = picked);
    final category = _category;
    if (category != null) {
      await ref
          .read(categoryListProvider.notifier)
          .updateCategory(category, colorValue: picked.toARGB32());
    }
  }

  Future<void> _pickEmoji() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SizedBox(
        height: 300,
        child: EmojiPicker(
          onEmojiSelected: (category, emoji) =>
              Navigator.of(context).pop(emoji.emoji),
        ),
      ),
    );
    if (picked == null) return;
    setState(() => _emoji = picked);
    final category = _category;
    if (category != null) {
      await ref
          .read(categoryListProvider.notifier)
          .updateCategory(category, emoji: picked);
    }
  }

  Future<void> _confirmDelete() async {
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
    if (!mounted) return;
    if (confirmed ?? false) {
      await ref.read(categoryListProvider.notifier).deleteCategory(_category!);
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              enabled: !_isDefault,
              decoration: const InputDecoration(labelText: 'Name'),
              onChanged: _onNameChanged,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                GestureDetector(
                  key: const Key('categoryEditSheet.colorSwatch'),
                  onTap: _pickColor,
                  child: CircleAvatar(backgroundColor: _color),
                ),
                if (!_isDefault) ...[
                  const SizedBox(width: 16),
                  IconButton(
                    key: const Key('categoryEditSheet.emojiButton'),
                    onPressed: _pickEmoji,
                    icon: Text(
                      _emoji ?? '➕',
                      style: const TextStyle(fontSize: 24),
                    ),
                  ),
                ],
              ],
            ),
            if (_category != null && !_isDefault) ...[
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: _confirmDelete,
                  child: const Text('Delete'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
