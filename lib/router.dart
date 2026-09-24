import 'package:go_router/go_router.dart';
import 'package:taskframe/core/platform/standalone_display.dart';
import 'package:taskframe/core/widgets/app_shell.dart';
import 'package:taskframe/features/account/widgets/account_screen.dart';
import 'package:taskframe/features/category/widgets/categories_screen.dart';
import 'package:taskframe/features/day/day_screen.dart';
import 'package:taskframe/features/now/now_screen.dart';
import 'package:taskframe/features/task/widgets/tasks_screen.dart';
import 'package:taskframe/features/template/widgets/templates_screen.dart';

/// Builds a fresh application router: a shell with six branches (Now,
/// Day/Week, Templates, Categories, Tasks, Account), each keeping its
/// own state alive when the others are shown. Bare `/` redirects to
/// `/day`, the app's default view.
///
/// [isStandalone] reports whether the app is running as an installed
/// PWA. iOS pins a home-screen PWA to whichever URL was open in Safari
/// at "Add to Home Screen" time, ignoring the web manifest's
/// `start_url` — so a device added while on `/account` would otherwise
/// launch straight into the (likely logged-out) account screen forever.
/// To fix that without breaking ordinary browser deep-links (e.g.
/// refreshing a `/tasks?q=...` search), the very first navigation of a
/// fresh router is forced to `/day` only when [isStandalone] is true;
/// every navigation after that behaves normally. Injectable so tests
/// can simulate standalone launches without a real browser; defaults
/// to the real platform check.
GoRouter createAppRouter({
  bool Function() isStandalone = isStandaloneDisplayMode,
}) {
  var hasHandledLaunch = false;
  return GoRouter(
    redirect: (context, state) {
      if (!hasHandledLaunch) {
        hasHandledLaunch = true;
        if (isStandalone()) return '/day';
      }
      return state.uri.path == '/' ? '/day' : null;
    },
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/now',
                builder: (context, state) => const NowScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/day',
                builder: (context, state) => const DayScreen(),
              ),
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
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/account',
                builder: (context, state) => const AccountScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

/// The application's single router instance.
final GoRouter appRouter = createAppRouter();
