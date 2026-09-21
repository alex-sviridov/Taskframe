import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/core/sync/sync_status.dart';
import 'package:taskframe/features/account/account_providers.dart';

/// A compact, always-visible line showing whether this device's data is
/// local-only or syncing, and whether the last attempt succeeded — see
/// the debugging session that found sync silently breaking (a dead
/// session, an offline device) with no way for a user to tell short of
/// noticing a change never arrived on another device.
class SyncStatusIndicator extends ConsumerWidget {
  /// Creates a [SyncStatusIndicator].
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(accountProvider).value;
    final syncStatus = ref.watch(syncStatusProvider);
    final colors = Theme.of(context).colorScheme;
    final (icon, label, color) = _describe(account, syncStatus, colors);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: color),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  (IconData, String, Color) _describe(
    AccountState? account,
    SyncStatus syncStatus,
    ColorScheme colors,
  ) {
    // Sync attempts always fail in guest mode (no session to push/pull
    // against) — irrelevant noise here, since there's nothing to sync.
    final email = account?.email;
    if (email == null) {
      return (Icons.cloud_off, 'Local only', colors.onSurfaceVariant);
    }
    if (account!.sessionExpired) {
      return (Icons.error_outline, 'Sync issue — log in again', colors.error);
    }
    return switch (syncStatus) {
      SyncStatus.syncing => (Icons.sync, 'Syncing…', colors.onSurfaceVariant),
      SyncStatus.idle => (Icons.cloud_done, 'Synced', colors.onSurfaceVariant),
      SyncStatus.error => (Icons.cloud_off, 'Sync issue', colors.error),
    };
  }
}
