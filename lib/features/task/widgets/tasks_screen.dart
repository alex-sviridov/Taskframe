import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:taskframe/core/responsive.dart';
import 'package:taskframe/features/category/models/category.dart';
import 'package:taskframe/features/category/providers.dart';
import 'package:taskframe/features/saved_search/models/saved_search.dart';
import 'package:taskframe/features/saved_search/providers.dart';
import 'package:taskframe/features/task/models/task.dart';
import 'package:taskframe/features/task/providers.dart';
import 'package:taskframe/features/task/search_query.dart';
import 'package:taskframe/features/task/widgets/task_card.dart';
import 'package:taskframe/features/task/widgets/task_edit_modal.dart';

/// Matches an *unfinished* `#word`/`#!word` immediately before the
/// cursor — no trailing space yet — so suggestions can be offered while
/// the user is still typing it, wherever the cursor currently sits.
///
/// The captured word uses `[^\s#/@]` rather than `\w`, since `\w` in
/// Dart's RegExp is ASCII-only ([A-Za-z0-9_]) and would silently fail to
/// match tags/categories containing letters outside that range (e.g.
/// Cyrillic); trigger characters (#/@) stay excluded so this still stops
/// at a following token typed with no space.
final _partialTagPattern = RegExp(r'(^|\s)#(!?)([^\s#/@]*)$');

/// The `/` counterpart of [_partialTagPattern].
final _partialStatusPattern = RegExp(r'(^|\s)/(!?)([^\s#/@]*)$');

/// The `@` counterpart of [_partialTagPattern].
final _partialCategoryPattern = RegExp(r'(^|\s)@(!?)([^\s#/@]*)$');

/// Which kind of token the suggestions dropdown is currently offering —
/// decides both the icon shown per row and which symbol/lookup
/// [_TasksScreenState._selectSuggestion] uses to complete it.
enum _TokenKind { tag, status, category }

/// Suggestions dropdown never lists more than this many options — the
/// tag/status vocabulary can grow arbitrarily large, but a floating list
/// longer than a handful of rows stops being scannable.
const _maxSuggestions = 4;

/// A [TextEditingController] whose [buildTextSpan] renders recognized
/// `#tag`/`#!tag`/`/opened`/`/!opened` tokens (see [parseSearchQuery])
/// as styled text within the one real, actively-edited field — bold +
/// tinted when included, error-toned when excluded.
///
/// Tokens are *not* given a `TextSpan.recognizer`: `RenderEditable`
/// asserts that any span with a recognizer requires a read-only,
/// non-obscured field (see
/// `RenderEditable.describeSemanticsConfiguration` in the Flutter
/// framework), which this field — still directly editable — is not.
/// Tap-to-toggle is instead handled by
/// `_TasksScreenState._handleFieldTap`, which hit-tests the tap
/// position against each token's rendered glyph boxes via
/// [RenderEditable.getBoxesForSelection].
class UnifiedQueryController extends TextEditingController {
  /// Creates a controller seeded with [text] (defaults to empty).
  new({super.text});

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    required bool withComposing,
    TextStyle? style,
  }) {
    final parsed = parseSearchQuery(text);
    final tokens = orderedTokenRanges(parsed);
    final colors = Theme.of(context).colorScheme;
    final spans = <TextSpan>[];
    var cursor = 0;
    for (final token in tokens) {
      if (token.range.start > cursor) {
        spans.add(
          TextSpan(
            text: text.substring(cursor, token.range.start),
            style: style,
          ),
        );
      }
      spans.add(
        TextSpan(
          text: text.substring(token.range.start, token.range.end),
          style: (style ?? const TextStyle()).copyWith(
            fontWeight: FontWeight.w600,
            color: token.excluded
                ? colors.onErrorContainer
                : colors.onPrimaryContainer,
            backgroundColor: token.excluded
                ? colors.errorContainer
                : colors.primaryContainer,
          ),
        ),
      );
      cursor = token.range.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor), style: style));
    }
    return TextSpan(style: style, children: spans);
  }
}

