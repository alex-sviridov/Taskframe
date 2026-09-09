import type { Page } from '@playwright/test';

/**
 * Double-clicks at [x, y] by sending two clicks far enough apart to clear
 * Flutter's minimum gap between taps of a double tap (40ms), but well
 * within its double-tap timeout (300ms).
 *
 * Must run before {@link enableFlutterAccessibility}: once Flutter's full
 * semantics tree is active, the raw double-tap gesture stops being
 * recognized (the semantics layer intercepts the pointer events instead of
 * letting them reach the app's gesture detector), so any test that needs
 * both a double-click and semantics-based assertions has to do the
 * double-click first.
 */
export async function doubleClickFreeSpace(
  page: Page,
  x: number,
  y: number,
): Promise<void> {
  await page.mouse.click(x, y);
  await page.waitForTimeout(60);
  await page.mouse.click(x, y);
}
