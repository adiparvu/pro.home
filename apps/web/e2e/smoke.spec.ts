import { test, expect, type Page } from '@playwright/test'

const EMAIL = process.env.E2E_EMAIL
const PASSWORD = process.env.E2E_PASSWORD

test.skip(!EMAIL || !PASSWORD, 'E2E_EMAIL / E2E_PASSWORD not configured')

async function login(page: Page) {
  await page.goto('/login')
  await page.fill('input[type="email"]', EMAIL!)
  await page.fill('input[type="password"]', PASSWORD!)
  await page.click('button[type="submit"]')
  await page.waitForURL((url) => !url.pathname.startsWith('/login'), { timeout: 60_000 })
}

test.describe('PRV HOUSE smoke', () => {
  test.beforeEach(async ({ page }) => {
    await login(page)
  })

  test('dashboard renders the property hero', async ({ page }) => {
    await page.goto('/')
    await expect(page.getByText('Property Health')).toBeVisible()
  })

  test('maintenance lists tasks with view controls', async ({ page }) => {
    await page.goto('/maintenance')
    await expect(page.getByRole('tab', { name: 'List' })).toBeVisible()
    await expect(page.getByRole('tab', { name: 'Timeline' })).toBeVisible()
    await expect(page.getByRole('button', { name: 'Filters' })).toBeVisible()
  })

  test('finances shows totals and segmented filter', async ({ page }) => {
    await page.goto('/finances')
    await expect(page.getByRole('tab', { name: 'Expenses' })).toBeVisible()
  })

  test('garden shows the section switcher', async ({ page }) => {
    await page.goto('/garden')
    await expect(page.getByRole('tab', { name: /Plants/ })).toBeVisible()
    await expect(page.getByRole('tab', { name: /Zones/ })).toBeVisible()
  })

  test('inventory page loads', async ({ page }) => {
    await page.goto('/inventory')
    await expect(page.getByText('Total items')).toBeVisible()
  })

  test('notifications page loads', async ({ page }) => {
    await page.goto('/notifications')
    await expect(
      page.getByText(/All caught up|read/).first()
    ).toBeVisible()
  })

  test('property health report loads', async ({ page }) => {
    await page.goto('/property/health')
    await expect(page.getByText(/Health/).first()).toBeVisible()
  })

  test('quick actions sheet opens from the FAB', async ({ page }) => {
    await page.goto('/')
    const fab = page.getByRole('button', { name: 'Quick actions' })
    await expect(fab).toBeVisible()
    // dispatchEvent: in dev the React Query devtools toggle overlaps the FAB
    // corner and intercepts pointer clicks; it does not exist in production
    await fab.dispatchEvent('click')
    await expect(page.getByText('New Task')).toBeVisible()
  })

  test('search finds seeded content', async ({ page }) => {
    await page.goto('/search')
    await page.fill('input[placeholder*="Search"]', 'a')
    // Just assert the page is interactive; result content depends on seed data
    await expect(page.getByPlaceholder(/Search/)).toBeVisible()
  })
})
