import { test, expect, type Locator } from '@playwright/test';
import { enableFlutterAccessibility } from './support/accessibility';
import {
  clickNearFieldTop,
  dragMouseUntilTrue,
  fillTextboxAndSubmit,
  gotoAndWaitForBoot,
} from './support/gestures';

/**
 * Reads the on-screen template column's name by focusing its rename
 * field and reading the real DOM `<input>` value. Flutter web only syncs
 * a text field's DOM value once it has an active text-editing client
 * attached (i.e. once focused) — before that, `inputValue()` reads back
 * empty even though the canvas-rendered text is visible on screen.
 * Focusing via a raw click (not `Locator.fill`, which would also
 * select/replace the text) is enough to trigger the sync.
 *
 * A `PageView` neighbor's rename field can still be mounted (and so
 * still matched by `getByRole`) right after a page turn, which would
 * otherwise make `getByRole('textbox')` resolve to more than one
 * element — and, mid-animation, a neighbor's box can transiently
 * overlap the viewport too, not just the genuinely current page's.
 * Picking whichever candidate's box center is *closest* to the
 * viewport's own center (rather than merely inside it, or merely the
 * first match) reliably singles out the current page: `PageView` lays
 * pages out edge-to-edge, so only the current one is ever truly
 * centered. (A field's *width* isn't a reliable bound on its own: a
 * `PageView`-nested field's reported box can run wider than the
 * viewport regardless of which page it's on — see `clickNearFieldTop`'s
 * doc comment for the matching quirk in its *height*.)
 *
 * Retries the whole search-and-read for up to [timeoutMs]: called right
 * after an action that changes which page is showing (a page turn, or
 * a template just added), the new page's field can still be a beat
 * away from existing at all, from being the one truly centered, or
 * from having synced its DOM value once focused — every template here
 * always has a non-empty name, so an empty read is always this
 * transient lag, never a real value. Time-based rather than a fixed
 * attempt count so it scales with how loaded the machine running it
 * is — confirmed flaky under CI load at a fixed 10 attempts (~3.5s),
 * which a quieter local run never hit.
 */
async function readTemplateName(
  page: import('@playwright/test').Page,
  timeoutMs = 10_000,
): Promise<string> {
  const viewportWidth = page.viewportSize()?.width ?? 800;
  const targetCenter = viewportWidth / 2;
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    const inputs = page.getByRole('textbox');
    const count = await inputs.count();
    let best: Locator | null = null;
    let bestDistance = Infinity;
    for (let i = 0; i < count; i++) {
      const candidate = inputs.nth(i);
      // A short timeout, not the default: right after a swipe/drag the
      // page is still settling, and a `count()`-matched index can go
      // stale (its element detaches) before `boundingBox()` gets to it —
      // without a short timeout that hangs the call for the suite's
      // full default instead of just falling through to the next retry.
      const box = await candidate.boundingBox({ timeout: 500 }).catch(() => null);
      if (!box) continue;
      const centerX = box.x + box.width / 2;
      if (centerX < 0 || centerX > viewportWidth) continue;
      const distance = Math.abs(centerX - targetCenter);
      if (distance < bestDistance) {
        bestDistance = distance;
        best = candidate;
      }
    }
    if (best) {
      await clickNearFieldTop(page, best);
      // The DOM/value sync on focus isn't instantaneous; reading
      // immediately after the click can still observe the pre-sync
      // empty value.
      await page.waitForTimeout(200);
      const value = await best.inputValue();
      if (value !== '') return value;
    }
    await page.waitForTimeout(150);
  }
  throw new Error('No on-screen template rename field with a synced value found');
}

test.describe('wide viewport', () => {
  test.use({ viewport: { width: 800, height: 720 } });

  test.beforeEach(async ({ page }) => {
    await gotoAndWaitForBoot(page, '/#/templates');
    await enableFlutterAccessibility(page);
  });

  test('starts empty with an add-template slot and a disabled add-block button', async ({
    page,
  }) => {
    await expect(page.getByRole('heading', { name: 'Templates' })).toBeVisible();
    await expect(
      page.getByRole('button', { name: 'Add template' }),
    ).toBeVisible();
    // No template yet to add a block to.
    await expect(page.getByRole('button', { name: 'Add block' })).toBeDisabled();
  });

  test('the add-template slot creates a template named "Template 1"', async ({
    page,
  }) => {
    await page.getByRole('button', { name: 'Add template' }).click();

    await expect(await readTemplateName(page)).toEqual('Template 1');
    await expect(page.getByRole('button', { name: 'Add block' })).toBeEnabled();
  });

  test('renaming a template autosaves without pressing enter', async ({
    page,
  }) => {
    await page.getByRole('button', { name: 'Add template' }).click();
    const input = page.getByRole('textbox');
    await clickNearFieldTop(page, input);

    await input.fill('Weekday');
    // No submit — autosave should still persist it after a short pause.
    await page.waitForTimeout(700);

    // Click elsewhere to drop focus, then refocus to confirm the new
    // name survived the round trip through the provider, not just the
    // field's own local edit buffer.
    await page.mouse.click(400, 400);
    await expect(await readTemplateName(page)).toEqual('Weekday');
  });

  test('renaming a template and submitting persists the new name', async ({
    page,
  }) => {
    await page.getByRole('button', { name: 'Add template' }).click();
    const input = page.getByRole('textbox');
    await clickNearFieldTop(page, input);

    await fillTextboxAndSubmit(input, 'Weekday');

    await page.mouse.click(400, 400);
    await expect(await readTemplateName(page)).toEqual('Weekday');
  });

});

