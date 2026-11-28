import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Shared responsive breakpoints and layout helpers for the Admin Panel
/// across Android phones (<600px), Android tablets (600–899px), and desktop (>=900px).
class AdminResponsive {
  static const double phoneBreakpoint = 600.0;
  static const double compactBreakpoint = 900.0;

  static bool isPhone(BuildContext context) =>
      MediaQuery.sizeOf(context).width < phoneBreakpoint;

  static bool isCompact(BuildContext context) =>
      MediaQuery.sizeOf(context).width < compactBreakpoint;

  /// Responsive horizontal & vertical page padding.
  static EdgeInsets pagePadding(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w < phoneBreakpoint) return const EdgeInsets.all(14);
    if (w < compactBreakpoint) return const EdgeInsets.all(18);
    return const EdgeInsets.all(24);
  }

  /// Safe clamped dialog width that never overflows small Android viewports.
  static double dialogWidth(BuildContext context, double preferred) {
    final maxAllowed = math.max(280.0, MediaQuery.sizeOf(context).width - 36.0);
    return math.min(preferred, maxAllowed);
  }

  /// Renders a responsive multi-column grid of KPI cards (4 cols desktop, 2 cols phone/tablet, 1 col tiny).
  static Widget kpiGrid(List<Widget> cards, {double spacing = 12}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final int cols = w >= 920 ? cards.length.clamp(1, 4) : (w >= 420 ? 2 : 1);
        final List<Widget> rows = [];
        for (int i = 0; i < cards.length; i += cols) {
          final slice = cards.sublist(i, math.min(i + cols, cards.length));
          rows.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (int j = 0; j < slice.length; j++) ...[
                    if (j > 0) SizedBox(width: spacing),
                    Expanded(child: slice[j]),
                  ],
                  if (slice.length < cols)
                    for (int k = 0; k < cols - slice.length; k++) ...[
                      SizedBox(width: spacing),
                      const Expanded(child: SizedBox.shrink()),
                    ],
                ],
              ),
            ),
          );
          if (i + cols < cards.length) rows.add(SizedBox(height: spacing));
        }
        return Column(children: rows);
      },
    );
  }
}
