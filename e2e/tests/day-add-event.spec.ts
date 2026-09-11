import { test, expect } from '@playwright/test';
import { enableFlutterAccessibility } from './support/accessibility';
import { doubleClickFreeSpace } from './support/gestures';

test.use({ viewport: { width: 800, height: 720 } });

// (300, 650) lands in the evening, after the hardcoded Cleaning block
// (19:00-20:00) and before the 23:00 day end, so it's always free space
// regardless of which day the suite runs on.
const freeSpace = { x: 300, y: 650 } as const;

test.beforeEach(async ({ page }) => {
  await page.goto('/');
  // Wait for Flutter to finish booting before sending raw pointer events;
  // it injects this placeholder once the app is ready to receive input.
  await page.locator('flt-semantics-placeholder').waitFor({ state: 'attached' });
});

test('double-clicking free space shows both create buttons', async ({
  page,
}) => {
  await doubleClickFreeSpace(page, freeSpace.x, freeSpace.y);
  await enableFlutterAccessibility(page);

  await expect(
    page.getByRole('button', { name: 'Create Event' }),
  ).toBeVisible();
  await expect(
    page.getByRole('button', { name: 'Create Frame' }),
  ).toBeVisible();
});

test('clicking Create Event adds a block titled "title" and opens its edit modal', async ({
  page,
}) => {
  await doubleClickFreeSpace(page, freeSpace.x, freeSpace.y);
  await enableFlutterAccessibility(page);

  await page.getByRole('button', { name: 'Create Event' }).click();

  // The edit modal opens immediately after creation, without a separate
  // tap — and while it's open, Flutter excludes the background grid from
  // the accessibility tree, so the block's own title isn't queryable
  // until the modal closes.
  await expect(page.getByRole('button', { name: 'Close' })).toBeVisible();

  await page.getByRole('button', { name: 'Close' }).click();
  await expect(page.getByText('title')).toBeVisible();
});

test('clicking the AppBar add button creates a block in the next free '
  + 'slot and opens its edit modal', async ({ page }) => {
  await enableFlutterAccessibility(page);

  await page.getByRole('button', { name: 'Add block' }).click();

  await expect(page.getByRole('button', { name: 'Close' })).toBeVisible();
});

// The title field's autofocus-when-empty behavior is covered at the
// widget-test level (test/widget/block_edit_modal_test.dart) instead of
// here: Flutter web only wires up its real DOM text-input focus in
// response to a trusted pointer event landing directly on the field, so
// an autofocus triggered from a *different* button's click handler never
// produces a browser-visible `document.activeElement` change for
// Playwright to assert on, even though Flutter's own focus tree is
// correctly focused.

test('clicking outside the draft dismisses it without creating a block', async ({
  page,
}) => {
  await doubleClickFreeSpace(page, freeSpace.x, freeSpace.y);
  await enableFlutterAccessibility(page);
  await expect(
    page.getByRole('button', { name: 'Create Event' }),
  ).toBeVisible();

  // A point well clear of the draft box, but still free grid space.
  await page.mouse.click(300, 450);

  await expect(
    page.getByRole('button', { name: 'Create Event' }),
  ).toHaveCount(0);
  await expect(page.getByText('title')).toHaveCount(0);
});
