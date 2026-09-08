# Taskframe Init (Stack Smoke-Test) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up a bare Flutter project (Riverpod + go_router) in this
empty repo that builds, lints, and tests cleanly, proving the stack works
before any real feature work starts.

**Architecture:** A single Flutter package at the repo root. `main.dart`
boots a `ProviderScope` around `App` (`MaterialApp.router`), which wires a
one-route `GoRouter` to a single `DayScreen`. Theming lives in
`core/theme.dart`. Tooling (lint, format, test, coverage) is fronted by a
`Makefile` so the same commands work locally and in CI.

**Tech Stack:** Flutter 3.x (stable channel), `flutter_riverpod`,
`go_router`, `very_good_analysis` + `custom_lint` + `riverpod_lint` for
static analysis, `flutter_test` for tests, GitHub Actions for CI.

**Spec:** `docs/superpowers/specs/2026-09-08-taskframe-init-design.md`

## Global Constraints

- Package/project name: `taskframe` (matches the repo directory).
- Platforms created: `android`, `ios`, `web`. Only **Web** is built/run and
  verified in this plan — the dev environment has no Android SDK,
  emulator, GUI, or Chrome. Android and iOS build/run happen later on a
  developer machine or dedicated CI runner.
- No domain logic, models, or real data — this is infrastructure only.
- Analyzer base: `package:very_good_analysis/analysis_options.yaml`, with
  `custom_lint` (via `riverpod_lint`) also enabled.
- `analysis_options.yaml` excludes `**/*.g.dart` and `**/*.freezed.dart`.
- `dart format --set-exit-if-changed .` is part of `make check`, not a
  manual habit.
- Test provider for app version is a hardcoded string `'0.1.0-smoke'` —
  not read from `pubspec.yaml`.
- `AppBar` title on the only screen is exactly `'Рамка дня'`.
- Makefile: every target is listed in `.PHONY`; `help` is the default
  (first) target; no logic beyond tool invocations lives in the
  Makefile itself — anything more complex goes in `scripts/`.
- Because `very_good_analysis` enables `public_member_api_docs`, every
  public class, top-level function, and top-level variable/provider gets
  a one-line `///` doc comment. This is a lint requirement of this
  project's chosen ruleset, not a general commenting preference.

---

### Task 1: Install Flutter SDK and verify the toolchain

**Files:** none in the repo — this task only prepares the local
environment (`~/flutter`, `~/.bashrc`).

**Interfaces:**
- Produces: a `flutter` executable on `PATH` for every later task.

- [ ] **Step 1: Clone the Flutter stable branch**

```bash
git clone https://github.com/flutter/flutter.git -b stable ~/flutter
```

- [ ] **Step 2: Add Flutter to PATH permanently and for the current shell**

```bash
echo 'export PATH="$HOME/flutter/bin:$PATH"' >> ~/.bashrc
export PATH="$HOME/flutter/bin:$PATH"
```

- [ ] **Step 3: Disable analytics prompts and confirm web support is on**

```bash
flutter config --no-analytics --enable-web
```

- [ ] **Step 4: Run doctor and confirm Flutter/Dart are functional**

```bash
flutter doctor -v
```

Expected: output includes resolved Flutter and Dart version lines with no
crash. Warnings/`[✗]` entries for Android toolchain, Android Studio, and
Chrome are expected and fine — those platforms are out of scope here.

- [ ] **Step 5: Confirm the version command works**

```bash
flutter --version
```

Expected: prints a Flutter/Dart version block (not a "command not found"
error). No commit — nothing in the repo changed in this task.

---

### Task 2: Scaffold the Flutter project and a placeholder test

**Files:**
- Create (via `flutter create`): `pubspec.yaml`, `lib/main.dart`,
  `android/`, `ios/`, `web/`, `test/widget_test.dart`, `.metadata`,
  `.gitignore`, `analysis_options.yaml` (overwritten in Task 3),
  `README.md`.
- Delete: `test/widget_test.dart` (default counter-app test).
- Modify: `lib/main.dart` (replace the counter-app template with a
  minimal stub — full wiring lands in Task 5).
- Create: `test/unit/placeholder_test.dart`.

**Interfaces:**
- Produces: a compiling `lib/main.dart` entry point and a green
  `flutter test` run, both of which every later task builds on.

- [ ] **Step 1: Generate the project scaffold**

```bash
flutter create --platforms=android,ios,web .
```

Run from the repo root (`/home/alex/taskframe`). The existing `.git/` and
`docs/` are untouched; `flutter create` only adds Flutter project files.

- [ ] **Step 2: Verify the scaffold**

