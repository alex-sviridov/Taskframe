import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/core/responsive.dart';
import 'package:taskframe/features/category/models/category.dart';
import 'package:taskframe/features/category/providers.dart';
import 'package:taskframe/features/category/widgets/category_picker.dart';
import 'package:taskframe/features/task/active_from_parsing.dart';
import 'package:taskframe/features/task/category_parsing.dart';
import 'package:taskframe/features/task/models/task.dart';
import 'package:taskframe/features/task/providers.dart';
import 'package:taskframe/features/task/repeat_parsing.dart';
import 'package:taskframe/features/task/tag_parsing.dart';
import 'package:taskframe/features/task/widgets/tag_pills.dart';

/// Matches an *unfinished* `#word` immediately before the cursor — no
/// trailing space yet — so suggestions can be offered while the user is
/// still typing it, wherever the cursor currently sits. The title's own
/// `!`-exclusion isn't a concept here (unlike the search bar's tokens),
/// so this is simpler than `tasks_screen.dart`'s counterpart.
final _partialTitleTagPattern = RegExp(r'(^|\s)#(\w*)$');

/// The `@` counterpart of [_partialTitleTagPattern].
final _partialTitleCategoryPattern = RegExp(r'(^|\s)@(\w*)$');

/// Which kind of token the title's suggestions dropdown is currently
/// offering.
enum _TitleSuggestionKind { tag, category }

