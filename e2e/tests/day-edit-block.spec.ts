import { test, expect } from '@playwright/test';
import { enableFlutterAccessibility } from './support/accessibility';
import { clickCenter, fillTextboxAndSubmit, gotoAndWaitForBoot } from './support/gestures';

test.use({ viewport: { width: 800, height: 720 } });

test.beforeEach(async ({ page }) => {
  await gotoAndWaitForBoot(page, '/#/day');
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

  await fillTextboxAndSubmit(page.getByRole('textbox'), 'Brunch');
  await page.getByRole('button', { name: 'Close' }).click();

  await expect(page.getByText('Brunch')).toBeVisible();
  await expect(page.getByText('Breakfast')).toHaveCount(0);
});

test('picking a time from the Starts dropdown updates it immediately, '
  + 'leaving the modal open', async ({ page }) => {
  await clickCenter(page, page.getByText('Breakfast'));
  await expect(page.getByRole('button', { name: 'Close' })).toBeVisible();

  // Breakfast seeds 07:00-07:30; clicking the field's current value opens
  // its dropdown menu of every valid 15-minute mark.
  await clickCenter(page, page.getByText('07:00'));
  await expect(page.getByRole('menuitem', { name: '07:15' })).toBeVisible();

  await page.getByRole('menuitem', { name: '07:15' }).click();

  await expect(page.getByRole('menuitem')).toHaveCount(0);
  await expect(page.getByRole('button', { name: 'Close' })).toBeVisible();
  await expect(page.getByRole('button', { name: '07:15' })).toBeVisible();
});

test('the type selector switches Event/Frame without closing the modal '
  + 'or losing the block', async ({ page }) => {
  await clickCenter(page, page.getByText('Breakfast'));
  await expect(page.getByRole('button', { name: 'Close' })).toBeVisible();

  await expect(page.getByRole('button', { name: 'Event' })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Frame' })).toBeVisible();

  await page.getByRole('button', { name: 'Frame' }).click();

  // Switching type doesn't close the modal. A frame's title is hidden
  // (not cleared), so it reappears once switched back to Event.
  await expect(page.getByRole('button', { name: 'Close' })).toBeVisible();
  await page.getByRole('button', { name: 'Event' }).click();
  await page.getByRole('button', { name: 'Close' }).click();
  await expect(page.getByText('Breakfast')).toBeVisible();
});

test('picking a new date via the calendar keeps the modal open and moves '
  + 'the block off the original day', async ({ page }) => {
  await clickCenter(page, page.getByText('Breakfast'));
  await expect(page.getByRole('button', { name: 'Close' })).toBeVisible();

  const dateRow = page.getByText(/^\d{2}\/\d{2}\/\d{4}$/);
  const dateBefore = await dateRow.textContent();
  await clickCenter(page, dateRow);

  // Pick a day guaranteed to differ from today's, so the click always
  // actually changes the date regardless of which day the suite runs on
  // (a fixed "15" would no-op on the 15th of the month, since the
  // calendar opens on the currently selected date). "1" and "2" are both
  // valid in every month, so exactly one of them always differs from
  // today's day-of-month. The Material date picker's accessible name for
  // a day cell is verbose (e.g. "15, Tuesday, September 15, 2026"), so
  // match on the leading day number only.
  const targetDay = new Date().getDate() === 1 ? 2 : 1;
  await page.getByRole('button', { name: new RegExp(`^${targetDay},`) }).click();
  await page.getByRole('button', { name: 'OK' }).click();

  // Only the calendar closes — the edit modal (and the block it's
  // editing) stays open, now showing the new date.
  await expect(page.getByRole('button', { name: 'Close' })).toBeVisible();
  await expect(async () => {
    expect(await dateRow.textContent()).not.toEqual(dateBefore);
  }).toPass();

  await page.getByRole('button', { name: 'Close' }).click();
  await expect(page.getByText('Breakfast')).toHaveCount(0);
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
