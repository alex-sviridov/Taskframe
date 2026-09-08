import 'package:flutter/material.dart';
import 'package:taskframe/core/theme.dart';
import 'package:taskframe/router.dart';

/// Root application widget wiring theme and routing together.
class App extends StatelessWidget {
  /// Creates an [App].
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerConfig: appRouter,
      theme: lightTheme,
      darkTheme: darkTheme,
      // Explicit even though it matches the default, to make the
      // light/dark switching behavior obvious at the call site.
      // ignore: avoid_redundant_argument_values
      themeMode: ThemeMode.system,
    );
  }
}
