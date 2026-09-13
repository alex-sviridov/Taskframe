import type { Locator, Page } from '@playwright/test';

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
 * Fills [textbox] with [value], retrying if it didn't stick. Under CI
 * load, a synthetic `fill()` occasionally lands on the field without the
 * app's text-editing client actually picking it up — confirmed by tracing
 * two separate failures: a renamed block that kept its default "title"
 * text, and a "Save" button that stayed disabled forever because the
 * field it validates never saw the new value — so the result is read back
 * via `inputValue()` and the fill reissued rather than trusted blind. A
 * short pause precedes each read: Flutter web only syncs a text field's
 * DOM value once its editing client has attached, which lags one beat
 * behind the field visibly accepting focus.
 */
export async function fillTextboxUntilSet(
  textbox: Locator,
  value: string,
  attempts = 3,
): Promise<void> {
  for (let attempt = 1; attempt <= attempts; attempt++) {
    await textbox.fill(value);
    await textbox.page().waitForTimeout(100);
    if ((await textbox.inputValue().catch(() => '')) === value) return;
    if (attempt === attempts) {
      throw new Error(`Textbox never settled on "${value}" after ${attempts} attempts`);
    }
  }
}

/**
 * {@link fillTextboxUntilSet}, but for a field whose value the app itself
 * rewrites as a side effect of the fill (so waiting for the typed value to
 * stick, as `fillTextboxUntilSet` does, would never succeed) — the caller
 * supplies its own check for "the fill was actually picked up" instead
 * (typically: the field now holds the app's rewritten value).
 */
export async function fillTextboxUntilTrue(
  textbox: Locator,
  value: string,
  succeeded: () => Promise<boolean>,
  attempts = 3,
): Promise<void> {
  for (let attempt = 1; attempt <= attempts; attempt++) {
    await textbox.fill(value);
    await textbox.page().waitForTimeout(100);
    if (await succeeded()) return;
    if (attempt === attempts) {
      throw new Error(`Textbox never picked up a fill of "${value}" after ${attempts} attempts`);
    }
  }
}

/**
 * {@link fillTextboxUntilSet}, then presses Enter — for the common case
 * where the caller was going to submit the field that way regardless.
 */
export async function fillTextboxAndSubmit(
  textbox: Locator,
  value: string,
  attempts = 3,
): Promise<void> {
  await fillTextboxUntilSet(textbox, value, attempts);
  await textbox.press('Enter');
}

/**
 * Clicks [point] and confirms it took effect by waiting for [marker] to
 * become visible, retrying the raw click itself (not just polling
 * afterwards) if it doesn't. Flutter web's canvas hit-testing occasionally
 * drops a single synthetic click outright under CI load — confirmed by
 * tracing a failure where the click's target screen never appeared even
 * after Playwright's full default timeout — so a plain locator wait after
 * a single click attempt isn't enough; the click has to be reissued.
 */
export async function clickUntilVisible(
  page: Page,
  point: { x: number; y: number },
  marker: Locator,
  { attempts = 3, timeoutMs = 2000 }: { attempts?: number; timeoutMs?: number } = {},
): Promise<void> {
  for (let attempt = 1; attempt <= attempts; attempt++) {
    await page.mouse.click(point.x, point.y);
    const visible = await marker
      .waitFor({ state: 'visible', timeout: timeoutMs })
      .then(() => true)
      .catch(() => false);
    if (visible) return;
    if (attempt === attempts) {
      throw new Error(
        `Click at (${point.x}, ${point.y}) did not produce the expected result after ${attempts} attempts`,
      );
    }
  }
}

/**
 * Clicks [point] and confirms it took effect by waiting for [marker] to
 * become hidden, retrying the raw click itself if it doesn't — the
 * dismiss-a-modal-via-barrier-tap counterpart to {@link clickUntilVisible}
 * (see its doc comment for why a single click can't be trusted under CI
 * load).
 */
