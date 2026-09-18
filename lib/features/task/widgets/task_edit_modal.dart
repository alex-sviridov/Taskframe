import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/core/responsive.dart';
import 'package:taskframe/features/category/models/category.dart';
import 'package:taskframe/features/category/widgets/category_picker.dart';
import 'package:taskframe/features/task/active_from_parsing.dart';
import 'package:taskframe/features/task/models/task.dart';
import 'package:taskframe/features/task/providers.dart';
import 'package:taskframe/features/task/repeat_parsing.dart';
import 'package:taskframe/features/task/tag_parsing.dart';
import 'package:taskframe/features/task/widgets/tag_pills.dart';

/// Whether [date] is set and still in the future — mirrors
/// `Task.isNotYetActive` for a date that may not be saved to a task yet.
bool _isFutureDated(DateTime? date) =>
    date != null && date.isAfter(DateTime.now());

/// Parses a `dd/mm/yy`/`dd/mm/yyyy` string as typed into the "Active
/// from" field (no leading `from`, unlike the title-parsing helpers).
/// Returns `null` for anything that isn't a valid full date.
DateTime? _parseActiveFromField(String text) {
  final match = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{2,4})$').firstMatch(text);
  if (match == null) return null;
  final day = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final yearText = match.group(3)!;
  final year = yearText.length <= 2
      ? 2000 + int.parse(yearText)
      : int.parse(yearText);
  final date = DateTime(year, month, day);
  if (date.year != year || date.month != month || date.day != day) {
    return null;
  }
  return date;
}

/// The repeat unit dropdown's options, in display order.
const _repeatUnits = {'d': 'Day', 'w': 'Week', 'm': 'Month', 'y': 'Year'};

