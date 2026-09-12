import { defineConfig, devices } from '@playwright/test';

const port = 8765;

export default defineConfig({
  testDir: './tests',
  fullyParallel: false,
  workers: 1,
  reporter: 'list',
  // A retried draft-open (see openDraftWithRetry) reloads the page and
  // reboots the Flutter web app a second time within the same test, which
  // can approach the default 30s budget on its own under CI load — give
  // tests enough headroom for that without masking a genuinely hung test.
  timeout: 60_000,
  use: {
    baseURL: `http://localhost:${port}`,
    trace: 'retain-on-failure',
  },
  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }],
  webServer: {
    // `flutter run -d web-server --release` starts accepting connections
    // before the release build it's compiling in the background has
    // finished writing `build/web/` — confirmed by a CI failure where the
    // very first request 404'd on `build/web/index.html`, and reloading
    // afterwards still didn't reliably boot Flutter (a stale/partial
    // response can outlive the write race that produced it). Building
    // first and only then serving the finished, static `build/web/`
    // removes that race entirely: by the time anything is listening on
    // the port, every asset is already complete.
    command:
      `flutter build web --release --pwa-strategy=offline-first`
      + ` && python3 -m http.server ${port} --directory build/web`,
    url: `http://localhost:${port}`,
    reuseExistingServer: false,
    timeout: 300_000,
    cwd: '..',
  },
});
