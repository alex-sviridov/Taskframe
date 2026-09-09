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

  const weekHeader = page.getByRole('group', {
    name: /^\d{2}\/\d{2}\/\d{4}(\s\d{2}\/\d{2}\/\d{4}){6}$/,
  });
  await expect(weekHeader).toBeVisible();
});

test('the next-week arrow advances all seven dates by a week', async ({
  page,
}) => {
  const weekHeader = page.getByRole('group', {
    name: /^\d{2}\/\d{2}\/\d{4}(\s\d{2}\/\d{2}\/\d{4}){6}$/,
  });
  const before = await weekHeader.getAttribute('aria-label');

  await page.getByRole('button', { name: 'Next week' }).click();

  await expect(async () => {
    const after = await weekHeader.getAttribute('aria-label');
    expect(after).not.toEqual(before);
  }).toPass();
});
