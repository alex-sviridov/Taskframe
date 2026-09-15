import { test, expect, type Locator, type Page } from '@playwright/test';
import { enableFlutterAccessibility } from './support/accessibility';
import {
  clickUntilHidden,
  clickUntilVisible,
  dismissModalByBarrier,
  fillTextboxUntilSet,
  fillTextboxUntilTrue,
  gotoAndWaitForBoot,
} from './support/gestures';

/**
 * The task edit modal's own title field, as opposed to the tasks screen's
 * persistent search field — every plain `getByRole('textbox')` in this file
 * would otherwise match both once the modal is open. Distinguished by
 * accessible name: the search field's name is its hint text ("Search:
 * #tag  @category  /opened  free text", collapsed to "Search: #tag
 * @category /opened free text" in the accessibility tree) regardless of its
 * current value, while the
 * modal's field has no name at all.
 */
function modalTextbox(page: Page): Locator {
  return page.getByRole('textbox', { name: /^(?!Search:).*$/ });
}

/**
 * Creates a category named [name] via the Categories screen's add action,
 * leaving color/emoji at their defaults (as in `day-block-category.spec.ts`
 * — the color picker and emoji picker aren't reliably automatable), then
 * navigates to the Tasks screen.
 *
 * Navigates by URL hash rather than the sidebar's "Categories"/"Tasks"
 * destinations: `NavigationDrawer` used as a standing sidebar (as
 * `AppShell` does here, outside a `Scaffold.drawer`) isn't exposed in
 * Flutter web's semantics tree, so its destinations aren't queryable the
 * way every other control in this suite is.
 */
async function addCategoryAndGoToTasks(page: Page, name: string): Promise<void> {
  await gotoAndWaitForBoot(page, '/#/categories');
  await enableFlutterAccessibility(page);

  await page.getByRole('button', { name: 'Add category' }).click();
  const field = page.getByRole('textbox');
  await fillTextboxUntilSet(field, name);
  // The sheet has no Save/Cancel button of its own — every field applies
  // live — so it's dismissed by tapping its barrier instead.
  await dismissModalByBarrier(page, field);

  // A hash-only navigation doesn't reload the page, so accessibility
  // (enabled once above) is still active here — enabling it again would
  // hang waiting for a placeholder that's already been consumed.
  await page.goto('/#/tasks');
}

/**
 * Dismisses the task edit modal by clicking its barrier/scrim, well
 * outside the modal's own bounds — the modal has no Save/Cancel button of
 * its own to tap instead, since every field applies live. Retried (see
 * {@link clickUntilHidden}) since, like every other raw click in this
 * suite, it can be silently dropped under CI load, leaving the modal
 * open and every assertion that expects it closed racing a gesture that
 * never actually landed.
 */
async function dismissTaskModal(page: Page): Promise<void> {
  await clickUntilHidden(page, { x: 770, y: 20 }, modalTextbox(page));
}

/**
 * The tasks screen's persistent search field, as opposed to the task edit
 * modal's own title field (see {@link modalTextbox}). Distinguished by
 * accessible name: the search field keeps its hint ("Search: #tag  @category
 * /opened  free text") as its name while empty; the modal's field has none.
 */
function searchTextbox(page: Page): Locator {
  return page.getByRole('textbox', { name: /^Search:/ });
}

/**
 * Creates a task titled [title] with each of [tags] attached, via the
 * modal's own "#tag " extraction (unaffected by this feature — see
 * "strips it from the title" above).
 */
async function addTaskWithTags(
  page: Page,
  title: string,
  tags: string[],
): Promise<void> {
  await page.getByRole('button', { name: 'Add task' }).click();
  const field = modalTextbox(page);
  await fillTextboxUntilSet(field, title);
  for (const tag of tags) {
    await fillTextboxUntilTrue(field, `${title} #${tag} `, async () =>
      (await field.inputValue().catch(() => '')) === `${title} `);
  }
  await dismissTaskModal(page);
}

/**
 * Creates a task titled [title] and assigns it to the category named
 * [categoryName] via the modal's category dropdown — the same picker
 * exercised by "picking a category from the dropdown" above. [categoryName]
 * must already exist (see {@link addCategoryAndGoToTasks}).
 */
