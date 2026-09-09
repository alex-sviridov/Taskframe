import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/day/day_grid_sizing.dart';

void main() {
  group('resolveSlotHeight', () {
    test('shrinks to fit when the available height allows it', () {
      final slotHeight = resolveSlotHeight(
        availableHeight: 680,
        slotCount: 68,
        minSlotHeight: 8,
      );

      expect(slotHeight, 10);
    });

    test('grows to fill extra available height', () {
      final slotHeight = resolveSlotHeight(
        availableHeight: 1360,
        slotCount: 68,
        minSlotHeight: 8,
      );

      expect(slotHeight, 20);
    });

    test('never shrinks below minSlotHeight, even if it overflows', () {
      final slotHeight = resolveSlotHeight(
        availableHeight: 300,
        slotCount: 68,
        minSlotHeight: 8,
      );

      expect(slotHeight, 8);
    });
  });
}