/// The title's suggestions dropdown never lists more than this many
/// options — matches the search bar's own limit.
const _maxTitleSuggestions = 4;

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
  late final FocusNode _titleFocusNode;

  /// Anchors the floating title-suggestions dropdown to the title
  /// field's current position/size — same mechanism as the search bar's
  /// own dropdown in `tasks_screen.dart`.
  final LayerLink _titleFieldLink = LayerLink();

  /// Reads the title field's laid-out size, so the floating dropdown can
  /// match its width and sit directly below it.
  final GlobalKey _titleFieldBoxKey = GlobalKey();

  /// The floating title-suggestions dropdown, inserted into the ambient
  /// [Overlay] on demand.
  OverlayEntry? _titleSuggestionsOverlayEntry;

  /// Set on Escape to hide the title suggestions dropdown until the next
  /// keystroke — otherwise a pure recompute from unchanged text would
  /// show the same suggestions right back.
  bool _titleSuggestionsDismissed = false;

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
    _titleFocusNode = FocusNode()
      ..addListener(() {
        if (mounted) setState(() {});
      });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _activeFromController.dispose();
    _repeatCountController.dispose();
    _titleFocusNode.dispose();
    _titleSuggestionsOverlayEntry?.remove();
    _titleSuggestionsOverlayEntry?.dispose();
    super.dispose();
  }

  /// Applies every keystroke immediately. In create mode, the task doesn't
  /// exist yet — the first non-empty value creates it (carrying along
  /// whatever category/closed the user already picked before typing);
  /// every keystroke after that, in either mode, updates the existing task.
  ///
  /// When the cursor is at the end and the just-typed text ends with
  /// `#tag `, that chunk is stripped from the title and added as a tag.
  /// Likewise for `@category` (matched against real category names —
  /// see [extractTrailingCategory]), which sets [_categoryId]; `from
  /// dd/mm[/yy]`, which sets [_activeFrom]; and `every` followed by a
  /// count and unit (e.g. `every 1w`/`every 1 week`), which sets
  /// [_repeat].
  Future<void> _onTitleChanged(String rawTitle) async {
    _titleSuggestionsDismissed = false;
    // Unconditional: a keystroke that matches no extraction pattern below
    // (e.g. an unfinished "#gro") still needs to rebuild so the
    // post-frame callback in build() re-syncs the title suggestions
    // dropdown for the new cursor/text state — the extraction-specific
    // setState calls further down only fire when a token actually
    // completes.
    setState(() {});
    final atEnd = _titleController.selection.baseOffset == rawTitle.length;
    final tagExtraction = atEnd ? extractTrailingTag(rawTitle) : null;
    final afterTag = tagExtraction?.title ?? rawTitle;
    final categories = ref.read(categoryListProvider).value ?? const [];
    final categoryExtraction = atEnd
        ? extractTrailingCategory(afterTag, categories)
        : null;
    final afterCategory = categoryExtraction?.title ?? afterTag;
    final activeFromExtraction = atEnd
        ? extractTrailingActiveFrom(afterCategory)
        : null;
    final afterActiveFrom = activeFromExtraction?.title ?? afterCategory;
    final repeatExtraction = atEnd
        ? extractTrailingRepeat(afterActiveFrom)
        : null;
    final title = repeatExtraction?.title ?? afterActiveFrom;
    if (tagExtraction != null ||
        categoryExtraction != null ||
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
    final newCategoryId = categoryExtraction?.categoryId;
    if (newCategoryId != null) setState(() => _categoryId = newCategoryId);
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
        categoryId: newCategoryId,
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
        categoryId: newCategoryId,
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
    final categories = ref.read(categoryListProvider).value ?? const [];
    final categoryExtraction = extractFinalCategory(
      tagExtraction?.title ?? _titleController.text,
      categories,
    );
    final activeFromExtraction = extractFinalActiveFrom(
      categoryExtraction?.title ??
          tagExtraction?.title ??
          _titleController.text,
    );
    final repeatExtraction = extractFinalRepeat(
      activeFromExtraction?.title ??
          categoryExtraction?.title ??
          tagExtraction?.title ??
          _titleController.text,
    );
    if (tagExtraction == null &&
        categoryExtraction == null &&
        activeFromExtraction == null &&
        repeatExtraction == null) {
      return;
    }
    final title =
        repeatExtraction?.title ??
        activeFromExtraction?.title ??
        categoryExtraction?.title ??
        tagExtraction!.title;
    _titleController.value = TextEditingValue(
      text: title,
      selection: TextSelection.collapsed(offset: title.length),
    );
    final newTags = tagExtraction == null || _tags.contains(tagExtraction.tag)
        ? _tags
        : [..._tags, tagExtraction.tag];
    final newCategoryId = categoryExtraction?.categoryId ?? _categoryId;
    final newActiveFrom = activeFromExtraction?.activeFrom ?? _activeFrom;
    final newRepeat = repeatExtraction?.repeat ?? _repeat;
    setState(() {
      _tags = newTags;
      if (categoryExtraction != null) _categoryId = newCategoryId;
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
          categoryId: categoryExtraction?.categoryId,
          activeFrom: activeFromExtraction?.activeFrom,
          repeat: repeatExtraction?.repeat,
        );
  }

  /// The title's suggestions dropdown current answer — tag names while
  /// the text immediately before the cursor ends in an unfinished
  /// `#word`, category names while it ends in an unfinished `@word`.
  /// `null` hides the dropdown: no partial match, no candidates,
  /// dismissed via Escape, or the title field isn't focused. Mirrors
  /// `_TasksScreenState._currentSuggestions` in `tasks_screen.dart`.
  ({List<String> options, _TitleSuggestionKind kind})?
  _currentTitleSuggestions() {
    if (_titleSuggestionsDismissed || !_titleFocusNode.hasFocus) return null;
    final cursor = _titleController.selection.baseOffset;
    if (cursor < 0) return null;
    final beforeCursor = _titleController.text.substring(0, cursor);
    final tagMatch = _partialTitleTagPattern.firstMatch(beforeCursor);
    if (tagMatch != null) {
      final partial = tagMatch.group(2)!.toLowerCase();
      final tasks = ref.read(taskListProvider).value ?? const <Task>[];
      final allTags = <String>{for (final t in tasks) ...t.tags};
      final options =
          allTags
              .difference(_tags.toSet())
              .where((tag) => tag.startsWith(partial))
              .toList()
            ..sort();
      return options.isEmpty
          ? null
          : (
              options: options.take(_maxTitleSuggestions).toList(),
              kind: _TitleSuggestionKind.tag,
            );
    }
    final categoryMatch = _partialTitleCategoryPattern.firstMatch(beforeCursor);
    if (categoryMatch != null) {
      final partial = categoryMatch.group(2)!.toLowerCase();
      final categories = ref.read(categoryListProvider).value ?? const [];
      final options =
          categories
              .map((c) => c.name.toLowerCase())
              .where((name) => name.startsWith(partial))
              .toList()
            ..sort();
      return options.isEmpty
          ? null
          : (
              options: options.take(_maxTitleSuggestions).toList(),
              kind: _TitleSuggestionKind.category,
            );
    }
    return null;
  }

  /// Completes the unfinished token immediately before the cursor with
  /// [option] plus a trailing space, then reinserts whatever followed the
  /// cursor — same shape a manually-typed `#tag `/`@category ` settles
  /// to — and re-runs [_onTitleChanged] on the result, since setting
  /// [_titleController]'s value directly doesn't itself invoke the
  /// field's `onChanged`.
  void _selectTitleSuggestion(
    String option, {
    required _TitleSuggestionKind kind,
  }) {
    final cursor = _titleController.selection.baseOffset;
    final text = _titleController.text;
    final beforeCursor = text.substring(0, cursor);
    final afterCursor = text.substring(cursor);
    final pattern = kind == _TitleSuggestionKind.tag
        ? _partialTitleTagPattern
        : _partialTitleCategoryPattern;
    final match = pattern.firstMatch(beforeCursor)!;
    final symbol = kind == _TitleSuggestionKind.tag ? '#' : '@';
    final prefix = beforeCursor.substring(0, match.start) + match.group(1)!;
    final completed = '$prefix$symbol$option ';
    _titleController.value = TextEditingValue(
      text: completed + afterCursor,
      selection: TextSelection.collapsed(offset: completed.length),
    );
    unawaited(_onTitleChanged(_titleController.text));
  }

  /// Inserts, rebuilds, or removes the floating title-suggestions
  /// dropdown to match [_currentTitleSuggestions]'s current answer.
  /// Called after every frame so it always runs once the title field's
  /// [_titleFieldBoxKey] render box is guaranteed to be laid out.
  void _syncTitleSuggestionsOverlay() {
    final hasSuggestions = _currentTitleSuggestions() != null;
    if (!hasSuggestions) {
      _titleSuggestionsOverlayEntry?.remove();
      _titleSuggestionsOverlayEntry?.dispose();
      _titleSuggestionsOverlayEntry = null;
      return;
    }
    if (_titleSuggestionsOverlayEntry != null) {
      _titleSuggestionsOverlayEntry!.markNeedsBuild();
      return;
    }
    final entry = OverlayEntry(builder: _buildTitleSuggestionsOverlay);
    _titleSuggestionsOverlayEntry = entry;
    Overlay.of(context).insert(entry);
  }

  /// Builds the floating dropdown's content, re-reading
  /// [_currentTitleSuggestions] fresh each time.
  Widget _buildTitleSuggestionsOverlay(BuildContext context) {
    final suggestions = _currentTitleSuggestions();
    if (suggestions == null) return const SizedBox.shrink();
    final fieldBox =
        _titleFieldBoxKey.currentContext?.findRenderObject() as RenderBox?;
    final fieldSize = fieldBox?.size ?? const Size(300, 48);
    return Positioned(
      width: fieldSize.width,
      child: CompositedTransformFollower(
        link: _titleFieldLink,
        showWhenUnlinked: false,
        offset: Offset(0, fieldSize.height + 4),
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final option in suggestions.options)
                  GestureDetector(
                    onTapDown: (_) =>
                        _selectTitleSuggestion(option, kind: suggestions.kind),
                    child: ListTile(
                      dense: true,
                      leading: Icon(
                        suggestions.kind == _TitleSuggestionKind.tag
                            ? Icons.tag
                            : Icons.category,
                      ),
                      title: Text(option),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  KeyEventResult _handleTitleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      if (_currentTitleSuggestions() != null) {
        setState(() => _titleSuggestionsDismissed = true);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
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
    // Overlay content can only be sized/positioned off the title field's
    // render box once this frame has actually laid it out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncTitleSuggestionsOverlay();
    });
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
                    child: CompositedTransformTarget(
                      link: _titleFieldLink,
                      child: Focus(
                        onKeyEvent: _handleTitleKeyEvent,
                        child: Container(
                          key: _titleFieldBoxKey,
                          child: TextField(
                            key: const Key('task-title-field'),
                            controller: _titleController,
                            focusNode: _titleFocusNode,
                            style: TextStyle(
                              decoration: _closed
                                  ? TextDecoration.lineThrough
                                  : null,
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
                      ),
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
                    child: TextField(
                      key: const Key('task-repeat-number-field'),
                      controller: _repeatCountController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText: 'Repeat',
                        hintText: '0',
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            DropdownButton<String>(
                              key: const Key('task-repeat-unit-dropdown'),
                              value: _repeatUnit,
                              underline: const SizedBox.shrink(),
                              items: [
                                for (final entry in _repeatUnits.entries)
                                  DropdownMenuItem(
                                    value: entry.key,
                                    child: Text(entry.value),
                                  ),
                              ],
                              onChanged: _onRepeatUnitChanged,
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
                      ),
                      onChanged: _onRepeatCountChanged,
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
