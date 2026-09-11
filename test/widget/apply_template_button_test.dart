import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/day/widgets/apply_template_button.dart';
import 'package:taskframe/features/day/widgets/apply_template_modal.dart';
import 'package:taskframe/features/template/providers.dart';

final _date = DateTime(2000);

Future<void> _pump(
  WidgetTester tester,
  ProviderContainer container, {
  required bool alwaysVisible,
}) => tester.pumpWidget(
  UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Scaffold(
        body: ApplyTemplateButton(date: _date, alwaysVisible: alwaysVisible),
      ),
    ),
  ),
);

void main() {
  group('ApplyTemplateButton', () {
    testWidgets('is disabled when there are no templates', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(templateListProvider.future);

      await _pump(tester, container, alwaysVisible: true);
      await tester.pump();

      final button = tester.widget<IconButton>(find.byType(IconButton));
      expect(button.onPressed, isNull);
    });

    testWidgets('opens the apply-template modal when tapped', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container
          .read(templateListProvider.notifier)
          .addTemplate(name: 'Morning');

      await _pump(tester, container, alwaysVisible: true);
      await tester.pump();

      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();

      expect(find.byType(ApplyTemplateModal), findsOneWidget);
    });

    testWidgets('is hidden until hovered when not alwaysVisible', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container
          .read(templateListProvider.notifier)
          .addTemplate(name: 'Morning');

      await _pump(tester, container, alwaysVisible: false);
      await tester.pump();

      Opacity opacityOf() => tester.widget<Opacity>(find.byType(Opacity));
      expect(opacityOf().opacity, 0);

      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await tester.pump();
      await gesture.moveTo(tester.getCenter(find.byType(IconButton)));
      await tester.pump();

      expect(opacityOf().opacity, 1);
    });
  });
}
