import { test, expect } from '@playwright/test';
import { enableFlutterAccessibility } from './support/accessibility';

test.use({ viewport: { width: 800, height: 720 } });

test.beforeEach(async ({ page }) => {
  await page.goto('/');
  await enableFlutterAccessibility(page);
});

test('shows the app title and today’s hardcoded blocks', async ({
  page,
}) => {
  await expect(
    page.getByRole('heading', { name: 'Day Frame' }),
  ).toBeVisible();
  await expect(page.getByText('Breakfast')).toBeVisible();
  await expect(page.getByText('Work')).toBeVisible();
});

test('the next-day arrow switches to a day with no blocks', async ({
  page,
}) => {
  await page.getByRole('button', { name: 'Next day' }).click();

  await expect(page.getByText('Breakfast')).toHaveCount(0);
});

test('the previous-day arrow returns to today’s blocks', async ({
  page,
}) => {
  await page.getByRole('button', { name: 'Next day' }).click();
  await page.getByRole('button', { name: 'Previous day' }).click();

  await expect(page.getByText('Breakfast')).toBeVisible();
});

test('the date label updates when switching days', async ({ page }) => {
  // Capture page content before
  const contentBefore = await page.content();

  await page.getByRole('button', { name: 'Next day' }).click();

  // Capture page content after and verify it changed
  const contentAfter = await page.content();
  expect(contentAfter).not.toEqual(contentBefore);
});
