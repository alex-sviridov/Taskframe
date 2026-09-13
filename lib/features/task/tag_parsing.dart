final _trailingTagPattern = RegExp(r'(^|\s)#(\w+) $');
final _finalTagPattern = RegExp(r'(^|\s)#(\w+)$');

/// If [text] ends with a `#tag` immediately followed by the space that was
/// just typed, returns the lowercased tag and the title with that `#tag `
/// chunk removed. Returns `null` when there is no such trailing tag.
({String title, String tag})? extractTrailingTag(String text) =>
    _extract(text, _trailingTagPattern);

/// If [text] ends with a `#tag` with nothing after it (no trailing space
/// needed) — the case where the user typed a tag and left/closed the field
/// without ever typing a following space — returns the lowercased tag and
/// the title with that `#tag` removed. Returns `null` when there is no
/// such tag at the very end.
({String title, String tag})? extractFinalTag(String text) =>
    _extract(text, _finalTagPattern);

({String title, String tag})? _extract(String text, RegExp pattern) {
  final match = pattern.firstMatch(text);
  if (match == null) return null;
  return (
    title: text.substring(0, match.start) + match.group(1)!,
    tag: match.group(2)!.toLowerCase(),
  );
}
