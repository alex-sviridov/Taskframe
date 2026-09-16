import 'package:go_router/go_router.dart';
import 'package:taskframe/core/widgets/app_shell.dart';
import 'package:taskframe/features/category/widgets/categories_screen.dart';
import 'package:taskframe/features/day/day_screen.dart';
import 'package:taskframe/features/account/widgets/account_screen.dart';
import 'package:taskframe/features/task/widgets/tasks_screen.dart';
import 'package:taskframe/features/template/widgets/templates_screen.dart';

/// Application router: a shell with four branches (Day/Week, Templates,
/// Categories, Tasks), each keeping its own state alive when the others are
/// shown.
final GoRouter appRouter = GoRouter(
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          AppShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/', builder: (context, state) => const DayScreen()),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/templates',
              builder: (context, state) => const TemplatesScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/categories',
              builder: (context, state) => const CategoriesScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/tasks',
              builder: (context, state) => const TasksScreen(),
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: '/account',
      builder: (context, state) => const AccountScreen(),
    ),
  ],
);