```bash
ls
```

Expected: `pubspec.yaml`, `lib/`, `test/`, `android/`, `ios/`, `web/`,
`docs/` all present.

- [ ] **Step 3: Remove the default counter-app test**

```bash
rm test/widget_test.dart
```

- [ ] **Step 4: Replace the counter-app stub in `lib/main.dart`**

```dart
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
```

- [ ] **Step 5: Write the placeholder unit test**

Create `test/unit/placeholder_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('test runner is wired up', () {
    expect(1 + 1, equals(2));
  });
}
```

- [ ] **Step 6: Run the tests**

```bash
flutter test
```

Expected: `00:0X +1: All tests passed!` (one test, from
`placeholder_test.dart`).

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
Scaffold Flutter project (android/ios/web) with placeholder test

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_018GjJJbKXZUqqKSvbC4apm4
EOF
)"
```

---

### Task 3: Add dependencies and configure the analyzer

**Files:**
- Modify: `pubspec.yaml` (dependencies and dev_dependencies).
- Modify: `analysis_options.yaml` (replace the `flutter create` default).

**Interfaces:**
- Consumes: the compiling stub from Task 2 (`lib/main.dart`).
- Produces: `flutter_riverpod`, `go_router`, `custom_lint`,
  `riverpod_lint`, `mocktail` available as imports for every later task;
  `flutter analyze` / `dart run custom_lint` as the standing static-check
  commands.

- [ ] **Step 1: Add runtime dependencies**

```bash
flutter pub add flutter_riverpod go_router
```

- [ ] **Step 2: Add dev dependencies**

```bash
flutter pub add --dev custom_lint riverpod_lint mocktail very_good_analysis
```

- [ ] **Step 3: Replace `analysis_options.yaml`**

```yaml
include: package:very_good_analysis/analysis_options.yaml

analyzer:
  plugins:
    - custom_lint
  exclude:
    - '**/*.g.dart'
    - '**/*.freezed.dart'
```

- [ ] **Step 4: Run static analysis**

```bash
flutter analyze
dart run custom_lint
```

Expected: both exit 0 with no issues. `lib/main.dart`'s `_PlaceholderApp`
is private, so `public_member_api_docs` does not apply to it; the doc
comment on `main` already satisfies that rule for the one public
declaration in the file. If either command reports an unexpected
violation, fix it in `lib/main.dart` rather than weakening the rule.

- [ ] **Step 5: Run the existing tests to confirm nothing broke**

```bash
flutter test
```

Expected: still `All tests passed!` (placeholder test only).

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml pubspec.lock analysis_options.yaml
git commit -m "$(cat <<'EOF'
Add Riverpod/go_router deps and configure very_good_analysis + custom_lint

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_018GjJJbKXZUqqKSvbC4apm4
EOF
)"
```

---

### Task 4: Implement `DayScreen` and its widget test

**Files:**
- Create: `lib/features/day/day_screen.dart`.
- Create: `test/widget/day_screen_test.dart`.

**Interfaces:**
- Consumes: `flutter_riverpod` (`Provider`, `ConsumerWidget`,
  `ProviderScope`) added in Task 3.
- Produces: `DayScreen` (a `ConsumerWidget`, no constructor args besides
  `key`) and `appVersionProvider` (`Provider<String>`), both imported by
  Task 5's `router.dart` and by this task's own test.

- [ ] **Step 1: Write the failing widget test**

Create `test/widget/day_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/day/day_screen.dart';

void main() {
  testWidgets(
    'DayScreen shows the title, placeholder text and version',
    (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: DayScreen(),
          ),
        ),
      );

      expect(find.widgetWithText(AppBar, 'Рамка дня'), findsOneWidget);
      expect(find.text('Здесь будет рамка дня'), findsOneWidget);
      expect(find.text('0.1.0-smoke'), findsOneWidget);
    },
  );
}
```

- [ ] **Step 2: Run the test and confirm it fails**

```bash
flutter test test/widget/day_screen_test.dart
```

Expected: FAIL — `day_screen.dart` does not exist yet
(`Target of URI doesn't exist`).

- [ ] **Step 3: Implement `DayScreen`**

Create `lib/features/day/day_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Hardcoded placeholder version, used only to prove [ProviderScope] wiring
/// works end to end. Not read from `pubspec.yaml`.
final appVersionProvider = Provider<String>((ref) => '0.1.0-smoke');

/// Empty day screen used to smoke-test that the app shell renders.
class DayScreen extends ConsumerWidget {
  const DayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final version = ref.watch(appVersionProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Рамка дня')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Здесь будет рамка дня'),
            const SizedBox(height: 8),
            Text(version),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the test and confirm it passes**

```bash
flutter test test/widget/day_screen_test.dart
```

Expected: `All tests passed!`

- [ ] **Step 5: Run static analysis**

```bash
flutter analyze
dart run custom_lint
```

Expected: no issues. `appVersionProvider` and `DayScreen` are public and
already carry `///` doc comments for `public_member_api_docs`.

