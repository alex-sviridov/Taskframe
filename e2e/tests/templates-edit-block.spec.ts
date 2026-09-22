import { test, expect } from '@playwright/test';
import { enableFlutterAccessibility } from './support/accessibility';
import {
  clickUntilVisible,
  fillTextboxAndSubmit,
  gotoAndWaitForBoot,
  openDraftWithRetry,
} from './support/gestures';

test.use({ viewport: { width: 800, height: 720 } });

// The trailing add-template slot: a large centered "+" filling the sole
// column shown when no template exists yet (AppBar height 56 + column
// header height 56, then vertically centered in the remaining grid area;
// horizontally centered across the full body width). Raw coordinates are
// used (rather than `getByRole`) because this click must happen *before*
// accessibility is enabled — see the comment on `addTemplateAndOpenDraft`
// below for why.
const addTemplateSlot = { x: 507, y: 416 } as const;

// Free grid space, comfortably below the AppBar + column header and away
// from the grid's edges regardless of which template is showing (there's
// never any seed data on a template, so anywhere on the grid is free).
const freeSpace = { x: 300, y: 300 } as const;

/**
 * Adds a single template, then double-clicks free grid space to open its
 * block-creation draft, leaving both buttons ("Create Event"/"Create
 * Frame") ready to click and accessibility enabled.
 *
 * Both the add-template-slot click and the double-click must happen
 * *before* `enableFlutterAccessibility`: once Flutter's full semantics
 * tree is active, raw double-tap gestures on the canvas stop being
 * recognized (confirmed empirically — the draft simply never opens), so
 * there is no later point at which a *new* template's grid could be
 * double-clicked after accessibility is on. The add-template slot has to
 * be clicked by raw coordinates for the same reason: enabling
 * accessibility first, just to click that one button by role, would
 * already be too late for the double-click that follows.
 */
async function addTemplateAndOpenDraft(page: import('@playwright/test').Page) {
  await openDraftWithRetry(
    page,
    async () => {
      await page.mouse.click(addTemplateSlot.x, addTemplateSlot.y);
      await page.waitForTimeout(300);

      await page.mouse.click(freeSpace.x, freeSpace.y);
      await page.waitForTimeout(60);
      await page.mouse.click(freeSpace.x, freeSpace.y);
      await page.waitForTimeout(200);

      await enableFlutterAccessibility(page);
    },
    page.getByRole('button', { name: 'Create Event' }),
  );
}

test.beforeEach(async ({ page }) => {
  await gotoAndWaitForBoot(page, '/#/templates');
});

test('creating an event adds a block with an empty title and opens its '
  + 'edit modal', async ({ page }) => {
  await addTemplateAndOpenDraft(page);

  await page.getByRole('button', { name: 'Create Event' }).click();

  await expect(page.getByRole('button', { name: 'Close' })).toBeVisible();
  await expect(page.getByRole('textbox').first()).toHaveValue('');
  await page.getByRole('button', { name: 'Close' }).click();
  // No placeholder text leaks onto the grid for an empty-titled block.
  await expect(page.getByText('title')).toHaveCount(0);
});

test('a template block\'s edit modal has no date row and no "Copy to '
  + 'next day" button', async ({ page }) => {
  await addTemplateAndOpenDraft(page);
  await page.getByRole('button', { name: 'Create Event' }).click();
  await expect(page.getByRole('button', { name: 'Close' })).toBeVisible();

  // Every day-block field a template block still has.
  await expect(page.getByRole('textbox')).toBeVisible();
  await expect(page.getByText('Category')).toBeVisible();
  await expect(page.getByRole('button', { name: 'Event' })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Frame' })).toBeVisible();

  // The two day-only fields this task's whole guarantee is about.
  await expect(page.getByText(/^\d{2}\/\d{2}\/\d{4}$/)).toHaveCount(0);
  await expect(
    page.getByRole('button', { name: 'Copy to next day' }),
  ).toHaveCount(0);
});

test('editing the title renames the block', async ({ page }) => {
  await addTemplateAndOpenDraft(page);
  await page.getByRole('button', { name: 'Create Event' }).click();
  await expect(page.getByRole('button', { name: 'Close' })).toBeVisible();

  await fillTextboxAndSubmit(page.getByRole('textbox').first(), 'Standup');
  await page.getByRole('button', { name: 'Close' }).click();

  await expect(page.getByText('Standup')).toBeVisible();
  await expect(page.getByText('title')).toHaveCount(0);
});

test('tapping delete twice removes the block and closes the modal', async ({
  page,
}) => {
  await addTemplateAndOpenDraft(page);
  await page.getByRole('button', { name: 'Create Event' }).click();
  await expect(page.getByRole('button', { name: 'Close' })).toBeVisible();

  await page.getByRole('button', { name: 'Delete' }).click();
  await expect(
    page.getByRole('button', { name: 'Tap again to delete' }),
  ).toBeVisible();
  await page.getByRole('button', { name: 'Tap again to delete' }).click();

  await expect(page.getByRole('button', { name: 'Close' })).toHaveCount(0);
  await expect(page.getByText('title')).toHaveCount(0);
});

test('a Frame block can be created and reopened', async ({ page }) => {
  await addTemplateAndOpenDraft(page);

  await page.getByRole('button', { name: 'Create Frame' }).click();
  await expect(page.getByRole('button', { name: 'Close' })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Frame' })).toBeVisible();
  await page.getByRole('button', { name: 'Close' }).click();

  // The block has no title text to locate it by, but it's the only block
  // on this template's grid, sitting where the draft was opened.
  await clickUntilVisible(
    page,
    freeSpace,
    page.getByRole('button', { name: 'Close' }),
  );
});
