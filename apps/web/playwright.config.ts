import { defineConfig, devices } from '@playwright/test'

/**
 * E2E smoke tests. Requires a running app and a test account:
 *   E2E_BASE_URL (default http://localhost:3000)
 *   E2E_EMAIL / E2E_PASSWORD — credentials of a seeded test user
 *
 * Run: pnpm exec playwright test
 */
export default defineConfig({
  testDir: './e2e',
  timeout: 60_000,
  retries: process.env.CI ? 2 : 0,
  workers: 1,
  reporter: process.env.CI ? 'github' : 'list',
  use: {
    baseURL: process.env.E2E_BASE_URL ?? 'http://localhost:3000',
    trace: 'retain-on-failure',
    ignoreHTTPSErrors: true,
  },
  projects: [
    {
      name: 'mobile',
      // Chromium with iPhone emulation (WebKit binaries are not required)
      use: { ...devices['iPhone 14 Pro'], browserName: 'chromium', colorScheme: 'dark' },
    },
    {
      name: 'desktop',
      use: { ...devices['Desktop Chrome'], colorScheme: 'dark' },
    },
  ],
})
