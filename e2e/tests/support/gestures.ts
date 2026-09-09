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

/**
 * Drags the mouse from [from] to [to] in [steps] intermediate moves,
 * holding the button down for the whole path and releasing at [to].
 * Used to simulate a desktop block drag, which starts immediately on
 * mouse-down (no long-press needed).
 */
export async function dragMouse(
  page: Page,
  from: { x: number; y: number },
  to: { x: number; y: number },
  { steps = 10 }: { steps?: number } = {},
): Promise<void> {
  await page.mouse.move(from.x, from.y);
  await page.mouse.down();
  for (let i = 1; i <= steps; i++) {
    const x = from.x + ((to.x - from.x) * i) / steps;
    const y = from.y + ((to.y - from.y) * i) / steps;
    await page.mouse.move(x, y);
  }
  await page.mouse.up();
}
