import { defineConfig, devices } from '@playwright/test';

const port = 8765;

export default defineConfig({
  testDir: './tests',
  fullyParallel: false,
  workers: 1,
  reporter: 'list',
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
