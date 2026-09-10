import 'package:flutter/widgets.dart';

/// Below this viewport width, the app shows narrow (mobile) layouts —
/// bottom nav instead of a side rail, near-fullscreen modals instead of
/// centered dialogs, full-bleed lists instead of capped/centered ones.
const narrowBreakpoint = 700.0;

/// Whether [context]'s viewport is narrower than [narrowBreakpoint].
bool isNarrow(BuildContext context) =>
    MediaQuery.sizeOf(context).width < narrowBreakpoint;
