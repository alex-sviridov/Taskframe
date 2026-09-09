import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Configures the visible range of the day grid.
///
/// Hardcoded to 6-23 for now; a future settings screen can let the user
/// override [daySettingsProvider] without the grid needing to change.
class DaySettings {
  /// Creates a [DaySettings].
  const new({required this.dayStartHour, required this.dayEndHour});

  /// The first hour shown on the grid (inclusive).
  final int dayStartHour;

  /// The last hour shown on the grid (inclusive).
  final int dayEndHour;
}

/// The day grid's start/end hours.
final daySettingsProvider = Provider<DaySettings>(
  (ref) => const DaySettings(dayStartHour: 6, dayEndHour: 23),
);
