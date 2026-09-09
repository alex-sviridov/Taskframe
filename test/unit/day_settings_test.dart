import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/day/day_settings.dart';

void main() {
  test(
    'daySettingsProvider defaults to a 6-23 day, Monday-first, European dates',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final settings = container.read(daySettingsProvider);

      expect(settings.dayStartHour, 6);
      expect(settings.dayEndHour, 23);
      expect(settings.firstDayOfWeek, DateTime.monday);
      expect(settings.dateFormat, 'dd/MM/yyyy');
    },
  );
}
