/// Decides which way to switch days from a horizontal fling's
/// [primaryVelocity] (as reported by `DragEndDetails`).
///
/// A fast enough leftward fling (negative velocity) returns `1` (next day);
/// a fast enough rightward fling returns `-1` (previous day). Anything
/// slower than [threshold], or no velocity at all, returns `null`.
int? resolveSwipeDirection(double? primaryVelocity, {double threshold = 300}) {
  if (primaryVelocity == null) {
    return null;
  }
  if (primaryVelocity <= -threshold) {
    return 1;
  }
  if (primaryVelocity >= threshold) {
    return -1;
  }
  return null;
}