export async function clickUntilHidden(
  page: Page,
  point: { x: number; y: number },
  marker: Locator,
  { attempts = 3, timeoutMs = 2000 }: { attempts?: number; timeoutMs?: number } = {},
): Promise<void> {
  for (let attempt = 1; attempt <= attempts; attempt++) {
    await page.mouse.click(point.x, point.y);
    const hidden = await marker
      .waitFor({ state: 'hidden', timeout: timeoutMs })
      .then(() => true)
      .catch(() => false);
    if (hidden) return;
    if (attempt === attempts) {
      throw new Error(
        `Click at (${point.x}, ${point.y}) did not dismiss the expected element after ${attempts} attempts`,
      );
    }
  }
}

/**
 * Runs [openDraft] (a raw double-click gesture that opens a block draft,
 * performed before Flutter's semantics tree activates — see
 * {@link doubleClickFreeSpace}) and confirms it worked by waiting for
 * [marker] (typically the "Create Event" button). Under CI load, Flutter's
 * double-tap recognizer occasionally misses the gesture entirely: the
 * marker never appears even after Playwright's full 5s poll, and by then
 * accessibility is already enabled, which permanently stops raw double-taps
 * from being recognized — so retrying the gesture on the same page can't
 * recover it. The only reliable recovery is reloading the page and
 * rerunning [openDraft] from scratch.
 */
export async function openDraftWithRetry(
  page: Page,
  openDraft: () => Promise<void>,
  marker: Locator,
  attempts = 6,
): Promise<void> {
  for (let attempt = 1; attempt <= attempts; attempt++) {
    await openDraft();
    const opened = await marker
      .waitFor({ state: 'visible', timeout: 5000 })
      .then(() => true)
      .catch(() => false);
    if (opened) return;
    if (attempt === attempts) {
      throw new Error(`Block draft did not open after ${attempts} attempts`);
    }
    await reloadAndWaitForBoot(page);
  }
}

/**
 * Reloads the current page and waits for Flutter to finish booting.
 *
 * Uses {@link Page.reload}, not `page.goto` on the current URL: this
 * suite's routes are hash fragments (e.g. `/#/templates`), and navigating
 * to a URL that's already current is a same-document, no-op navigation in
 * Chromium — no request is made and the existing (broken) Flutter
 * instance is never actually replaced, so waiting for a fresh
 * `flt-semantics-placeholder` afterwards hangs forever. `reload()` always
 * forces a real navigation regardless of the hash.
 */
async function reloadAndWaitForBoot(page: Page): Promise<void> {
  await page.reload();
  await page.locator('flt-semantics-placeholder').waitFor({ state: 'attached' });
}

/**
 * Navigates to [path] and waits for Flutter to finish booting (the
 * `flt-semantics-placeholder` it injects once ready for input), retrying
 * once via a full reload if the first boot hangs. Weaker/busier CI runners
 * occasionally serve a page that never finishes booting on the very first
 * load — confirmed by a CI run where a `beforeEach`'s plain `goto` +
 * `waitFor` exceeded a 60s test timeout — and a fresh reload reliably
 * recovers where waiting longer on the same load does not.
 */
export async function gotoAndWaitForBoot(page: Page, path: string): Promise<void> {
  await page.goto(path);
  const booted = await page
    .locator('flt-semantics-placeholder')
    .waitFor({ state: 'attached', timeout: 20_000 })
    .then(() => true)
    .catch(() => false);
  if (booted) return;
  await reloadAndWaitForBoot(page);
}

/**
 * Reads [locator]'s bounding box, retrying if it's transiently `null`.
 * Right after a state change that moves or recreates the underlying
 * widget (e.g. a block landing in a new column after a drag), Flutter web
 * briefly detaches the old semantics node before the rebuilt one attaches
 * — a plain `boundingBox()` call can land in that gap and return `null`
 * even though the text was visible moments before (and will be again a
 * frame later).
 */
