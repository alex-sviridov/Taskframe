import 'package:flutter/widgets.dart';

/// Below this viewport width, the app shows narrow (mobile) layouts —
/// bottom nav instead of a side rail, near-fullscreen modals instead of
/// centered dialogs, full-bleed lists instead of capped/centered ones.
///
/// [isNarrow] and this breakpoint measure the full window/viewport width
/// via [MediaQuery], which is the right signal for top-level layout
/// decisions (nav chrome, modal shape) made before any shell inset exists.
/// It is the *wrong* signal for a widget that might be nested inside chrome
/// that insets the available space — e.g. behind a `NavigationRail`, which
/// eats part of the window's width without changing `MediaQuery`'s
/// reported size. A widget in that position should measure its own
/// available width instead (e.g. via `LayoutBuilder`'s `constraints.maxWidth`
/// or its own `RenderBox`), not the window.
const narrowBreakpoint = 700.0;

/// Whether [context]'s viewport is narrower than [narrowBreakpoint].
bool isNarrow(BuildContext context) =>
    MediaQuery.sizeOf(context).width < narrowBreakpoint;
