// test/unit/paginate_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/core/sync/paginate.dart';

void main() {
  test('returns everything from a single page shorter than perPage', () async {
    final result = await fetchAllPages<int>(
      (page) async => page == 1 ? [1, 2, 3] : [],
      perPage: 200,
    );

    expect(result, [1, 2, 3]);
  });

  test('keeps fetching subsequent pages until one comes back shorter than '
      'perPage, accumulating every item in order', () async {
    final pages = {
      1: [1, 2],
      2: [3, 4],
      3: [5],
    };

    final result = await fetchAllPages<int>(
      (page) async => pages[page] ?? [],
      perPage: 2,
    );

    expect(result, [1, 2, 3, 4, 5]);
  });

  test('requests pages starting at 1 and increasing by 1', () async {
    final requestedPages = <int>[];

    await fetchAllPages<int>((page) async {
      requestedPages.add(page);
      return page < 3 ? [0, 0] : [0];
    }, perPage: 2);

    expect(requestedPages, [1, 2, 3]);
  });
}
