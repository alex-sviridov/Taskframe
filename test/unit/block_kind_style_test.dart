import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/day/models/time_object.dart';
import 'package:taskframe/features/day/widgets/block_kind_style.dart';

void main() {
  group('BlockKindStyle', () {
    test('anchor is styled as a red event', () {
      expect(BlockKind.anchor.icon, Icons.event);
      expect(BlockKind.anchor.color, Colors.red);
      expect(BlockKind.anchor.label, 'Event');
    });

    test('frame is styled as a blue frame', () {
      expect(BlockKind.frame.icon, Icons.crop_free);
      expect(BlockKind.frame.color, Colors.blue);
      expect(BlockKind.frame.label, 'Frame');
    });
  });
}
