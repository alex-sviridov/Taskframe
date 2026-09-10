import { test, expect } from '@playwright/test';
import { enableFlutterAccessibility } from './support/accessibility';
import { clickCenter } from './support/gestures';

test.use({ viewport: { width: 800, height: 720 } });

test.beforeEach(async ({ page }) => {
  await page.goto('/');
  await enableFlutterAccessibility(page);
});

test('clicking an existing block opens its edit modal', async ({ page }) => {
  await clickCenter(page, page.getByText('Breakfast'));

  await expect(page.getByRole('button', { name: 'Close' })).toBeVisible();
});

test('editing the title and pressing Enter renames the block', async ({
  page,
}) => {
  await clickCenter(page, page.getByText('Breakfast'));
  await expect(page.getByRole('button', { name: 'Close' })).toBeVisible();

  await page.getByRole('textbox').fill('Brunch');
  await page.getByRole('textbox').press('Enter');
  await page.getByRole('button', { name: 'Close' }).click();

  await expect(page.getByText('Brunch')).toBeVisible();
  await expect(page.getByText('Breakfast')).toHaveCount(0);
});

test('opening the start time picker and confirming Done closes it, '
  + 'leaving the modal open', async ({ page }) => {
  await clickCenter(page, page.getByText('Breakfast'));
  await expect(page.getByRole('button', { name: 'Close' })).toBeVisible();

  await clickCenter(page, page.getByText('Starts'));
  await expect(page.getByRole('button', { name: 'Done' })).toBeVisible();

  await page.getByRole('button', { name: 'Done' }).click();

  await expect(page.getByRole('button', { name: 'Done' })).toHaveCount(0);
  await expect(page.getByRole('button', { name: 'Close' })).toBeVisible();
});

test('copying a block to the next day shows it there', async ({ page }) => {
  await clickCenter(page, page.getByText('Breakfast'));
  await expect(page.getByRole('button', { name: 'Close' })).toBeVisible();

  await page.getByRole('button', { name: 'Copy to next day' }).click();
  await page.getByRole('button', { name: 'Close' }).click();

  const dateLabel = page.getByRole('group', {
    name: /^\w+day, \d{2}\/\d{2}\/\d{4}$/,
  });
  const dateBeforeNav = await dateLabel.getAttribute('aria-label');

  await page.getByRole('button', { name: 'Next day' }).click();

  // The page-turn animation transiently keeps both today's and tomorrow's
  // pages mounted, so "Breakfast" briefly matches twice; wait for the date
  // label to actually change (the page has settled) before asserting.
  await expect(async () => {
    const after = await dateLabel.getAttribute('aria-label');
    expect(after).not.toEqual(dateBeforeNav);
  }).toPass();

  await expect(page.getByText('Breakfast')).toBeVisible();
});

test('tapping delete twice removes the block and closes the modal', async ({
  page,
}) => {
  await clickCenter(page, page.getByText('Breakfast'));
  await expect(page.getByRole('button', { name: 'Close' })).toBeVisible();

  await page.getByRole('button', { name: 'Delete' }).click();
  await expect(
    page.getByRole('button', { name: 'Tap again to delete' }),
  ).toBeVisible();
  await page.getByRole('button', { name: 'Tap again to delete' }).click();

  await expect(page.getByRole('button', { name: 'Close' })).toHaveCount(0);
  await expect(page.getByText('Breakfast')).toHaveCount(0);
});

test.describe('narrow viewport', () => {
  test.use({ viewport: { width: 400, height: 800 } });

  test('tapping a block opens and closes its edit modal', async ({
    page,
  }) => {
    await clickCenter(page, page.getByText('Breakfast'));
    await expect(page.getByRole('button', { name: 'Close' })).toBeVisible();

    await page.getByRole('button', { name: 'Close' }).click();

    await expect(page.getByRole('button', { name: 'Close' })).toHaveCount(0);
  });
});

test.describe('wide viewport', () => {
  test.use({ viewport: { width: 1200, height: 800 } });

  test('tapping a block opens and closes its edit modal', async ({
    page,
  }) => {
    await clickCenter(page, page.getByText('Breakfast'));
    await expect(page.getByRole('button', { name: 'Close' })).toBeVisible();

    await page.getByRole('button', { name: 'Close' }).click();

    await expect(page.getByRole('button', { name: 'Close' })).toHaveCount(0);
  });
});
