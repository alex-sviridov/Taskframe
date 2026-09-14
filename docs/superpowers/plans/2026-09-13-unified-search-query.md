# Unified Search Query Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the tasks screen's separate free-text field + pill-row
search UI with a single unified text input, where `#tag`/`#!tag` and
`/opened`/`/!opened` tokens render as styled (bold, tinted) text inline
within the same field, tap-to-toggle, and everything (filtering, URL
sync, autocomplete) derives from parsing that one string fresh on every
change.

**Architecture:** A new pure-Dart module (`search_query.dart`) parses a
raw query string into tag/status tokens (with exact character ranges)
plus leftover free text, and mutates a token's `!` in place. A custom
`TextEditingController.buildTextSpan` override renders those token
ranges as styled, tappable `TextSpan`s directly inside the one real,
actively-edited `TextField` — no second field, no overlay. `tasks_screen.dart`'s
filtering, URL sync (`q` only), and autocomplete (now cursor-relative,
not end-of-string) all derive from `parseSearchQuery` calls instead of
the `_selectedTags`/`_openedFilter` fields being replaced.

**Tech Stack:** Flutter/Dart, `flutter_riverpod`, `go_router`. No new
dependencies.

**Spec:** `docs/superpowers/specs/2026-09-13-unified-search-query-design.md`

## Global Constraints

- One `TextEditingController`, one `TextField` for the search bar — no
  ghost/ invisible field, no `Stack` overlay.
- Recognized tokens render as styled text (bold + tinted
  foreground/background, error-toned when excluded) — not rounded chip
  widgets.
- No delete (X) affordance on a token — removal is plain text editing.
- Autocomplete triggers on an unfinished token immediately before the
  *cursor* (`_searchController.selection.baseOffset`), not just at the
  end of the string.
- URL sync uses a single `q` param holding the raw query string
  verbatim. The `tags`/`status` params are retired — a URL using them is
  read as if `q` were absent (empty query), not an error.
- `lib/features/task/tag_parsing.dart` (used by the edit modal) is
  untouched — this plan only touches the tasks screen's search bar.

---

### Task 1: `search_query.dart` — parser

**Files:**
- Create: `lib/features/task/search_query.dart`
- Test: `test/unit/search_query_test.dart`

**Interfaces:**
- Consumes: nothing (pure Dart, only `TextRange` from
  `package:flutter/services.dart`).
- Produces: `openedStatusWord` (`const String`), `TagToken` (`tag: String`,
  `excluded: bool`, `range: TextRange`), `StatusToken` (`excluded: bool`,
  `range: TextRange`), `ParsedQuery` (`tagTokens: List<TagToken>`,
  `statusToken: StatusToken?`, `freeText: String`), and
  `ParsedQuery parseSearchQuery(String text)` — all consumed by Task 2
  (toggling) and Task 3 (`tasks_screen.dart`).

- [ ] **Step 1: Write the failing tests**

Create `test/unit/search_query_test.dart`:

```dart
import 'package:flutter/services.dart' show TextRange;
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/task/search_query.dart';

void main() {
  group('parseSearchQuery', () {
    test('plain text with no tokens is all free text', () {
      final parsed = parseSearchQuery('Buy milk');
      expect(parsed.tagTokens, isEmpty);
      expect(parsed.statusToken, isNull);
      expect(parsed.freeText, 'Buy milk');
    });

    test('a single #tag is extracted, leaving empty free text', () {
      final parsed = parseSearchQuery('#groceries');
      expect(parsed.tagTokens, hasLength(1));
      expect(parsed.tagTokens.single.tag, 'groceries');
      expect(parsed.tagTokens.single.excluded, isFalse);
      expect(parsed.tagTokens.single.range, const TextRange(start: 0, end: 10));
      expect(parsed.freeText, isEmpty);
    });

    test('#!tag is an excluded tag token', () {
      final parsed = parseSearchQuery('#!urgent');
      expect(parsed.tagTokens.single.tag, 'urgent');
      expect(parsed.tagTokens.single.excluded, isTrue);
    });

    test('tag names are lowercased', () {
      final parsed = parseSearchQuery('#GROCERIES');
      expect(parsed.tagTokens.single.tag, 'groceries');
    });

    test('multiple #tags are all extracted, in order', () {
      final parsed = parseSearchQuery('#a #b');
      expect(parsed.tagTokens.map((t) => t.tag), ['a', 'b']);
      expect(parsed.freeText, isEmpty);
    });

    test('/opened is a status token, not excluded', () {
      final parsed = parseSearchQuery('/opened');
      expect(parsed.statusToken, isNotNull);
      expect(parsed.statusToken!.excluded, isFalse);
      expect(parsed.freeText, isEmpty);
    });

    test('/!opened is an excluded status token', () {
      final parsed = parseSearchQuery('/!opened');
      expect(parsed.statusToken!.excluded, isTrue);
    });

    test('/OPENED is recognized case-insensitively', () {
      final parsed = parseSearchQuery('/OPENED');
      expect(parsed.statusToken, isNotNull);
    });

    test('only the first /opened is recognized; a second is left as '
        'plain text', () {
      final parsed = parseSearchQuery('/opened /opened');
      expect(parsed.statusToken!.excluded, isFalse);
      expect(parsed.freeText, '/opened');
    });

    test('/other (not "opened") is left entirely as plain text', () {
      final parsed = parseSearchQuery('/other');
      expect(parsed.statusToken, isNull);
      expect(parsed.tagTokens, isEmpty);
      expect(parsed.freeText, '/other');
    });

    test('a mixed query extracts tags and status, collapsing the '
        'remaining whitespace into single spaces', () {
      final parsed = parseSearchQuery('Buy milk #groceries /opened extra');
      expect(parsed.tagTokens.map((t) => t.tag), ['groceries']);
      expect(parsed.statusToken!.excluded, isFalse);
      expect(parsed.freeText, 'Buy milk extra');
    });
  });

  group('orderedTokenRanges', () {
    test('combines tag and status tokens sorted by position, regardless '
        'of which list they came from', () {
      final parsed = parseSearchQuery('/opened #groceries');
      final ranges = orderedTokenRanges(parsed);
      expect(ranges, hasLength(2));
      expect(ranges.first.range.start, 0); // "/opened"
      expect(ranges.last.range.start, 8); // "#groceries"
    });
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/unit/search_query_test.dart`
Expected: FAIL — `search_query.dart` doesn't exist yet (import error).

