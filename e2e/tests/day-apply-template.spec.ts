import { test, expect } from '@playwright/test';
import { enableFlutterAccessibility } from './support/accessibility';
import { clickCenter, clickUntilVisible, openDraftWithRetry } from './support/gestures';

test.use({ viewport: { width: 800, height: 720 } });

// The AppBar's "Add template" action, clicked before accessibility is
// enabled — see the comment on `templates-edit-block.spec.ts`'s
// `addTemplateAndOpenDraft` for why: a raw double-tap gesture (used below
// to open the block draft) stops being recognized once Flutter's full
// semantics tree is active, so this and the double-click both have to
// happen first.
const addTemplateButton = { x: 780, y: 28 } as const;

// The sidebar's "Day" destination isn't exposed in Flutter's semantics
// tree (only the active screen's own content is), so switching branches
// has to be a raw coordinate click rather than `getByRole`, regardless of
// whether accessibility has been enabled.
const dayDestination = { x: 100, y: 28 } as const;

/**
 * Adds a template, opens a block draft at [y] (a fixed x, arbitrary but
 * consistent y — the same y always resolves to the same time-of-day on
 * both the templates screen and the day screen, since both share the
 * same day-settings grid at the same viewport height), enables
 * accessibility, creates an Event, and titles it [title].
 */
async function addTemplateWithEventAt(
  page: import('@playwright/test').Page,
  y: number,
  title: string,
) {
  await openDraftWithRetry(
    page,
    async () => {
      await page.mouse.click(addTemplateButton.x, addTemplateButton.y);
      await page.waitForTimeout(300);

      await page.mouse.click(300, y);
      await page.waitForTimeout(60);
      await page.mouse.click(300, y);
      await page.waitForTimeout(200);

      await enableFlutterAccessibility(page);
    },
    page.getByRole('button', { name: 'Create Event' }),
  );

  await page.getByRole('button', { name: 'Create Event' }).click();
  await expect(page.getByRole('button', { name: 'Close' })).toBeVisible();
  await page.getByRole('textbox').first().fill(title);
  await page.getByRole('textbox').first().press('Enter');
  await page.getByRole('button', { name: 'Close' }).click();
  await expect(page.getByText(title)).toBeVisible();
}

test.beforeEach(async ({ page }) => {
  await page.goto('/#/templates');
  await page.locator('flt-semantics-placeholder').waitFor({ state: 'attached' });
});

test('applying a template with no conflicts adds its event to the day', async ({
  page,
}) => {
  await addTemplateWithEventAt(page, 300, 'Standup');

  // Switch to the day screen, then page to a day with no seeded blocks
  // (only "today" is seeded), so nothing here could conflict with
  // "Standup" regardless of what time it landed on.
  await clickUntilVisible(
    page,
    dayDestination,
    page.getByRole('heading', { name: 'Day Frame' }),
  );
  await page.getByRole('button', { name: 'Next day' }).click();

  await page.getByRole('button', { name: 'Apply template' }).click();
  await clickCenter(page, page.getByText('Template 1'));

  await expect(page.getByText('Standup')).toBeVisible();
});

test('an overlapping template event is skipped, leaving the existing '
  + 'block untouched', async ({ page }) => {
  // Near the very top of the grid, so this event starts at (or very
  // near) the day's start hour — matching where the day screen's own
  // "Add block" button places its first block on an empty day.
  await addTemplateWithEventAt(page, 126, 'Conflict');

  await clickUntilVisible(
    page,
    dayDestination,
    page.getByRole('heading', { name: 'Day Frame' }),
  );
  await page.getByRole('button', { name: 'Next day' }).click();

  await page.getByRole('button', { name: 'Add block' }).click();
  await expect(page.getByRole('button', { name: 'Close' })).toBeVisible();
  await page.getByRole('button', { name: 'Close' }).click();
  await expect(page.getByText('title')).toBeVisible();

  await page.getByRole('button', { name: 'Apply template' }).click();
  await clickCenter(page, page.getByText('Template 1'));

  await expect(page.getByText('Conflict')).toHaveCount(0);
  await expect(page.getByText('title')).toBeVisible();
});

test('the apply-template button is disabled when there are no templates', async ({
  page,
}) => {
  await enableFlutterAccessibility(page);
  await clickUntilVisible(
    page,
    dayDestination,
    page.getByRole('heading', { name: 'Day Frame' }),
  );

  await expect(page.getByRole('button', { name: 'Apply template' })).toBeDisabled();
});
