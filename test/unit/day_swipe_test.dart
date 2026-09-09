import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/day/day_swipe.dart';

void main() {
  group('resolveSwipeDirection', () {
    test('a fast leftward fling resolves to the next day', () {
      expect(resolveSwipeDirection(-500), 1);
    });

    test('a fast rightward fling resolves to the previous day', () {
      expect(resolveSwipeDirection(500), -1);
    });

    test('a fling slower than the threshold resolves to nothing', () {
      expect(resolveSwipeDirection(100), isNull);
      expect(resolveSwipeDirection(-100), isNull);
    });

    test('no primary velocity resolves to nothing', () {
      expect(resolveSwipeDirection(null), isNull);
    });

    test('a custom threshold is respected', () {
      expect(resolveSwipeDirection(-150, threshold: 100), 1);
      expect(resolveSwipeDirection(-80, threshold: 100), isNull);
    });
  });
}