/// Lists every task as a [TaskCard], in creation order, and lets the user
/// add or edit one via [showTaskEditModal]. Closing a task is a checkbox
/// on its own card — see [TaskCard] — so this screen only wires up
/// add/open-for-edit.
///
/// A single search field doubles as the query: plain text filters by
/// title, `#tag`/`#!tag` anywhere in the text filters tasks by tag
/// (multiple combine with AND), `@category`/`@!category` filters by the
/// task's category name (multiple also combine with AND — since a task
/// has exactly one category, more than one *included* category can
/// never match), and `/opened`/`/!opened` filters by closed status. With
/// no status token, closed tasks are shown only if closed today or
/// later — `/!opened` is required to see ones closed before today.
/// Recognized tokens render as styled (not extracted)
/// text — tapping one toggles it between included/excluded; removing
/// one is plain text editing. The whole query string mirrors to/from the
/// `q` query parameter of the current route (when reached via
/// [GoRouter]), so it's shareable and survives a refresh.
class TasksScreen extends ConsumerStatefulWidget {
  /// Creates a [TasksScreen].
  const new({super.key});

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  late final UnifiedQueryController _searchController;
  late final FocusNode _searchFocusNode;

  /// Anchors the floating suggestions dropdown to the search field's
  /// current position/size, via [CompositedTransformTarget] and
  /// [CompositedTransformFollower].
  final LayerLink _searchFieldLink = LayerLink();

  /// Reads the search field's laid-out size, so the floating dropdown
  /// (built outside the field's own layout via [Overlay]) can match its
  /// width and sit directly below it.
  final GlobalKey _searchFieldKey = GlobalKey();

  /// The floating suggestions dropdown, inserted into the ambient
  /// [Overlay] on demand (see [_syncSuggestionsOverlay]) rather than laid
  /// out inline, so it floats over the task list instead of pushing it
  /// down.
  OverlayEntry? _suggestionsOverlayEntry;

  /// Set on Escape to hide the suggestions dropdown until the next
  /// keystroke (see [_onSearchChanged], which clears it) — otherwise a
  /// pure recompute of [_currentSuggestions] from unchanged text would
  /// show the same suggestions right back.
  bool _suggestionsDismissed = false;

  /// Whether the filter row (the `#tag` / `/status` / `@category` quick
  /// insert buttons below the search field) is currently shown. Toggled
  /// only by the filter icon in the search field's suffix — inserting a
  /// symbol via one of the row's own buttons leaves it open, so more than
  /// one filter can be added without reopening it.
  bool _filterRowOpen = false;

  /// The most recent pointer-down position on the search field, in
  /// global coordinates — captured by the wrapping [Listener] so
  /// [_handleFieldTap] (which [TextField.onTap] calls with no position
  /// of its own) can test the tap against each token's actual on-screen
  /// character boxes. Deliberately *not* derived from the resulting
  /// caret offset: a caret offset is a boundary between characters, not
  /// proof a tap landed on a glyph (tapping the trailing half of a
  /// token's last character, the space just before a token, or the
  /// field's empty leading padding can all resolve to a caret offset
  /// that numerically falls inside — or right at the edge of — a
  /// token's range without the tap having visually landed on it).
  Offset? _lastPointerDownPosition;

