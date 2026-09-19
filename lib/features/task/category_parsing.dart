import 'package:taskframe/features/category/models/category.dart';

// Any non-space, non-trigger character, not `\w`, since `\w` in Dart's
// RegExp is ASCII-only ([A-Za-z0-9_]) and would silently fail to match
// category names containing letters outside that range (e.g. Cyrillic
// "уборка"). Trigger characters (#/@) stay excluded so this still stops
// at a following token typed with no space, same as `\w` did by not
// matching them either.
final _trailingCategoryPattern = RegExp(r'(^|\s)@([^\s#/@]+) $');
final _finalCategoryPattern = RegExp(r'(^|\s)@([^\s#/@]+)$');

/// If [text] ends with an `@category` immediately followed by the space
/// that was just typed, and `category` matches (case-insensitively) the
/// name of one of [categories], returns that category's id and the title
/// with the `@category ` chunk removed. Returns `null` when there is no
/// such trailing `@word`, or the word doesn't match any category name —
/// categories are a closed vocabulary, so an unmatched word is left as
/// plain text rather than extracted.
({String title, String categoryId})? extractTrailingCategory(
  String text,
  List<Category> categories,
) => _extract(text, _trailingCategoryPattern, categories);

/// If [text] ends with an `@category` with nothing after it (no trailing
/// space needed) — the case where the user typed a category and
/// left/closed the field without ever typing a following space — returns
/// that category's id and the title with the `@category` chunk removed.
/// Returns `null` when there is no such `@word` at the very end, or it
/// doesn't match any category name.
({String title, String categoryId})? extractFinalCategory(
  String text,
  List<Category> categories,
) => _extract(text, _finalCategoryPattern, categories);

({String title, String categoryId})? _extract(
  String text,
  RegExp pattern,
  List<Category> categories,
) {
  final match = pattern.firstMatch(text);
  if (match == null) return null;
  final word = match.group(2)!.toLowerCase();
  Category? category;
  for (final candidate in categories) {
    if (candidate.name.toLowerCase() == word) {
      category = candidate;
      break;
    }
  }
  if (category == null) return null;
  return (
    title: text.substring(0, match.start) + match.group(1)!,
    categoryId: category.id,
  );
}
