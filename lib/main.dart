import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/app.dart';

/// Entry point: boots the app inside a Riverpod [ProviderScope].
void main() {
  runApp(const ProviderScope(child: App()));
}
