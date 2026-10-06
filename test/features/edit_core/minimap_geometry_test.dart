import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/features/edit_core/minimap_geometry.dart';

/// The minimap draws at a fixed per-line pitch and scrolls a long document
/// under the panel, the way VS Code's proportional minimap does. That makes
/// three things load-bearing: the pitch ([minimapLineStride]), where the map's
/// window and the viewport band land for a frame ([minimapLayout]), and how a
/// point on the panel reads back as a line ([minimapLineAt]). All three are
/// pure, so they are tested here rather than through a widget — a widget test
/// would need the Rust editor renderer, which silently no-ops when its DLL is
/// absent.
void main() {
  // A 600px panel at density 1: three device pixels a line, two hundred lines.
  const panelHeight = 600.0;
  const densePanelHeight = 600.0;
  const density = 1.0;

  group('minimapLineStride', () {
    test('is fixed, whatever the document length', () {
      // The whole point of scrolling over compressing: a long file is drawn at
      // the same pitch as a short one instead of being squeezed until its
      // bars fall below a pixel.
      for (final lineCount in [10, 200, 1000, 100000]) {
        expect(
          minimapLineStride(devicePixelRatio: density),
          3,
          reason: '$lineCount',
        );
      }
    });

    test('the pitch scales with the device pixel ratio', () {
      expect(minimapLineStride(devicePixelRatio: 2), 1.5);
    });
  });

  group('minimapLinesFitting', () {
    test('is how many lines the panel spans, rounded down', () {
      expect(minimapLinesFitting(panelHeight: panelHeight, lineStride: 3), 200);
    });

    test('a panel too short for one line still gets one', () {
      expect(minimapLinesFitting(panelHeight: 1, lineStride: 3), 1);
    });
  });

  group('minimapLayout', () {
    MinimapLayout layoutFor(
      int lineCount,
      int first,
      int count, {
      double panel = panelHeight,
      double dpr = density,
    }) => minimapLayout(
      panelHeight: panel,
      lineCount: lineCount,
      devicePixelRatio: dpr,
      first: first,
      count: count,
    );

    group('a document that fits', () {
      test('is the whole map, with no scrolling', () {
        final layout = layoutFor(150, 40, 40);
        expect(layout.scrolls, isFalse);
        expect(layout.startLine, 0);
      });

      test('leaves the rest of the panel empty rather than stretching', () {
        // 150 lines at three pixels is 450 of a 600 panel, the same as VS
        // Code's proportional mode on a short file.
        final layout = layoutFor(150, 0, 40);
        expect(layout.bandTop, 0);
        expect(layout.bandHeight, 120);
        expect(150 * layout.lineStride, lessThan(panelHeight));
      });

      test('puts the band where its first line sits', () {
        final layout = layoutFor(150, 40, 40);
        expect(layout.bandTop, 40 * layout.lineStride);
      });
    });

    group('a document taller than the panel', () {
      test('scrolls, and reports so', () {
        final layout = layoutFor(1000, 480, 40);
        expect(layout.scrolls, isTrue);
      });

      test('keeps the whole pitch — the map never squeezes to fit', () {
        expect(layoutFor(1000, 480, 40).lineStride, 3);
      });

      test('at the top of the file the window is the top of the file', () {
        final layout = layoutFor(1000, 0, 40);
        expect(layout.startLine, 0);
        expect(layout.bandTop, 0);
        expect(layout.bandHeight, 120);
      });

      test(
        'half way down, the window trails the viewport by the slider travel',
        () {
          // 960 scrollable lines against a 480px travel, so half way is 240px;
          // at three pixels a line that is eighty lines of window.
          final layout = layoutFor(1000, 480, 40);
          expect(layout.bandTop, 240);
          expect(layout.startLine, 400);
        },
      );

      test('at the bottom the band ends flush with the panel', () {
        final layout = layoutFor(1000, 960, 40);
        expect(layout.bandTop + layout.bandHeight, panelHeight);
      });

      test(
        'the window trails the viewport by more than the band, never less',
        () {
          // The band is the slider rounded down to a whole line, so it sits at
          // or above the slider and the window always shows a screenful of the
          // file *above* the viewport rather than only the viewport itself.
          for (var first = 0; first < 960; first += 7) {
            final layout = layoutFor(1000, first, 40);
            expect(layout.startLine, lessThanOrEqualTo(first));
            expect(
              first - layout.startLine,
              lessThanOrEqualTo(layout.linesFitting),
            );
          }
        },
      );
    });

    group('the band stays inside the panel', () {
      // The invariant the whole scrolling arrangement exists to protect: the
      // map moves under the band, so the band has to be derived from where
      // the window actually is rather than from the viewport's line numbers
      // alone.
      test('at every scroll position of a long document', () {
        for (var first = 0; first <= 99960; first += 137) {
          final layout = layoutFor(100000, first, 40);
          expect(
            layout.bandTop,
            greaterThanOrEqualTo(0),
            reason: 'first=$first',
          );
          expect(
            layout.bandTop + layout.bandHeight,
            lessThanOrEqualTo(panelHeight + 1e-9),
            reason: 'first=$first',
          );
        }
      });

      test('at every scroll position of every panel density', () {
        for (final dpr in [1.0, 1.25, 1.5, 2.0, 3.0]) {
          for (var first = 0; first < 4000; first += 23) {
            final layout = layoutFor(4000, first, 33, dpr: dpr);
            expect(layout.bandTop, greaterThanOrEqualTo(0));
            expect(
              layout.bandTop + layout.bandHeight,
              lessThanOrEqualTo(densePanelHeight + 1e-9),
              reason: 'dpr=$dpr first=$first',
            );
          }
        }
      });

      test('with a viewport taller than the panel', () {
        // Wrapping can put more lines on screen than the map has room for.
        final layout = layoutFor(1000, 400, 900);
        expect(
          layout.bandTop + layout.bandHeight,
          lessThanOrEqualTo(panelHeight),
        );
      });

      test('with a viewport larger than the document', () {
        // A stale report that outran a file that just shrank.
        final layout = layoutFor(1000, 400, 1200);
        expect(layout.bandTop, greaterThanOrEqualTo(0));
        expect(
          layout.bandTop + layout.bandHeight,
          lessThanOrEqualTo(panelHeight),
        );
      });

      test('with a viewport reaching past the last line', () {
        final layout = layoutFor(1000, 5000, 40);
        expect(layout.bandTop, greaterThanOrEqualTo(0));
        expect(
          layout.bandTop + layout.bandHeight,
          lessThanOrEqualTo(panelHeight),
        );
        expect(layout.startLine, lessThanOrEqualTo(999));
      });

      test('with a negative first line', () {
        final layout = layoutFor(1000, -5, 40);
        expect(layout.bandTop, 0);
      });

      test('with a one pixel panel', () {
        final layout = layoutFor(1000, 500, 40, panel: 1);
        expect(layout.bandTop, greaterThanOrEqualTo(0));
        expect(layout.bandTop + layout.bandHeight, lessThanOrEqualTo(1 + 1e-9));
      });
    });

    group('degenerate documents', () {
      test('an empty document has nothing to draw', () {
        final layout = layoutFor(0, 0, 40);
        expect(layout.startLine, 0);
        expect(layout.bandHeight, 0);
        expect(layout.scrolls, isFalse);
      });

      test('an empty viewport still leaves a band', () {
        // No highlight at all reads as "the map forgot where I am" rather
        // than "the editor is between lines".
        final layout = layoutFor(1000, 400, 0);
        expect(layout.bandHeight, greaterThan(0));
      });

      test('a panel with no height still yields a usable pitch', () {
        final layout = layoutFor(1000, 0, 40, panel: 0);
        expect(layout.lineStride, 3);
        expect(layout.scrolls, isFalse);
      });
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

  group('minimapLineAt', () {
    test('reads the panel top as the start of the window, not line 0', () {
      // The whole reason hit-testing takes the window: on a scrolled map the
      // first line on screen is not the first line in the file.
      expect(
        minimapLineAt(y: 0, startLine: 4000, lineStride: 3, lineCount: 100000),
        4000,
      );
    });

    test('reads further down the panel as further into the file', () {
      expect(
        minimapLineAt(
          y: 300,
          startLine: 4000,
          lineStride: 3,
          lineCount: 100000,
        ),
        4100,
      );
    });

    test('reads the same point on an unscrolled map as before', () {
      expect(
        minimapLineAt(y: 300, startLine: 0, lineStride: 3, lineCount: 100000),
        100,
      );
    });

    test('clamps a click past the last line', () {
      expect(
        minimapLineAt(y: 999999, startLine: 0, lineStride: 3, lineCount: 500),
        499,
      );
    });

    test(
      'a click above the window names a line above it, not a repeat of it',
      () {
        // Dragging the band up past the window's top edge is how the reader
        // scrolls back, so the pointer resolving above [startLine] is the point
        // rather than a clamp: it names the line the pointer is actually over.
        expect(
          minimapLineAt(
            y: -100,
            startLine: 4000,
            lineStride: 3,
            lineCount: 100000,
          ),
          3967,
        );
      },
    );

    test('a click above the first line clamps to the first', () {
      expect(
        minimapLineAt(y: -100, startLine: 0, lineStride: 3, lineCount: 500),
        0,
      );
    });

    test('a pitch of zero cannot divide', () {
      expect(
        minimapLineAt(y: 100, startLine: 0, lineStride: 0, lineCount: 500),
        0,
      );
    });
  });

  group('minimapBarEdge', () {
    double edgeOf(int line, {double dpr = 2}) => minimapBarEdge(
      line: line,
      windowStart: 0,
      lineStride: 1.5,
      devicePixelRatio: dpr,
    );

    test("puts the window's first line at the picture's own top", () {
      expect(
        minimapBarEdge(
          line: 400,
          windowStart: 400,
          lineStride: 1.5,
          devicePixelRatio: 2,
        ),
        0,
      );
    });

    test('spans the picture exactly across the recorded lines', () {
      // The last recorded line's top edge is the recording's own height, so a
      // bar's bottom lands on the picture's bottom and none of them falls off.
      for (final dpr in <double>[1, 1.5, 2, 2.5, 3]) {
        expect(
          edgeOf(538, dpr: dpr),
          closeTo(538 * 1.5, 1 / dpr),
          reason: 'density $dpr',
        );
      }
    });

    test('does not shrink the recording as the display gets denser', () {
      // The bug this pins: dividing a logical position by the density a
      // second time laid a window's bars out across half the picture on a 2x
      // display, so the panel drew a fraction of the lines it had recorded.
      final atOne = edgeOf(538, dpr: 1);
      final atTwo = edgeOf(538, dpr: 2);
      final atThree = edgeOf(538, dpr: 3);
      expect(atTwo, closeTo(atOne, 1));
      expect(atThree, closeTo(atOne, 1));
    });

    test('stays on a whole device pixel', () {
      for (var line = 0; line < 40; line++) {
        final logical = edgeOf(line, dpr: 2);
        expect(
          logical * 2,
          closeTo((logical * 2).roundToDouble(), 1e-9),
          reason: 'line $line',
        );
      }
    });

    test('never lets a bar shrink below nothing', () {
      // A stride finer than a device pixel still leaves the edge monotonic, so
      // the `max(bottom - top, ...)` in the caller is the only floor needed.
      expect(edgeOf(100, dpr: 1), greaterThanOrEqualTo(0));
      expect(edgeOf(1, dpr: 1), greaterThanOrEqualTo(0));
    });
  });
}
