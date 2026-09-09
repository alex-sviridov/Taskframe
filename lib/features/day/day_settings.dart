import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Configures the visible range and layout of the day/week schedule.
///
/// Hardcoded for now; a future settings screen can let the user override
/// [daySettingsProvider] without the grid/screen needing to change.
class DaySettings {
  /// Creates a [DaySettings].
  const new({
    required this.dayStartHour,
    required this.dayEndHour,
    required this.firstDayOfWeek,
    required this.dateFormat,
  });

  /// The first hour shown on the grid (inclusive).
  final int dayStartHour;

  /// The last hour shown on the grid (inclusive).
  final int dayEndHour;

  /// The weekday (`DateTime.monday`..`DateTime.sunday`) a week starts on,
  /// in week view.
  final int firstDayOfWeek;

  /// A date-format pattern using `dd`/`MM`/`yyyy` tokens, e.g.
  /// `'dd/MM/yyyy'` (European) or `'MM/dd/yyyy'` (US). See `formatDate`.
  final String dateFormat;
}

/// The day/week schedule's hardcoded layout settings.
final daySettingsProvider = Provider<DaySettings>(
  (ref) => const DaySettings(
    dayStartHour: 6,
    dayEndHour: 23,
    firstDayOfWeek: DateTime.monday,
    dateFormat: 'dd/MM/yyyy',
  ),
);
