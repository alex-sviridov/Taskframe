import { test, expect, type Page } from '@playwright/test';
import { enableFlutterAccessibility } from './support/accessibility';
import { clickCenter, fillTextboxUntilSet, gotoAndWaitForBoot } from './support/gestures';

/**
 * Creates a category named [name] via the Categories screen's add action,
 * leaving color/emoji at their defaults (the color picker and emoji picker
 * aren't reliably automatable), then navigates to the Day screen.
 *
 * Navigates by URL hash rather than the sidebar's "Categories"/"Day"
 * destinations: `NavigationDrawer` used as a standing sidebar (as
 * `AppShell` does here, outside a `Scaffold.drawer`) isn't exposed in
 * Flutter web's semantics tree, so its destinations aren't queryable the
 * way every other control in this suite is.
 */
async function addCategoryAndGoToDay(page: Page, name: string): Promise<void> {
  await gotoAndWaitForBoot(page, '/#/categories');
  await enableFlutterAccessibility(page);

  await page.getByRole('button', { name: 'Add category' }).click();
  await fillTextboxUntilSet(page.getByRole('textbox'), name);
  await page.getByRole('button', { name: 'Save' }).click();
  // The sheet's closing animation can transiently leave both its own
  // "Work" text field and the newly added list row matching `getByText`
  // at once; wait for the sheet itself to fully close first.
  await expect(page.getByRole('button', { name: 'Save' })).toHaveCount(0);

  // A hash-only navigation doesn't reload the page, so accessibility
  // (enabled once above) is still active here — enabling it again would
  // hang waiting for a placeholder that's already been consumed.
  await page.goto('/#/');
}

test.describe('wide viewport', () => {
  test.use({ viewport: { width: 800, height: 720 } });

  test('picking a category from the dropdown persists it, surviving '
    + 'closing and reopening the modal', async ({ page }) => {
    await addCategoryAndGoToDay(page, 'Work');

    await clickCenter(page, page.getByText('Breakfast'));
    await expect(page.getByRole('button', { name: 'Close' })).toBeVisible();

    // A labeled field, not a bare colored control, is what makes the
    // dropdown read as a dropdown.
    await expect(page.getByText('Category')).toBeVisible();
    // The default category is Breakfast's starting category, and is the
    // dropdown's closed-state label until a different one is picked.
    await expect(page.getByRole('button', { name: 'Default' })).toBeVisible();

    await page.getByRole('button', { name: 'Default' }).click();
    await page.getByRole('menuitem', { name: 'Work' }).click();

    await expect(page.getByRole('button', { name: 'Work' })).toBeVisible();

    await page.getByRole('button', { name: 'Close' }).click();
    await clickCenter(page, page.getByText('Breakfast'));
    await expect(page.getByRole('button', { name: 'Close' })).toBeVisible();

    await expect(page.getByRole('button', { name: 'Work' })).toBeVisible();
  });
});

test.describe('narrow viewport', () => {
  test.use({ viewport: { width: 400, height: 800 } });

  test('tapping the category chip opens a wheel picker instead of a '
    + 'dropdown', async ({ page }) => {
    await addCategoryAndGoToDay(page, 'Work');

    await clickCenter(page, page.getByText('Breakfast'));
    await expect(page.getByRole('button', { name: 'Close' })).toBeVisible();

    // Same field chrome as the wide dropdown, just triggering a wheel
    // instead of a menu.
    await expect(page.getByText('Category')).toBeVisible();
    await expect(page.getByRole('menuitem')).toHaveCount(0);

    await clickCenter(page, page.getByText('Default'));

    await expect(page.getByRole('slider')).toBeVisible();
  });
});
