COVERAGE_DIR := coverage

.PHONY: help setup format format-check analyze test test-coverage integration-test \
	e2e check run run-android run-web build-apk build-web build-ios clean

help:
	@echo "Available targets:"
	@echo "  setup          Install dependencies and git hooks"
	@echo "  format         Format Dart code"
	@echo "  format-check   Check formatting (CI)"
	@echo "  analyze        Run static analysis (flutter analyze + custom_lint)"
	@echo "  test           Run tests"
	@echo "  test-coverage  Run tests with a coverage report"
	@echo "  integration-test  Run integration tests against a local PocketBase"
	@echo "  e2e            Run Playwright end-to-end tests against flutter web"
	@echo "  check          format-check + analyze + test + e2e (run before pushing)"
	@echo "  run            Build the release web bundle and serve it on :8080"
	@echo "  run-android    Run on an Android device/emulator"
	@echo "  run-web        Run in Chrome"
	@echo "  build-apk      Build a release APK"
	@echo "  build-web      Build a release web bundle"
	@echo "  build-ios      Unavailable locally: requires macOS + Xcode"
	@echo "  clean          Remove build artifacts and coverage data"

setup:
	flutter pub get
	./scripts/install-hooks.sh
	cd e2e && npm ci && npx playwright install --with-deps chromium

format:
	dart format .

format-check:
	dart format --set-exit-if-changed .

analyze:
	flutter analyze
	dart run custom_lint

test:
	flutter test test/unit test/widget

test-coverage:
	flutter test --coverage test/unit test/widget
	@if command -v genhtml >/dev/null 2>&1; then \
		genhtml $(COVERAGE_DIR)/lcov.info -o $(COVERAGE_DIR)/html; \
	else \
		echo "genhtml not found; coverage/lcov.info generated, skipping HTML report"; \
	fi

integration-test:
	@echo "Requires: docker compose up -d pocketbase, then"
	@echo "  dart run scripts/setup_pocketbase.dart http://localhost:8090 dev@taskframe.local dev-password-change-me"
	flutter test test/integration

e2e:
	cd e2e && npx playwright test

check: format-check analyze test e2e

# Builds first and only then serves the finished, static build/web/ —
# `flutter run -d web-server` starts accepting connections before its
# background release build finishes writing build/web/, which can serve a
# stale or partial bundle (see e2e/playwright.config.ts's webServer).
run:
	@fuser -k 8080/tcp 2>/dev/null || true
	flutter build web --release --pwa-strategy=offline-first
	python3 -m http.server 8080 --directory build/web

run-android:
	flutter run -d android

run-web:
	flutter run -d chrome

build-apk:
	flutter build apk --release

build-web:
	flutter build web --release --pwa-strategy=offline-first

build-ios:
	@echo "build-ios is unavailable locally: requires macOS + Xcode. Added later via a macos-latest CI runner."

clean:
	flutter clean
	rm -rf $(COVERAGE_DIR)
