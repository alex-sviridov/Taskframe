import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/core/widgets/colored_list_card.dart';

void main() {
  group('foregroundColorFor', () {
    test('returns white for a dark background', () {
      expect(foregroundColorFor(Colors.black), Colors.white);
    });

    test('returns black for a light background', () {
      expect(foregroundColorFor(Colors.white), Colors.black);
    });

    test('returns white for a dark, saturated color', () {
      expect(foregroundColorFor(const Color(0xFF1A237E)), Colors.white);
    });

    test('returns black for a light, pastel color', () {
      expect(foregroundColorFor(const Color(0xFFFFF9C4)), Colors.black);
    });
  });
}
