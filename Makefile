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
