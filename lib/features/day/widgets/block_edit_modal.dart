import 'package:flutter/material.dart';

/// A fixed-height row of empty, non-interactive rounded squares reserving
/// visual space for a future category carousel. Carries no data model or
/// selection state yet.
class BlockCategoryPlaceholder extends StatelessWidget {
  /// Creates a [BlockCategoryPlaceholder].
  const BlockCategoryPlaceholder({super.key});

  static const double _size = 40;
  static const int _count = 5;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: _size,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _count,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) => Container(
          width: _size,
          height: _size,
          decoration: BoxDecoration(
            border: Border.all(color: scheme.outlineVariant),
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }
}
