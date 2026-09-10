import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/core/responsive.dart';

void _setViewportWidth(WidgetTester tester, double width) {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  group('isNarrow', () {
    testWidgets('is true below narrowBreakpoint', (tester) async {
      _setViewportWidth(tester, 600);

      late bool result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              result = isNarrow(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(result, isTrue);
    });

    testWidgets('is false at narrowBreakpoint', (tester) async {
      _setViewportWidth(tester, narrowBreakpoint);

      late bool result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              result = isNarrow(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(result, isFalse);
    });

    testWidgets('is false above narrowBreakpoint', (tester) async {
      _setViewportWidth(tester, 1000);

      late bool result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              result = isNarrow(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(result, isFalse);
    });
  });
}