async function addTaskWithCategory(
  page: Page,
  title: string,
  categoryName: string,
): Promise<void> {
  await page.getByRole('button', { name: 'Add task' }).click();
  await fillTextboxUntilSet(modalTextbox(page), title);
  await page.getByRole('button', { name: 'Default' }).click();
  await page.getByRole('menuitem', { name: categoryName }).click();
  await expect(page.getByRole('button', { name: categoryName })).toBeVisible();
  await dismissTaskModal(page);
}

test.describe('wide viewport', () => {
  test.use({ viewport: { width: 800, height: 720 } });

  test.beforeEach(async ({ page }) => {
    await gotoAndWaitForBoot(page, '/#/tasks');
    await enableFlutterAccessibility(page);
  });

  test('starts empty with an add button', async ({ page }) => {
    await expect(page.getByRole('heading', { name: 'Tasks' })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Add task' })).toBeVisible();
    await expect(page.getByRole('checkbox')).toHaveCount(0);
  });

  test('typing a title creates the task live, with no Save step', async ({
    page,
  }) => {
    await page.getByRole('button', { name: 'Add task' }).click();

    await fillTextboxUntilSet(modalTextbox(page), 'Buy milk');
    await dismissTaskModal(page);

    // The card row is a `ListTile` with `onTap`, so Flutter's semantics
    // expose the whole row as a button (its accessible name is the title
    // text) rather than a plain text node — hence `getByRole`, not
    // `getByText`, throughout this file for card rows.
    await expect(page.getByRole('button', { name: 'Buy milk' })).toBeVisible();
    await expect(page.getByRole('checkbox')).toHaveCount(1);
  });

  test('toggling a card checkbox closes the task, and it stays closed on '
    + 'reopening', async ({ page }) => {
    await page.getByRole('button', { name: 'Add task' }).click();
    await fillTextboxUntilSet(modalTextbox(page), 'Buy milk');
    await dismissTaskModal(page);

    await page.getByRole('checkbox').click();

    // Closing is a card-level action; it must not have opened the modal.
    await expect(modalTextbox(page)).toHaveCount(0);

    await page.getByRole('button', { name: 'Buy milk' }).click();
    await expect(page.getByRole('checkbox').first()).toBeChecked();
  });

  test('editing the title in the modal updates the card live', async ({
    page,
  }) => {
    await page.getByRole('button', { name: 'Add task' }).click();
    await fillTextboxUntilSet(modalTextbox(page), 'Buy milk');
    await dismissTaskModal(page);

    await page.getByRole('button', { name: 'Buy milk' }).click();
    await fillTextboxUntilSet(modalTextbox(page), 'Buy oat milk');
    await dismissTaskModal(page);

    await expect(
      page.getByRole('button', { name: 'Buy oat milk' }),
    ).toBeVisible();
    await expect(
      page.getByRole('button', { name: 'Buy milk', exact: true }),
    ).toHaveCount(0);
  });

  test('picking a category from the dropdown persists it, surviving '
    + 'closing and reopening the modal', async ({ page }) => {
    await addCategoryAndGoToTasks(page, 'Work');

    await page.getByRole('button', { name: 'Add task' }).click();
    await fillTextboxUntilSet(modalTextbox(page), 'Ship it');

    // The default category is the dropdown's closed-state label until a
    // different one is picked — same signal `day-block-category.spec.ts`
    // uses for the day screen's block category picker (the two share the
    // same `BlockCategoryPicker` widget).
    await expect(page.getByRole('button', { name: 'Default' })).toBeVisible();
    await page.getByRole('button', { name: 'Default' }).click();
    await page.getByRole('menuitem', { name: 'Work' }).click();
    await expect(page.getByRole('button', { name: 'Work' })).toBeVisible();

    await dismissTaskModal(page);
    await page.getByRole('button', { name: 'Ship it' }).click();

    await expect(page.getByRole('button', { name: 'Work' })).toBeVisible();
  });

  test('typing "#tag " strips it from the title and shows a tag pill', async ({
    page,
  }) => {
    await page.getByRole('button', { name: 'Add task' }).click();
    // The extraction rewrites the field's own value as soon as the
    // trailing "#groceries " is typed, so the textbox never settles on
    // that raw value — fillTextboxUntilSet's equality check would never
    // pass. Use fillTextboxUntilTrue instead, checking for the app's
    // rewritten value, so a fill the app's text-editing client didn't
    // actually pick up (see fillTextboxUntilSet's doc comment) still
    // gets retried rather than silently trusted.
    await fillTextboxUntilTrue(modalTextbox(page), 'Buy #groceries ', async () =>
      (await modalTextbox(page).inputValue().catch(() => '')) === 'Buy ');

    // A pill renders as a Flutter `Chip`, exposed in the semantics tree
    // as a checkbox labeled with the tag text.
    await expect(page.getByRole('checkbox', { name: 'groceries' })).toBeVisible();
    await expect(modalTextbox(page)).toHaveValue('Buy ');

    await dismissTaskModal(page);

    await expect(page.getByRole('button', { name: 'Buy' })).toBeVisible();
    await expect(page.getByRole('checkbox', { name: 'groceries' })).toBeVisible();
  });

  test('a trailing "#tag" with no space is still added when the modal is '
    + 'dismissed', async ({ page }) => {
    await page.getByRole('button', { name: 'Add task' }).click();
    // Nothing rewrites the field while typing here (extraction only
    // happens on exit), so — unlike the trailing-space case — a plain
    // fillTextboxUntilSet can wait for the typed value to actually
    // stick, guarding against a fill the app's text-editing client
    // didn't pick up (see its doc comment).
    await fillTextboxUntilSet(modalTextbox(page), 'Buy #groceries');
    // Also wait for the Delete button — proof the task itself was
    // created, not just that the field holds the right text — before
    // dismissing, since the exit-time tag extraction needs a task to
    // apply to.
    await expect(page.getByRole('button', { name: 'Delete' })).toBeVisible();

    await dismissTaskModal(page);

    await expect(page.getByRole('button', { name: 'Buy' })).toBeVisible();
    await expect(page.getByRole('checkbox', { name: 'groceries' })).toBeVisible();
  });

  test('removing a tag pill in the edit modal persists the removal', async ({
    page,
  }) => {
    await page.getByRole('button', { name: 'Add task' }).click();
    // See the "strips it from the title" test above for why this needs
    // fillTextboxUntilTrue rather than a plain fill or fillTextboxUntilSet.
    await fillTextboxUntilTrue(modalTextbox(page), 'Buy #groceries ', async () =>
      (await modalTextbox(page).inputValue().catch(() => '')) === 'Buy ');
    const pill = page.getByRole('checkbox', { name: 'groceries' });
    await expect(pill).toBeVisible();

    // `InputChip`'s delete affordance reports as disabled in the
    // semantics/ARIA tree even once its own tap handler is live (a
    // Flutter-web quirk, not an actual disabled state — the Flutter
    // widget tests confirm the tap handler works), so a plain click is
    // permanently blocked by Playwright's actionability check; force is
    // required. Even forced, the click's target coordinates are read
    // from the chip's current layout box, which can still be mid-
    // transition through its own entrance animation (~195ms — see
    // chip.dart's _kSelectDuration) right after the pill first appears,
    // so wait for that to settle first.
    await page.waitForTimeout(400);
    await pill.getByRole('button', { name: 'Delete' }).click({ force: true });
    await expect(pill).toHaveCount(0);

    await dismissTaskModal(page);
    await expect(page.getByRole('checkbox', { name: 'groceries' })).toHaveCount(0);
  });

  test('Delete asks for confirmation, then removes the task', async ({
    page,
  }) => {
    await page.getByRole('button', { name: 'Add task' }).click();
    await fillTextboxUntilSet(modalTextbox(page), 'Buy milk');

    await page.getByRole('button', { name: 'Delete' }).click();
    await expect(page.getByText('Delete this task?')).toBeVisible();

    await page.getByRole('button', { name: 'Delete' }).last().click();

    await expect(page.getByRole('button', { name: 'Buy milk' })).toHaveCount(0);
    await expect(page.getByRole('checkbox')).toHaveCount(0);
  });

  test.describe('unified search query', () => {
    test('a #tag anywhere in the search text filters to tasks with that '
      + 'tag', async ({ page }) => {
      await addTaskWithTags(page, 'Buy milk', ['groceries']);
      await addTaskWithTags(page, 'Walk the dog', []);

      await fillTextboxUntilSet(searchTextbox(page), '#groceries');

      await expect(page.getByRole('button', { name: 'Buy milk' })).toBeVisible();
      await expect(page.getByRole('button', { name: 'Walk the dog' })).toHaveCount(0);
    });

    test('several #tags combine with AND', async ({ page }) => {
      await addTaskWithTags(page, 'Buy milk', ['groceries', 'urgent']);
      await addTaskWithTags(page, 'Buy eggs', ['groceries']);

      await fillTextboxUntilSet(searchTextbox(page), '#groceries #urgent');

      await expect(page.getByRole('button', { name: 'Buy milk' })).toBeVisible();
      await expect(page.getByRole('button', { name: 'Buy eggs' })).toHaveCount(0);
    });

    test('#!tag excludes tasks with that tag', async ({ page }) => {
      await addTaskWithTags(page, 'Buy milk', ['urgent']);
      await addTaskWithTags(page, 'Walk the dog', []);

      await fillTextboxUntilSet(searchTextbox(page), '#!urgent');

      await expect(page.getByRole('button', { name: 'Buy milk' })).toHaveCount(0);
      await expect(page.getByRole('button', { name: 'Walk the dog' })).toBeVisible();
    });

    test('tapping a rendered tag token toggles it between include and '
      + 'exclude', async ({ page }) => {
      await addTaskWithTags(page, 'Buy milk', ['urgent']);
      await addTaskWithTags(page, 'Sell couch', []);

      const search = searchTextbox(page);
      await fillTextboxUntilSet(search, '#urgent');
      await expect(page.getByRole('button', { name: 'Buy milk' })).toBeVisible();
      await expect(page.getByRole('button', { name: 'Sell couch' })).toHaveCount(0);

      // Click near the start of the field's text, not its center — the
      // field is much wider than "#urgent", and text is left-aligned
      // after the prefix icon, so a center click would land past the end
      // of the text in empty space. Adjust the x offset if it doesn't
      // land on the token in practice (re-run with a Playwright trace to
      // see exactly where the click landed vs. where the text renders).
      // Wrapped in clickUntilVisible (see support/gestures.ts) rather than
      // a raw page.mouse.click, since a single synthetic click can be
      // silently dropped by Flutter web's canvas hit-testing under CI
      // load — "Sell couch" becoming visible is the marker that the tap
      // actually landed and toggled the token, not just a fixed wait.
      const box = (await search.boundingBox())!;
      await clickUntilVisible(
        page,
        { x: box.x + 45, y: box.y + box.height / 2 },
        page.getByRole('button', { name: 'Sell couch' }),
      );

      await expect(page.getByRole('button', { name: 'Buy milk' })).toHaveCount(0);
      await expect(page.getByRole('button', { name: 'Sell couch' })).toBeVisible();
      await expect(search).toHaveValue('#!urgent');
    });

    test('backspacing through a tag token removes it and un-filters', async ({
      page,
    }) => {
      await addTaskWithTags(page, 'Buy milk', ['groceries']);
      await addTaskWithTags(page, 'Walk the dog', []);

      const search = searchTextbox(page);
      await fillTextboxUntilSet(search, '#groceries');
      await expect(page.getByRole('button', { name: 'Walk the dog' })).toHaveCount(0);

      await search.fill('');
      await page.waitForTimeout(200);

      await expect(page.getByRole('button', { name: 'Walk the dog' })).toBeVisible();
    });

    test('/opened filters to tasks that are not closed', async ({ page }) => {
      await addTaskWithTags(page, 'Buy milk', []);
      await page.getByRole('button', { name: 'Add task' }).click();
      await fillTextboxUntilSet(modalTextbox(page), 'Walk the dog');
      await page.getByRole('checkbox').first().click();
      await dismissTaskModal(page);

      await fillTextboxUntilSet(searchTextbox(page), '/opened');

      await expect(page.getByRole('button', { name: 'Buy milk' })).toBeVisible();
      await expect(page.getByRole('button', { name: 'Walk the dog' })).toHaveCount(0);
    });

    test('an @category anywhere in the search text filters to tasks with '
      + 'that category', async ({ page }) => {
      await addCategoryAndGoToTasks(page, 'Work');
      await addTaskWithCategory(page, 'Ship it', 'Work');
      await addTaskWithTags(page, 'Buy milk', []);

      await fillTextboxUntilSet(searchTextbox(page), '@work');

      await expect(page.getByRole('button', { name: 'Ship it' })).toBeVisible();
      await expect(page.getByRole('button', { name: 'Buy milk' })).toHaveCount(0);
    });

    test('@!category excludes tasks with that category', async ({ page }) => {
      await addCategoryAndGoToTasks(page, 'Work');
      await addTaskWithCategory(page, 'Ship it', 'Work');
      await addTaskWithTags(page, 'Buy milk', []);

      await fillTextboxUntilSet(searchTextbox(page), '@!work');

      await expect(page.getByRole('button', { name: 'Ship it' })).toHaveCount(0);
      await expect(page.getByRole('button', { name: 'Buy milk' })).toBeVisible();
    });

    test('several @categories combine with AND — since a task has only one '
      + 'category, two different included ones together match nothing', async ({
      page,
    }) => {
      await addCategoryAndGoToTasks(page, 'Work');
      await addCategoryAndGoToTasks(page, 'Home');
      await addTaskWithCategory(page, 'Ship it', 'Work');

      await fillTextboxUntilSet(searchTextbox(page), '@work @home');

      await expect(page.getByRole('button', { name: 'Ship it' })).toHaveCount(0);
    });

    test('typing #groceries into an empty search field shows a tag '
      + 'suggestion dropdown that completes on tap', async ({ page }) => {
      await addTaskWithTags(page, 'Buy milk', ['groceries']);

      const search = searchTextbox(page);
      await fillTextboxUntilSet(search, '#gro');

      // The suggestion renders as a plain button, not a list-semantics
      // node — confirmed via the accessibility tree snapshot, not assumed.
      const suggestion = page.getByRole('button', { name: 'groceries' });
      await expect(suggestion).toBeVisible();
      const suggestionBox = (await suggestion.boundingBox())!;
      // Wrapped in clickUntilHidden (see support/gestures.ts) rather than
      // a raw page.mouse.click: a single synthetic click can be silently
      // dropped by Flutter web's canvas hit-testing under CI load, and the
      // suggestion closing (rather than a fixed wait) is the marker that
      // the tap actually landed and completed the tag.
      await clickUntilHidden(
        page,
        {
          x: suggestionBox.x + suggestionBox.width / 2,
          y: suggestionBox.y + suggestionBox.height / 2,
        },
        suggestion,
      );

      // Confirmed via probing: selecting the suggestion updates the app's
      // real text-editing state (the task list filters correctly right
      // away), but the search field's underlying DOM `<input>` — what
      // `inputValue()`/`toHaveValue()` read — is a Flutter-web semantics
      // mirror that only resyncs to the true value when the field is
      // next focused; it stays stale (still "#gro") until then. Force
      // that resync via a direct DOM focus() rather than a synthetic
      // pointer click — focus() isn't subject to the canvas-hit-testing
      // drop risk a raw click carries (there's no click-retry marker for
      // "the mirrored value changed" to wrap around, since the value
      // isn't reflected in any DOM attribute or text node Playwright can
      // observe — confirmed by probing).
      await search.focus();
      await page.waitForTimeout(300);

      await expect(search).toHaveValue('#groceries ');
    });

    test('tapping the /status filter button opens the "opened" '
      + 'suggestion dropdown', async ({ page }) => {
      // Regresses a real-browser-only bug: focusing the search field
      // programmatically (rather than via a direct tap on it) selects
      // all of its text on desktop/web platforms, which left the
      // dropdown's cursor-position matching unable to find a partial
      // token — invisible to the widget-test suite, which runs under a
      // fixed non-desktop TargetPlatform that doesn't select-all on
      // focus.
      //
      // The filter row's buttons are plain (non-interactive) `Chip`s —
      // deliberately not `ActionChip`s, see `_buildFilterRow`'s doc — so
      // they aren't exposed with button semantics; addressed by their
      // aria-label instead of a role.
      await page.getByRole('button', { name: 'Filters' }).click();
      await page.locator('[aria-label="/status"]').click();

      await expect(page.getByRole('button', { name: 'opened' })).toBeVisible();
    });
  });
});

test.describe('narrow viewport', () => {
  test.use({ viewport: { width: 400, height: 800 } });

  test('the add button creates a task live through the bottom-sheet '
    + 'modal', async ({ page }) => {
    await gotoAndWaitForBoot(page, '/#/tasks');
    await enableFlutterAccessibility(page);

    await page.getByRole('button', { name: 'Add task' }).click();
    await fillTextboxUntilSet(modalTextbox(page), 'Buy milk');
    await clickUntilHidden(page, { x: 200, y: 10 }, modalTextbox(page));

    await expect(page.getByRole('button', { name: 'Buy milk' })).toBeVisible();
    await expect(page.getByRole('checkbox')).toHaveCount(1);
  });
});