- [ ] **Step 6: Run the full test suite**

```bash
flutter test
```

Expected: 2 tests passed (`placeholder_test.dart` + `day_screen_test.dart`).

- [ ] **Step 7: Commit**

```bash
git add lib/features/day/day_screen.dart test/widget/day_screen_test.dart
git commit -m "$(cat <<'EOF'
Add DayScreen with a smoke-test Riverpod provider

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_018GjJJbKXZUqqKSvbC4apm4
EOF
)"
```

---

### Task 5: Wire theme, router, and app shell; replace the stub `main.dart`

**Files:**
- Create: `lib/core/theme.dart`.
- Create: `lib/router.dart`.
- Create: `lib/app.dart`.
- Modify: `lib/main.dart` (replace the Task 2 stub entirely).

**Interfaces:**
- Consumes: `DayScreen` from `lib/features/day/day_screen.dart` (Task 4).
- Produces: `lightTheme`, `darkTheme` (`ThemeData`), `appRouter`
  (`GoRouter`), `App` (`StatelessWidget`) — final shape of the app,
  nothing later depends on these beyond running the app.

- [ ] **Step 1: Implement the theme**

Create `lib/core/theme.dart`:

```dart
import 'package:flutter/material.dart';

/// Light theme, built from a single seed color (Material 3).
final ThemeData lightTheme = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
);

/// Dark theme, built from the same seed color (Material 3).
final ThemeData darkTheme = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: Colors.teal,
    brightness: Brightness.dark,
  ),
);
```

- [ ] **Step 2: Implement the router**

Create `lib/router.dart`:

```dart
import 'package:go_router/go_router.dart';

import 'features/day/day_screen.dart';

/// Application router with the single smoke-test route.
final GoRouter appRouter = GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const DayScreen(),
    ),
  ],
);
```

- [ ] **Step 3: Implement the app shell**

Create `lib/app.dart`:

```dart
import 'package:flutter/material.dart';

import 'core/theme.dart';
import 'router.dart';

/// Root application widget wiring theme and routing together.
class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerConfig: appRouter,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: ThemeMode.system,
    );
  }
}
```

- [ ] **Step 4: Replace `lib/main.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

/// Entry point: boots the app inside a Riverpod [ProviderScope].
void main() {
  runApp(const ProviderScope(child: App()));
}
```

- [ ] **Step 5: Run the full test suite**

```bash
flutter test
```

Expected: still 2 tests passed — `App`/`router`/`theme` are not directly
tested (out of spec scope), but must not break `DayScreen`'s test.

- [ ] **Step 6: Run static analysis**

```bash
flutter analyze
dart run custom_lint
```

Expected: no issues. `lightTheme`, `darkTheme`, `appRouter`, and `App`
are public and carry doc comments.

- [ ] **Step 7: Build for web to prove the whole graph compiles**

```bash
flutter build web --release
```

Expected: succeeds, producing `build/web/`. This is the closest this
environment gets to "runs in a browser" — there is no Chrome installed
here to actually launch `flutter run -d chrome`; do that manually on a
machine that has Chrome to confirm the visual result and theme
switching.

- [ ] **Step 8: Commit**

```bash
git add lib/core/theme.dart lib/router.dart lib/app.dart lib/main.dart
git commit -m "$(cat <<'EOF'
Wire theme, router, and app shell; boot through DayScreen

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_018GjJJbKXZUqqKSvbC4apm4
EOF
)"
```

---

### Task 6: Add the Makefile and the pre-commit hook

**Files:**
- Create: `Makefile`.
- Create: `scripts/pre-commit`.
- Create: `scripts/install-hooks.sh`.

**Interfaces:**
- Consumes: `flutter`/`dart` commands only — no code interfaces.
- Produces: `make check` as the single command CI and Task 7 rely on.

- [ ] **Step 1: Write the pre-commit hook script**

Create `scripts/pre-commit`:

```bash
#!/usr/bin/env bash
set -euo pipefail
make format-check analyze
```

- [ ] **Step 2: Write the hook installer**

Create `scripts/install-hooks.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
repo_root="$(git rev-parse --show-toplevel)"
cp "$repo_root/scripts/pre-commit" "$repo_root/.git/hooks/pre-commit"
chmod +x "$repo_root/.git/hooks/pre-commit"
echo "Installed pre-commit hook."
```