export async function waitForBoundingBox(
  locator: Locator,
  timeoutMs = 5000,
): Promise<{ x: number; y: number; width: number; height: number }> {
  const start = Date.now();
  while (true) {
    const box = await locator.boundingBox();
    if (box) return box;
    if (Date.now() - start > timeoutMs) {
      throw new Error('Timed out waiting for a non-null bounding box');
    }
    await locator.page().waitForTimeout(50);
  }
}

/**
 * Clicks the center of [locator]'s bounding box via a raw mouse click,
 * rather than {@link Locator.click}. Flutter web's semantics DOM nests a
 * static text node (what {@link Page.getByText} resolves to) inside its
 * tappable ancestor element, and that ancestor intercepts pointer events —
 * so a direct `locator.click()` on the text node itself fails with
 * "intercepts pointer events". Clicking by raw coordinates instead lands on
 * whatever's topmost there, which is the tappable ancestor, same as a real
 * tap would hit.
 */
export async function clickCenter(page: Page, locator: Locator): Promise<void> {
  const box = (await locator.boundingBox())!;
  await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
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
    // Give Flutter's renderer a frame to process this position (and update
    // its drag-target hit-testing) before the next one arrives. Firing all
    // the moves back-to-back can outrun the engine under CI load, so the
    // gesture's *final* recognized position ends up short of where the
    // mouse actually released — confirmed by tracing a drop that landed
    // back in the origin column despite `mouse.up()` firing at a
    // coordinate well inside the target one.
    await page.waitForTimeout(16);
  }
  await page.mouse.up();
}

/**
 * Drags [locator] from [from] to [to] (see {@link dragMouse}), retrying if
 * it doesn't actually move. Flutter's `Draggable` occasionally never
 * enters the drag at all under CI load — the `mouse.down()` and the first
 * `mouse.move()` land close enough together that the gesture arena hasn't
 * finished registering the pointer as "down" yet, so the whole gesture is
 * dropped and the block is found back at its exact original position
 * (confirmed by tracing a "failed" run: the reported box was pixel-for-
 * pixel identical to the one before the drag, not just short of the
 * target). A plain post-drag assertion doesn't recover from this — the
 * drag itself has to be reissued.
 */
export async function dragMouseUntilMoved(
  page: Page,
  from: { x: number; y: number },
  to: { x: number; y: number },
  locator: Locator,
  originalBox: { x: number; y: number },
  { attempts = 3, steps = 10 }: { attempts?: number; steps?: number } = {},
): Promise<{ x: number; y: number; width: number; height: number }> {
  for (let attempt = 1; attempt <= attempts; attempt++) {
    await dragMouse(page, from, to, { steps });
    const box = await waitForBoundingBox(locator);
    if (box.x !== originalBox.x || box.y !== originalBox.y) return box;
    if (attempt === attempts) {
      throw new Error(`Drag from (${from.x}, ${from.y}) to (${to.x}, ${to.y}) never moved the block after ${attempts} attempts`);
    }
  }
  throw new Error('unreachable');
}

/**
 * Drags the mouse from [from] to [to] (see {@link dragMouse}), retrying up
 * to [attempts] times until [succeeded] returns `true`. Same "gesture
 * silently dropped under CI load" issue {@link dragMouseUntilMoved}
 * guards against, but for a drag whose success isn't visible as some
 * locator's bounding box moving — e.g. a swipe that pages to a different
 * view. The caller supplies its own success check instead.
 */
export async function dragMouseUntilTrue(
  page: Page,
  from: { x: number; y: number },
  to: { x: number; y: number },
  succeeded: () => Promise<boolean>,
  { attempts = 3, steps = 10 }: { attempts?: number; steps?: number } = {},
): Promise<void> {
  for (let attempt = 1; attempt <= attempts; attempt++) {
    await dragMouse(page, from, to, { steps });
    if (await succeeded()) return;
    if (attempt === attempts) {
      throw new Error(`Drag from (${from.x}, ${from.y}) to (${to.x}, ${to.y}) never succeeded after ${attempts} attempts`);
    }
  }
}