- [ ] **Step 3: Write the implementation**

Create `lib/features/task/search_query.dart`:

```dart
import 'package:flutter/services.dart' show TextRange;

/// The only status word currently recognized — [Task] has no other
/// boolean field to filter by, so any other word after `/` is left
/// alone as plain search text rather than treated as a token.
const openedStatusWord = 'opened';

/// A `#tag`/`#!tag` occurrence found anywhere in a unified search query
/// string, together with the exact range of characters it occupies —
/// used to mutate exactly that range when toggled ([toggleQueryToken])
/// and to know where to style it when rendering.
class TagToken {
  const TagToken({
    required this.tag,
    required this.excluded,
    required this.range,
  });

  final String tag;
  final bool excluded;
  final TextRange range;
}

/// A `/opened`/`/!opened` occurrence — at most one is recognized per
/// query (see [parseSearchQuery]).
class StatusToken {
  const StatusToken({required this.excluded, required this.range});

  final bool excluded;
  final TextRange range;
}

/// The parsed pieces of a unified search query string: every tag token,
/// at most one status token, and the free text left over once every
/// recognized token's characters are removed.
class ParsedQuery {
  const ParsedQuery({
    required this.tagTokens,
    required this.statusToken,
    required this.freeText,
  });

  final List<TagToken> tagTokens;
  final StatusToken? statusToken;
  final String freeText;
}

final _tokenPattern = RegExp(r'(#|/)(!?)(\w+)');

/// Parses [text] for every `#tag`/`#!tag` and the first `/opened`/
/// `/!opened` occurrence, returning their positions plus the leftover
/// free text (every recognized token's characters removed, whitespace
/// collapsed and trimmed).
///
/// A `/word` where `word` isn't [openedStatusWord] is left alone as
/// plain text. A second `/opened`/`/!opened` beyond the first is also
/// left as plain text: only one status filter slot exists.
ParsedQuery parseSearchQuery(String text) {
  final tagTokens = <TagToken>[];
  StatusToken? statusToken;
  final removedRanges = <TextRange>[];

  for (final match in _tokenPattern.allMatches(text)) {
    final symbol = match.group(1)!;
    final excluded = match.group(2) == '!';
    final word = match.group(3)!;
    final range = TextRange(start: match.start, end: match.end);
    if (symbol == '#') {
      tagTokens.add(
        TagToken(tag: word.toLowerCase(), excluded: excluded, range: range),
      );
      removedRanges.add(range);
    } else if (statusToken == null && word.toLowerCase() == openedStatusWord) {
      statusToken = StatusToken(excluded: excluded, range: range);
      removedRanges.add(range);
    }
  }

  final buffer = StringBuffer();
  var cursor = 0;
  for (final range in removedRanges) {
    buffer.write(text.substring(cursor, range.start));
    cursor = range.end;
  }
  buffer.write(text.substring(cursor));
  final freeText = buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();

  return ParsedQuery(
    tagTokens: tagTokens,
    statusToken: statusToken,
    freeText: freeText,
  );
}