- [ ] **Step 3: Make both scripts executable**

```bash
chmod +x scripts/pre-commit scripts/install-hooks.sh
```

- [ ] **Step 4: Write the Makefile**

Create `Makefile`:

```makefile
COVERAGE_DIR := coverage

.PHONY: help setup format format-check analyze test test-coverage check \
	run-android run-web build-apk build-web build-ios clean

help:
	@echo "Available targets:"
	@echo "  setup          Install dependencies and git hooks"
	@echo "  format         Format Dart code"
	@echo "  format-check   Check formatting (CI)"
	@echo "  analyze        Run static analysis (flutter analyze + custom_lint)"
	@echo "  test           Run tests"
	@echo "  test-coverage  Run tests with a coverage report"
	@echo "  check          format-check + analyze + test (run before pushing)"
	@echo "  run-android    Run on an Android device/emulator"
	@echo "  run-web        Run in Chrome"
	@echo "  build-apk      Build a release APK"
	@echo "  build-web      Build a release web bundle"
	@echo "  build-ios      Unavailable locally: requires macOS + Xcode"
	@echo "  clean          Remove build artifacts and coverage data"

setup:
	flutter pub get
	./scripts/install-hooks.sh

format:
	dart format .

format-check:
	dart format --set-exit-if-changed .

analyze:
	flutter analyze
	dart run custom_lint

test:
	flutter test

test-coverage:
	flutter test --coverage
	@command -v genhtml >/dev/null 2>&1 && \
		genhtml $(COVERAGE_DIR)/lcov.info -o $(COVERAGE_DIR)/html || \
		echo "genhtml not found; coverage/lcov.info generated, skipping HTML report"

check: format-check analyze test

run-android:
	flutter run -d android

run-web:
	flutter run -d chrome

build-apk:
	flutter build apk --release

build-web:
	flutter build web --release

build-ios:
	@echo "build-ios is unavailable locally: requires macOS + Xcode. Added later via a macos-latest CI runner."

clean:
	flutter clean
	rm -rf $(COVERAGE_DIR)
```

- [ ] **Step 5: Verify `make` with no arguments runs `help`**

```bash
make
```

Expected: prints the target list (from the `help` recipe), does not run
`flutter`.

- [ ] **Step 6: Verify `make check` passes end to end**

```bash
make check
```

Expected: `format-check`, `analyze`, and `test` all succeed in sequence.

- [ ] **Step 7: Verify `make setup` installs the hook**

```bash
make setup
test -x .git/hooks/pre-commit && echo "hook installed"
```

Expected: `flutter pub get` runs (no-op if already resolved), then "hook
installed" prints.

- [ ] **Step 8: Verify coverage generation**

```bash
make test-coverage
ls coverage/lcov.info
```

Expected: `flutter test --coverage` succeeds and `coverage/lcov.info`
exists (an HTML report is a bonus if `genhtml` happens to be installed,
not a requirement here).

- [ ] **Step 9: Commit**

`.git/hooks/pre-commit` itself is a local Git internal, not tracked by
Git — only the scripts and Makefile are repo files.

```bash
git add Makefile scripts/pre-commit scripts/install-hooks.sh
git commit -m "$(cat <<'EOF'
Add Makefile and pre-commit hook scripts

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_018GjJJbKXZUqqKSvbC4apm4
EOF
)"
```

---

### Task 7: Add the CI workflow

**Files:**
- Create: `.github/workflows/ci.yml`.

**Interfaces:**
- Consumes: `make setup`, `make check`, `make build-web` from Task 6.
- Produces: nothing further downstream — this is the last task.

- [ ] **Step 1: Write the workflow**

Create `.github/workflows/ci.yml`:

```yaml
name: CI

on:
  push:
    branches: [main, master]
  pull_request:

jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
      - run: make setup
      - run: make check
      - run: make build-web
```

- [ ] **Step 2: Validate the YAML syntax locally**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))" \
  && echo "valid YAML"
```

Expected: prints `valid YAML` with no exception. This only checks syntax
— the workflow itself only goes green once pushed and run by GitHub
Actions.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "$(cat <<'EOF'
Add GitHub Actions CI (make setup, make check, make build-web)

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_018GjJJbKXZUqqKSvbC4apm4
EOF
)"
```

- [ ] **Step 4: Push and confirm the workflow runs green**

```bash
git push
```

Then check the Actions tab (or `gh run watch` if the `gh` CLI is
authenticated) for a green run on the pushed branch. This is the final
readiness criterion from the spec.
