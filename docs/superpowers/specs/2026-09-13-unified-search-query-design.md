# Unified search query — design

## Context

The tasks screen's search bar currently has two visually separate pieces:
a plain `TextField` holding free-text title search, and a row of
`InputChip` pills below it for `#tag`/`#!tag` and `/opened`/`/!opened`
filters. Typing a recognized token *extracts* it out of the text field
into separate state (`_selectedTags: List<String>`,
`_openedFilter: bool?`), leaving the field holding only whatever plain
text remains. A floating dropdown offers autocomplete for an unfinished
token at the end of the field.

This spec replaces that two-tier model with a single unified text input:
one string is the only source of truth, tokens render as styled text
inline within the same flow (not a separate row), and everything else
(filtering, URL sync, autocomplete) is derived from that one string by
parsing it fresh on every change.

## Goals

- One `TextField`, one `TextEditingController`, one string. No
  `_selectedTags`/`_openedFilter` fields extracted out of the text.
- Recognized tokens (`#tag`, `#!tag`, `/opened`, `/!opened`) render as
  colored/highlighted text inline with the surrounding plain text —
  bold + tinted background, error-toned when excluded — rather than a
  rounded chip shape (see Approach: true chip widgets were tried and
  dropped for a real alignment problem).
- Tapping a token toggles it between included/excluded, mutating the `!`
  character in place.
- Removing a token is plain text editing (backspace/select+delete) — no
  delete (X) affordance on the inline chip.
- Autocomplete triggers based on an unfinished token immediately before
  the *cursor*, not just at the end of the string, and inserts at that
  position.
- The URL mirrors the field exactly: a single `q` param holding the raw
  query string. The existing `tags`/`status` params are retired.

## Non-goals

- Multi-line input, IME composition edge cases beyond what Flutter's
  standard `TextField` already handles.
- Preserving old-style `?tags=...&status=...` links — this is a breaking
  URL-shape change, accepted per stakeholder decision.
- Reworking the edit modal's own `#tag` handling (`tag_parsing.dart`) —
  unaffected by this change.

## Approach

**A custom `TextEditingController.buildTextSpan` override, styling
recognized token ranges directly within the one real, actively-edited
field — no second field, no overlay.**

Three approaches were considered.

The first idea — a ghost/invisible `TextField` for editing, with a
decorative `WidgetSpan`-based chip overlay painted on top — was worked
through in detail and abandoned: a chip's rendered width (padded,
rounded, with an icon) is never exactly the width of the raw characters
it stands in for, so the overlay's line layout and the invisible field's
line layout diverge in width after the *first* token. Everything
rendered after that point drifts out of alignment between the two
layers — a real, not cosmetic, problem for any query with more than one
token or free text following a token, i.e. exactly the cases this
feature exists for.

A true inline `WidgetSpan` chip *inside the actively-edited text itself*
(no ghost field, via the same `buildTextSpan` override) was also
rejected: Flutter's cursor/selection math for a `WidgetSpan` inside text
that's actually being edited is not properly supported — a chip occupies
one internal "object replacement" position decoupled from its visual
width, so clicking near a chip, arrow-keying past it, or selecting
across it behaves unpredictably.

Pulling in a third-party rich-text-editing package was rejected as
before: no rich-text dependencies exist in this repo today, no
off-the-shelf package natively supports "tap a token to toggle a custom
state," and the integration risk isn't justified for one feature.

**What's left, and what this spec uses:** style the token's *own
characters* differently — bold, tinted foreground/background — rather
than replacing them with a differently-sized widget. Since a styled
`TextSpan` occupies exactly the width of the text it contains (it's the
same characters, just colored), there is no alignment problem at all,
for any number of tokens anywhere in the string. This needs no ghost
field: `TextEditingController.buildTextSpan` is overridden directly on
the one real, actively-edited controller, returning a `TextSpan` tree
where recognized ranges get a distinct `style` and a
`TextSpan.recognizer` (a `TapGestureRecognizer`) — Flutter's native,
fully-supported mechanism for making part of a text span tappable,
including inside an editable field. A tap landing precisely on a
token's characters fires its recognizer (toggle); a tap anywhere else is
unclaimed and falls through to the field's normal cursor-placement
behavior, exactly as today.

## Data flow

`_searchController.text` is the only state. A pure function parses it on
every change:

```
({
  List<({String tag, bool excluded, TextRange range})> tagTokens,
  ({bool excluded, TextRange range})? statusToken,
  String freeText,
}) _parseQuery(String text)
```

- `tagTokens`: every `#tag`/`#!tag` occurrence anywhere in the string
  (regex scan across the whole string, not just a trailing match),
  each carrying the exact character range it occupies (needed to mutate
  the right spot when toggled, and to know where to place a chip when
  rendering).
- `statusToken`: at most one recognized `/opened`/`/!opened` occurrence
  — first one found; extras are left as plain text, same "single slot"
  rule as today. `null` when absent.
- `freeText`: the string with every recognized token's characters
  removed and whitespace collapsed/trimmed — this is what the title
  substring filter uses.

`_filter(tasks)`, `_syncUrl()`, and the chip-rendering overlay all derive
from a fresh `_parseQuery(_searchController.text)` call — no cached
`_selectedTags`/`_openedFilter` fields to keep in sync by hand.

`_syncUrl()` becomes: `router.replace('/tasks', queryParameters: {if
(text.isNotEmpty) 'q': text})`. Loading from a route seeds the
controller directly with `params?['q'] ?? ''` — no separate seeding logic
for tags/status.

