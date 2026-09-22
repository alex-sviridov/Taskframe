import { test, expect, type Page } from '@playwright/test';
import { enableFlutterAccessibility } from './support/accessibility';
import {
  dragMouseUntilMoved,
  fillTextboxAndSubmit,
  gotoAndWaitForBoot,
  openDraftWithRetry,
  waitForBoundingBox,
} from './support/gestures';

// A new block's title starts empty, so it can't be located by text right
// after creation; every test in this suite names it this instead, purely
// so the drag logic below has stable text to locate the block by. Not
// "Block": the AppBar's own "Add block" button would then also match a
// plain `getByText`.
const blockTitle = 'Meeting';

/**
 * Adds a template (raw click — see the comment in
 * templates-edit-block.spec.ts for why this must run before accessibility
 * is enabled) and creates one event block on it via a double-click draft,
 * naming it [blockTitle] and leaving accessibility enabled and the modal
 * closed so the block is ready to drag.
 */
async function addTemplateWithBlock(
  page: Page,
  addTemplateSlot: { x: number; y: number },
  blockPosition: { x: number; y: number },
) {
  await openDraftWithRetry(
    page,
    async () => {
      await page.mouse.click(addTemplateSlot.x, addTemplateSlot.y);
      await page.waitForTimeout(300);

      await page.mouse.click(blockPosition.x, blockPosition.y);
      await page.waitForTimeout(60);
      await page.mouse.click(blockPosition.x, blockPosition.y);
      await page.waitForTimeout(200);

      await enableFlutterAccessibility(page);
    },
    page.getByRole('button', { name: 'Create Event' }),
  );
  await page.getByRole('button', { name: 'Create Event' }).click();
  await expect(page.getByRole('button', { name: 'Close' })).toBeVisible();
  await fillTextboxAndSubmit(page.getByRole('textbox').first(), blockTitle);
  await page.getByRole('button', { name: 'Close' }).click();
  await expect(page.getByText(blockTitle)).toBeVisible();
}

test.describe('single template', () => {
  test.use({ viewport: { width: 800, height: 720 } });
  // The trailing add-template slot: centered in the sole column shown
  // when no template exists yet (see templates-edit-block.spec.ts).
  const addTemplateSlot = { x: 507, y: 416 } as const;
  const blockPosition = { x: 300, y: 300 } as const;

  test.beforeEach(async ({ page }) => {
    await gotoAndWaitForBoot(page, '/#/templates');
  });

  test('dragging a block to a new time moves it there', async ({ page }) => {
    await addTemplateWithBlock(page, addTemplateSlot, blockPosition);

    const block = page.getByText(blockTitle);
    const box = await waitForBoundingBox(block);

    const movedBox = await dragMouseUntilMoved(
      page,
      { x: box.x + box.width / 2, y: box.y + box.height / 2 },
      { x: box.x + box.width / 2, y: box.y + box.height / 2 + 150 },
      page.getByText(blockTitle),
      box,
    );
    expect(movedBox.y).toBeGreaterThan(box.y + 50);
  });
});

test.describe('two templates side by side', () => {
  test.use({ viewport: { width: 1200, height: 800 } });
  // The trailing add-template slot for the first (only) template — still
  // a single full-width column even at this wider viewport.
  const addTemplateSlot = { x: 707, y: 456 } as const;
  // Comfortably inside the left column once a second template exists:
  // three columns share the row at this width (template 1, template 2,
  // then the trailing add-template slot), HourGutter-flanked on both
  // sides of the grid.
  const leftColumnPosition = { x: 300, y: 300 } as const;
  // Comfortably inside the middle (second template's) column — not the
  // add-template slot, which now occupies the row's third column.
  const rightColumnX = 600;

  test.beforeEach(async ({ page }) => {
    await gotoAndWaitForBoot(page, '/#/templates');
  });

  test('dragging a block across the gap moves it into the other '
    + 'template\'s column', async ({ page }) => {
    await addTemplateWithBlock(page, addTemplateSlot, leftColumnPosition);
    // A second template, so there's somewhere to drag into.
    await page.getByRole('button', { name: 'Add template' }).click();
    await expect(
      page.getByRole('button', { name: 'Delete template' }),
    ).toHaveCount(2);

    const block = page.getByText(blockTitle);
    const box = await waitForBoundingBox(block);
    expect(box.x).toBeLessThan(rightColumnX);

    const movedBox = await dragMouseUntilMoved(
      page,
      { x: box.x + box.width / 2, y: box.y + box.height / 2 },
      { x: rightColumnX, y: box.y + box.height / 2 },
      page.getByText(blockTitle),
      box,
    );
    expect(movedBox.x).toBeGreaterThan(box.x + 200);
  });
});

test.describe('regression: dragging after visiting the Day screen first', () => {
  test.use({ viewport: { width: 800, height: 720 } });
  // The trailing add-template slot: centered in the sole column shown
  // when no template exists yet (see templates-edit-block.spec.ts).
  const addTemplateSlot = { x: 507, y: 416 } as const;
  const blockPosition = { x: 300, y: 300 } as const;

  // Once both the Day screen and the Templates screen have been visited
  // in the same session, `StatefulShellRoute.indexedStack` keeps both
  // branches' widget trees laid out (only the inactive one is offstage,
  // not unbuilt) — so their drag-target registries both hold live
  // entries at once. This regression-tests that dragging a template
  // block still resolves against the Templates screen's own columns,
  // not a stale entry left over from the Day screen.
  //
  // The template and block are created first, on a freshly (and only)
  // loaded Templates route — matching every other passing test in this
  // suite — and only *then* does the test visit Day and come back. Doing
  // it in that order, rather than visiting Day before creating anything,
  // avoids racing the raw pre-accessibility clicks this suite needs for
  // block creation against an in-flight route transition, which proved
  // flaky under full-suite load: the fixed short waits are tuned for a
  // freshly loaded page, not a page mid-navigation.
  test('a template block still drags correctly after the Day screen has '
    + 'been visited', async ({ page }) => {
    const pageErrors: Error[] = [];
    page.on('pageerror', (error) => pageErrors.push(error));

    await gotoAndWaitForBoot(page, '/#/templates');
    await addTemplateWithBlock(page, addTemplateSlot, blockPosition);

    // Hash-only navigation to Day and back — both branches' widget
    // trees stay mounted underneath, exactly the scenario the fix
    // addresses. Accessibility is already enabled at this point, which
    // is fine: neither hop needs a double-click.
    await page.goto('/#/day');
    await expect(page.getByRole('heading', { name: 'Day Frame' })).toBeVisible();
    await page.goto('/#/templates');

    const block = page.getByText(blockTitle);
    const box = await waitForBoundingBox(block);

    // The block genuinely moved, rather than the drag silently failing.
    const movedBox = await dragMouseUntilMoved(
      page,
      { x: box.x + box.width / 2, y: box.y + box.height / 2 },
      { x: box.x + box.width / 2, y: box.y + box.height / 2 + 150 },
      page.getByText(blockTitle),
      box,
    );
    expect(movedBox.y).toBeGreaterThan(box.y + 50);

    // No uncaught exception (the original bug threw a type-cast error
    // from inside the pointer-event handler).
    expect(pageErrors).toEqual([]);
  });
});
