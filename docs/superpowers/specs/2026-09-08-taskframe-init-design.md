# Инициализация проекта «Рамка дня» (smoke-тест стека)

Дата: 2026-09-08

## Цель

Убедиться, что выбранный стек (Flutter + Riverpod + go_router) собирается,
линтуется, тестируется и запускается. Никакой доменной логики, моделей и
данных — это исключительно проверка инфраструктуры перед началом реальной
разработки.

## Стек

- Flutter 3.x
- Таргеты: Android, iOS, Web — платформенные папки создаются через
  `flutter create`. Локально в этой задаче реально проверяется только
  **Web**: окружение разработки headless (нет GUI, KVM, Android SDK,
  Chrome), поэтому ни Android-эмулятор, ни iOS-симулятор здесь не
  запустить. Android и iOS сборка/запуск проверяются позже, на
  устройстве/CI с соответствующим тулчейном (Android — вручную на
  компьютере разработчика или в CI с Android SDK; iOS — на macOS-раннере,
  Codemagic / GitHub Actions).
- `flutter_riverpod` — state management
- `go_router` — роутинг

## Проект

- Имя пакета: `taskframe` (совпадает с именем репозитория).
- Создаётся командой `flutter create --platforms=android,ios,web .`
  в корне репозитория (репозиторий сейчас пуст, есть только `.git`).
- Дефолтные файлы, сгенерированные `flutter create` (счётчик-пример,
  `test/widget_test.dart` и т.п.), удаляются и заменяются структурой ниже.

## Структура кода

```
lib/
  core/
    theme.dart              — светлая и тёмная тема, Material 3
  router.dart                — go_router, единственный маршрут '/'
  app.dart                   — MaterialApp.router
  main.dart                  — runApp(ProviderScope(...))
  features/
    day/
      day_screen.dart        — экран-заглушка
test/
  unit/
    placeholder_test.dart    — тривиальный тест раннера
  widget/
    day_screen_test.dart     — тест рендера DayScreen
Makefile
analysis_options.yaml
scripts/
  install-hooks.sh
  pre-commit
.github/
  workflows/
    ci.yml
```

### core/theme.dart

Экспортирует `ThemeData lightTheme` и `ThemeData darkTheme`, оба на базе
`ColorScheme.fromSeed` (Material 3, `useMaterial3: true`). Конкретный seed
color — свободный выбор на этапе реализации, важно лишь, что светлая и
тёмная темы визуально различимы.

### router.dart

`GoRouter` с единственным маршрутом:

```dart
GoRoute(path: '/', builder: (context, state) => const DayScreen())
```

### app.dart

`MaterialApp.router` с `routerConfig`, `theme: lightTheme`,
`darkTheme: darkTheme`, `themeMode: ThemeMode.system` — так проверяется,
что переключение системной темы меняет оформление.

### main.dart

```dart
void main() {
  runApp(const ProviderScope(child: App()));
}
```

### features/day/day_screen.dart

- `ConsumerWidget`.
- `AppBar(title: const Text('Рамка дня'))`.
- По центру экрана — текст-заглушка (например, «Здесь будет рамка дня»).
- Под заглушкой — значение тестового провайдера:

```dart
final appVersionProvider = Provider<String>((ref) => '0.1.0-smoke');
```

Значение — хардкод-строка. Провайдер существует только чтобы подтвердить,
что `ProviderScope` подключён и чтение провайдера в виджете работает;
реальной версией пакета (`pubspec.yaml`) он не связан.

## Тесты

- `test/unit/placeholder_test.dart` — тривиальная проверка
  (`expect(1 + 1, equals(2))` или аналог), подтверждающая что тестовый
  раннер и зависимости для unit-тестов настроены. Позже сюда лягут
  unit-тесты `TimelineEngine` (без Flutter-зависимостей).
- `test/widget/day_screen_test.dart` — оборачивает `DayScreen` в
  `ProviderScope` и `MaterialApp`, проверяет через `find.text`, что:
  - `AppBar` содержит заголовок «Рамка дня»;
  - текст-заглушка отрисован;
  - значение `appVersionProvider` отображается на экране.
- Coverage: `flutter test --coverage` генерирует `coverage/lcov.info`.
  `make test-coverage` дополнительно запускает `genhtml`, если он
  установлен в системе; если нет — оставляет `.info`-файл и печатает
  предупреждение, не проваливая цель.

