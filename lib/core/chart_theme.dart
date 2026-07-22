import 'package:flutter/material.dart';

import 'theme.dart';

/// Chart palette and mark specs for the Analytics tab (Phase 8.8).
///
/// ## Why these hexes
///
/// The app's own accent colours were tried first and **failed** validation on
/// the newsprint paper surface (`#F7F0E4`): `primaryGreen ↔ redAccent` collapse
/// to ΔE 4.4 under protanopia — the classic red/green confusion — and both sit
/// under the chroma floor, reading as grey rather than doing identity work.
/// They remain correct for UI accents, where nothing depends on telling two of
/// them apart; they are not safe as series colours.
///
/// These three are the documented categorical slots, snapped one step darker
/// because our paper surface is darker than the reference white. Validated
/// all-pairs against `#F7F0E4`:
///
/// * lightness band  PASS (3/3 inside L 0.43–0.77)
/// * chroma floor    PASS (3/3 ≥ 0.10)
/// * CVD separation  PASS (worst all-pairs ΔE 9.4, deutan)
/// * normal vision   PASS (worst all-pairs ΔE 22.2)
/// * contrast        PASS (3/3 ≥ 3:1)
///
/// Three slots is also the cap: adding the 4th documented slot fails the
/// normal-vision floor (yellow ↔ orange, ΔE 13.7). No chart here needs more —
/// two series maximum, plus one for a single-series accent. A fourth category
/// folds into `Other`, it never gets a generated hue.
class ChartTheme {
  ChartTheme._();

  /// Categorical slot 1 — assigned in fixed order, never by rank, so a filter
  /// that drops a series never repaints the survivors.
  static const Color series1 = Color(0xFF256ABF); // blue
  static const Color series2 = Color(0xFFD95926); // orange
  static const Color series3 = Color(0xFF199E70); // aqua

  /// The surface these were validated against.
  static const Color surface = AppTheme.paper;

  /// Recessive chrome: hairline, solid, one shade off the surface. Never
  /// dashed — dashing reads as "projection" when it is only a grid.
  static const Color grid = AppTheme.paperMuted;
  static const Color axis = AppTheme.inkSoft;

  /// Ink for values, labels, and legends. Text never wears the series colour;
  /// the mark beside it carries identity.
  static const Color labelInk = AppTheme.ink;
  static const Color mutedInk = AppTheme.inkSoft;

  /// A partial or not-yet-real period (current month, unavailable snapshot).
  /// Distinguished by opacity *and* an explicit written note, never colour
  /// alone.
  static const double partialOpacity = 0.45;

  static const double barWidth = 14;
  static const double lineWidth = 2;
  static const double markerRadius = 4;

  /// Slot for a series index. Beyond the third the caller must fold into
  /// `Other` — cycling would hand two series the same identity.
  static Color seriesColor(int index) {
    assert(index >= 0 && index < 3,
        'Only three validated categorical slots exist; fold the tail into Other.');
    return switch (index) {
      0 => series1,
      1 => series2,
      _ => series3,
    };
  }

  static TextStyle axisLabel(BuildContext context) =>
      Theme.of(context).textTheme.labelSmall?.copyWith(color: mutedInk) ??
      const TextStyle(fontSize: 10, color: mutedInk);
}
