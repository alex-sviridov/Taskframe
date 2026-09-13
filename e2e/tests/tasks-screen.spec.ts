import { test, expect, type Page } from '@playwright/test';
import { enableFlutterAccessibility } from './support/accessibility';
import { fillTextboxUntilSet, gotoAndWaitForBoot } from './support/gestures';

/**
 * Creates a category named [name] via the Categories screen's add action,
 * leaving color/emoji at their defaults (as in `day-block-category.spec.ts`
 * — the color picker and emoji picker aren't reliably automatable), then
 * navigates to the Tasks screen.
 *
 * Navigates by URL hash rather than the sidebar's "Categories"/"Tasks"
 * destinations: `NavigationDrawer` used as a standing sidebar (as
 * `AppShell` does here, outside a `Scaffold.drawer`) isn't exposed in
 * Flutter web's semantics tree, so its destinations aren't queryable the
 * way every other control in this suite is.
 */
async function addCategoryAndGoToTasks(page: Page, name: string): Promise<void> {
  await gotoAndWaitForBoot(page, '/#/categories');
  await enableFlutterAccessibility(page);

  await page.getByRole('button', { name: 'Add category' }).click();
  await fillTextboxUntilSet(page.getByRole('textbox'), name);
  await page.getByRole('button', { name: 'Save' }).click();
  // The sheet's closing animation can transiently leave both its own
  // text field and the newly added list row matching a text query at
  // once; wait for the sheet itself to fully close first.
  await expect(page.getByRole('button', { name: 'Save' })).toHaveCount(0);

  // A hash-only navigation doesn't reload the page, so accessibility
  // (enabled once above) is still active here — enabling it again would
  // hang waiting for a placeholder that's already been consumed.
  await page.goto('/#/tasks');
}

/**
 * Dismisses the task edit modal by clicking its barrier/scrim, well
 * outside the modal's own bounds — the modal has no Save/Cancel button of
 * its own to tap instead, since every field applies live.
 */
async function dismissTaskModal(page: Page): Promise<void> {
  await page.mouse.click(770, 20);
}

