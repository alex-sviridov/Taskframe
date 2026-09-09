import type { Page } from '@playwright/test';

/**
 * Flutter web renders to a canvas by default, so widget text and labels
 * aren't in the DOM. Clicking the placeholder Flutter injects turns on
 * its full semantics tree, exposing that content as real DOM/ARIA nodes
 * that Playwright locators can query.
 */
export async function enableFlutterAccessibility(page: Page): Promise<void> {
  const placeholder = page.locator('flt-semantics-placeholder');
  await placeholder.waitFor({ state: 'attached' });
  // The placeholder sits off-screen by design (it only matters to screen
  // readers), so a real pointer click fails Playwright's viewport check.
  await placeholder.dispatchEvent('click');
}