  @override
  void initState() {
    super.initState();
    final params = GoRouter.maybeOf(context)?.state.uri.queryParameters;
    _searchController = UnifiedQueryController(text: params?['q'] ?? '')
      ..addListener(_onSearchChanged);
    _searchFocusNode = FocusNode()
      ..addListener(() {
        if (mounted) setState(() {});
      });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // `GoRouter.maybeOf(context)?.state` (unlike [GoRouterState.of]) does
    // not register this as a listener of route changes, so it would never
    // see a `q` update that happens while this screen stays mounted — as
    // when a saved view navigates here via `context.go('/tasks?q=...')`.
    // [GoRouterState.of] does subscribe, via an [InheritedWidget], so this
    // re-runs whenever the route's query actually changes.
    if (GoRouter.maybeOf(context) == null) return;
    final urlQuery = GoRouterState.of(context).uri.queryParameters['q'] ?? '';
    if (urlQuery != _searchController.text) {
      // Bypass the listener that normally fires on every edit: it calls
      // [_syncUrl], which would push another route change right back at
      // the router while this screen is still building in response to the
      // first one.
      _searchController.removeListener(_onSearchChanged);
      _searchController.value = TextEditingValue(
        text: urlQuery,
        selection: TextSelection.collapsed(offset: urlQuery.length),
      );
      _searchController.addListener(_onSearchChanged);
    }
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _suggestionsOverlayEntry?.remove();
    _suggestionsOverlayEntry?.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _suggestionsDismissed = false;
    setState(() {});
    _syncUrl();
  }

  /// Toggles the token at [range] (currently `excluded` or not) by
  /// inserting/removing its `!`, then re-applies the result as the
  /// field's new value — this re-enters [_onSearchChanged] via the
  /// controller's own listener, so the rebuild/URL-sync happens there.
  void _toggleToken(TextRange range, {required bool excluded}) {
    final result = toggleQueryToken(
      _searchController.text,
      range,
      currentlyExcluded: excluded,
      cursorOffset: _searchController.selection.baseOffset,
    );
    _searchController.value = TextEditingValue(
      text: result.text,
      selection: TextSelection.collapsed(offset: result.cursorOffset),
    );
  }

