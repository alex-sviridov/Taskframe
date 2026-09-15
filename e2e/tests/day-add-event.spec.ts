import { test, expect, type Page } from '@playwright/test';
import { enableFlutterAccessibility } from './support/accessibility';
import {
  dragMouse,
  gotoAndWaitForBoot,
  openDraftWithRetry,
  waitForBoundingBox,
} from './support/gestures';

test.use({ viewport: { width: 800, height: 720 } });

// (300, 650) lands in the evening, after the hardcoded Cleaning block
// (19:00-20:00) and before the 23:00 day end, so it's always free space
// regardless of which day the suite runs on.
const freeSpace = { x: 300, y: 650 } as const;

test.beforeEach(async ({ page }) => {
  // Waits for Flutter to finish booting before sending raw pointer events;
  // it injects a placeholder once the app is ready to receive input.
  await gotoAndWaitForBoot(page, '/');
});

/**
 * Clicks free space to open a block draft, retrying (via a page reload)
 * if Flutter's gesture recognizer misses the click — see
 * {@link openDraftWithRetry}.
 */
async function openFreeSpaceDraft(page: Page) {
  await openDraftWithRetry(
    page,
    async () => {
      await page.mouse.click(freeSpace.x, freeSpace.y);
      await enableFlutterAccessibility(page);
    },
    page.getByRole('button', { name: 'Create Event' }),
  );
}

test('clicking free space shows both create buttons', async ({
  page,
}) => {
  await openFreeSpaceDraft(page);

  await expect(
    page.getByRole('button', { name: 'Create Event' }),
  ).toBeVisible();
  await expect(
    page.getByRole('button', { name: 'Create Frame' }),
  ).toBeVisible();
});

test('clicking Create Event adds a block with an empty title and opens '
  + 'its edit modal', async ({ page }) => {
  await openFreeSpaceDraft(page);

  await page.getByRole('button', { name: 'Create Event' }).click();

  // The edit modal opens immediately after creation, without a separate
  // tap.
  await expect(page.getByRole('button', { name: 'Close' })).toBeVisible();
  await expect(page.getByRole('textbox').first()).toHaveValue('');

  await page.getByRole('button', { name: 'Close' }).click();
  // No placeholder text leaks onto the grid for an empty-titled block.
  await expect(page.getByText('title')).toHaveCount(0);
});

test('dragging vertically before releasing sizes the new block to the '
  + 'drag, instead of the 30-minute default', async ({ page }) => {
  await openDraftWithRetry(
    page,
    async () => {
      // Two 15-minute slots (32px at this viewport's slot height) below
      // the default drag start, so the draft should size to roughly an
      // hour instead of 30 minutes.
      await dragMouse(
        page,
        { x: freeSpace.x, y: freeSpace.y },
        { x: freeSpace.x, y: freeSpace.y + 32 },
      );
      await enableFlutterAccessibility(page);
    },
    page.getByRole('button', { name: 'Create Event' }),
  );

  await page.getByRole('button', { name: 'Create Event' }).click();
  await expect(page.getByRole('button', { name: 'Close' })).toBeVisible();

  // The Starts/Ends dropdowns' accessible name is "Starts HH:MM"/"Ends
  // HH:MM" — the gap between them should reflect the drag, not the
  // 30-minute default.
  const startsName = await page
    .getByRole('button', { name: /^Starts \d{2}:\d{2}$/ })
    .innerText();
  const endsName = await page
    .getByRole('button', { name: /^Ends \d{2}:\d{2}$/ })
    .innerText();
  const toMinutes = (label: string) => {
    const [h, m] = label.split(' ')[1].split(':').map(Number);
    return h * 60 + m;
  };
  expect(toMinutes(endsName!) - toMinutes(startsName!)).toBeGreaterThan(30);
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

test('clicking elsewhere on free space opens a new draft there instead of '
  + 'creating a block', async ({ page }) => {
  await openFreeSpaceDraft(page);

  const createEventButton = page.getByRole('button', { name: 'Create Event' });
  const originalBox = await waitForBoundingBox(createEventButton);

  // A point well clear of the first draft box, but still free grid space.
  // "Create Event" stays visible either way (the first draft, or a new
  // one), so a dropped click can't be caught by visibility alone — poll
  // for its box actually moving instead, retrying the click itself like
  // clickUntilVisible's sibling helpers do.
  await expect(async () => {
    await page.mouse.click(300, 450);
    const box = await waitForBoundingBox(createEventButton);
    expect(box.y).not.toEqual(originalBox.y);
  }).toPass();

  // The click opened a fresh draft at the new position, replacing the
  // first one — still without committing any block.
  await expect(page.getByText('title')).toHaveCount(0);
});
