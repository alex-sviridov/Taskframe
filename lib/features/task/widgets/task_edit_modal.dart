import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/core/responsive.dart';
import 'package:taskframe/features/category/models/category.dart';
import 'package:taskframe/features/category/widgets/category_picker.dart';
import 'package:taskframe/features/task/models/task.dart';
import 'package:taskframe/features/task/providers.dart';
import 'package:taskframe/features/task/tag_parsing.dart';
import 'package:taskframe/features/task/widgets/tag_pills.dart';

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
  late List<String> _tags;

  /// The task backing this modal. Starts as `null` in create mode until
  /// [_onTitleChanged] creates it on the first non-empty keystroke — from
  /// then on (and always, in edit mode) every field edit applies live via
  /// this task, with no separate Save step.
  Task? _task;

  /// The in-flight creation triggered by the first keystroke, set
  /// synchronously (before awaiting it) so a keystroke arriving while it's
  /// still pending waits on the same task instead of creating a second one
  /// — real typing fires one `onChanged` per character, faster than a
  /// single `addTask` round-trip resolves.
  Future<Task>? _pendingCreate;

  @override
  void initState() {
    super.initState();
    _task = widget.task;
    _titleController = TextEditingController(text: widget.task?.title ?? '');
    _categoryId = widget.task?.categoryId ?? Category.defaultId;
    _closed = widget.task?.closed ?? false;
    _tags = widget.task?.tags ?? [];
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  /// Applies every keystroke immediately. In create mode, the task doesn't
  /// exist yet — the first non-empty value creates it (carrying along
  /// whatever category/closed the user already picked before typing);
  /// every keystroke after that, in either mode, updates the existing task.
  ///
  /// When the cursor is at the end and the just-typed text ends with
  /// `#tag `, that chunk is stripped from the title and added as a tag.
  Future<void> _onTitleChanged(String rawTitle) async {
    final atEnd = _titleController.selection.baseOffset == rawTitle.length;
    final extraction = atEnd ? extractTrailingTag(rawTitle) : null;
    final title = extraction?.title ?? rawTitle;
    if (extraction != null) {
      _titleController.value = TextEditingValue(
        text: title,
        selection: TextSelection.collapsed(offset: title.length),
      );
    }
    final newTags = extraction != null && !_tags.contains(extraction.tag)
        ? [..._tags, extraction.tag]
        : null;
    if (newTags != null) setState(() => _tags = newTags);

    final notifier = ref.read(taskListProvider.notifier);
    if (_task != null) {
      await notifier.updateTask(_task!, title: title, tags: newTags);
      return;
    }
    if (_pendingCreate != null) {
      final created = await _pendingCreate!;
      if (!mounted) return;
      await notifier.updateTask(created, title: title, tags: newTags);
      return;
    }
    if (title.isEmpty) return;
    final future = notifier.addTask(title: title, categoryId: _categoryId);
    _pendingCreate = future;
    final created = await future;
    if (_closed) await notifier.updateTask(created, closed: true);
    if (newTags != null) await notifier.updateTask(created, tags: newTags);
    if (!mounted) return;
    setState(() {
      _task = created;
      _pendingCreate = null;
    });
  }

  /// Catches a `#tag` left dangling at the end of the title with no
  /// trailing space — [_onTitleChanged] only extracts on a trailing
  /// space, so a tag typed right before the modal closes would otherwise
  /// never be picked up. Called as the modal is dismissed, before the
  /// pop actually goes through.
  Future<void> _applyPendingTagOnExit() async {
    final extraction = extractFinalTag(_titleController.text);
    if (extraction == null) return;
    _titleController.value = TextEditingValue(
      text: extraction.title,
      selection: TextSelection.collapsed(offset: extraction.title.length),
    );
    final newTags = _tags.contains(extraction.tag)
        ? _tags
        : [..._tags, extraction.tag];
    setState(() => _tags = newTags);

    final task =
        _task ?? (_pendingCreate != null ? await _pendingCreate : null);
    if (task == null) return;
    if (!mounted) return;
    await ref
        .read(taskListProvider.notifier)
        .updateTask(task, title: extraction.title, tags: newTags);
  }

  /// Removes [tag] from this task's tags, persisting the change.
  Future<void> _onTagRemoved(String tag) async {
    final tags = [
      for (final t in _tags)
        if (t != tag) t,
    ];
    setState(() => _tags = tags);
    final task = _task;
    if (task != null) {
      await ref.read(taskListProvider.notifier).updateTask(task, tags: tags);
    }
  }

  Future<void> _onCategorySelected(String id) async {
    setState(() => _categoryId = id);
    final task = _task;
    if (task != null) {
      await ref
          .read(taskListProvider.notifier)
          .updateTask(task, categoryId: id);
    }
  }

  Future<void> _onClosedChanged(bool value) async {
    setState(() => _closed = value);
    final task = _task;
    if (task != null) {
      await ref.read(taskListProvider.notifier).updateTask(task, closed: value);
    }
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
      await ref.read(taskListProvider.notifier).deleteTask(_task!);
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _applyPendingTagOnExit();
        if (context.mounted) Navigator.of(context).pop();
      },
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Checkbox(
                    shape: const CircleBorder(),
                    value: _closed,
                    onChanged: (value) => _onClosedChanged(value ?? !_closed),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _titleController,
                      style: TextStyle(
                        decoration: _closed ? TextDecoration.lineThrough : null,
                      ),
                      onChanged: _onTitleChanged,
                    ),
                  ),
                ],
              ),
              if (_tags.isNotEmpty) ...[
                const SizedBox(height: 8),
                TagPills(tags: _tags, onRemoved: _onTagRemoved),
              ],
              const SizedBox(height: 16),
              BlockCategoryPicker(
                selectedCategoryId: _categoryId,
                onSelected: _onCategorySelected,
              ),
              if (_task != null) ...[
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
      ),
    );
  }
}
