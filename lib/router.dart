import 'package:go_router/go_router.dart';
import 'package:taskframe/features/day/day_screen.dart';

/// Application router with the single smoke-test route.
final GoRouter appRouter = GoRouter(
  routes: [GoRoute(path: '/', builder: (context, state) => const DayScreen())],
);
