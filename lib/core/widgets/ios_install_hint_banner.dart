import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/core/platform/standalone_display.dart';
import 'package:taskframe/core/storage/app_settings_repository.dart';

/// How long after a dismissal the install hint stays hidden before it's
/// eligible to show again.
const _dismissCooldown = Duration(days: 14);

/// Whether the app is currently running as an iOS Safari browser tab —
/// i.e. iOS, on the web, and not already launched from the home screen.
/// A [Provider] (rather than a plain function) so tests can override it
/// without needing a real browser.
final isIosBrowserTabProvider = Provider<bool>(
  (ref) =>
      kIsWeb &&
      defaultTargetPlatform == TargetPlatform.iOS &&
      !isStandaloneDisplayMode(),
);

/// Whether [IosInstallHintBanner] should currently be shown: only on an
/// iOS browser tab, and only if it's never been dismissed or the
/// dismissal is older than [_dismissCooldown].
final installHintVisibleProvider = FutureProvider<bool>((ref) async {
  if (!ref.watch(isIosBrowserTabProvider)) return false;

  final dismissedAt = await ref
      .watch(appSettingsRepositoryProvider)
      .getInstallHintDismissedAt();
  if (dismissedAt == null) return true;

  return DateTime.now().difference(dismissedAt) > _dismissCooldown;
});

/// A dismissible banner teaching iOS Safari users how to install
/// Taskframe, shown when [installHintVisibleProvider] resolves `true`.
/// iOS has no native install prompt (no `beforeinstallprompt`), so this
/// is the only way users learn about Share → Add to Home Screen.
class IosInstallHintBanner extends ConsumerWidget {
  /// Creates an [IosInstallHintBanner].
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = ref.watch(installHintVisibleProvider).value ?? false;
    if (!visible) return const SizedBox.shrink();

    return MaterialBanner(
      content: const Text(
        'Install Taskframe: tap Share, then "Add to Home Screen".',
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await ref
                .read(appSettingsRepositoryProvider)
                .setInstallHintDismissedAt(DateTime.now());
            // Riverpod's WidgetRef (backed by the widget's Element here)
            // throws a StateError from ref.invalidate/read if the widget
            // has been unmounted since the await above started — it does
            // not silently no-op — so guard with the context it exposes.
            if (!ref.context.mounted) return;
            ref.invalidate(installHintVisibleProvider);
          },
          child: const Text('Dismiss'),
        ),
      ],
    );
  }
}