  /// Inserts [symbol] (`#`, `/`, or `@`) at the search field's current
  /// cursor position — same character a manually-typed token starts
  /// with, so the existing suggestions dropdown (which already matches
  /// an empty partial) opens for it. A leading space is added first when
  /// the cursor doesn't already sit at the start of the text or right
  /// after whitespace, so the inserted symbol doesn't fuse onto the
  /// preceding word.
  void _insertSymbol(String symbol) {
    final text = _searchController.text;
    var cursor = _searchController.selection.baseOffset;
    if (cursor < 0) cursor = text.length;
    final needsLeadingSpace = cursor > 0 && text[cursor - 1] != ' ';
    final insertion = (needsLeadingSpace ? ' ' : '') + symbol;
    final newText = text.replaceRange(cursor, cursor, insertion);
    final newCursor = cursor + insertion.length;
    _searchController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newCursor),
    );
    _searchFocusNode.requestFocus();
    // A field that gains focus programmatically (rather than via a direct
    // tap on it) selects all of its text on desktop/web platforms — this
    // clobbers the collapsed selection just set above. Reassert it once
    // that focus-driven selection has been applied. (Not exercised by
    // widget tests: flutter_test runs under a fixed non-desktop
    // TargetPlatform, which doesn't reproduce this platform-specific
    // behavior — see the e2e test instead.)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _searchController.selection = TextSelection.collapsed(offset: newCursor);
    });
  }

  /// Called on every tap on the search field (see [TextField.onTap]).
  /// Uses [_lastPointerDownPosition] — the raw pixel position the
  /// wrapping [Listener] captured for this tap — against each
  /// recognized token's actual rendered character boxes (via
  /// [RenderEditable.getBoxesForSelection]) to decide whether the tap
  /// landed on a token; if so, toggles it via [_toggleToken] instead of
  /// leaving a plain cursor placement. Testing real glyph geometry
  /// (rather than the resulting caret offset) is deliberate: a caret
  /// offset is a boundary between characters, not proof a tap landed on
  /// a glyph.
  void _handleFieldTap() {
    final position = _lastPointerDownPosition;
    if (position == null) return;
    final root = _searchFieldKey.currentContext?.findRenderObject();
    if (root == null) return;
    final renderEditable = _findRenderEditable(root);
    if (renderEditable == null) return;
    final local = renderEditable.globalToLocal(position);
    final parsed = parseSearchQuery(_searchController.text);
    for (final token in orderedTokenRanges(parsed)) {
      final boxes = renderEditable.getBoxesForSelection(
        TextSelection(
          baseOffset: token.range.start,
          extentOffset: token.range.end,
        ),
      );
      if (boxes.any((box) => box.toRect().contains(local))) {
        _toggleToken(token.range, excluded: token.excluded);
        return;
      }
    }
  }

  /// Depth-first search of the render tree rooted at [root] for the
  /// first [RenderEditable] — [TextField] has no public getter for its
  /// internal one, but it's always present a few layers down (inside
  /// its [EditableText]).
  RenderEditable? _findRenderEditable(RenderObject root) {
    RenderEditable? found;
    void visit(RenderObject child) {
      if (found != null) return;
      if (child is RenderEditable) {
        found = child;
        return;
      }
      child.visitChildren(visit);
    }

    visit(root);
    return found;
  }

  /// The dropdown's current suggestions — tag names while the text
  /// immediately before the cursor ends in an unfinished `#word`/
  /// `#!word`, category names while it ends in an unfinished `@word`/
  /// `@!word`, or `opened` while it ends in an unfinished `/word`/
  /// `/!word` and no status filter is set yet. `null` hides the
  /// dropdown: no partial match, no candidates, dismissed via Escape, or
  /// the field isn't focused.
  ({List<String> options, _TokenKind kind})? _currentSuggestions(
    List<Task> tasks,
    List<Category> categories,
  ) {
    if (_suggestionsDismissed || !_searchFocusNode.hasFocus) return null;
    final cursor = _searchController.selection.baseOffset;
    if (cursor < 0) return null;
    final beforeCursor = _searchController.text.substring(0, cursor);
    final tagMatch = _partialTagPattern.firstMatch(beforeCursor);
    if (tagMatch != null) {
      final partial = tagMatch.group(3)!.toLowerCase();
      final parsed = parseSearchQuery(_searchController.text);
      final selected = {for (final t in parsed.tagTokens) t.tag};
      final allTags = <String>{for (final task in tasks) ...task.tags};
      final options =
          allTags
              .difference(selected)
              .where((tag) => tag.startsWith(partial))
              .toList()
            ..sort();
      return options.isEmpty
          ? null
          : (
              options: options.take(_maxSuggestions).toList(),
              kind: _TokenKind.tag,
            );
    }
    final categoryMatch = _partialCategoryPattern.firstMatch(beforeCursor);
    if (categoryMatch != null) {
      final partial = categoryMatch.group(3)!.toLowerCase();
      final parsed = parseSearchQuery(_searchController.text);
      final selected = {for (final t in parsed.categoryTokens) t.category};
      final allCategoryNames = <String>{
        for (final category in categories) category.name.toLowerCase(),
      };
      final options =
          allCategoryNames
              .difference(selected)
              .where((name) => name.startsWith(partial))
              .toList()
            ..sort();
      return options.isEmpty
          ? null
          : (
              options: options.take(_maxSuggestions).toList(),
              kind: _TokenKind.category,
            );
    }
    final statusMatch = _partialStatusPattern.firstMatch(beforeCursor);
    if (statusMatch != null) {
      final parsed = parseSearchQuery(_searchController.text);
      final partial = statusMatch.group(3)!.toLowerCase();
      final options = [
        if (parsed.statusToken == null && openedStatusWord.startsWith(partial))
          openedStatusWord,
        if (parsed.activeToken == null && activeStatusWord.startsWith(partial))
          activeStatusWord,
      ];
      if (options.isNotEmpty) {
        return (options: options, kind: _TokenKind.status);
      }
    }
    return null;
  }

  /// Completes the unfinished token immediately before the cursor with
  /// [option] plus a trailing space, then reinserts whatever followed
  /// the cursor — same shape a manually-typed `#tag `/`@category `/
  /// `/opened ` settles to, so the assignment re-enters
  /// [_onSearchChanged].
  void _selectSuggestion(String option, {required _TokenKind kind}) {
    final cursor = _searchController.selection.baseOffset;
    final text = _searchController.text;
    final beforeCursor = text.substring(0, cursor);
    final afterCursor = text.substring(cursor);
    final pattern = switch (kind) {
      _TokenKind.status => _partialStatusPattern,
      _TokenKind.tag => _partialTagPattern,
      _TokenKind.category => _partialCategoryPattern,
    };
    final match = pattern.firstMatch(beforeCursor)!;
    final prefix = beforeCursor.substring(0, match.start) + match.group(1)!;
    final symbol = switch (kind) {
      _TokenKind.status => '/',
      _TokenKind.tag => '#',
      _TokenKind.category => '@',
    };
    final completed = '$prefix$symbol${match.group(2)}$option ';
    _searchController.value = TextEditingValue(
      text: completed + afterCursor,
      selection: TextSelection.collapsed(offset: completed.length),
    );
  }

  /// Inserts, rebuilds, or removes the floating suggestions dropdown to
  /// match [_currentSuggestions]'s current answer. Called after every
  /// frame (see the `addPostFrameCallback` in [build]) so it always runs
  /// once the search field's [_searchFieldKey] render box — needed to
  /// size/position the dropdown — is guaranteed to be laid out.
  void _syncSuggestionsOverlay() {
    final tasks = ref.read(taskListProvider).value ?? const <Task>[];
    final categories =
        ref.read(categoryListProvider).value ?? const <Category>[];
    final hasSuggestions = _currentSuggestions(tasks, categories) != null;
    if (!hasSuggestions) {
      _suggestionsOverlayEntry?.remove();
      _suggestionsOverlayEntry?.dispose();
      _suggestionsOverlayEntry = null;
      return;
    }
    if (_suggestionsOverlayEntry != null) {
      _suggestionsOverlayEntry!.markNeedsBuild();
      return;
    }
    final entry = OverlayEntry(builder: _buildSuggestionsOverlay);
    _suggestionsOverlayEntry = entry;
    Overlay.of(context).insert(entry);
  }

  /// Builds the floating dropdown's content, re-reading
  /// [_currentSuggestions] fresh each time (rather than capturing a stale
  /// snapshot) since [OverlayEntry.markNeedsBuild] just re-invokes this.
  Widget _buildSuggestionsOverlay(BuildContext context) {
    final tasks = ref.read(taskListProvider).value ?? const <Task>[];
    final categories =
        ref.read(categoryListProvider).value ?? const <Category>[];
    final suggestions = _currentSuggestions(tasks, categories);
    if (suggestions == null) return const SizedBox.shrink();
    final fieldBox =
        _searchFieldKey.currentContext?.findRenderObject() as RenderBox?;
    final fieldSize = fieldBox?.size ?? const Size(300, 48);
    return Positioned(
      width: fieldSize.width,
      child: CompositedTransformFollower(
        link: _searchFieldLink,
        showWhenUnlinked: false,
        offset: Offset(0, fieldSize.height + 4),
        // Keeps the search field focused (and the dropdown itself open)
        // while a suggestion is being tapped — without this, the tap
        // target's own focusable ink response steals focus on the way
        // down, which would hide the dropdown (and remove the tapped
        // row) before the tap completes.
        //
        // TextFieldTapRegion additionally keeps the search field itself
        // focused *after* the tap completes: the dropdown lives in the
        // ambient Overlay, outside the field's own widget subtree, so
        // without this a completed tap still counts as "outside" the
        // field and triggers its default tap-outside unfocus behavior.
        // TextFieldTapRegion's default groupId groups it with every text
        // field, so this works regardless of which field is focused.
        child: TextFieldTapRegion(
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
                      // Selection fires on tap-DOWN, not tap-up: by tap-up,
                      // the search field may already have lost focus (see
                      // above) and this row rebuilt away.
                      onTapDown: (_) =>
                          _selectSuggestion(option, kind: suggestions.kind),
                      child: ListTile(
                        dense: true,
                        leading: Icon(switch (suggestions.kind) {
                          _TokenKind.status => Icons.radio_button_unchecked,
                          _TokenKind.tag => Icons.tag,
                          _TokenKind.category => Icons.category,
                        }),
                        title: Text(option),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The row of quick-insert filter buttons shown below the search field
  /// while [_filterRowOpen] is true — tapping one inserts its symbol via
  /// [_insertSymbol], which reopens the existing suggestions dropdown for
  /// that kind of token.
  Widget _buildFilterRow() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      // A focusable tap target (e.g. ActionChip, which owns its own
      // FocusNode) claims focus for itself right after its onPressed
      // fires, undoing _insertSymbol's own requestFocus() call on the
      // search field. Every button below is therefore a plain
      // GestureDetector (never focusable on its own) reacting to
      // onTapDown — the same fix the suggestions dropdown uses (see its
      // own `Focus(canRequestFocus: false, ...)` above) and for the same
      // reason.
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        child: Row(
          children: [
            _filterButton(icon: Icons.tag, label: '#tag', symbol: '#'),
            const SizedBox(width: 8),
            _filterButton(
              icon: Icons.radio_button_unchecked,
              label: '/status',
              symbol: '/',
            ),
            const SizedBox(width: 8),
            _filterButton(
              icon: Icons.category,
              label: '@category',
              symbol: '@',
            ),
          ],
        ),
      ),
    );
  }

  /// One quick-insert button of [_buildFilterRow] — a static (visually
  /// chip-like) [Chip] for display plus a [GestureDetector] for the tap
  /// itself, so nothing in the subtree owns a [FocusNode] that could
  /// steal focus from the search field (see [_buildFilterRow]'s doc).
  Widget _filterButton({
    required IconData icon,
    required String label,
    required String symbol,
  }) {
    return GestureDetector(
      onTapDown: (_) => _insertSymbol(symbol),
      child: Chip(avatar: Icon(icon, size: 18), label: Text(label)),
    );
  }

  KeyEventResult _handleSearchKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      final tasks = ref.read(taskListProvider).value ?? const <Task>[];
      final categories =
          ref.read(categoryListProvider).value ?? const <Category>[];
      if (_currentSuggestions(tasks, categories) != null) {
        setState(() => _suggestionsDismissed = true);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void _syncUrl() {
    final router = GoRouter.maybeOf(context);
    if (router == null) return;
    final text = _searchController.text;
    unawaited(
      router.replace<void>(
        Uri(
          path: '/tasks',
          queryParameters: text.isEmpty ? null : {'q': text},
        ).toString(),
      ),
    );
  }

  List<Task> _filter(List<Task> tasks, List<Category> categories) {
    final parsed = parseSearchQuery(_searchController.text);
    final query = parsed.freeText.toLowerCase();
    final categoryNameById = {
      for (final category in categories)
        category.id: category.name.toLowerCase(),
    };
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    return [
      for (final task in tasks)
        if ((query.isEmpty || task.title.toLowerCase().contains(query)) &&
            (parsed.statusToken != null
                ? task.closed == parsed.statusToken!.excluded
                : !(task.closed &&
                      task.closedAt != null &&
                      task.closedAt!.isBefore(todayStart))) &&
            (parsed.activeToken == null ||
                task.isNotYetActive == parsed.activeToken!.excluded) &&
            parsed.tagTokens.every(
              (t) => t.excluded
                  ? !task.tags.contains(t.tag)
                  : task.tags.contains(t.tag),
            ) &&
            parsed.categoryTokens.every((t) {
              final taskCategoryName = categoryNameById[task.categoryId];
              return t.excluded
                  ? taskCategoryName != t.category
                  : taskCategoryName == t.category;
            }))
          task,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final tasksAsync = ref.watch(taskListProvider);
    final categoriesAsync = ref.watch(categoryListProvider);
    // Overlay content can only be sized/positioned off the search field's
    // render box once this frame has actually laid it out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncSuggestionsOverlay();
    });

    final savedViews =
        ref.watch(savedSearchListProvider).value ?? const <SavedSearch>[];
    final currentQuery = _searchController.text.trim();
    SavedSearch? matchingView;
    for (final view in savedViews) {
      if (view.query == currentQuery) {
        matchingView = view;
        break;
      }
    }

    return Scaffold(
      appBar: AppBar(
        // Reserves the leading slot so AppShell's floating hamburger button
        // (narrow widths only) has room without covering the title.
        leading: const SizedBox(),
        title: const Text('Tasks'),
        actions: [
          IconButton(
            tooltip: 'Add task',
            icon: const Icon(Icons.add),
            onPressed: () => showTaskEditModal(context: context),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(_filterRowOpen ? 104 : 56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CompositedTransformTarget(
                  link: _searchFieldLink,
                  child: Focus(
                    onKeyEvent: _handleSearchKeyEvent,
                    child: Listener(
                      onPointerDown: (event) =>
                          _lastPointerDownPosition = event.position,
                      child: TextField(
                        key: _searchFieldKey,
                        controller: _searchController,
                        focusNode: _searchFocusNode,
                        onTap: _handleFieldTap,
                        decoration: InputDecoration(
                          hintText:
                              'Search: #tag  @category  /opened  /active  '
                              'free text',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_searchController.text.isNotEmpty)
                                IconButton(
                                  icon: const Icon(Icons.clear),
                                  tooltip: 'Clear search',
                                  onPressed: _searchController.clear,
                                ),
                              IconButton(
                                icon: const Icon(Icons.filter_alt),
                                tooltip: 'Filters',
                                color: _filterRowOpen
                                    ? Theme.of(context).colorScheme.primary
                                    : null,
                                onPressed: () => setState(
                                  () => _filterRowOpen = !_filterRowOpen,
                                ),
                              ),
                              if (currentQuery.isNotEmpty)
                                IconButton(
                                  icon: Icon(
                                    matchingView != null
                                        ? Icons.star
                                        : Icons.star_border,
                                  ),
                                  tooltip: matchingView != null
                                      ? 'Remove pinned view'
                                      : 'Pin this search',
                                  onPressed: () {
                                    if (matchingView != null) {
                                      unawaited(
                                        ref
                                            .read(
                                              savedSearchListProvider.notifier,
                                            )
                                            .deleteView(matchingView),
                                      );
                                    } else {
                                      unawaited(
                                        ref
                                            .read(
                                              savedSearchListProvider.notifier,
                                            )
                                            .addView(currentQuery),
                                      );
                                    }
                                  },
                                ),
                            ],
                          ),
                          isDense: true,
                          filled: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (_filterRowOpen) _buildFilterRow(),
              ],
            ),
          ),
        ),
      ),
      body: switch (tasksAsync) {
        AsyncData(:final value) => LayoutBuilder(
          builder: (context, constraints) {
            final isNarrowWidth = constraints.maxWidth < narrowBreakpoint;
            final list = ListView(
              padding: isNarrowWidth
                  ? EdgeInsets.zero
                  : const EdgeInsets.symmetric(vertical: 8),
              children: [
                for (final task in _filter(
                  value,
                  categoriesAsync.value ?? const <Category>[],
                ))
                  TaskCard(
                    task: task,
                    onTap: () =>
                        showTaskEditModal(context: context, task: task),
                  ),
              ],
            );
            if (isNarrowWidth) return list;
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: list,
              ),
            );
          },
        ),
        AsyncError() => const Center(child: Text('Failed to load tasks')),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}
