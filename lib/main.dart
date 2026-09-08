import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Temporary bootstrap widget; replaced once theming and routing land.
void main() {
  runApp(const ProviderScope(child: _PlaceholderApp()));
}

class _PlaceholderApp extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text('taskframe'),
        ),
      ),
    );
  }
}