test.describe('wide viewport, hover-revealed delete button', () => {
  test.use({ viewport: { width: 800, height: 720 } });

  // These interact via raw coordinates and enable accessibility only at
  // the end, unlike this file's other tests — Flutter web's semantics
  // tree, once active, no longer forwards raw pointer-hover transitions
  // to the framework (confirmed empirically: identical mouse-move
  // sequences reveal the button before accessibility is enabled and
  // never after), so hover has to happen first. The button's govern
  // state (`_hovering`) doesn't reset when accessibility turns on, so a
  // button already revealed by hover stays revealed and clickable by
  // role afterward — that's what lets the deletion itself still be
  // asserted through the accessibility tree below.
  const addTemplateButton = { x: 507, y: 128 } as const;
  // Within Template 1's header cell, right of its title text — clear of
  // the sidebar (which extends to ~x=213) and left of the second
  // (add-template) column. The whole cell is one `MouseRegion`, not
  // just the title text, so this doesn't need to be pixel-precise.
  const template1Header = { x: 400, y: 84 } as const;
  const awayFromAnyHeader = { x: 400, y: 400 } as const;

  test('the delete button only shows on hover, and removes the template '
    + 'when clicked', async ({ page }) => {
    await gotoAndWaitForBoot(page, '/#/templates');
    // A settle pause before the very first raw interaction: right after
    // `gotoAndWaitForBoot` resolves, Flutter has injected its semantics
    // placeholder but can still be a beat away from being hit-testable,
    // so an immediate click can silently miss (confirmed empirically).
    // Every other raw-coordinate flow in this suite is wrapped in
    // `openDraftWithRetry`, which absorbs the same race by retrying;
    // this test has no such wrapper, so it waits instead.
    await page.waitForTimeout(500);
    await page.mouse.click(addTemplateButton.x, addTemplateButton.y);
    await page.waitForTimeout(500);

    // Two-step move (away, then onto the header) so Flutter's
    // MouseTracker sees a real enter transition rather than a jump.
    await page.mouse.move(awayFromAnyHeader.x, awayFromAnyHeader.y);
    await page.mouse.move(template1Header.x, template1Header.y, { steps: 5 });
    await page.waitForTimeout(300);

    await enableFlutterAccessibility(page);
    await expect(
      page.getByRole('button', { name: 'Delete template' }),
    ).toHaveCount(1);

    await page.getByRole('button', { name: 'Delete template' }).click();

    await expect(
      page.getByRole('button', { name: 'Add template' }),
    ).toBeVisible();
  });
});

test.describe('wide viewport with two templates', () => {
  test.use({ viewport: { width: 1200, height: 800 } });

  test('a second added template shows as a second column', async ({
    page,
  }) => {
    await gotoAndWaitForBoot(page, '/#/templates');
    await enableFlutterAccessibility(page);

    // At this width the add-template slot shares the row with real
    // templates until 7 fill it, so both adds are reachable directly.
    await page.getByRole('button', { name: 'Add template' }).click();
    await page.getByRole('button', { name: 'Add template' }).click();

    // Two rename fields (always visible, unlike the hover-only delete
    // button) mean two real template columns.
    await expect(page.getByRole('textbox')).toHaveCount(2);
  });
});

test.describe('wide viewport with eight templates', () => {
  test.use({ viewport: { width: 1200, height: 800 } });

  test('the 8th template pages to a second page', async ({ page }) => {
    await gotoAndWaitForBoot(page, '/#/templates');
    await enableFlutterAccessibility(page);

    // The first 7 adds all land on page one alongside the add-template
    // slot, which is pushed to page two only once page one is full.
    // Rename fields (always visible, unlike the hover/focus-only delete
    // button) are a page's real-template count.
    for (let i = 0; i < 7; i++) {
      await page.getByRole('button', { name: 'Add template' }).click();
    }
    await expect(page.getByRole('textbox')).toHaveCount(7);

    await page.getByRole('button', { name: 'Next templates' }).click();
    await page.getByRole('button', { name: 'Add template' }).click();

    // Adding opens straight to the new (8th) template's page.
    await expect(page.getByRole('textbox')).toHaveCount(1);
    await expect(
      page.getByRole('button', { name: 'Next templates' }),
    ).toBeDisabled();
    await expect(
      page.getByRole('button', { name: 'Previous templates' }),
    ).toBeEnabled();

    await page.getByRole('button', { name: 'Previous templates' }).click();

    await expect(page.getByRole('textbox')).toHaveCount(7);
    await expect(
      page.getByRole('button', { name: 'Previous templates' }),
    ).toBeDisabled();
  });
});

