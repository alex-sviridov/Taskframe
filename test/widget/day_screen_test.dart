import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/day/day_screen.dart';

void main() {
  testWidgets(
    'DayScreen shows the title, placeholder text and version',
    (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: DayScreen(),
          ),
        ),
      );

      expect(find.widgetWithText(AppBar, 'Рамка дня'), findsOneWidget);
      expect(find.text('Здесь будет рамка дня'), findsOneWidget);
      expect(find.text('0.1.0-smoke'), findsOneWidget);
    },
  );
}