/// Every recognized token in [parsed] (tag and status alike) as a
/// uniform `(range, excluded)` shape, sorted left-to-right — the order
/// rendering (and any other range-based consumer) needs.
List<({TextRange range, bool excluded})> orderedTokenRanges(
  ParsedQuery parsed,
) {
  final ranges = [
    for (final t in parsed.tagTokens) (range: t.range, excluded: t.excluded),
    if (parsed.statusToken != null)
      (
        range: parsed.statusToken!.range,
        excluded: parsed.statusToken!.excluded,
      ),
  ];
  ranges.sort((a, b) => a.range.start.compareTo(b.range.start));
  return ranges;
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/unit/search_query_test.dart`
Expected: PASS (12 tests).

- [ ] **Step 5: Analyze and commit**

Run: `flutter analyze lib/features/task/search_query.dart test/unit/search_query_test.dart`
Expected: `No issues found!`

```bash
git add lib/features/task/search_query.dart test/unit/search_query_test.dart
git commit -m "Add pure parser for the unified search query string"
```

---

### Task 2: `search_query.dart` — token toggling

**Files:**
- Modify: `lib/features/task/search_query.dart`
- Test: `test/unit/search_query_test.dart`

**Interfaces:**
- Consumes: `TagToken`/`StatusToken`/`ParsedQuery`/`parseSearchQuery` from Task 1.
- Produces: `({String text, int cursorOffset}) toggleQueryToken(String text, TextRange range, {required bool currentlyExcluded, required int cursorOffset})` — consumed by Task 3's `_toggleToken`.

- [ ] **Step 1: Write the failing tests**

Add to `test/unit/search_query_test.dart` (inside `main()`, alongside the
existing groups):

```dart
  group('toggleQueryToken', () {
    test('toggling an included tag to excluded inserts "!" right after '
        'the "#"', () {
      final parsed = parseSearchQuery('#groceries');
      final result = toggleQueryToken(
        '#groceries',
        parsed.tagTokens.single.range,
        currentlyExcluded: false,
        cursorOffset: 0,
      );
      expect(result.text, '#!groceries');
    });

    test('toggling an excluded tag to included removes the "!"', () {
      final result = toggleQueryToken(
        '#!groceries',
        const TextRange(start: 0, end: 11),
        currentlyExcluded: true,
        cursorOffset: 0,
      );
      expect(result.text, '#groceries');
    });

    test('the cursor shifts forward by 1 when it was at or after the '
        'edit point', () {
      // "Buy #groceries", cursor right after "groceries" (offset 14).
      final result = toggleQueryToken(
        'Buy #groceries',
        const TextRange(start: 4, end: 14),
        currentlyExcluded: false,
        cursorOffset: 14,
      );
      expect(result.text, 'Buy #!groceries');
      expect(result.cursorOffset, 15);
    });

    test('the cursor is unchanged when it was before the edit point', () {
      // "Buy #groceries", cursor after "Buy " (offset 4), right at the
      // token's own start — the edit happens one character later (right
      // after the "#"), so this cursor position is unaffected.
      final result = toggleQueryToken(
        'Buy #groceries',
        const TextRange(start: 4, end: 14),
        currentlyExcluded: false,
        cursorOffset: 4,
      );
      expect(result.cursorOffset, 4);
    });

    test('toggling a status token works the same way, with "/"', () {
      final parsed = parseSearchQuery('/opened');
      final result = toggleQueryToken(
        '/opened',
        parsed.statusToken!.range,
        currentlyExcluded: false,
        cursorOffset: 7,
      );
      expect(result.text, '/!opened');
      expect(result.cursorOffset, 8);
    });
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/unit/search_query_test.dart`
Expected: FAIL — `toggleQueryToken` isn't defined.

- [ ] **Step 3: Write the implementation**

Append to `lib/features/task/search_query.dart`:

```dart
/// Returns [text] with the token at [range] toggled between its
/// included and excluded form (inserting/removing the `!` right after
/// the `#`/`/`), and the equivalent offset for [cursorOffset] once that
/// edit is applied (shifted by the token's change in length if the
/// cursor was positioned at or after the edit point, unchanged
/// otherwise).
({String text, int cursorOffset}) toggleQueryToken(
  String text,
  TextRange range, {
  required bool currentlyExcluded,
  required int cursorOffset,
}) {
  final bangIndex = range.start + 1;
  final String newText;
  final int delta;
  if (currentlyExcluded) {
    newText = text.replaceRange(bangIndex, bangIndex + 1, '');
    delta = -1;
  } else {
    newText = text.replaceRange(bangIndex, bangIndex, '!');
    delta = 1;
  }
  final newCursor = cursorOffset >= bangIndex ? cursorOffset + delta : cursorOffset;
  return (text: newText, cursorOffset: newCursor);
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/unit/search_query_test.dart`
Expected: PASS (17 tests total).

- [ ] **Step 5: Analyze and commit**

Run: `flutter analyze lib/features/task/search_query.dart test/unit/search_query_test.dart`
Expected: `No issues found!`

```bash
git add lib/features/task/search_query.dart test/unit/search_query_test.dart
git commit -m "Add token-toggling to the unified search query parser"
```

---

### Task 3: Smoke-check `TextSpan.recognizer` inside an actively-edited `TextField`

This is a spike, not production code — the spec flags this as the one
real technical risk worth verifying before building the rest of the
feature on top of it. Keep it small and throwaway.

**Files:**
- Create (temporary): `lib/features/task/widgets/_tap_span_probe.dart` — a
  throwaway screen, not wired into the app's router.

- [ ] **Step 1: Write a minimal probe screen**

```dart
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Throwaway probe: confirms a [TextSpan.recognizer] inside an actively-
/// edited [TextField]'s [TextEditingController.buildTextSpan] override
/// fires on tap, and that typing/cursor placement elsewhere in the field
/// still works normally. Delete this file once verified — it exists
/// only to de-risk Task 4 before writing it for real.
class TapSpanProbe extends StatefulWidget {
  const TapSpanProbe({super.key});

  @override
  State<TapSpanProbe> createState() => _TapSpanProbeState();
}

class _TapSpanProbeState extends State<TapSpanProbe> {
  late final _ProbeController _controller;
  int _taps = 0;

  @override
  void initState() {
    super.initState();
    _controller = _ProbeController(text: 'Buy milk TAPME rest')
      ..onTokenTap = () => setState(() => _taps++);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(controller: _controller),
            Text('Taps: $_taps'),
          ],
        ),
      ),
    );
  }
}

class _ProbeController extends TextEditingController {
  _ProbeController({super.text});

