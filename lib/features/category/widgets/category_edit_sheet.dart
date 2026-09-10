import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart' hide Category;
import 'package:taskframe/features/category/models/category.dart';
import 'package:taskframe/features/category/providers.dart';

/// Opens the edit sheet for [category] (edit mode) or, when [category] is
/// `null`, for creating a new category (create mode).
Future<void> showCategoryEditSheet({
  required BuildContext context,
  required WidgetRef ref,
  Category? category,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _CategoryEditSheetContent(category: category),
  );
}

class _CategoryEditSheetContent extends ConsumerStatefulWidget {
  const _CategoryEditSheetContent({this.category});

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

  bool get _isDefault => widget.category?.isDefault ?? false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.category?.name ?? '');
    _color = Color(widget.category?.colorValue ?? 0xFF009688);
    _emoji = widget.category?.emoji;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
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
    if (picked != null) setState(() => _color = picked);
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
    if (picked != null) setState(() => _emoji = picked);
  }

  Future<void> _save() async {
    final notifier = ref.read(categoryListProvider.notifier);
    if (widget.category == null) {
      await notifier.addCategory(
        name: _nameController.text,
        colorValue: _color.toARGB32(),
        emoji: _emoji,
      );
    } else {
      await notifier.updateCategory(
        widget.category!,
        name: _nameController.text,
        colorValue: _color.toARGB32(),
        emoji: _emoji,
      );
    }
    if (mounted) Navigator.of(context).pop();
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
              onChanged: (_) => setState(() {}),
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
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: (_isDefault || _nameController.text.isNotEmpty)
                      ? _save
                      : null,
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
