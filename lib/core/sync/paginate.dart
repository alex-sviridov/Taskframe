/// Calls [fetchPage] for page 1, 2, 3, ... accumulating every returned
/// item, until a page comes back with fewer than [perPage] items —
/// PocketBase's own signal that there's no next page. Used by
/// `PocketBaseSyncClient.listChangedSince` so a burst of remote changes
/// larger than one page isn't silently truncated to just the first page.
Future<List<T>> fetchAllPages<T>(
  Future<List<T>> Function(int page) fetchPage, {
  required int perPage,
}) async {
  final all = <T>[];
  var page = 1;
  while (true) {
    final items = await fetchPage(page);
    all.addAll(items);
    if (items.length < perPage) return all;
    page++;
  }
}