/// Splits a compact `<n><unit>` repeat string (e.g. `"2w"`) into its
/// count and unit, as produced by [extractTrailingRepeat]/
/// [extractFinalRepeat]/[Task.repeat] — always well-formed by
/// construction, so this never returns `null`.
({String count, String unit}) _splitRepeat(String repeat) {
  final match = RegExp(r'^(\d+)([dwmy])$').firstMatch(repeat)!;
  return (count: match.group(1)!, unit: match.group(2)!);
}

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
  late final TextEditingController _activeFromController;
  late final TextEditingController _repeatCountController;
  late String _categoryId;
  late bool _closed;
  late List<String> _tags;
  DateTime? _activeFrom;
  String _repeatUnit = 'w';

  /// The stored `Task.repeat` form (e.g. `"2w"`) derived from
  /// [_repeatCountController]/[_repeatUnit] — `null` while the count is
  /// empty, since an empty count means "no repeat".
  String? get _repeat => _repeatCountController.text.isEmpty
      ? null
      : '${_repeatCountController.text}$_repeatUnit';

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
    _activeFrom = widget.task?.activeFrom;
    _activeFromController = TextEditingController(
      text: _activeFrom == null ? '' : formatActiveFrom(_activeFrom!),
    );
    final initialRepeat = widget.task?.repeat;
    final split = initialRepeat == null ? null : _splitRepeat(initialRepeat);
    _repeatCountController = TextEditingController(text: split?.count ?? '');
    _repeatUnit = split?.unit ?? 'w';
  }

  @override
  void dispose() {
    _titleController.dispose();
    _activeFromController.dispose();
    _repeatCountController.dispose();
    super.dispose();
  }

  /// Applies every keystroke immediately. In create mode, the task doesn't
  /// exist yet — the first non-empty value creates it (carrying along
  /// whatever category/closed the user already picked before typing);
  /// every keystroke after that, in either mode, updates the existing task.
  ///
  /// When the cursor is at the end and the just-typed text ends with
  /// `#tag `, that chunk is stripped from the title and added as a tag.
  /// Likewise for `from dd/mm[/yy]`, which sets [_activeFrom] instead, and
  /// `every <n><unit>`/`every <n> <word>`, which sets [_repeat].
  Future<void> _onTitleChanged(String rawTitle) async {
    final atEnd = _titleController.selection.baseOffset == rawTitle.length;
    final tagExtraction = atEnd ? extractTrailingTag(rawTitle) : null;
    final afterTag = tagExtraction?.title ?? rawTitle;
    final activeFromExtraction = atEnd
        ? extractTrailingActiveFrom(afterTag)
        : null;
    final afterActiveFrom = activeFromExtraction?.title ?? afterTag;
    final repeatExtraction = atEnd
        ? extractTrailingRepeat(afterActiveFrom)
        : null;
    final title = repeatExtraction?.title ?? afterActiveFrom;
    if (tagExtraction != null ||
        activeFromExtraction != null ||
        repeatExtraction != null) {
      _titleController.value = TextEditingValue(
        text: title,
        selection: TextSelection.collapsed(offset: title.length),
      );
    }
    final newTags = tagExtraction != null && !_tags.contains(tagExtraction.tag)
        ? [..._tags, tagExtraction.tag]
        : null;
    if (newTags != null) setState(() => _tags = newTags);
    final newActiveFrom = activeFromExtraction?.activeFrom;
    if (newActiveFrom != null) {
      setState(() {
        _activeFrom = newActiveFrom;
        _activeFromController.text = formatActiveFrom(newActiveFrom);
      });
    }
    final newRepeat = repeatExtraction?.repeat;
    if (newRepeat != null) {
      final split = _splitRepeat(newRepeat);
      setState(() {
        _repeatCountController.text = split.count;
        _repeatUnit = split.unit;
      });
    }

    final notifier = ref.read(taskListProvider.notifier);
    if (_task != null) {
      await notifier.updateTask(
        _task!,
        title: title,
        tags: newTags,
        activeFrom: newActiveFrom,
        repeat: newRepeat,
      );
      return;
    }
    if (_pendingCreate != null) {
      final created = await _pendingCreate!;
      if (!mounted) return;
      await notifier.updateTask(
        created,
        title: title,
        tags: newTags,
        activeFrom: newActiveFrom,
        repeat: newRepeat,
      );
      return;
    }
    if (title.isEmpty) return;
    final future = notifier.addTask(title: title, categoryId: _categoryId);
    _pendingCreate = future;
    final created = await future;
    if (_closed) await notifier.updateTask(created, closed: true);
    if (newTags != null) await notifier.updateTask(created, tags: newTags);
    if (newActiveFrom != null) {
      await notifier.updateTask(created, activeFrom: newActiveFrom);
    }
    if (newRepeat != null) {
      await notifier.updateTask(created, repeat: newRepeat);
    }
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
    final tagExtraction = extractFinalTag(_titleController.text);
    final activeFromExtraction = extractFinalActiveFrom(
      tagExtraction?.title ?? _titleController.text,
    );
    final repeatExtraction = extractFinalRepeat(
      activeFromExtraction?.title ??
          tagExtraction?.title ??
          _titleController.text,
    );
    if (tagExtraction == null &&
        activeFromExtraction == null &&
        repeatExtraction == null) {
      return;
    }
    final title =
        repeatExtraction?.title ??
        activeFromExtraction?.title ??
        tagExtraction!.title;
    _titleController.value = TextEditingValue(
      text: title,
      selection: TextSelection.collapsed(offset: title.length),
    );
    final newTags = tagExtraction == null || _tags.contains(tagExtraction.tag)
        ? _tags
        : [..._tags, tagExtraction.tag];
    final newActiveFrom = activeFromExtraction?.activeFrom ?? _activeFrom;
    final newRepeat = repeatExtraction?.repeat ?? _repeat;
    setState(() {
      _tags = newTags;
      if (activeFromExtraction != null) {
        _activeFrom = newActiveFrom;
        _activeFromController.text = formatActiveFrom(newActiveFrom!);
      }
      if (repeatExtraction != null) {
        final split = _splitRepeat(newRepeat!);
        _repeatCountController.text = split.count;
        _repeatUnit = split.unit;
      }
    });

    final task =
        _task ?? (_pendingCreate != null ? await _pendingCreate : null);
    if (task == null) return;
    if (!mounted) return;
    await ref
        .read(taskListProvider.notifier)
        .updateTask(
          task,
          title: title,
          tags: newTags,
          activeFrom: activeFromExtraction?.activeFrom,
          repeat: repeatExtraction?.repeat,
        );
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

  /// Applies a typed `dd/mm/yy`/`dd/mm/yyyy` value from the "Active from"
  /// field. An empty value clears [_activeFrom]; anything else that
  /// doesn't parse as a full date is left alone (no update) until it
  /// does.
  Future<void> _onActiveFromFieldChanged(String text) async {
    if (text.isEmpty) {
      setState(() => _activeFrom = null);
      final task = _task;
      if (task != null) {
        await ref
            .read(taskListProvider.notifier)
            .updateTask(task, clearActiveFrom: true);
      }
      return;
    }
    final parsed = _parseActiveFromField(text);
    if (parsed == null) return;
    setState(() => _activeFrom = parsed);
    final task = _task;
    if (task != null) {
      await ref
          .read(taskListProvider.notifier)
          .updateTask(task, activeFrom: parsed);
    }
  }

  /// Opens the standard Material date picker, applying the result the
  /// same way a typed date does.
  Future<void> _pickActiveFrom() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _activeFrom ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );
    if (picked == null || !mounted) return;
    final date = DateTime(picked.year, picked.month, picked.day);
    _activeFromController.text = formatActiveFrom(date);
    await _onActiveFromFieldChanged(_activeFromController.text);
  }

  /// Clears the "Active from" field and the task's [Task.activeFrom].
  Future<void> _clearActiveFrom() async {
    _activeFromController.clear();
    await _onActiveFromFieldChanged('');
  }

  /// Applies a typed count from the repeat number field. An empty value
  /// clears [Task.repeat]; the unit dropdown's current value combines
  /// with any other count to form the stored repeat string (see
  /// [_repeat]).
  Future<void> _onRepeatCountChanged(String text) async {
    setState(() {});
    final task = _task;
    if (task == null) return;
    if (text.isEmpty) {
      await ref
          .read(taskListProvider.notifier)
          .updateTask(task, clearRepeat: true);
      return;
    }
    await ref.read(taskListProvider.notifier).updateTask(task, repeat: _repeat);
  }

  /// Applies a newly picked repeat unit. Only touches the task if a
  /// count is already set — an empty count means "no repeat" regardless
  /// of unit.
  Future<void> _onRepeatUnitChanged(String? unit) async {
    if (unit == null) return;
    setState(() => _repeatUnit = unit);
    final task = _task;
    if (task != null && _repeat != null) {
      await ref
          .read(taskListProvider.notifier)
          .updateTask(task, repeat: _repeat);
    }
  }

  /// Clears the repeat count/unit and the task's [Task.repeat].
  Future<void> _clearRepeat() async {
    _repeatCountController.clear();
    setState(() => _repeatUnit = 'w');
    final task = _task;
    if (task != null) {
      await ref
          .read(taskListProvider.notifier)
          .updateTask(task, clearRepeat: true);
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
                      key: const Key('task-title-field'),
                      controller: _titleController,
                      style: TextStyle(
                        decoration: _closed ? TextDecoration.lineThrough : null,
                        color: _isFutureDated(_activeFrom)
                            ? Theme.of(context).disabledColor
                            : null,
                        fontStyle: _isFutureDated(_activeFrom)
                            ? FontStyle.italic
                            : null,
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
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('task-active-from-field'),
                      controller: _activeFromController,
                      decoration: InputDecoration(
                        labelText: 'Active from',
                        hintText: 'dd/mm/yy',
                        suffixIcon: _activeFromController.text.isEmpty
                            ? IconButton(
                                icon: const Icon(Icons.calendar_today),
                                tooltip: 'Pick a date',
                                onPressed: _pickActiveFrom,
                              )
                            : IconButton(
                                key: const Key('task-active-from-clear'),
                                icon: const Icon(Icons.clear),
                                tooltip: 'Clear active-from date',
                                onPressed: _clearActiveFrom,
                              ),
                      ),
                      onTap: _pickActiveFrom,
                      onChanged: _onActiveFromFieldChanged,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Repeat',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: Theme.of(context).hintColor),
                        ),
                        Row(
                          children: [
                            SizedBox(
                              width: 28,
                              child: TextField(
                                key: const Key('task-repeat-number-field'),
                                controller: _repeatCountController,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                decoration: const InputDecoration(
                                  border: UnderlineInputBorder(),
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                ),
                                onChanged: _onRepeatCountChanged,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: DropdownButton<String>(
                                key: const Key('task-repeat-unit-dropdown'),
                                value: _repeatUnit,
                                isExpanded: true,
                                items: [
                                  for (final entry in _repeatUnits.entries)
                                    DropdownMenuItem(
                                      value: entry.key,
                                      child: Text(entry.value),
                                    ),
                                ],
                                onChanged: _onRepeatUnitChanged,
                              ),
                            ),
                            if (_repeatCountController.text.isNotEmpty)
                              IconButton(
                                key: const Key('task-repeat-clear'),
                                icon: const Icon(Icons.clear),
                                tooltip: 'Clear repeat',
                                onPressed: _clearRepeat,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
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
