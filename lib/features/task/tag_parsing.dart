final _trailingTagPattern = RegExp(r'(^|\s)#(\w+) $');

/// If [text] ends with a `#tag` immediately followed by the space that was
/// just typed, returns the lowercased tag and the title with that `#tag `
/// chunk removed. Returns `null` when there is no such trailing tag.
({String title, String tag})? extractTrailingTag(String text) {
  final match = _trailingTagPattern.firstMatch(text);
  if (match == null) return null;
  return (
    title: text.substring(0, match.start) + match.group(1)!,
    tag: match.group(2)!.toLowerCase(),
  );
}