  VoidCallback? onTokenTap;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final index = text.indexOf('TAPME');
    if (index < 0) return TextSpan(text: text, style: style);
    return TextSpan(
      style: style,
      children: [
        TextSpan(text: text.substring(0, index), style: style),
        TextSpan(
          text: 'TAPME',
          style: style?.copyWith(
            color: Colors.white,
            backgroundColor: Colors.red,
          ),
          recognizer: TapGestureRecognizer()..onTap = onTokenTap,
        ),
        TextSpan(text: text.substring(index + 5), style: style),
      ],
    );
  }
}
```

- [ ] **Step 2: Run it manually and verify**

Temporarily point `lib/main.dart`'s `MaterialApp`/router at
`TapSpanProbe` (or add a one-off route), then:

```bash
flutter run -d web-server --web-port=8080
```

In the browser at `localhost:8080`: confirm tapping directly on the red
"TAPME" text increments the tap counter, and clicking/typing anywhere
else in the field places the cursor normally (no interference). If this
does *not* work as expected, stop and re-open the design conversation —
the rest of this plan depends on it.

- [ ] **Step 3: Revert the probe**

```bash
git checkout -- lib/main.dart  # or wherever it was temporarily wired in
rm lib/features/task/widgets/_tap_span_probe.dart
```

No commit for this task — it's a spike; nothing from it ships.

---

### Task 4: Rewrite `tasks_screen.dart`'s search bar

This is the core task: replaces `_selectedTags`/`_openedFilter` with
`parseSearchQuery`-derived state throughout, adds `UnifiedQueryController`,
and switches autocomplete to cursor-relative matching.

**Files:**
- Modify: `lib/features/task/widgets/tasks_screen.dart` (full rewrite of
  its search-bar-related code — everything from the top-level
  `_searchTagPattern` declaration through the end of `_FilterPill`,
  i.e. roughly today's lines 13–575)
- Test: `test/widget/tasks_screen_test.dart` (rewrite everything from the
  `'typing in the search field filters...'` test, roughly today's line
  146, through the end of the `'search suggestions dropdown'` group at
  line 828 — the non-search tests above that, lines 52–144, are
  unaffected and stay as-is)

**Interfaces:**
- Consumes: `openedStatusWord`, `TagToken`, `StatusToken`, `ParsedQuery`,
  `parseSearchQuery`, `orderedTokenRanges`, `toggleQueryToken` from
  `search_query.dart` (Tasks 1–2).
- Produces: `TasksScreen` (unchanged public API — still a plain
  `ConsumerStatefulWidget` with no constructor parameters).

- [ ] **Step 1: Write the new widget tests**

Replace `test/widget/tasks_screen_test.dart` from the
`'typing in the search field filters...'` test through the end of the
file with the following (keep everything above it, including the
`_pump`/`_buildTestRouter`/`_pumpWithRouter` helpers and the
`'starts empty'` through `'toggling a card checkbox...'` tests,
unchanged):

```dart
    testWidgets('typing plain text filters tasks by title '
        '(case-insensitive substring)', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(categoryListProvider.future);
      await container.read(taskListProvider.future);
      await container
          .read(taskListProvider.notifier)
          .addTask(title: 'Buy milk');
      await container
          .read(taskListProvider.notifier)
          .addTask(title: 'Walk the dog');
      await _pump(tester, container: container);

      await tester.enterText(find.byType(TextField), 'MILK');
      await tester.pump();

      expect(find.text('Buy milk'), findsOneWidget);
      expect(find.text('Walk the dog'), findsNothing);
    });

    testWidgets('clearing the search field restores the full list', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(categoryListProvider.future);
      await container.read(taskListProvider.future);
      await container
          .read(taskListProvider.notifier)
          .addTask(title: 'Buy milk');
      await container
          .read(taskListProvider.notifier)
          .addTask(title: 'Walk the dog');
      await _pump(tester, container: container);

      await tester.enterText(find.byType(TextField), 'milk');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.clear));
      await tester.pump();

      expect(find.text('Buy milk'), findsOneWidget);
      expect(find.text('Walk the dog'), findsOneWidget);
    });

    testWidgets('a #tag anywhere in the text filters to tasks with that '
        'tag', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(categoryListProvider.future);
      await container.read(taskListProvider.future);
      final tagged = await container
          .read(taskListProvider.notifier)
          .addTask(title: 'Buy milk');
      await container
          .read(taskListProvider.notifier)
          .updateTask(tagged, tags: ['groceries']);
      await container
          .read(taskListProvider.notifier)
          .addTask(title: 'Walk the dog');
      await _pump(tester, container: container);

      await tester.enterText(find.byType(TextField), '#groceries');
      await tester.pump();

      expect(find.text('Buy milk'), findsOneWidget);
      expect(find.text('Walk the dog'), findsNothing);
    });

    testWidgets('several #tags in the text combine with AND', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(categoryListProvider.future);
      await container.read(taskListProvider.future);
      final notifier = container.read(taskListProvider.notifier);
      final both = await notifier.addTask(title: 'Buy milk');
      await notifier.updateTask(both, tags: ['groceries', 'urgent']);
      final one = await notifier.addTask(title: 'Buy eggs');
      await notifier.updateTask(one, tags: ['groceries']);
      await _pump(tester, container: container);

      await tester.enterText(find.byType(TextField), '#groceries #urgent');
      await tester.pump();

      expect(find.text('Buy milk'), findsOneWidget);
      expect(find.text('Buy eggs'), findsNothing);
    });

    testWidgets('#!tag excludes tasks with that tag', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(categoryListProvider.future);
      await container.read(taskListProvider.future);
      final tagged = await container
          .read(taskListProvider.notifier)
          .addTask(title: 'Buy milk');
      await container
          .read(taskListProvider.notifier)
          .updateTask(tagged, tags: ['urgent']);
      await container
          .read(taskListProvider.notifier)
          .addTask(title: 'Walk the dog');
      await _pump(tester, container: container);

      await tester.enterText(find.byType(TextField), '#!urgent');
      await tester.pump();

      expect(find.text('Buy milk'), findsNothing);
      expect(find.text('Walk the dog'), findsOneWidget);
    });

    testWidgets('/opened filters to tasks that are not closed', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(categoryListProvider.future);
      await container.read(taskListProvider.future);
      await container
          .read(taskListProvider.notifier)
          .addTask(title: 'Buy milk');
      final closed = await container
          .read(taskListProvider.notifier)
          .addTask(title: 'Walk the dog');
      await container
          .read(taskListProvider.notifier)
          .updateTask(closed, closed: true);
      await _pump(tester, container: container);

      await tester.enterText(find.byType(TextField), '/opened');
      await tester.pump();

      expect(find.text('Buy milk'), findsOneWidget);
      expect(find.text('Walk the dog'), findsNothing);
    });

    testWidgets('/!opened filters to closed tasks', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(categoryListProvider.future);
      await container.read(taskListProvider.future);
      await container
          .read(taskListProvider.notifier)
          .addTask(title: 'Buy milk');
      final closed = await container
          .read(taskListProvider.notifier)
          .addTask(title: 'Walk the dog');
      await container
          .read(taskListProvider.notifier)
          .updateTask(closed, closed: true);
      await _pump(tester, container: container);

      await tester.enterText(find.byType(TextField), '/!opened');
      await tester.pump();

      expect(find.text('Buy milk'), findsNothing);
      expect(find.text('Walk the dog'), findsOneWidget);
    });

    testWidgets('a /word that is not "opened" is left as plain search '
        'text', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(categoryListProvider.future);
      await container.read(taskListProvider.future);
      await container
          .read(taskListProvider.notifier)
          .addTask(title: '/other task');
      await _pump(tester, container: container);

      await tester.enterText(find.byType(TextField), '/other');
      await tester.pump();

      expect(find.text('/other task'), findsOneWidget);
    });

    testWidgets('tapping a rendered tag token toggles it between '
        'include and exclude', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(categoryListProvider.future);
      await container.read(taskListProvider.future);
      final tagged = await container
          .read(taskListProvider.notifier)
          .addTask(title: 'Buy milk');
      await container
          .read(taskListProvider.notifier)
          .updateTask(tagged, tags: ['urgent']);
      await container
          .read(taskListProvider.notifier)
          .addTask(title: 'Sell couch');
      await _pump(tester, container: container);

      await tester.enterText(find.byType(TextField), '#urgent');
      await tester.pump();
      expect(find.text('Buy milk'), findsOneWidget);
      expect(find.text('Sell couch'), findsNothing);

      // Tap near the start of the field's text (not its center — the
      // field is much wider than "#urgent", and text is left-aligned
      // after the prefix icon, so a center tap would land past the end
      // of the text in empty space). If this offset doesn't land on the
      // token in practice, use `debugDumpRenderTree()` or nudge the x
      // value — the field's prefix icon plus content padding puts text
      // start a little past the field's own left edge.
      final fieldTopLeft = tester.getTopLeft(find.byType(TextField));
      await tester.tapAt(fieldTopLeft + const Offset(45, 24));
      await tester.pump();

      expect(find.byType(TasksScreen), findsOneWidget); // still mounted
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, '#!urgent');
      expect(find.text('Buy milk'), findsNothing);
      expect(find.text('Sell couch'), findsOneWidget);
    });

    testWidgets('backspacing through a tag token\'s characters removes '
        'it and un-filters', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(categoryListProvider.future);
      await container.read(taskListProvider.future);
      final tagged = await container
          .read(taskListProvider.notifier)
          .addTask(title: 'Buy milk');
      await container
          .read(taskListProvider.notifier)
          .updateTask(tagged, tags: ['groceries']);
      await container
          .read(taskListProvider.notifier)
          .addTask(title: 'Walk the dog');
      await _pump(tester, container: container);

      await tester.enterText(find.byType(TextField), '#groceries');
      await tester.pump();
      expect(find.text('Walk the dog'), findsNothing);

      await tester.enterText(find.byType(TextField), '');
      await tester.pump();

      expect(find.text('Walk the dog'), findsOneWidget);
    });

    testWidgets("the field is seeded from the route's q query parameter, "
        'verbatim', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(categoryListProvider.future);
      await container.read(taskListProvider.future);
      final tagged = await container
          .read(taskListProvider.notifier)
          .addTask(title: 'Buy milk');
      await container
          .read(taskListProvider.notifier)
          .updateTask(tagged, tags: ['groceries']);
      await container
          .read(taskListProvider.notifier)
          .addTask(title: 'Walk the dog');
      final router = _buildTestRouter(
        initialLocation: '/tasks?q=%23groceries',
      );

      await _pumpWithRouter(tester, router, container: container);

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, '#groceries');
      expect(find.text('Buy milk'), findsOneWidget);
      expect(find.text('Walk the dog'), findsNothing);
    });

    testWidgets('typing updates the q query parameter in the address '
        'bar to the raw text, verbatim', (tester) async {
      final router = _buildTestRouter();
      await _pumpWithRouter(tester, router);

      await tester.enterText(find.byType(TextField), 'Buy #milk');
      await tester.pump();

      expect(
        router.routerDelegate.currentConfiguration.uri.queryParameters['q'],
        'Buy #milk',
      );
    });

    testWidgets('a URL with the retired tags/status params behaves like '
        'an empty query', (tester) async {
      final router = _buildTestRouter(
        initialLocation: '/tasks?tags=groceries&status=opened',
      );
      await _pumpWithRouter(tester, router);

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, isEmpty);
    });
  });

  group('search suggestions dropdown', () {
    testWidgets('typing "#" at the cursor shows every distinct tag '
        'across loaded tasks', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(categoryListProvider.future);
      await container.read(taskListProvider.future);
      final notifier = container.read(taskListProvider.notifier);
      final milk = await notifier.addTask(title: 'Buy milk');
      await notifier.updateTask(milk, tags: ['groceries']);
      final dog = await notifier.addTask(title: 'Walk the dog');
      await notifier.updateTask(dog, tags: ['urgent']);
      await _pump(tester, container: container);

      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), '#');
      await tester.pump();
      await tester.pump();

      expect(find.widgetWithText(ListTile, 'groceries'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'urgent'), findsOneWidget);
    });

    testWidgets('a partial token in the middle of the text (cursor '
        'placed right after it) still triggers suggestions', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(categoryListProvider.future);
      await container.read(taskListProvider.future);
      final notifier = container.read(taskListProvider.notifier);
      final milk = await notifier.addTask(title: 'Buy milk');
      await notifier.updateTask(milk, tags: ['groceries']);
      await _pump(tester, container: container);

      await tester.tap(find.byType(TextField));
      // "#gro" followed by " rest", cursor placed right after "#gro".
      await tester.enterText(find.byType(TextField), '#gro rest');
      final field = tester.widget<TextField>(find.byType(TextField));
      field.controller!.selection = const TextSelection.collapsed(
        offset: 4,
      );
      await tester.pump();
      await tester.pump();

      expect(find.widgetWithText(ListTile, 'groceries'), findsOneWidget);
    });

    testWidgets('selecting a suggestion inserts it at the cursor, not '
        'at the end of the field', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(categoryListProvider.future);
      await container.read(taskListProvider.future);
      final notifier = container.read(taskListProvider.notifier);
      final milk = await notifier.addTask(title: 'Buy milk');
      await notifier.updateTask(milk, tags: ['groceries']);
      await _pump(tester, container: container);

      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), '#gro rest');
      final field = tester.widget<TextField>(find.byType(TextField));
      field.controller!.selection = const TextSelection.collapsed(
        offset: 4,
      );
      await tester.pump();
      await tester.pump();

      await tester.tap(find.widgetWithText(ListTile, 'groceries'));
      await tester.pump();
      await tester.pump();

      expect(field.controller!.text, '#groceries  rest');
    });

    testWidgets('typing "/" shows "opened" as the only suggestion, only '
        'while unset', (tester) async {
      await _pump(tester);

      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), '/');
      await tester.pump();
      await tester.pump();

      expect(find.widgetWithText(ListTile, 'opened'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '/opened /');
      await tester.pump();
      await tester.pump();

      expect(find.byType(ListTile), findsNothing);
    });

    testWidgets('pressing Escape closes the dropdown', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(categoryListProvider.future);
      await container.read(taskListProvider.future);
      final notifier = container.read(taskListProvider.notifier);
      final milk = await notifier.addTask(title: 'Buy milk');
      await notifier.updateTask(milk, tags: ['groceries']);
      await _pump(tester, container: container);

      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), '#');
      await tester.pump();
      await tester.pump();
      expect(find.byIcon(Icons.tag), findsWidgets);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump();

      expect(find.byIcon(Icons.tag), findsNothing);
    });

    testWidgets('the dropdown closes when the search field loses focus', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(categoryListProvider.future);
      await container.read(taskListProvider.future);
      final notifier = container.read(taskListProvider.notifier);
      final milk = await notifier.addTask(title: 'Buy milk');
      await notifier.updateTask(milk, tags: ['groceries']);
      await _pump(tester, container: container);

      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), '#');
      await tester.pump();
      await tester.pump();
      expect(find.byIcon(Icons.tag), findsWidgets);

      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await tester.pump();

      expect(find.byIcon(Icons.tag), findsNothing);
    });

    testWidgets('the dropdown never shows more than 4 suggestions', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(categoryListProvider.future);
      await container.read(taskListProvider.future);
      final notifier = container.read(taskListProvider.notifier);
      for (final tag in ['aa', 'ab', 'ac', 'ad', 'ae']) {
        final task = await notifier.addTask(title: 'Task $tag');
        await notifier.updateTask(task, tags: [tag]);
      }
      await _pump(tester, container: container);

      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), '#a');
      await tester.pump();
      await tester.pump();

      expect(find.byIcon(Icons.tag), findsNWidgets(4));
    });
  });
}
```

Also update the two existing tests that used the old
`find.descendant(of: find.byType(Dialog), matching: find.byType(TextField))`
pattern (`'adding a task via the app bar action shows it in the list'`
and `'tapping a task card opens it in edit mode'`, both above line 146
and therefore unchanged in shape) — no change needed there, since they
already scope to the modal's `Dialog`, distinct from the search field.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/widget/tasks_screen_test.dart`
Expected: FAIL — compile errors (`_selectedTags` etc. still referenced
by the old `tasks_screen.dart`, and the new tests reference behavior
that doesn't exist yet).

- [ ] **Step 3: Rewrite `tasks_screen.dart`**

Replace the entire file content with:

```dart
import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:taskframe/core/responsive.dart';
import 'package:taskframe/features/task/models/task.dart';
import 'package:taskframe/features/task/providers.dart';
import 'package:taskframe/features/task/search_query.dart';
import 'package:taskframe/features/task/widgets/task_card.dart';
import 'package:taskframe/features/task/widgets/task_edit_modal.dart';

/// Matches an *unfinished* `#word`/`#!word` immediately before the
/// cursor — no trailing space yet — so suggestions can be offered while
/// the user is still typing it, wherever the cursor currently sits.
final _partialTagPattern = RegExp(r'(^|\s)#(!?)(\w*)$');

/// The `/` counterpart of [_partialTagPattern].
final _partialStatusPattern = RegExp(r'(^|\s)/(!?)(\w*)$');

/// Suggestions dropdown never lists more than this many options — the
/// tag/status vocabulary can grow arbitrarily large, but a floating list
/// longer than a handful of rows stops being scannable.
const _maxSuggestions = 4;

/// A [TextEditingController] whose [buildTextSpan] renders recognized
/// `#tag`/`#!tag`/`/opened`/`/!opened` tokens (see [parseSearchQuery])
/// as styled, tappable text within the one real, actively-edited field
/// — bold + tinted when included, error-toned when excluded. Tapping a
/// token's own characters calls [onTokenTapped]; everywhere else falls
/// through to normal cursor placement, since only token ranges carry a
/// [TextSpan.recognizer].
class UnifiedQueryController extends TextEditingController {
  UnifiedQueryController({super.text, required this.onTokenTapped});

  final void Function(TextRange range, {required bool excluded}) onTokenTapped;

  final List<TapGestureRecognizer> _recognizers = [];

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    _disposeRecognizers();
    final parsed = parseSearchQuery(text);
    final tokens = orderedTokenRanges(parsed);
    final colors = Theme.of(context).colorScheme;
    final spans = <TextSpan>[];
    var cursor = 0;
    for (final token in tokens) {
      if (token.range.start > cursor) {
        spans.add(
          TextSpan(text: text.substring(cursor, token.range.start), style: style),
        );
      }
      final recognizer = TapGestureRecognizer()
        ..onTap = () => onTokenTapped(token.range, excluded: token.excluded);
      _recognizers.add(recognizer);
      spans.add(
        TextSpan(
          text: text.substring(token.range.start, token.range.end),
          style: (style ?? const TextStyle()).copyWith(
            fontWeight: FontWeight.w600,
            color: token.excluded
                ? colors.onErrorContainer
                : colors.onPrimaryContainer,
            backgroundColor:
                token.excluded ? colors.errorContainer : colors.primaryContainer,
          ),
          recognizer: recognizer,
        ),
      );
      cursor = token.range.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor), style: style));
    }
    return TextSpan(style: style, children: spans);
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }
}

