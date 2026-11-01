import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/models/window_placement.dart';

void main() {
  group('WindowPlacement JSON', () {
    test('round-trips bounds and maximized flag', () {
      const placement = WindowPlacement(
        bounds: Rect.fromLTWH(120.5, 80.25, 1280, 720),
        maximized: true,
      );

      final json = placement.toJson();
      expect(json, {
        'x': 120.5,
        'y': 80.25,
        'width': 1280.0,
        'height': 720.0,
        'maximized': true,
      });

      expect(WindowPlacement.fromJson(json), placement);
    });

    test('accepts integer JSON numbers', () {
      final placement = WindowPlacement.fromJson({
        'x': 100,
        'y': 200,
        'width': 1280,
        'height': 800,
      });

      expect(placement, isNotNull);
      expect(placement!.bounds, const Rect.fromLTWH(100, 200, 1280, 800));
      expect(placement.maximized, isFalse);
    });

    test('rejects missing or non-numeric fields', () {
      expect(WindowPlacement.fromJson(null), isNull);
      expect(WindowPlacement.fromJson({}), isNull);
      expect(
        WindowPlacement.fromJson({
          'x': 0,
          'y': 0,
          'width': '1280',
          'height': 800,
        }),
        isNull,
      );
      expect(
        WindowPlacement.fromJson({
          'x': 0,
          'y': 0,
          'width': null,
          'height': 800,
        }),
        isNull,
      );
    });

    test('rejects non-finite coordinates and sizes', () {
      for (final bad in [
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        expect(
          WindowPlacement.fromJson({
            'x': bad,
            'y': 0,
            'width': 1280,
            'height': 800,
          }),
          isNull,
        );
        expect(
          WindowPlacement.fromJson({
            'x': 0,
            'y': 0,
            'width': bad,
            'height': 800,
          }),
          isNull,
        );
      }
    });

    test('rejects implausibly small sizes', () {
      expect(
        WindowPlacement.fromJson({'x': 0, 'y': 0, 'width': 319, 'height': 800}),
        isNull,
      );
      expect(
        WindowPlacement.fromJson({
          'x': 0,
          'y': 0,
          'width': 1280,
          'height': 299,
        }),
        isNull,
      );
      expect(
        WindowPlacement.fromJson({'x': 0, 'y': 0, 'width': 320, 'height': 300}),
        isNotNull,
      );
    });

    test('defaults maximized to false for unknown values', () {
      final placement = WindowPlacement.fromJson({
        'x': 0,
        'y': 0,
        'width': 1280,
        'height': 800,
        'maximized': 'yes',
      });
      expect(placement?.maximized, isFalse);
    });
  });

  group('WindowPlacement.clampToVisibleAreas', () {
    const primary = Rect.fromLTWH(0, 0, 1920, 1080);

    test('returns the placement unchanged when there are no displays', () {
      const placement = WindowPlacement(
        bounds: Rect.fromLTWH(-4000, -3000, 1200, 800),
        maximized: true,
      );

      final result = placement.clampToVisibleAreas(const []);
      expect(identical(result, placement), isTrue);
      expect(result.bounds, placement.bounds);
      expect(result.maximized, isTrue);
    });

    test('keeps a fully visible window in place', () {
      const placement = WindowPlacement(
        bounds: Rect.fromLTWH(100, 120, 1200, 800),
      );

      expect(placement.clampToVisibleAreas([primary]).bounds, placement.bounds);
    });

    test('centers an offscreen window on the primary display', () {
      const placement = WindowPlacement(
        bounds: Rect.fromLTWH(-5000, -5000, 1200, 800),
      );

      expect(
        placement.clampToVisibleAreas([primary]).bounds,
        const Rect.fromLTWH(360, 140, 1200, 800),
      );
    });

    test('centers a barely visible window (<25% visible)', () {
      // Visible intersection: 120 x 180 = 21,600 px, well under 25% of the
      // 960,000 px window.
      const placement = WindowPlacement(
        bounds: Rect.fromLTWH(1800, 900, 1200, 800),
      );

      expect(
        placement.clampToVisibleAreas([primary]).bounds,
        const Rect.fromLTWH(360, 140, 1200, 800),
      );
    });

    test('keeps a mostly visible window and pulls it inside the display', () {
      const placement = WindowPlacement(
        bounds: Rect.fromLTWH(800, 300, 1200, 800),
      );

      expect(
        placement.clampToVisibleAreas([primary]).bounds,
        const Rect.fromLTWH(720, 280, 1200, 800),
      );
    });

    test('grows windows below the minimum size', () {
      const placement = WindowPlacement(
        bounds: Rect.fromLTWH(100, 100, 200, 300),
      );

      expect(
        placement.clampToVisibleAreas([primary]).bounds,
        const Rect.fromLTWH(100, 100, 320, 480),
      );
    });

    test('honors a custom minimum size', () {
      const placement = WindowPlacement(
        bounds: Rect.fromLTWH(10, 10, 500, 400),
      );

      expect(
        placement.clampToVisibleAreas([
          primary,
        ], minimumSize: const Size(1000, 700)).bounds,
        const Rect.fromLTWH(10, 10, 1000, 700),
      );
    });

    test('uses the display with the largest intersection', () {
      const second = Rect.fromLTWH(1920, 0, 1920, 1080);
      const placement = WindowPlacement(
        bounds: Rect.fromLTWH(2000, 100, 1200, 800),
      );

      final result = placement.clampToVisibleAreas([primary, second]);
      expect(result.bounds, placement.bounds);
    });

    test('centers offscreen windows on the primary display, not another', () {
      const second = Rect.fromLTWH(1920, 0, 1920, 1080);
      const placement = WindowPlacement(
        bounds: Rect.fromLTWH(9000, 9000, 1200, 800),
      );

      expect(
        placement.clampToVisibleAreas([primary, second]).bounds,
        const Rect.fromLTWH(360, 140, 1200, 800),
      );
    });

    test('clamps an oversized window to the display origin', () {
      const placement = WindowPlacement(
        bounds: Rect.fromLTWH(-500, -500, 3000, 2000),
      );

      expect(
        placement.clampToVisibleAreas([primary]).bounds,
        const Rect.fromLTWH(0, 0, 3000, 2000),
      );
    });

    test('preserves the maximized flag while fitting bounds', () {
      const placement = WindowPlacement(
        bounds: Rect.fromLTWH(-5000, -5000, 1200, 800),
        maximized: true,
      );

      final result = placement.clampToVisibleAreas([primary]);
      expect(result.maximized, isTrue);
      expect(result.bounds, const Rect.fromLTWH(360, 140, 1200, 800));
    });

    test('ignores empty work areas', () {
      const placement = WindowPlacement(
        bounds: Rect.fromLTWH(-100, -100, 1200, 800),
      );

      expect(
        placement.clampToVisibleAreas([Rect.zero]).bounds,
        placement.bounds,
      );
    });
  });
}
