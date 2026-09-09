import { test, expect } from '@playwright/test';
import { enableFlutterAccessibility } from './support/accessibility';

test.use({ viewport: { width: 1200, height: 800 } });

test.beforeEach(async ({ page }) => {
  await page.goto('/');
  await enableFlutterAccessibility(page);
});

const dateHeading = /^\d{2}\/\d{2}\/\d{4}$/;

test('shows a full week of day headers on a wide viewport', async ({
  page,
}) => {
  await expect(page.getByText('Breakfast')).toBeVisible();

  await expect(page.getByRole('heading', { name: dateHeading })).toHaveCount(
    7,
  );
});

test('the next-week arrow advances all seven dates by a week', async ({
  page,
}) => {
  const headers = page.getByRole('heading', { name: dateHeading });
  const before = await headers.allTextContents();

  await page.getByRole('button', { name: 'Next week' }).click();

  await expect(async () => {
    const after = await headers.allTextContents();
    expect(after).not.toEqual(before);
  }).toPass();
});
