/// The characters allowed inside a `#tag` or `@category` token: Unicode
/// letters, Unicode digits, and `-`. Every other character — including
/// symbols like `.`, `_`, `!`, `'` — is a divider, exactly like space
/// already is, so it simply ends the token early rather than becoming
/// part of it.
///
/// Uses `\p{L}`/`\p{N}` rather than `\w`, since `\w` in Dart's RegExp is
/// ASCII-only ([A-Za-z0-9_]) and would silently fail to match tags or
/// category names containing letters outside that range (e.g. Cyrillic).
/// Any `RegExp` built with this fragment must pass `unicode: true` for
/// the `\p{...}` escapes to work.
const tokenWordChar = r'[\p{L}\p{N}-]';