## Rendering

`_UnifiedQueryController extends TextEditingController`, overriding
`buildTextSpan`:

```
@override
TextSpan buildTextSpan({
  required BuildContext context,
  TextStyle? style,
  required bool withComposing,
}) {
  final parsed = parseSearchQuery(text);
  final tokens = /* parsed.tagTokens + parsed.statusToken, as
                    (range, excluded) pairs, sorted by range.start */;
  final colors = Theme.of(context).colorScheme;
  final spans = <TextSpan>[];
  var cursor = 0;
  for (final token in tokens) {
    if (token.range.start > cursor) {
      spans.add(TextSpan(text: text.substring(cursor, token.range.start), style: style));
    }
    spans.add(TextSpan(
      text: text.substring(token.range.start, token.range.end),
      style: (style ?? const TextStyle()).copyWith(
        fontWeight: FontWeight.w600,
        color: token.excluded ? colors.onErrorContainer : colors.onPrimaryContainer,
        backgroundColor: token.excluded ? colors.errorContainer : colors.primaryContainer,
      ),
      recognizer: TapGestureRecognizer()
        ..onTap = () => onTokenTapped(token.range, excluded: token.excluded),
    ));
    cursor = token.range.end;
  }
  if (cursor < text.length) {
    spans.add(TextSpan(text: text.substring(cursor), style: style));
  }
  return TextSpan(style: style, children: spans);
}
```

The `TextField` itself is otherwise unchanged from today — same
`decoration` (hint/prefix icon/clear suffix), same single controller,
no `Stack`, no second field. A tap landing on a token's own characters
fires that span's `TapGestureRecognizer` (toggle); a tap anywhere else
has no recognizer to claim it and falls through to `TextField`'s normal
cursor-placement handling, unchanged from today.

Each `buildTextSpan` call creates fresh `TapGestureRecognizer`s for the
current token set; the controller disposes the previous batch at the
start of each call (and any stragglers in its own `dispose()`), which is
the standard lifecycle for span recognizers rebuilt on every change.

## Interaction

- **Toggling**: `onTokenTapped(TextRange range, {required bool
  excluded})` inserts/removes the `!` character immediately after the
  `#`/`/` at that exact range via a `TextEditingValue` replace, shifting
  the cursor offset by ±1 if it was positioned after the edit point.
- **Autocomplete at cursor**: the existing partial-token regexes
  (`_partialTagPattern`/`_partialStatusPattern`) now match against
  `text.substring(0, _searchController.selection.baseOffset)` instead of
  the whole string, so an unfinished token anywhere the cursor currently
  sits (not just at the very end) triggers suggestions. Selecting a
  suggestion inserts the completed word + trailing space at the cursor's
  position (replacing just the partial token), not necessarily appended
  at the end.
- **Removal**: no dedicated delete icon — backspacing or selecting a
  token's characters and deleting removes it, since it's literal text.
- **Escape / dismissal**: unchanged — still hides the floating
  suggestions overlay via the existing `_suggestionsDismissed` flag.

## Testing

Most of `tasks_screen_test.dart`'s search-related tests currently assert
against `_selectedTags`/a separate `InputChip` row and need rewriting,
not just extending, since that model goes away. Since tokens no longer
render as separate widgets (`InputChip`/`ListTile` in earlier turns),
assertions shift from widget-tree lookups to checking rendered
`TextSpan` styling/`recognizer` presence at the right ranges, plus
functional outcomes (filtered task list, URL). New coverage should
include:

- A mixed string (`"Buy milk #groceries /opened"`) produces the right
  spans (plain vs. styled+tappable at the right ranges) and filters
  correctly.
- Tapping a token's rendered text toggles its `!` in place and
  re-renders/re-filters.
- Backspacing through a token's characters removes it and un-filters.
- Autocomplete triggers for a partial token with the cursor positioned
  mid-string (not just at the end), and completes at that position.
- URL round-trip: a raw query string in `?q=...` seeds the field
  verbatim on load, and edits sync back to `?q=...`.
- `tags=`/`status=` params are no longer read (confirm a URL using the
  old params behaves like an empty query, not an error).

Existing `e2e/tests/tasks-screen.spec.ts` search/tag coverage will also
need rework: selectors currently assume a separate search `textbox`
plus separate `InputChip` pills outside it; with tokens now styled text
inside the one field rather than separate semantic nodes, Playwright's
accessibility-tree view needs re-verification (via the same kind of
probe-test approach used earlier this session) before finalizing
selectors — clicking a specific token's on-screen position (via
coordinates) is likely the reliable mechanism, since there's no longer a
separate tappable element to target by role/name.

## Risks

- `TextSpan.recognizer`-based taps inside an actively-edited `TextField`
  is well-documented, standard Flutter behavior, but should get an early
  smoke check in the running app before building the rest of the feature
  on top of it.
- This is a rewrite of the search bar's internals built over the last
  several turns of this session (tag pills, status pill, autocomplete) —
  not additive. Expect the bulk of `tasks_screen.dart`'s state/rendering
  for the search bar to change.
- Breaking URL-shape change: old `?tags=...&status=...` links stop being
  understood (accepted).
- e2e selectors for tapping a token lose the "target by accessible
  role/name" mechanism they relied on for the separate-pill design;
  coordinate-based clicks are more brittle to incidental layout changes.
