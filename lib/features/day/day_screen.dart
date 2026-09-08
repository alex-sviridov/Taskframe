import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Hardcoded placeholder version, used only to prove [ProviderScope] wiring
/// works end to end. Not read from `pubspec.yaml`.
final appVersionProvider = Provider<String>((ref) => '0.1.0-smoke');

/// Empty day screen used to smoke-test that the app shell renders.
class DayScreen extends ConsumerWidget {
  /// Creates a [DayScreen].
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final version = ref.watch(appVersionProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Рамка дня')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Здесь будет рамка дня'),
            const SizedBox(height: 8),
            Text(version),
          ],
        ),
      ),
    );
  }
}
