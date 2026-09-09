import { test, expect } from '@playwright/test';
import { enableFlutterAccessibility } from './support/accessibility';
import { dragMouse } from './support/gestures';

test.use({ viewport: { width: 800, height: 720 } });

test.beforeEach(async ({ page }) => {
  await page.goto('/');
  await page.locator('flt-semantics-placeholder').waitFor({ state: 'attached' });
  await enableFlutterAccessibility(page);
});

test('dragging a block to a new time moves it there', async ({ page }) => {
  // Breakfast is at 7:00-7:30, a fixed hardcoded block for today.
  await expect(page.getByText('Breakfast')).toBeVisible();
  const breakfast = page.getByText('Breakfast');
  const box = (await breakfast.boundingBox())!;

  // Drag straight down by roughly 4 hours' worth of pixels; the exact
  // landing slot isn't asserted, only that the block moved off its
  // original position.
  await dragMouse(
    page,
    { x: box.x + box.width / 2, y: box.y + box.height / 2 },
    { x: box.x + box.width / 2, y: box.y + box.height / 2 + 300 },
  );

  await expect(page.getByText('Breakfast')).toBeVisible();
  const movedBox = (await page.getByText('Breakfast').boundingBox())!;
  expect(movedBox.y).toBeGreaterThan(box.y + 50);
});

test('dragging a block into the right edge pages to the next day', async ({
  page,
}) => {
  await expect(page.getByText('Breakfast')).toBeVisible();
  const breakfast = page.getByText('Breakfast');
  const box = (await breakfast.boundingBox())!;

  // Drag to the right edge and hold there past the dwell time before
  // releasing, so the screen pages to tomorrow. The dwell is 600ms and
  // the page-turn animation itself takes another 250ms; waiting 900ms
  // (rather than exactly the dwell time) and giving the animation a
  // moment to settle before releasing avoids a race where mouse-up lands
  // mid-transition and commits the drop back onto the original day.
  await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
  await page.mouse.down();
  await page.mouse.move(780, box.y + box.height / 2);
  await page.waitForTimeout(900);
  await page.mouse.move(780, box.y + box.height / 2 + 1);
  await page.waitForTimeout(100);
  await page.mouse.up();

  await expect(page.getByText('Breakfast')).toHaveCount(0);
});