test.describe('wide viewport', () => {
  test.use({ viewport: { width: 800, height: 720 } });

  test.beforeEach(async ({ page }) => {
    await gotoAndWaitForBoot(page, '/#/tasks');
    await enableFlutterAccessibility(page);
  });

  test('starts empty with an add button', async ({ page }) => {
    await expect(page.getByRole('heading', { name: 'Tasks' })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Add task' })).toBeVisible();
    await expect(page.getByRole('checkbox')).toHaveCount(0);
  });

  test('typing a title creates the task live, with no Save step', async ({
    page,
  }) => {
    await page.getByRole('button', { name: 'Add task' }).click();

    await fillTextboxUntilSet(page.getByRole('textbox'), 'Buy milk');
    await dismissTaskModal(page);

    // The card row is a `ListTile` with `onTap`, so Flutter's semantics
    // expose the whole row as a button (its accessible name is the title
    // text) rather than a plain text node — hence `getByRole`, not
    // `getByText`, throughout this file for card rows.
    await expect(page.getByRole('button', { name: 'Buy milk' })).toBeVisible();
    await expect(page.getByRole('checkbox')).toHaveCount(1);
  });

  test('toggling a card checkbox closes the task, and it stays closed on '
    + 'reopening', async ({ page }) => {
    await page.getByRole('button', { name: 'Add task' }).click();
    await fillTextboxUntilSet(page.getByRole('textbox'), 'Buy milk');
    await dismissTaskModal(page);

    await page.getByRole('checkbox').click();

    // Closing is a card-level action; it must not have opened the modal.
    await expect(page.getByRole('textbox')).toHaveCount(0);

    await page.getByRole('button', { name: 'Buy milk' }).click();
    await expect(page.getByRole('checkbox').first()).toBeChecked();
  });

  test('editing the title in the modal updates the card live', async ({
    page,
  }) => {
    await page.getByRole('button', { name: 'Add task' }).click();
    await fillTextboxUntilSet(page.getByRole('textbox'), 'Buy milk');
    await dismissTaskModal(page);

    await page.getByRole('button', { name: 'Buy milk' }).click();
    await fillTextboxUntilSet(page.getByRole('textbox'), 'Buy oat milk');
    await dismissTaskModal(page);

    await expect(
      page.getByRole('button', { name: 'Buy oat milk' }),
    ).toBeVisible();
    await expect(
      page.getByRole('button', { name: 'Buy milk', exact: true }),
    ).toHaveCount(0);
  });

  test('picking a category from the dropdown persists it, surviving '
    + 'closing and reopening the modal', async ({ page }) => {
    await addCategoryAndGoToTasks(page, 'Work');

    await page.getByRole('button', { name: 'Add task' }).click();
    await fillTextboxUntilSet(page.getByRole('textbox'), 'Ship it');

    // The default category is the dropdown's closed-state label until a
    // different one is picked — same signal `day-block-category.spec.ts`
    // uses for the day screen's block category picker (the two share the
    // same `BlockCategoryPicker` widget).
    await expect(page.getByRole('button', { name: 'Default' })).toBeVisible();
    await page.getByRole('button', { name: 'Default' }).click();
    await page.getByRole('menuitem', { name: 'Work' }).click();
    await expect(page.getByRole('button', { name: 'Work' })).toBeVisible();

    await dismissTaskModal(page);
    await page.getByRole('button', { name: 'Ship it' }).click();

    await expect(page.getByRole('button', { name: 'Work' })).toBeVisible();
  });

  test('typing "#tag " strips it from the title and shows a tag pill', async ({
    page,
  }) => {
    await page.getByRole('button', { name: 'Add task' }).click();
    // The extraction rewrites the field's own value as soon as the
    // trailing "#groceries " is typed, so the textbox never settles on
    // that raw value — `fill` it directly and assert on the result.
    await page.getByRole('textbox').fill('Buy #groceries ');

    // A pill renders as a Flutter `Chip`, exposed in the semantics tree
    // as a checkbox labeled with the tag text.
    await expect(page.getByRole('checkbox', { name: 'groceries' })).toBeVisible();
    await expect(page.getByRole('textbox')).toHaveValue('Buy ');

    await dismissTaskModal(page);

    await expect(page.getByRole('button', { name: 'Buy' })).toBeVisible();
    await expect(page.getByRole('checkbox', { name: 'groceries' })).toBeVisible();
  });

  test('a trailing "#tag" with no space is still added when the modal is '
    + 'dismissed', async ({ page }) => {
    await page.getByRole('button', { name: 'Add task' }).click();
    await page.getByRole('textbox').fill('Buy #groceries');

    await dismissTaskModal(page);

    await expect(page.getByRole('button', { name: 'Buy' })).toBeVisible();
    await expect(page.getByRole('checkbox', { name: 'groceries' })).toBeVisible();
  });

  test('removing a tag pill in the edit modal persists the removal', async ({
    page,
  }) => {
    await page.getByRole('button', { name: 'Add task' }).click();
    await page.getByRole('textbox').fill('Buy #groceries ');
    const pill = page.getByRole('checkbox', { name: 'groceries' });
    await expect(pill).toBeVisible();

    // `InputChip`'s delete affordance briefly reports as disabled in the
    // semantics tree while its entrance animation settles (harmless —
    // the tap handler itself works, as covered by the Flutter widget
    // tests), so Playwright's actionability check never clears; force
    // the click rather than waiting on it.
    await pill.getByRole('button', { name: 'Delete' }).click({ force: true });
    await expect(pill).toHaveCount(0);

    await dismissTaskModal(page);
    await expect(page.getByRole('checkbox', { name: 'groceries' })).toHaveCount(0);
  });

  test('Delete asks for confirmation, then removes the task', async ({
    page,
  }) => {
    await page.getByRole('button', { name: 'Add task' }).click();
    await fillTextboxUntilSet(page.getByRole('textbox'), 'Buy milk');

    await page.getByRole('button', { name: 'Delete' }).click();
    await expect(page.getByText('Delete this task?')).toBeVisible();

    await page.getByRole('button', { name: 'Delete' }).last().click();

    await expect(page.getByRole('button', { name: 'Buy milk' })).toHaveCount(0);
    await expect(page.getByRole('checkbox')).toHaveCount(0);
  });
});

test.describe('narrow viewport', () => {
  test.use({ viewport: { width: 400, height: 800 } });

  test('the add button creates a task live through the bottom-sheet '
    + 'modal', async ({ page }) => {
    await gotoAndWaitForBoot(page, '/#/tasks');
    await enableFlutterAccessibility(page);

    await page.getByRole('button', { name: 'Add task' }).click();
    await fillTextboxUntilSet(page.getByRole('textbox'), 'Buy milk');
    await page.mouse.click(200, 10);

    await expect(page.getByRole('button', { name: 'Buy milk' })).toBeVisible();
    await expect(page.getByRole('checkbox')).toHaveCount(1);
  });
});
