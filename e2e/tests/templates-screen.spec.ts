import { test, expect } from '@playwright/test';
import { enableFlutterAccessibility } from './support/accessibility';
import { clickCenter, dragMouse } from './support/gestures';

/**
 * Reads a template column's name by focusing its rename field and
 * reading the real DOM `<input>` value. Flutter web only syncs a text
 * field's DOM value once it has an active text-editing client attached
 * (i.e. once focused) — before that, `inputValue()` reads back empty
 * even though the canvas-rendered text is visible on screen. Focusing
 * via a raw click (not `Locator.fill`, which would also select/replace
 * the text) is enough to trigger the sync.
 */
async function readTemplateName(page: import('@playwright/test').Page) {
  const input = page.getByRole('textbox');
  await clickCenter(page, input);
  // The DOM/value sync on focus isn't instantaneous; reading immediately
  // after the click can still observe the pre-sync empty value.
  await page.waitForTimeout(200);
  return input.inputValue();
}

test.describe('wide viewport', () => {
  test.use({ viewport: { width: 800, height: 720 } });

  test.beforeEach(async ({ page }) => {
    await page.goto('/#/templates');
    await enableFlutterAccessibility(page);
  });

  test('starts empty with an add button', async ({ page }) => {
    await expect(page.getByRole('heading', { name: 'Templates' })).toBeVisible();
    await expect(page.getByText('No templates yet')).toBeVisible();
    await expect(
      page.getByRole('button', { name: 'Add template' }),
    ).toBeVisible();
  });

  test('the add button creates a template named "Template 1"', async ({
    page,
  }) => {
    await page.getByRole('button', { name: 'Add template' }).click();

    await expect(page.getByText('No templates yet')).toHaveCount(0);
    await expect(await readTemplateName(page)).toEqual('Template 1');
    await expect(
      page.getByRole('button', { name: 'Delete template' }),
    ).toHaveCount(1);
  });

  test('renaming a template persists the new name', async ({ page }) => {
    await page.getByRole('button', { name: 'Add template' }).click();
    const input = page.getByRole('textbox');
    await clickCenter(page, input);

    await input.fill('Weekday');
    await input.press('Enter');

    // Click elsewhere to drop focus, then refocus to confirm the new
    // name survived the round trip through the provider, not just the
    // field's own local edit buffer.
    await page.mouse.click(400, 400);
    await expect(await readTemplateName(page)).toEqual('Weekday');
  });

  test('the delete button removes the template', async ({ page }) => {
    await page.getByRole('button', { name: 'Add template' }).click();
    await expect(
      page.getByRole('button', { name: 'Delete template' }),
    ).toHaveCount(1);

    await page.getByRole('button', { name: 'Delete template' }).click();

    await expect(
      page.getByRole('button', { name: 'Delete template' }),
    ).toHaveCount(0);
    await expect(page.getByText('No templates yet')).toBeVisible();
  });
});

test.describe('wide viewport with two templates', () => {
  test.use({ viewport: { width: 1200, height: 800 } });

  test('a second added template shows as a second column', async ({
    page,
  }) => {
    await page.goto('/#/templates');
    await enableFlutterAccessibility(page);

    await page.getByRole('button', { name: 'Add template' }).click();
    await page.getByRole('button', { name: 'Add template' }).click();

    await expect(
      page.getByRole('button', { name: 'Delete template' }),
    ).toHaveCount(2);
  });
});

test.describe('narrow viewport', () => {
  test.use({ viewport: { width: 500, height: 800 } });

  test('with one template there is no paging arrow', async ({ page }) => {
    await page.goto('/#/templates');
    await enableFlutterAccessibility(page);
    await page.getByRole('button', { name: 'Add template' }).click();

    await expect(page.getByRole('button', { name: 'Next template' })).toHaveCount(
      0,
    );
  });

  test('the next-template arrow pages to the second template and back', async ({
    page,
  }) => {
    await page.goto('/#/templates');
    await enableFlutterAccessibility(page);
    await page.getByRole('button', { name: 'Add template' }).click();
    await page.getByRole('button', { name: 'Add template' }).click();

    // Adding a template navigates straight to it, so after adding a
    // second one we're already viewing it (the last page): "Next" is
    // disabled, "Previous" isn't. Asserting on the arrows' own
    // enabled/disabled state — rather than reading the rename field's
    // text, which needs a focus round-trip that's flaky immediately
    // after a page-turn animation — is a robust, unambiguous signal for
    // which page is showing, driven by the same `currentIndex` the app
    // itself uses.
    await expect(page.getByRole('button', { name: 'Next template' })).toBeDisabled();
    await expect(page.getByRole('button', { name: 'Previous template' })).toBeEnabled();

    await page.getByRole('button', { name: 'Previous template' }).click();

    await expect(page.getByRole('button', { name: 'Previous template' })).toBeDisabled();
    await expect(page.getByRole('button', { name: 'Next template' })).toBeEnabled();

    await page.getByRole('button', { name: 'Next template' }).click();

    await expect(page.getByRole('button', { name: 'Next template' })).toBeDisabled();
    await expect(page.getByRole('button', { name: 'Previous template' })).toBeEnabled();
  });

  test('a horizontal drag on free grid space swipes to the next '
    + 'template', async ({ page }) => {
    await page.goto('/#/templates');
    await enableFlutterAccessibility(page);
    await page.getByRole('button', { name: 'Add template' }).click();
    await page.getByRole('button', { name: 'Add template' }).click();
    // Adding opens straight to the new (last) template; page back to the
    // first one so there's somewhere to swipe forward to.
    await page.getByRole('button', { name: 'Previous template' }).click();
    await expect(page.getByRole('button', { name: 'Previous template' })).toBeDisabled();

    // Free grid space, well below the header, dragged leftward like a
    // real finger swipe (a genuine drag rather than a fling, matching
    // this suite's other drag helper).
    await dragMouse(page, { x: 300, y: 300 }, { x: 20, y: 300 });

    // Swiped forward to the last template: "Next" disabled again, same
    // signal the arrow-paging test above uses and for the same reason.
    await expect(page.getByRole('button', { name: 'Next template' })).toBeDisabled();
    await expect(page.getByRole('button', { name: 'Previous template' })).toBeEnabled();
  });
});