## Линтеры

`analysis_options.yaml`:

```yaml
include: package:very_good_analysis/analysis_options.yaml

analyzer:
  plugins:
    - custom_lint
  exclude:
    - '**/*.g.dart'
    - '**/*.freezed.dart'
```

- Базовый набор — `very_good_analysis` (строже `flutter_lints`, осознанный
  выбор для проекта, который сразу начинается с высокой планки качества).
- `custom_lint` + `riverpod_lint` в `dev_dependencies`, подключаются через
  `analyzer.plugins`. Конкретные версии зависимостей фиксируются по месту
  на этапе `flutter pub get` — важна их взаимная совместимость
  (`custom_lint` ⟷ `riverpod_lint` ⟷ `flutter_riverpod`).
- Дополнительные точечные повышения правил до `error` рассматриваются по
  факту первого прогона `flutter analyze`, если `very_good_analysis`
  оставит что-то существенное на уровне warning.
- `dart format --set-exit-if-changed .` — часть проверки (`make
  format-check`), не отдельная ручная привычка.

### Pre-commit хук

- `scripts/pre-commit` — шелл-скрипт, вызывающий `make format-check
  analyze`.
- `scripts/install-hooks.sh` — копирует/симлинкает его в
  `.git/hooks/pre-commit` и делает исполняемым.
- `make setup` вызывает `flutter pub get` и затем
  `scripts/install-hooks.sh`.

## Makefile

Цели (без логики внутри — только вызовы `flutter`/`dart`/скриптов,
сложное выносится в `scripts/`):

| Цель | Действие |
|---|---|
| `help` (default) | Список целей |
| `setup` | `flutter pub get` + установка git-хуков |
| `format` | `dart format .` |
| `format-check` | `dart format --set-exit-if-changed .` |
| `analyze` | `flutter analyze` + `dart run custom_lint` |
| `test` | `flutter test` |
| `test-coverage` | `flutter test --coverage` + `genhtml` (если доступен) |
| `check` | `format-check` + `analyze` + `test` — единственное, что нужно помнить перед пушем |
| `run-android` | `flutter run -d android` |
| `run-web` | `flutter run -d chrome` |
| `build-apk` | `flutter build apk --release` |
| `build-web` | `flutter build web --release` |
| `build-ios` | echo-заглушка: «недоступно локально, требует macOS» |
| `clean` | `flutter clean` + удаление `coverage/` |

Все цели помечены `.PHONY`. `run-android` и `build-apk` присутствуют в
Makefile (нужны позже, когда появится Android-тулчейн), но в этой задаче
не выполняются и не входят в критерий готовности — в текущем окружении
нет Android SDK/эмулятора.

## CI

`.github/workflows/ci.yml`, `ubuntu-latest`:

1. checkout
2. `subosito/flutter-action` (канал stable)
3. `make setup`
4. `make check`
5. `make build-web`

Job для iOS (macOS-раннер) добавляется отдельно, вне рамок этой задачи.

## Критерий готовности

- `flutter run -d chrome` (или `flutter build web` + локальный сервер)
  работает и рендерит `DayScreen`.
- Переключение системной темы меняет оформление приложения (проверяется
  в браузере через настройки ОС/DevTools emulate).
- `make check` проходит целиком без ошибок.
- CI зелёный (`make check` + `make build-web` на `ubuntu-latest`).
- Android: папка `android/` создана командой `flutter create`, `flutter
  build apk` не запускается и не проверяется в этой задаче — нет
  Android SDK/эмулятора в текущем окружении. Проверяется позже вручную
  на компьютере разработчика.
- iOS: папка `ios/` создана командой `flutter create`; сборка и запуск
  не проверяются — вне рамок этой задачи.

## Вне рамок

- Любая доменная логика, модели данных, реальные экраны кроме
  `DayScreen`.
- `flutter run`/`flutter build apk` на Android — нет Android SDK/эмулятора
  в текущем окружении; проверка переносится на устройство разработчика.
- `flutter build ios` / запуск iOS-симулятора.
- Реальная версия приложения из `pubspec.yaml` (можно подключить
  `package_info_plus` позже, когда появится практическая необходимость).
- macOS CI job.
