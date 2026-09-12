import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/core/storage/app_settings_repository.dart';
import 'package:taskframe/core/widgets/ios_install_hint_banner.dart';

class _FakeAppSettingsRepository implements AppSettingsRepository {
  new({this._dismissedAt});
  DateTime? _dismissedAt;

  @override
  Future<DateTime?> getInstallHintDismissedAt() async => _dismissedAt;

  @override
  Future<void> setInstallHintDismissedAt(DateTime time) async {
    _dismissedAt = time;
  }
}

Future<void> _pump(WidgetTester tester, List<Override> overrides) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: const MaterialApp(home: Scaffold(body: IosInstallHintBanner())),
    ),
  );
  await tester.pump();
}

void main() {
  group('IosInstallHintBanner', () {
    testWidgets('is hidden when not an iOS browser tab', (tester) async {
      await _pump(tester, [
        isIosBrowserTabProvider.overrideWithValue(false),
        appSettingsRepositoryProvider.overrideWithValue(
          _FakeAppSettingsRepository(),
        ),
      ]);

      expect(find.byType(MaterialBanner), findsNothing);
    });

    testWidgets('is shown on an iOS browser tab with no prior dismissal', (
      tester,
    ) async {
      await _pump(tester, [
        isIosBrowserTabProvider.overrideWithValue(true),
        appSettingsRepositoryProvider.overrideWithValue(
          _FakeAppSettingsRepository(),
        ),
      ]);

      expect(find.byType(MaterialBanner), findsOneWidget);
    });

    testWidgets('is hidden shortly after being dismissed', (tester) async {
      await _pump(tester, [
        isIosBrowserTabProvider.overrideWithValue(true),
        appSettingsRepositoryProvider.overrideWithValue(
          _FakeAppSettingsRepository(dismissedAt: DateTime.now()),
        ),
      ]);

      expect(find.byType(MaterialBanner), findsNothing);
    });

    testWidgets('is shown again after the cooldown has passed', (tester) async {
      await _pump(tester, [
        isIosBrowserTabProvider.overrideWithValue(true),
        appSettingsRepositoryProvider.overrideWithValue(
          _FakeAppSettingsRepository(
            dismissedAt: DateTime.now().subtract(const Duration(days: 15)),
          ),
        ),
      ]);

      expect(find.byType(MaterialBanner), findsOneWidget);
    });

    testWidgets('dismiss button hides the banner and records the '
        'dismissal', (tester) async {
      final repository = _FakeAppSettingsRepository();
      await _pump(tester, [
        isIosBrowserTabProvider.overrideWithValue(true),
        appSettingsRepositoryProvider.overrideWithValue(repository),
      ]);
      expect(find.byType(MaterialBanner), findsOneWidget);

      await tester.tap(find.text('Dismiss'));
      // Two pumps: one for the dismiss write + invalidate to land, a
      // second for the re-fetch FutureProvider it triggers to resolve.
      await tester.pump();
      await tester.pump();

      expect(find.byType(MaterialBanner), findsNothing);
      expect(await repository.getInstallHintDismissedAt(), isNotNull);
    });
  });
}