test.describe('narrow viewport', () => {
  test.use({ viewport: { width: 500, height: 800 } });

  test('with no templates yet there is no paging arrow', async ({ page }) => {
    await gotoAndWaitForBoot(page, '/#/templates');
    await enableFlutterAccessibility(page);

    await expect(
      page.getByRole('button', { name: 'Next template' }),
    ).toHaveCount(0);
  });

  test('the delete button only shows once the rename field is focused '
    + '(entered edit mode)', async ({ page }) => {
    await gotoAndWaitForBoot(page, '/#/templates');
    await enableFlutterAccessibility(page);
    await page.getByRole('button', { name: 'Add template' }).click();

    // Hidden until the title is tapped into edit mode — hover doesn't
    // apply on a touch viewport.
    await expect(
      page.getByRole('button', { name: 'Delete template' }),
    ).toHaveCount(0);

    // A plain `.click()` centers on the textbox's reported box, which
    // (nested in a `PageView`) can run tall enough to land past the
    // field itself — see `clickNearFieldTop`'s doc comment.
    await clickNearFieldTop(page, page.getByRole('textbox'));
    await expect(
      page.getByRole('button', { name: 'Delete template' }),
    ).toHaveCount(1);
  });

  test('the next-template arrow pages between a template and the '
    + 'add-template slot', async ({ page }) => {
    await gotoAndWaitForBoot(page, '/#/templates');
    await enableFlutterAccessibility(page);
    await page.getByRole('button', { name: 'Add template' }).click();

    // On Template 1's page; the add-template slot is next.
    await expect(
      page.getByRole('button', { name: 'Previous template' }),
    ).toBeDisabled();
    await expect(await readTemplateName(page)).toEqual('Template 1');

    await page.getByRole('button', { name: 'Next template' }).click();

    // The add-template slot's page has no rename field or delete button.
    await expect(
      page.getByRole('button', { name: 'Delete template' }),
    ).toHaveCount(0);

    await page.getByRole('button', { name: 'Previous template' }).click();

    await expect(await readTemplateName(page)).toEqual('Template 1');
  });

  test('adding a second template pages between both templates', async ({
    page,
  }) => {
    await gotoAndWaitForBoot(page, '/#/templates');
    await enableFlutterAccessibility(page);
    await page.getByRole('button', { name: 'Add template' }).click();
    await page.getByRole('button', { name: 'Next template' }).click();
    await page.getByRole('button', { name: 'Add template' }).click();

    // Adding opens straight to Template 2, between Template 1 and the
    // add-template slot (now pushed one page further out).
    await expect(await readTemplateName(page)).toEqual('Template 2');

    await page.getByRole('button', { name: 'Previous template' }).click();

    await expect(await readTemplateName(page)).toEqual('Template 1');
  });

  test('a horizontal drag on free grid space swipes to the next '
    + 'page', async ({ page }) => {
    await gotoAndWaitForBoot(page, '/#/templates');
    await enableFlutterAccessibility(page);
    await page.getByRole('button', { name: 'Add template' }).click();
    await expect(
      page.getByRole('button', { name: 'Previous template' }),
    ).toBeDisabled();

    // Free grid space, well below the header, dragged leftward like a
    // real finger swipe (a genuine drag rather than a fling, matching
    // this suite's other drag helper). Retried like this suite's block
    // drags: the same "gesture silently dropped under CI load" race
    // dragMouseUntilMoved guards against, but success here is the page
    // having turned, not a locator's box having moved. "Previous"
    // becoming enabled is a robust, animation-independent signal that
    // we've left Template 1's page — a *structural* one (unlike reading
    // the rename field's text, which needs a focus round-trip that's
    // flaky immediately after a page-turn animation, worse still right
    // after a real drag gesture rather than a plain click).
    await dragMouseUntilTrue(page, { x: 300, y: 300 }, { x: 20, y: 300 }, async () => {
      try {
        await expect(page.getByRole('button', { name: 'Previous template' })).toBeEnabled({
          timeout: 1000,
        });
        return true;
      } catch {
        return false;
      }
    });

    // Landed on the trailing add-template slot: no rename field or
    // delete button, and (being the last page) "Next" is now disabled —
    // another structural, text-free signal.
    await expect(
      page.getByRole('button', { name: 'Delete template' }),
    ).toHaveCount(0);
    await expect(
      page.getByRole('button', { name: 'Next template' }),
    ).toBeDisabled();
  });
});
