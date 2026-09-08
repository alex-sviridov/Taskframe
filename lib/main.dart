import 'package:flutter/material.dart';

/// Temporary bootstrap widget; replaced once theming and routing land.
void main() {
  runApp(const _PlaceholderApp());
}

class _PlaceholderApp extends StatelessWidget {
  const _PlaceholderApp();

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
