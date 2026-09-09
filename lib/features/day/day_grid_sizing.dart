/// Picks the pixel height of a single 15-minute slot so the day grid fills
/// [availableHeight] when it can, without ever shrinking a slot below
/// [minSlotHeight] (below that, a slot stops being visually distinct).
///
/// When [minSlotHeight] wins, the grid's total height exceeds
/// [availableHeight] and the caller is expected to make it scrollable.
double resolveSlotHeight({
  required double availableHeight,
  required int slotCount,
  required double minSlotHeight,
}) {
  final fitted = availableHeight / slotCount;
  return fitted > minSlotHeight ? fitted : minSlotHeight;
}
