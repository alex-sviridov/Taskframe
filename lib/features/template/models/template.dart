import 'package:meta/meta.dart';

/// One template: a named, reusable set of events, editable with the same
/// schedule UI a real day uses (see `TemplatesScreen`).
@immutable
class Template {
  /// Creates a [Template].
  const new({required this.id, required this.name});

  /// Reconstructs a [Template] from a map produced by [toMap].
  factory fromMap(Map<String, Object?> map) =>
      Template(id: map['id']! as String, name: map['name']! as String);

  /// Unique identifier for this template — also its `TemplateColumn.
  /// templateId`.
  final String id;

  /// Display name, shown as this template's column header.
  final String name;

  /// Returns a copy of this template with [name] replaced.
  Template copyWith({String? name}) =>
      Template(id: id, name: name ?? this.name);

  /// This template's field values as a JSON-safe map, for storage.
  Map<String, Object?> toMap() => {'id': id, 'name': name};

  @override
  bool operator ==(Object other) =>
      other is Template && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);
}
