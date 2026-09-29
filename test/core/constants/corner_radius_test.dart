import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/constants/corner_radius.dart';
import 'package:pyrite_ide/core/services/app.dart';

void main() {
  group('AppCornerRadii', () {
    test('exposes one outer radius and one gap per style tier', () {
      for (final style in ThemeStyle.values) {
        final corners = AppCornerRadii.forStyle(style);
        expect(corners.outer, greaterThan(0), reason: '$style');
        expect(corners.gap, greaterThan(0), reason: '$style');
        // The inner radius is only useful if it stays non-negative.
        expect(corners.inner, greaterThanOrEqualTo(0), reason: '$style');
      }
    });

    test('outer radius equals gap plus inner radius for every tier', () {
      for (final style in ThemeStyle.values) {
        final corners = AppCornerRadii.forStyle(style);
        expect(
          corners.outer,
          moreOrLessEquals(corners.gap + corners.inner),
          reason: 'outer == gap + inner must hold for $style',
        );
      }
    });

    test('nestedRadius keeps outer == gap + inner for any gap', () {
      for (final style in ThemeStyle.values) {
        final corners = AppCornerRadii.forStyle(style);
        for (final gap in <double>[0, 1, 2, 4, 8, 12, 99]) {
          final expected = corners.outer - gap;
          expect(
            corners.nestedRadius(gap).topLeft.x,
            expected < 0 ? 0 : moreOrLessEquals(expected),
            reason: 'style=$style gap=$gap',
          );
        }
      }
    });

    test(
      'standard and comfortable share one scale; compact is one notch tighter',
      () {
        // Corner radius is part of the design language, not of density. Standard
        // and comfortable therefore use the same scale, and compact only trims
        // it slightly: enough that a dense layout stops looking over-rounded,
        // not so much that the app reads as a different product.
        for (final style in <ThemeStyle>[
          ThemeStyle.standard,
          ThemeStyle.comfortable,
        ]) {
          expect(
            AppCornerRadii.forStyle(style).outer,
            AppCornerRadii.comfortable.outer,
            reason: '$style must use the comfortable outer radius',
          );
          expect(
            AppCornerRadii.forStyle(style).gap,
            AppCornerRadii.comfortable.gap,
            reason: '$style must use the comfortable gap',
          );
        }

        final compact = AppCornerRadii.forStyle(ThemeStyle.compact);
        expect(compact.outer, AppCornerRadii.compact.outer);
        expect(compact.gap, AppCornerRadii.compact.gap);
        // Smaller than comfortable...
        expect(compact.outer, lessThan(AppCornerRadii.comfortable.outer));
        expect(compact.gap, lessThan(AppCornerRadii.comfortable.gap));
        // ...but only slightly, so switching tiers never reads as a redesign.
        expect(
          compact.outer,
          greaterThanOrEqualTo(AppCornerRadii.comfortable.outer - 2),
        );
      },
    );

    test('the compact tier stays part of the same corner scale', () {
      // The compact tier tightens the corner; it must not invent a new shape
      // language. Its inner radius stays in the same neighbourhood as every
      // other tier's, and the outer/gap/inner relationship still holds.
      final compact = AppCornerRadii.forStyle(ThemeStyle.compact);
      final comfortable = AppCornerRadii.forStyle(ThemeStyle.comfortable);
      expect(compact.inner, greaterThan(0));
      expect(
        compact.inner,
        greaterThanOrEqualTo(comfortable.inner - 2),
        reason: 'compact must not collapse the nested radius',
      );
      expect(
        compact.outer,
        moreOrLessEquals(compact.gap + compact.inner),
        reason: 'outer == gap + inner must hold for compact',
      );
    });

    test('no tier is square: every outer radius stays visibly round', () {
      for (final style in ThemeStyle.values) {
        expect(
          AppCornerRadii.forStyle(style).outer,
          greaterThanOrEqualTo(6),
          reason: '$style must not look right-angled',
        );
        // The gap is real spacing between two nested surfaces, so it has to
        // survive the compact trim too: with outer 10 and a gap of 6 or more
        // the inner corner would collapse to nothing.
        expect(
          AppCornerRadii.forStyle(style).gap,
          lessThan(AppCornerRadii.forStyle(style).outer),
          reason: '$style must leave room for a nested corner',
        );
      }
    });

    test('all top-level surfaces of a tier share one outer radius', () {
      for (final style in ThemeStyle.values) {
        final corners = AppCornerRadii.forStyle(style);
        // Any two outer surfaces must be indistinguishable in shape, no
        // matter which accessor a call site happens to use.
        expect(corners.outerRadius, corners.outerRadius);
        expect(
          corners.outerRadius.topLeft.x,
          corners.outerRadius.topRight.x,
          reason: 'outer radius must be uniform on every corner ($style)',
        );
        expect(corners.outerRadius.topLeft.x, corners.outer);
      }
    });

    test('nested radius is never larger than its parent radius', () {
      for (final style in ThemeStyle.values) {
        final corners = AppCornerRadii.forStyle(style);
        expect(corners.inner, lessThanOrEqualTo(corners.outer));
        for (final gap in <double>[0, 2, 4, 8]) {
          expect(
            corners.nestedRadius(gap).topLeft.x,
            lessThanOrEqualTo(corners.outer),
            reason: 'style=$style gap=$gap',
          );
        }
      }
    });

    testWidgets('context resolves the extension installed on the theme', (
      tester,
    ) async {
      const corners = AppCornerRadii(outer: 10, gap: 3);
      late BuildContext captured;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            extensions: const <ThemeExtension<dynamic>>[corners],
          ),
          home: Builder(
            builder: (context) {
              captured = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(captured.corners.outer, 10);
      expect(captured.outerCorners.topLeft.x, 10);
      // inner == outer - gap
      expect(captured.innerCorners.topLeft.x, 7);
      expect(captured.nestedCorners(4).topLeft.x, 6);
    });

    testWidgets('context falls back to the standard scale when unthemed', (
      tester,
    ) async {
      late BuildContext captured;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              captured = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(captured.corners.outer, AppCornerRadii.fallback.outer);
    });
  });
}
