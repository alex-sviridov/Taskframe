import 'package:flutter/material.dart';
import 'package:taskframe/features/day/models/time_object.dart';

/// The icon, color and label a [BlockKind] is shown with everywhere it
/// appears in the UI — the draft overlay's create buttons and the block
/// edit modal's type selector alike — so the two never drift apart.
extension BlockKindStyle on BlockKind {
  /// The icon representing this kind.
  IconData get icon => switch (this) {
    BlockKind.anchor => Icons.event,
    BlockKind.frame => Icons.crop_free,
  };

  /// The color representing this kind.
  Color get color => switch (this) {
    BlockKind.anchor => Colors.red,
    BlockKind.frame => Colors.blue,
  };

  /// The user-facing label for this kind.
  String get label => switch (this) {
    BlockKind.anchor => 'Event',
    BlockKind.frame => 'Frame',
  };
}
