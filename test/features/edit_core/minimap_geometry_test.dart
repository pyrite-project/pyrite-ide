import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/features/edit_core/minimap_geometry.dart';

/// The minimap compresses the whole document into its visible panel, which
/// makes two things load-bearing: the per-line stride that does the
/// compressing ([minimapLineStride]) and where the viewport band lands inside
/// the panel ([minimapViewportBand]). Both are pure, so they are tested here
/// rather than through a widget — a widget test would need the Rust editor
/// renderer, which silently no-ops when its DLL is absent.
void main() {
  group('minimapLineStride', () {
    test('a short document takes the capped stride', () {
      expect(
        minimapLineStride(
          panelHeight: 600,
          lineCount: 100,
          devicePixelRatio: 1,
        ),
        3,
      );
    });

    test('the cap scales with the device pixel ratio', () {
      expect(
        minimapLineStride(
          panelHeight: 600,
          lineCount: 100,
          devicePixelRatio: 2,
        ),
        1.5,
      );
    });

    test('a long document compresses to fit the panel exactly', () {
      final stride = minimapLineStride(
        panelHeight: 600,
        lineCount: 1200,
        devicePixelRatio: 1,
      );
      expect(stride, 0.5);
      expect(stride * 1200, 600);
    });

    test('a very long document still fits the panel', () {
      // The one invariant fit-to-panel cannot break: lineCount * stride never
      // exceeds the panel, or the tail of the document would be off the map.
      final stride = minimapLineStride(
        panelHeight: 600,
        lineCount: 100000,
        devicePixelRatio: 1,
      );
      expect(stride * 100000, closeTo(600, 1e-6));
      expect(stride, lessThan(3));
    });

    test('an empty document takes the cap', () {
      expect(
        minimapLineStride(panelHeight: 600, lineCount: 0, devicePixelRatio: 1),
        3,
      );
    });

    test('a panel with no height cannot divide; falls back to the cap', () {
      expect(
        minimapLineStride(panelHeight: 0, lineCount: 100, devicePixelRatio: 1),
        3,
      );
    });
  });

  group('minimapViewportBand', () {
    test('the band sits where its first line sits', () {
      final band = minimapViewportBand(
        first: 100,
        count: 40,
        lineStride: 0.5,
        panelHeight: 600,
      );
      expect(band.top, 50);
      expect(band.height, 20);
    });

    test('the band at the top of the document starts at the top', () {
      final band = minimapViewportBand(
        first: 0,
        count: 40,
        lineStride: 2,
        panelHeight: 200,
      );
      expect(band.top, 0);
      expect(band.height, 80);
    });

    test('a viewport taller than the panel is clamped to the panel', () {
      // A short file in a tall window, or wrapping that puts more lines on
      // screen than the map has room for: the band must not paint past the
      // bottom edge, which is the one thing a "where am I" cue must never do.
      final band = minimapViewportBand(
        first: 0,
        count: 500,
        lineStride: 2,
        panelHeight: 200,
      );
      expect(band.height, 200);
      expect(band.top, 0);
    });

    test('a band pushed past the bottom is pulled back inside', () {
      // Defensive: a viewport report that outran the document (a stale render,
      // a shrinking file) must still land inside the panel.
      final band = minimapViewportBand(
        first: 990,
        count: 40,
        lineStride: 2,
        panelHeight: 200,
      );
      expect(band.top + band.height, lessThanOrEqualTo(200));
    });

    test('a negative first line clamps to the top', () {
      final band = minimapViewportBand(
        first: -5,
        count: 40,
        lineStride: 2,
        panelHeight: 200,
      );
      expect(band.top, 0);
    });

    test('an empty viewport still leaves a one pixel band', () {
      // Zero lines would mean no highlight at all, which reads as "the map
      // forgot where I am" rather than "the editor is between lines".
      final band = minimapViewportBand(
        first: 10,
        count: 0,
        lineStride: 2,
        panelHeight: 200,
      );
      expect(band.height, 1);
    });
  });
}
