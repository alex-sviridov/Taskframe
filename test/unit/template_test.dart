import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/template/models/template.dart';

void main() {
  group('Template', () {
    test('copyWith replaces name and keeps id', () {
      const template = Template(id: 't1', name: 'Weekday');
      final renamed = template.copyWith(name: 'Weekend');
      expect(renamed.id, 't1');
      expect(renamed.name, 'Weekend');
    });

    test('copyWith with no arguments keeps the same name', () {
      const template = Template(id: 't1', name: 'Weekday');
      expect(template.copyWith().name, 'Weekday');
    });
  });

  group('toMap/fromMap', () {
    test('fromMap(toMap()) round-trips every field', () {
      const template = Template(id: 'template-1', name: 'Weekday');

      final restored = Template.fromMap(template.toMap());

      expect(restored.id, template.id);
      expect(restored.name, template.name);
    });
  });
}
