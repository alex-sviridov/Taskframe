import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sembast/sembast.dart';
import 'package:taskframe/core/storage/app_database.dart';

/// Loads and stores small, single-value app settings — currently just
/// when the iOS install hint was last dismissed.
abstract class AppSettingsRepository {
  /// When the install hint was last dismissed, or `null` if never.
  Future<DateTime?> getInstallHintDismissedAt();

  /// Records that the install hint was dismissed at [time].
  Future<void> setInstallHintDismissedAt(DateTime time);
}

/// An [AppSettingsRepository] that keeps its value in memory for the
/// life of the app.
class InMemoryAppSettingsRepository implements AppSettingsRepository {
  DateTime? _dismissedAt;

  @override
  Future<DateTime?> getInstallHintDismissedAt() async => _dismissedAt;

  @override
  Future<void> setInstallHintDismissedAt(DateTime time) async {
    _dismissedAt = time;
  }
}

/// An [AppSettingsRepository] backed by a sembast [Database], persisting
/// the dismissal time across restarts.
class SembastAppSettingsRepository implements AppSettingsRepository {
  /// Creates a [SembastAppSettingsRepository] reading/writing [db].
  SembastAppSettingsRepository(this._db);

  final Database _db;

  static const _key = 'install_hint_dismissed_at';

  @override
  Future<DateTime?> getInstallHintDismissedAt() async {
    final record = await settingsStore.record(_key).get(_db);
    final iso = record?['value'] as String?;
    return iso == null ? null : DateTime.parse(iso);
  }

  @override
  Future<void> setInstallHintDismissedAt(DateTime time) async {
    await settingsStore.record(_key).put(_db, {
      'value': time.toIso8601String(),
    });
  }
}

/// The backing store for app settings. Overriding this single provider
/// (as `main.dart` does with [SembastAppSettingsRepository]) is enough to
/// persist settings; nothing downstream needs to change.
final appSettingsRepositoryProvider = Provider<AppSettingsRepository>(
  (ref) => InMemoryAppSettingsRepository(),
);
