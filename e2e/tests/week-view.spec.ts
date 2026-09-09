import { test, expect } from '@playwright/test';
import { enableFlutterAccessibility } from './support/accessibility';

test.use({ viewport: { width: 1200, height: 800 } });

test.beforeEach(async ({ page }) => {
  await page.goto('/');
  await enableFlutterAccessibility(page);
});

test('shows a full week of day headers on a wide viewport', async ({
  page,
}) => {
  await expect(page.getByText('Breakfast')).toBeVisible();

  const dateLabels = page.getByText(/^\d{2}\/\d{2}\/\d{4}$/);
  await expect(dateLabels).toHaveCount(7);
});

test('the next-week arrow advances all seven dates by a week', async ({
  page,
}) => {
  const dateLabels = page.getByText(/^\d{2}\/\d{2}\/\d{4}$/);
  const before = await dateLabels.allTextContents();

  await page.getByRole('button', { name: 'Next week' }).click();

  await expect(async () => {
    const after = await dateLabels.allTextContents();
    expect(after).not.toEqual(before);
  }).toPass();
});