/// Lists every task as a [TaskCard], in creation order, and lets the user
/// add or edit one via [showTaskEditModal]. Closing a task is a checkbox
/// on its own card — see [TaskCard] — so this screen only wires up
/// add/open-for-edit.
///
/// A single search field doubles as the query: plain text filters by
/// title, `#tag`/`#!tag` anywhere in the text filters tasks by tag
/// (multiple combine with AND), and `/opened`/`/!opened` filters by
/// closed status. Recognized tokens render as styled (not extracted)
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

  @override
  void initState() {
    super.initState();
    final params = GoRouter.maybeOf(context)?.state.uri.queryParameters;
    _searchController = UnifiedQueryController(
      text: params?['q'] ?? '',
      onTokenTapped: _toggleToken,
    )..addListener(_onSearchChanged);
    _searchFocusNode = FocusNode()
      ..addListener(() {
        if (mounted) setState(() {});
      });
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

  /// The dropdown's current suggestions — tag names while the text
  /// immediately before the cursor ends in an unfinished `#word`/
  /// `#!word`, or `opened` while it ends in an unfinished `/word`/
  /// `/!word` and no status filter is set yet. `null` hides the
  /// dropdown: no partial match, no candidates, dismissed via Escape, or
  /// the field isn't focused.
  ({List<String> options, bool isStatus})? _currentSuggestions(
    List<Task> tasks,
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
          : (options: options.take(_maxSuggestions).toList(), isStatus: false);
    }
    final statusMatch = _partialStatusPattern.firstMatch(beforeCursor);
    if (statusMatch != null) {
      final parsed = parseSearchQuery(_searchController.text);
      if (parsed.statusToken == null) {
        final partial = statusMatch.group(3)!.toLowerCase();
        if (openedStatusWord.startsWith(partial)) {
          return (options: [openedStatusWord], isStatus: true);
        }
      }
    }
    return null;
  }

  /// Completes the unfinished token immediately before the cursor with
  /// [option] plus a trailing space, then reinserts whatever followed
  /// the cursor — same shape a manually-typed `#tag `/`/opened ` settles
  /// to, so the assignment re-enters [_onSearchChanged].
  void _selectSuggestion(String option, {required bool isStatus}) {
    final cursor = _searchController.selection.baseOffset;
    final text = _searchController.text;
    final beforeCursor = text.substring(0, cursor);
    final afterCursor = text.substring(cursor);
    final match = (isStatus ? _partialStatusPattern : _partialTagPattern)
        .firstMatch(beforeCursor)!;
    final prefix = beforeCursor.substring(0, match.start) + match.group(1)!;
    final symbol = isStatus ? '/' : '#';
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
    final hasSuggestions = _currentSuggestions(tasks) != null;
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
    final suggestions = _currentSuggestions(tasks);
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
                    onTapDown: (_) => _selectSuggestion(
                      option,
                      isStatus: suggestions.isStatus,
                    ),
                    child: ListTile(
                      dense: true,
                      leading: Icon(
                        suggestions.isStatus
                            ? Icons.radio_button_unchecked
                            : Icons.tag,
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

  KeyEventResult _handleSearchKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      final tasks = ref.read(taskListProvider).value ?? const <Task>[];
      if (_currentSuggestions(tasks) != null) {
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

  List<Task> _filter(List<Task> tasks) {
    final parsed = parseSearchQuery(_searchController.text);
    final query = parsed.freeText.toLowerCase();
    return [
      for (final task in tasks)
        if ((query.isEmpty || task.title.toLowerCase().contains(query)) &&
            (parsed.statusToken == null ||
                task.closed == parsed.statusToken!.excluded) &&
            parsed.tagTokens.every(
              (t) => t.excluded
                  ? !task.tags.contains(t.tag)
                  : task.tags.contains(t.tag),
            ))
          task,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final tasksAsync = ref.watch(taskListProvider);
    // Overlay content can only be sized/positioned off the search field's
    // render box once this frame has actually laid it out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncSuggestionsOverlay();
    });

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
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: CompositedTransformTarget(
              link: _searchFieldLink,
              child: Focus(
                onKeyEvent: _handleSearchKeyEvent,
                child: TextField(
                  key: _searchFieldKey,
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  decoration: InputDecoration(
                    hintText: 'Search: #tag  /opened  free text',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            tooltip: 'Clear search',
                            onPressed: _searchController.clear,
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
                for (final task in _filter(value))
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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/widget/tasks_screen_test.dart`
Expected: PASS — every test in the file, both the unchanged
non-search tests and the new search/suggestion tests.

- [ ] **Step 5: Run the full unit+widget suite and analyzer**

Run: `flutter test`
Expected: PASS, no regressions elsewhere.

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/features/task/widgets/tasks_screen.dart test/widget/tasks_screen_test.dart
git commit -m "Unify the tasks search bar into a single styled-text query field"
```

---

### Task 5: Rework `e2e/tests/tasks-screen.spec.ts`

**Files:**
- Modify: `e2e/tests/tasks-screen.spec.ts`
- Temporary: `e2e/tests/_probe.spec.ts` (created and deleted within this task)

**Interfaces:**
- Consumes: the rewritten `TasksScreen` from Task 4 (no new exported
  Dart API — this task only touches Playwright specs).

- [ ] **Step 1: Probe the new accessibility tree**

Create `e2e/tests/_probe.spec.ts`:

```ts
import { test, expect } from '@playwright/test';
import { enableFlutterAccessibility } from './support/accessibility';
import { gotoAndWaitForBoot } from './support/gestures';

test.use({ viewport: { width: 800, height: 720 } });

test('probe unified query field', async ({ page }) => {
  await gotoAndWaitForBoot(page, '/#/tasks');
  await enableFlutterAccessibility(page);

  const search = page.getByRole('textbox');
  await search.fill('Buy milk #groceries /opened');
  await page.waitForTimeout(500);

  expect(true).toBe(false); // force the page snapshot into the error output
});
```

Run:

```bash
cd e2e && npx playwright test tests/_probe.spec.ts
```

Read the "Page snapshot" in the failure output — confirm the field's
accessible `value`/`name` includes the raw text verbatim (no separate
semantic nodes for the styled tokens, since they're plain text within
one field now, not separate widgets). This determines whether existing
`page.getByRole('textbox', ...)`-based selectors in the spec below need
any adjustment, and whether tapping a token needs a coordinate-based
click (`page.mouse.click(x, y)`) rather than a role/name-based locator —
the spec's Testing/Risks sections already anticipate the latter.

Delete the probe once done: `rm e2e/tests/_probe.spec.ts`.

- [ ] **Step 2: Rewrite the "search bar tag filters" and "search
  suggestions dropdown"-adjacent tests**

In `e2e/tests/tasks-screen.spec.ts`, replace the `modalTextbox`,
`searchTextbox`, `searchTagPill`, `addTaskWithTags`, `searchByTag`
helpers and the `test.describe('search bar tag filters', ...)` block
with:

```ts
/**
 * The task edit modal's own title field, as opposed to the tasks
 * screen's persistent search field — every plain `getByRole('textbox')`
 * in this file would otherwise match both once the modal is open.
 * Distinguished by accessible name: the search field keeps its hint
 * ("Search: #tag  /opened  free text") as its name while empty; the
 * modal's field has none.
 */
function modalTextbox(page: Page): Locator {
  return page.getByRole('textbox', { name: /^(?!Search:).*$/ });
}

function searchTextbox(page: Page): Locator {
  return page.getByRole('textbox', { name: /^Search:/ });
}

/**
 * Creates a task titled [title] with each of [tags] attached, via the
 * modal's own "#tag " extraction (unaffected by this feature — see
 * "strips it from the title" above).
 */
async function addTaskWithTags(
  page: Page,
  title: string,
  tags: string[],
): Promise<void> {
  await page.getByRole('button', { name: 'Add task' }).click();
  const field = modalTextbox(page);
  await fillTextboxUntilSet(field, title);
  for (const tag of tags) {
    await fillTextboxUntilTrue(field, `${title} #${tag} `, async () =>
      (await field.inputValue().catch(() => '')) === `${title} `);
  }
  await dismissTaskModal(page);
}

test.describe('unified search query', () => {
  test('a #tag anywhere in the search text filters to tasks with that '
    + 'tag', async ({ page }) => {
    await addTaskWithTags(page, 'Buy milk', ['groceries']);
    await addTaskWithTags(page, 'Walk the dog', []);

    await fillTextboxUntilSet(searchTextbox(page), '#groceries');

    await expect(page.getByRole('button', { name: 'Buy milk' })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Walk the dog' })).toHaveCount(0);
  });

  test('several #tags combine with AND', async ({ page }) => {
    await addTaskWithTags(page, 'Buy milk', ['groceries', 'urgent']);
    await addTaskWithTags(page, 'Buy eggs', ['groceries']);

    await fillTextboxUntilSet(searchTextbox(page), '#groceries #urgent');

    await expect(page.getByRole('button', { name: 'Buy milk' })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Buy eggs' })).toHaveCount(0);
  });

  test('#!tag excludes tasks with that tag', async ({ page }) => {
    await addTaskWithTags(page, 'Buy milk', ['urgent']);
    await addTaskWithTags(page, 'Walk the dog', []);

    await fillTextboxUntilSet(searchTextbox(page), '#!urgent');

    await expect(page.getByRole('button', { name: 'Buy milk' })).toHaveCount(0);
    await expect(page.getByRole('button', { name: 'Walk the dog' })).toBeVisible();
  });

  test('tapping a rendered tag token toggles it between include and '
    + 'exclude', async ({ page }) => {
    await addTaskWithTags(page, 'Buy milk', ['urgent']);
    await addTaskWithTags(page, 'Sell couch', []);

    const search = searchTextbox(page);
    await fillTextboxUntilSet(search, '#urgent');
    await expect(page.getByRole('button', { name: 'Buy milk' })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Sell couch' })).toHaveCount(0);

    // Click near the start of the field's text, not its center — the
    // field is much wider than "#urgent", and text is left-aligned
    // after the prefix icon, so a center click would land past the end
    // of the text in empty space. Adjust the x offset if it doesn't
    // land on the token in practice (re-run with a Playwright trace to
    // see exactly where the click landed vs. where the text renders).
    const box = (await search.boundingBox())!;
    await page.mouse.click(box.x + 45, box.y + box.height / 2);

    await expect(page.getByRole('button', { name: 'Buy milk' })).toHaveCount(0);
    await expect(page.getByRole('button', { name: 'Sell couch' })).toBeVisible();
    await expect(search).toHaveValue('#!urgent');
  });

  test('backspacing through a tag token removes it and un-filters', async ({
    page,
  }) => {
    await addTaskWithTags(page, 'Buy milk', ['groceries']);
    await addTaskWithTags(page, 'Walk the dog', []);

    const search = searchTextbox(page);
    await fillTextboxUntilSet(search, '#groceries');
    await expect(page.getByRole('button', { name: 'Walk the dog' })).toHaveCount(0);

    await search.fill('');
    await page.waitForTimeout(200);

    await expect(page.getByRole('button', { name: 'Walk the dog' })).toBeVisible();
  });

  test('/opened filters to tasks that are not closed', async ({ page }) => {
    await addTaskWithTags(page, 'Buy milk', []);
    await page.getByRole('button', { name: 'Add task' }).click();
    await fillTextboxUntilSet(modalTextbox(page), 'Walk the dog');
    await page.getByRole('checkbox').first().click();
    await dismissTaskModal(page);

    await fillTextboxUntilSet(searchTextbox(page), '/opened');

    await expect(page.getByRole('button', { name: 'Buy milk' })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Walk the dog' })).toHaveCount(0);
  });

  test('typing #groceries into an empty search field shows a tag '
    + 'suggestion dropdown that completes on tap', async ({ page }) => {
    await addTaskWithTags(page, 'Buy milk', ['groceries']);

    const search = searchTextbox(page);
    await fillTextboxUntilSet(search, '#gro');

    await expect(page.getByRole('listitem').filter({ hasText: 'groceries' })).toBeVisible();
    await page.getByRole('listitem').filter({ hasText: 'groceries' }).click();

    await expect(search).toHaveValue('#groceries ');
  });
});
```

Adjust `modalTextbox`/`searchTextbox`'s regex per whatever the Step 1
probe actually showed for the field's accessible name (the hint text
`"Search: #tag  /opened  free text"` set in Task 4 is the intended
accessible name while the field is empty — confirm this against the
probe's snapshot rather than assuming).

- [ ] **Step 3: Run the rewritten spec**

```bash
cd e2e && npx playwright test tests/tasks-screen.spec.ts
```

Expected: PASS. If a selector doesn't match what the probe showed,
adjust it and rerun — do not guess a fix without re-probing.

- [ ] **Step 4: Commit**

```bash
git add e2e/tests/tasks-screen.spec.ts
git commit -m "Rework tasks-screen e2e search coverage for the unified query field"
```

---

### Task 6: Final regression pass and manual verification

**Files:** none (verification only).

- [ ] **Step 1: Full Dart test suite**

Run: `flutter test`
Expected: PASS, zero failures.

- [ ] **Step 2: Analyzer**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: Full e2e suite** (not just the tasks-screen spec — confirm
  no unrelated regression)

```bash
cd e2e && npx playwright test
```

Expected: PASS.

- [ ] **Step 4: Manual check in the running app**

```bash
flutter run -d web-server --web-port=8080
```

In the browser: type a mixed query (`Buy milk #groceries /opened`),
confirm both tokens render styled and tappable, confirm tapping each
toggles its color to the excluded (error-toned) style and the list
re-filters, confirm the autocomplete dropdown appears/completes
correctly with the cursor placed mid-string (not just at the end), and
confirm backspacing through a token removes it. This is the one thing
automated tests can't fully cover — real rendering/interaction feel.

- [ ] **Step 5: Commit** (only if Step 4 surfaced fixes; otherwise skip)

If manual verification required code changes, commit them with a
message describing what was found and fixed.
