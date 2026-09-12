import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/core/responsive.dart';
import 'package:taskframe/features/category/models/category.dart';
import 'package:taskframe/features/category/widgets/category_picker.dart';
import 'package:taskframe/features/task/models/task.dart';
import 'package:taskframe/features/task/providers.dart';

/// Opens the edit modal for [task] (edit mode) or, when [task] is `null`,
/// for creating a new task (create mode). Near-fullscreen on a narrow
/// (mobile) width, a centered fixed-width dialog on a wide one — matching
/// `showCategoryEditSheet`'s responsive shell.
Future<void> showTaskEditModal({required BuildContext context, Task? task}) {
  if (isNarrow(context)) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _TaskEditModalContent(task: task),
    );
  }
  return showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 640),
        child: _TaskEditModalContent(task: task),
      ),
    ),
  );
}

class _TaskEditModalContent extends ConsumerStatefulWidget {
  const new({this.task});

  final Task? task;

  @override
  ConsumerState<_TaskEditModalContent> createState() =>
      _TaskEditModalContentState();
}

class _TaskEditModalContentState extends ConsumerState<_TaskEditModalContent> {
  late final TextEditingController _titleController;
  late String _categoryId;
  late bool _closed;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.task?.title ?? '');
    _categoryId = widget.task?.categoryId ?? Category.defaultId;
    _closed = widget.task?.closed ?? false;
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final notifier = ref.read(taskListProvider.notifier);
    if (widget.task == null) {
      await notifier.addTask(
        title: _titleController.text,
        categoryId: _categoryId,
      );
    } else {
      await notifier.updateTask(
        widget.task!,
        title: _titleController.text,
        closed: _closed,
        categoryId: _categoryId,
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this task?'),
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
      await ref.read(taskListProvider.notifier).deleteTask(widget.task!);
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
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Title'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            BlockCategoryPicker(
              selectedCategoryId: _categoryId,
              onSelected: (id) => setState(() => _categoryId = id),
            ),
            if (widget.task != null) ...[
              const SizedBox(height: 16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Closed'),
                value: _closed,
                onChanged: (value) => setState(() => _closed = value),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (widget.task != null)
                  TextButton(
                    onPressed: _confirmDelete,
                    child: const Text('Delete'),
                  )
                else
                  const SizedBox(),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: _titleController.text.isNotEmpty
                          ? _save
                          : null,
                      child: const Text('Save'),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
