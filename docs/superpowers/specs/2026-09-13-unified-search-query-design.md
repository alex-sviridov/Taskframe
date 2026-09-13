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
one string is the only source of truth, tokens render as inline pill
chips within the same text flow (not a separate row), and everything
else (filtering, URL sync, autocomplete) is derived from that one string
by parsing it fresh on every change.

## Goals

- One `TextField`, one `TextEditingController`, one string. No
  `_selectedTags`/`_openedFilter` fields extracted out of the text.
- Recognized tokens (`#tag`, `#!tag`, `/opened`, `/!opened`) render as
  rounded, padded chip widgets inline with the surrounding plain text —
  the same visual language as today's pills (block icon + error colors
  when excluded, radio-button icon for the status pill).
- Tapping a chip toggles it between included/excluded, mutating the `!`
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

**"Ghost field" — a real, invisible-text `TextField` for editing, with a
decorative chip overlay painted on top.**

Two other approaches were considered and rejected:

- Rendering chips *inside* the actively-edited text via a custom
  `TextEditingController.buildTextSpan` override returning `WidgetSpan`s
  directly. Flutter's cursor/selection math for `WidgetSpan` inside text
  that's actually being edited is not properly supported — a chip
  occupies one internal "object replacement" position decoupled from its
  visual width, so clicking near a chip, arrow-keying past it, or
  selecting across it behaves unpredictably. This is the natural first
  idea and the reason it's usually abandoned.
- Pulling in a third-party rich-text-editing package. This repo has no
  rich-text dependencies today, off-the-shelf packages don't natively
  support "tap a token to toggle a custom state," and the integration
  risk isn't justified for one feature.

The ghost-field technique sidesteps the hard problem entirely: the real
`TextField` (`style: TextStyle(color: Colors.transparent)`, cursor and
selection colors unaffected) handles 100% standard plain-text editing —
typing, cursor placement, selection, IME — with zero special-casing.
Its text is invisible; what's visible is a separately-painted
`Text.rich` sitting in the same position (`Stack`), built from the exact
same string, where recognized token ranges become `WidgetSpan`s
containing a small chip widget and everything else is plain `TextSpan`
text. This is the standard technique behind syntax-highlighting and
mention-chip text editors.

Pointer routing falls out naturally: a plain `TextSpan` has no
recognizer and isn't a distinct widget, so taps there aren't claimed by
the overlay and fall through to the real `TextField` beneath for normal
cursor placement. A `WidgetSpan`'s chip *is* a real widget with its own
gesture handling, so a tap precisely on a chip is claimed by the chip
itself.

The one real cost: the overlay's plain-text styling and the real
field's `style` must be kept pixel-identical (font family/size/weight/
letter-spacing, padding) so glyph positions in the invisible field line
up with what the overlay paints, keeping the cursor visually where it
looks like it should be.

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

`_UnifiedQueryField` (replacing today's plain `TextField` in the
AppBar's `bottom`):

```
Stack(
  children: [
    TextField(
      controller: _searchController,
      focusNode: _searchFocusNode,
      style: /* transparent text color, everything else matches the
                overlay's plain-span style */,
      decoration: /* same hint/prefix/clear-suffix as today */,
    ),
    Text.rich(
      TextSpan(children: [
        // walk _parseQuery(text)'s token ranges left-to-right,
        // alternating plain TextSpan(text: segment) and
        // WidgetSpan(child: _InlineFilterPill(...))
      ]),
    ),
  ],
)
```

The overlay is *not* wrapped in `IgnorePointer`: a plain `TextSpan` has
no recognizer and isn't a distinct widget, so `RichText`'s hit-testing
never claims a hit there — those pixels fall through to the `TextField`
beneath on their own. Only a `WidgetSpan`'s chip is an actual widget
that can claim its own pixels, so only taps precisely on a chip are
intercepted; everything else reaches the real field untouched.

`_InlineFilterPill` reuses today's `_FilterPill` visuals (block icon +
error colors when excluded, radio-button icon for the status pill) but
drops the delete (X) affordance — its only interaction is `onPressed`
(toggle), wrapped in `WidgetSpan(alignment: PlaceholderAlignment.middle,
child: ...)` so it sits on the text baseline.

## Interaction

- **Toggling**: a chip's `onPressed` calls `_toggleTokenAt(TextRange
  range)`, which inserts/removes the `!` character immediately after the
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
not just extending, since that model goes away. New coverage should
include:

- A mixed string (`"Buy milk #groceries /opened"`) renders the right
  inline chips in the right positions and filters correctly.
- Tapping a chip toggles its `!` in place and re-renders/re-filters.
- Backspacing through a token's characters removes it and un-filters.
- Autocomplete triggers for a partial token with the cursor positioned
  mid-string (not just at the end), and completes at that position.
- URL round-trip: a raw query string in `?q=...` seeds the field
  verbatim on load, and edits sync back to `?q=...`.
- `tags=`/`status=` params are no longer read (confirm a URL using the
  old params behaves like an empty query, not an error).

Existing `e2e/tests/tasks-screen.spec.ts` search/tag coverage will also
need rework: selectors currently assume a separate search `textbox`
plus separate `InputChip` pills outside it; with pills now painted
inline over a ghost field, Playwright's accessibility-tree view of the
field's *visible* text vs the chips' own semantics needs re-verification
(likely via the same kind of probe-test approach used earlier this
session) before finalizing selectors.

## Risks

- Pixel alignment between the ghost field and the overlay depends on
  exact `TextStyle`/padding parity and needs real-device verification in
  the running app, not just widget tests.
- This is a rewrite of the search bar's internals built over the last
  several turns of this session (tag pills, status pill, autocomplete) —
  not additive. Expect the bulk of `tasks_screen.dart`'s state/rendering
  for the search bar to change.
- Breaking URL-shape change: old `?tags=...&status=...` links stop being
  understood (accepted).
