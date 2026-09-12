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
    command: `flutter run -d web-server --web-port=${port} --release`,
    url: `http://localhost:${port}`,
    reuseExistingServer: false,
    timeout: 180_000,
    cwd: '..',
  },
});
