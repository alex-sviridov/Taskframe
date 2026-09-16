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
	@echo "  run            Build and run the web app + PocketBase via Docker Compose"
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

# Brings up the web app and its PocketBase backend together, exactly as
# they run in production: nginx serving the release web bundle on :8080
# and proxying /api/ to the pocketbase service (see nginx.conf and
# docker-compose.yml). --build picks up local changes on every run.
run:
	docker compose up --build

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
