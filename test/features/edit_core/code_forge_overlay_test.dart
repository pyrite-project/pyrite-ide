import 'dart:io';

import 'package:code_forge/code_forge/code_area.dart';
import 'package:code_forge/code_forge/root_overlay_portal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/features/edit_core/themed_code_forge.dart';

void main() {
  testWidgets('root overlay popup stays anchored above later siblings', (
    tester,
  ) async {
    var popupTaps = 0;
    var coveringPanelTaps = 0;
    Rect? overlayBoundsInTarget;

    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          children: [
            Positioned(
              left: 400,
              top: 80,
              width: 120,
              height: 160,
              child: Stack(
                children: [
                  CodeForgeRootOverlayPortal(
                    targetSize: const Size(120, 160),
                    overlayChild: Builder(
                      builder: (context) {
                        overlayBoundsInTarget =
                            CodeForgeRootOverlayGeometry.maybeOf(
                              context,
                            )!.overlayBoundsInTarget;
                        return Positioned(
                          left: 80,
                          top: 140,
                          width: 140,
                          height: 80,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => popupTaps += 1,
                            child: const ColoredBox(
                              color: Colors.white,
                              child: Text('completion-popup'),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 520,
              top: 240,
              width: 200,
              height: 240,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => coveringPanelTaps += 1,
                child: const ColoredBox(color: Colors.red),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pump();

    final popup = find.text('completion-popup');
    expect(overlayBoundsInTarget, const Rect.fromLTRB(-400, -80, 400, 520));
    expect(tester.getTopLeft(popup), const Offset(480, 220));
    expect(tester.getBottomRight(popup).dx, greaterThan(520));

    await tester.tap(popup);
    expect(popupTaps, 1);
    expect(coveringPanelTaps, 0);

    await tester.tapAt(const Offset(650, 400));
    expect(coveringPanelTaps, 1);
  });

  testWidgets('a popup anchored to the target bottom ignores the overlay size', (
    tester,
  ) async {
    // Regression: the overlay child used to be laid out in a box sized like the
    // whole root overlay instead of the target. `Positioned(top:)` measures from
    // the top of that box so it looked fine, but `Positioned(bottom:)` measures
    // from its bottom - which put every bottom-anchored popup (the LSP hover
    // when it flips above the cursor) hundreds of pixels below the word.
    const targetOrigin = Offset(200, 100);
    const targetSize = Size(300, 200);
    const bottomGap = 10.0;
    const anchorY = 150.0;
    const popupHeight = 60.0;

    // Measure after the frame instead of during build: a Builder runs before
    // its own child render object exists, so reading it there threw a null
    // check error and left the variable unassigned.
    final popupKey = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          children: [
            Positioned(
              left: targetOrigin.dx,
              top: targetOrigin.dy,
              width: targetSize.width,
              height: targetSize.height,
              child: Stack(
                children: [
                  CodeForgeRootOverlayPortal(
                    targetSize: targetSize,
                    overlayChild: Builder(
                      builder: (context) {
                        return Positioned(
                          bottom: targetSize.height - anchorY + bottomGap,
                          left: 0,
                          width: 200,
                          height: popupHeight,
                          child: ColoredBox(key: popupKey, color: Colors.white),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pump();

    // The popup's bottom edge must sit `bottomGap` above the anchor, measured
    // inside the 200px-tall target - not inside the 600px-tall test window.
    final popupTopLeft =
        (popupKey.currentContext!.findRenderObject()! as RenderBox)
            .localToGlobal(Offset.zero);
    expect(
      popupTopLeft.dy,
      targetOrigin.dy + (anchorY - bottomGap - popupHeight),
    );
  });

  test('the hover popup keeps a tight gap to the hovered line', () {
    // The hover popup is anchored to the line it documents, so a wide gap reads
    // as a detached popup. Guard against it silently creeping back up to the
    // generic popup gap.
    expect(kHoverAnchorGap, greaterThan(0));
    expect(kHoverAnchorGap, lessThan(8));
  });

  test('themed editor uses and can override outer hover radius', () {
    const customOuterRadius = BorderRadius.all(Radius.circular(32));
    final defaultStyle = buildThemedCodeForgeHoverDetailsStyle(
      foreground: Colors.white,
      background: Colors.black,
      primary: Colors.blue,
      fontSize: 15,
    );
    final customStyle = buildThemedCodeForgeHoverDetailsStyle(
      foreground: Colors.white,
      background: Colors.black,
      primary: Colors.blue,
      fontSize: 15,
      borderRadius: customOuterRadius,
    );
    final defaultShape = defaultStyle.shape as RoundedRectangleBorder;
    final customShape = customStyle.shape as RoundedRectangleBorder;

    expect(
      defaultShape.borderRadius,
      CodeForge.defaultHoverDetailsBorderRadius,
    );
    expect(customShape.borderRadius, customOuterRadius);
  });

  group('code block spacing follows the content around it', () {
    // A code block is a filled, outlined surface, so a margin on a side that
    // nothing fills reads as a stray empty band. Each gap therefore tracks the
    // content on its own side, and the one exception is the rule below.
    const lone = '```dart\nvoid main() {}\n```';
    const below = '```dart\nvoid main() {}\n```\n\nThen some prose.';
    const above = 'Some prose.\n\n```dart\nvoid main() {}\n```';
    const code = 'void main() {}';

    test('a block with nothing below it needs no bottom gap', () {
      expect(codeBlockHasContentBelow(lone, code), isFalse);
    });

    test('a block with prose below it keeps its bottom gap', () {
      expect(codeBlockHasContentBelow(below, code), isTrue);
    });

    test('content above a block is reported separately from content below', () {
      expect(
        codeBlockHasContentAbove(below, code),
        isFalse,
        reason: 'the gap tracks each side on its own',
      );
      expect(
        codeBlockHasContentAbove(above, code),
        isTrue,
        reason: 'prose running into a block is the visible lump',
      );
      expect(codeBlockHasContentAbove(lone, code), isFalse);
    });

    test('a rule below a block is recognised as a rule', () {
      // A rule is a line the author drew to divide the text, so a band between
      // the block and that rule only breaks the line the rule is there to draw.
      for (final rule in const [
        '---',
        '***',
        '___',
        '* * *',
        '- - -',
        '_____',
        '   ***',
      ]) {
        expect(
          codeBlockIsFollowedByRule('$lone\n\n$rule', code),
          isTrue,
          reason: '`$rule` is a thematic break',
        );
      }
    });

    test('prose below a block is not mistaken for a rule', () {
      for (final line in const [
        'Then some prose.',
        '-- not a rule, only two dashes',
        '- a list item',
        '***bold***',
        'a --- b',
      ]) {
        expect(
          codeBlockIsFollowedByRule('$lone\n\n$line', code),
          isFalse,
          reason: '`$line` still needs the gap',
        );
      }
    });

    test('only the first content below decides whether a rule follows', () {
      expect(
        codeBlockIsFollowedByRule('$lone\n\n---\n\nThen some prose.', code),
        isTrue,
        reason: 'the rule is what the block butts up against',
      );
      expect(
        codeBlockIsFollowedByRule('$below\n\n---', code),
        isFalse,
        reason: 'the prose is the first content below',
      );
    });

    test('trailing blank lines are not content', () {
      expect(
        codeBlockHasContentBelow('$below\n\n   \n', code),
        isTrue,
        reason: 'the prose still counts',
      );
      expect(
        codeBlockHasContentBelow('$lone\n\n\n', code),
        isFalse,
        reason: 'whitespace is not content',
      );
    });

    test('a neighbouring code block counts as content below', () {
      const two = '```dart\nfirst();\n```\n```dart\nsecond();\n```';
      expect(codeBlockHasContentBelow(two, 'first();'), isTrue);
      expect(codeBlockHasContentBelow(two, 'second();'), isFalse);
    });

    test('only the last block in a document loses its gap', () {
      const two =
          '```dart\nfirst();\n```\n\nSome prose.\n\n```dart\nsecond();\n```';
      expect(codeBlockHasContentBelow(two, 'first();'), isTrue);
      expect(codeBlockHasContentBelow(two, 'second();'), isFalse);
    });

    test('an unterminated block runs to the end of the document', () {
      expect(
        codeBlockHasContentBelow('```dart\nvoid main() {}', code),
        isFalse,
      );
      expect(
        codeBlockHasContentAbove(
          'Some prose.\n\n```dart\nvoid main() {}',
          code,
        ),
        isTrue,
        reason: 'an unterminated block can still follow prose',
      );
    });

    test('text outside any fence is not mistaken for a block', () {
      expect(codeBlockHasContentBelow('No fences at all here.', code), isFalse);
      expect(codeBlockHasContentAbove('No fences at all here.', code), isFalse);
    });
  });

  testWidgets('a popup code block gaps only the sides that hold content', (
    tester,
  ) async {
    // The rendered block is the contract: each gap tracks the content on its
    // own side, the corner is derived from the host, and a rule below the
    // block keeps it flush so the rule stays a single unbroken line.
    const code = 'void main() {}';
    Widget build(String source) => overlayCodeBlockConfig(
      source: source,
      outer: const BorderRadius.all(Radius.circular(12)),
      gap: 8,
      theme: const {},
      textStyle: const TextStyle(),
      styleNotMatched: const TextStyle(),
    ).builder!(code, 'dart');

    EdgeInsets marginOf() =>
        tester.widget<Container>(find.byType(Container).first).margin!
            as EdgeInsets;

    expect(
      kCodeBlockGap,
      8,
      reason: 'the gap beside a block is 4 more than it used to be',
    );

    const cases = <String, ({int top, int bottom})>{
      'nothing around': (top: 0, bottom: 0),
      'prose below': (top: 0, bottom: 8),
      'prose above': (top: 8, bottom: 0),
      'prose on both sides': (top: 8, bottom: 8),
      'rule below': (top: 0, bottom: 0),
      'prose above and a rule below': (top: 8, bottom: 0),
      'rule below and prose under it': (top: 0, bottom: 0),
      'a rule above': (top: 8, bottom: 0),
    };
    const sources = <String, String>{
      'nothing around': '```dart\nvoid main() {}\n```',
      'prose below': '```dart\nvoid main() {}\n```\n\nProse.',
      'prose above': 'Prose.\n\n```dart\nvoid main() {}\n```',
      'prose on both sides': 'Prose.\n\n```dart\nvoid main() {}\n```\n\nMore.',
      'rule below': '```dart\nvoid main() {}\n```\n\n---',
      'prose above and a rule below':
          'Prose.\n\n```dart\nvoid main() {}\n```\n\n***',
      'rule below and prose under it':
          '```dart\nvoid main() {}\n```\n\n---\n\nProse.',
      'a rule above': 'Prose.\n\n---\n\n```dart\nvoid main() {}\n```',
    };

    for (final name in cases.keys) {
      await tester.pumpWidget(MaterialApp(home: build(sources[name]!)));
      final margin = marginOf();
      expect(margin.top, cases[name]!.top, reason: '$name: top');
      expect(margin.bottom, cases[name]!.bottom, reason: '$name: bottom');
    }
  });
  test('a hover code block keeps its fill, outline, and nested corner', () {
    // A fenced code block is a surface nested inside the popup that holds it,
    // so its corner follows the same rule as every other nested surface:
    // outer == gap + inner, with gap equal to the real inset. The fill and the
    // hairline outline come from the editor theme so the block reads as code
    // and belongs to the theme it is shown in.
    //
    // The two things that must never regress are the outline surviving and the
    // corner staying concentric with the popup instead of collapsing to a
    // right angle.
    final decoration = overlayCodeBlockDecoration(
      const BorderRadius.all(Radius.circular(12)),
      gap: 8,
      background: const Color(0xFF1E1E1E),
      outline: const Color(0xFFD4D4D4),
    );

    expect(
      decoration.color,
      const Color(0xFF1E1E1E),
      reason: 'fill is restored',
    );
    expect(
      decoration.border,
      isNotNull,
      reason: 'hairline outline is restored',
    );
    expect(
      (decoration.border! as Border).top.color,
      const Color(0xFFD4D4D4),
      reason: 'outline comes from the editor theme',
    );
    expect(
      decoration.borderRadius,
      BorderRadius.circular(4),
      reason: 'outer 12 - gap 8, floored so it is never square',
    );
  });

  test('a code block corner stays rounded no matter how deep the gap is', () {
    // A deeply inset block would take outer - gap all the way to zero, and a
    // square corner is the one shape that visibly breaks the app's scale, so
    // the radius is clamped from below. It is also clamped from above so it can
    // never come out rounder than the popup that holds it.
    final shallow = overlayCodeBlockDecoration(
      const BorderRadius.all(Radius.circular(12)),
      gap: 2,
      background: const Color(0xFF1E1E1E),
      outline: const Color(0xFFD4D4D4),
    );
    expect(shallow.borderRadius, BorderRadius.circular(10), reason: '12 - 2');

    final deep = overlayCodeBlockDecoration(
      const BorderRadius.all(Radius.circular(12)),
      gap: 20,
      background: const Color(0xFF1E1E1E),
      outline: const Color(0xFFD4D4D4),
    );
    expect(deep.borderRadius, BorderRadius.circular(4), reason: 'floored');

    final tiny = overlayCodeBlockDecoration(
      const BorderRadius.all(Radius.circular(3)),
      gap: 1,
      background: const Color(0xFF1E1E1E),
      outline: const Color(0xFFD4D4D4),
    );
    expect(
      tiny.borderRadius,
      BorderRadius.circular(3),
      reason: 'never rounder than the surface holding it',
    );
    for (final radius in [
      shallow,
      deep,
      tiny,
    ].map((d) => (d.borderRadius! as BorderRadius).topLeft.x)) {
      expect(
        radius,
        greaterThan(0),
        reason: 'no code block may be a right angle',
      );
    }
  });
  test('a full-bleed popup row takes its corner from the card clip', () {
    // Completion and code-action rows run edge to edge inside their card, so no
    // gap separates a row from the surface holding it. Any radius of its own
    // A square row cannot mismatch the border at any radius.
    for (final corner in <double>[
      BorderRadius.zero.topLeft.x,
      BorderRadius.zero.topRight.x,
      BorderRadius.zero.bottomLeft.x,
      BorderRadius.zero.bottomRight.x,
    ]) {
      expect(corner, 0);
    }
  });

  test('every overlay outer radius is identical and inner = outer - gap', () {
    // The whole point of this scale: one outer radius for every popup the
    // editor draws, with anything nested inside derived as `outer - gap`. A
    // nested corner that grows larger than its parent is the visible bug this
    // guards against.
    final outer = CodeForge.defaultOverlayBorderRadius.topLeft.x;
    expect(CodeForge.defaultHoverDetailsBorderRadius.topLeft.x, outer);
    expect(
      nestedOverlayBorderRadius(outer).topLeft.x,
      moreOrLessEquals(outer - kOverlayPadding),
    );
    // A nested radius is never larger than the surface that contains it.
    for (final outerRadius in <double>[0, 2, 6, 8, 12, 16, 32]) {
      final nested = nestedOverlayBorderRadius(outerRadius).topLeft.x;
      expect(
        nested,
        lessThanOrEqualTo(outerRadius),
        reason: 'outer=$outerRadius',
      );
      expect(nested, greaterThanOrEqualTo(0), reason: 'outer=$outerRadius');
    }
    // Per-corner radii collapse to a single value, so no surface can show a
    // mixed outer/inner shape.
    for (final radius in <BorderRadius>[
      CodeForge.defaultOverlayBorderRadius,
      CodeForge.defaultHoverDetailsBorderRadius,
    ]) {
      expect(radius.topLeft.x, radius.topRight.x);
      expect(radius.topLeft.x, radius.bottomLeft.x);
      expect(radius.topLeft.x, radius.bottomRight.x);
    }
  });

  testWidgets('a popup with its own scrollbar shows exactly one thumb', (
    tester,
  ) async {
    // Regression: on Windows/macOS/Linux Flutter wraps every vertical
    // Scrollable in a Scrollbar of its own. That injected thumb only fades
    // in while scrolling and is stadium-shaped, so a popup that already
    // draws a rectangular RawScrollbar showed two stacked thumbs: the popup's
    // at rest, plus the injected one for as long as scrolling lasted.
    //
    // The platform one has to be suppressed for any subtree that supplies
    // its own themed scrollbar.

    final controller = ScrollController();
    addTearDown(controller.dispose);

    Widget popup({required Widget child}) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            height: 100,
            child: PopupScrollConfiguration(
              child: RawScrollbar(
                controller: controller,
                thumbVisibility: true,
                child: child,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpWidget(
      popup(
        child: ListView.builder(
          controller: controller,
          itemCount: 40,
          itemBuilder: (_, i) => SizedBox(height: 40, child: Text('row $i')),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(RawScrollbar), findsOneWidget);
    expect(find.byType(Scrollbar), findsNothing);

    // Scrolling is what made the duplicate appear, so it has to stay absent
    // once the view is actually scrolling.
    controller.jumpTo(200);
    await tester.pump();
    controller.jumpTo(400);
    await tester.pump();

    expect(find.byType(RawScrollbar), findsOneWidget);
    expect(find.byType(Scrollbar), findsNothing);
  });

  test(
    'every popup that draws its own scrollbar suppresses the platform one',
    () {
      // Each of these popups supplies a themed, always-visible RawScrollbar. If
      // one is left outside PopupScrollConfiguration, the desktop platform
      // scrollbar lands on the same edge and the popup grows a second thumb.
      final source = _withoutLineComments(
        File('code_forge/lib/code_forge/code_area.dart').readAsStringSync(),
      );

      var checked = 0;
      for (final match in RegExp('RawScrollbar[(]').allMatches(source)) {
        final open = match.end - 1;
        final close = _matchingParen(source, open);
        if (close == -1) continue;

        final enclosing = _enclosingCallStart(source, open);
        if (enclosing == null) continue;
        final wrapperOpen = source.lastIndexOf(
          'PopupScrollConfiguration(',
          enclosing,
        );
        final wrapperClose = _matchingParen(source, wrapperOpen);
        expect(
          wrapperClose > open,
          isTrue,
          reason:
              'a RawScrollbar at offset $open is not wrapped in '
              'PopupScrollConfiguration, so Flutter injects a second thumb '
              'into it on desktop',
        );
        checked++;
      }

      expect(
        checked,
        greaterThanOrEqualTo(5),
        reason:
            'hover, code action, completion, completion docs and signature '
            'help all scroll',
      );
    },
  );

  test('popup rows keep hover and selection on the same full-bleed box', () {
    // A popup row paints two backgrounds: the selected one comes from the row
    // container's own BoxDecoration, the hover one is ink from the InkWell it
    // contains. If that container also carried padding, the padding would inset
    // the ink while leaving the decoration full-bleed, so hover would read as a
    // narrower box than selection on the very same row.
    //
    // The content inset therefore lives *inside* the InkWell, leaving the row
    // container unpadded so both fills cover the same rectangle and the card's
    // clip gives them the outer corner.
    final source = _withoutLineComments(
      File('code_forge/lib/code_forge/code_area.dart').readAsStringSync(),
    );

    final rows = <String>[];
    for (final match in RegExp('Container[(]').allMatches(source)) {
      final open = match.end - 1;
      final close = _matchingParen(source, open);
      if (close == -1) continue;
      final body = source.substring(open, close);
      if (!body.contains('selectedBackgroundColor')) continue;

      final ink = body.indexOf('child: InkWell(');
      expect(
        ink,
        greaterThan(0),
        reason: 'a row that paints a selection is wrapped in an InkWell',
      );
      expect(
        body.substring(0, ink),
        isNot(contains('padding:')),
        reason:
            'padding on the row container insets the hover ink away from the card edge',
      );
      expect(
        body.substring(ink, body.indexOf('child: Row(')),
        contains('Padding('),
        reason: 'the content inset belongs inside the InkWell, not around it',
      );
      rows.add(match.group(0)!);
    }

    expect(
      rows.length,
      greaterThanOrEqualTo(2),
      reason:
          'both the completion list and the code-action list build this row',
    );
  });
}

/// Strips `//` line comments so a comment may talk about padding without the
/// source scan mistaking the prose for an argument.
String _withoutLineComments(String source) =>
    source.replaceAll(RegExp(r'//[^\n]*'), '');

/// Index of the `)` that closes the `(` at [open], or -1 when unbalanced.
int _matchingParen(String source, int open) {
  var depth = 0;
  for (var i = open; i < source.length; i++) {
    final char = source[i];
    if (char == '(') {
      depth++;
    } else if (char == ')') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return -1;
}

/// Offset of the start of the call expression that encloses [open], or null if
/// [open] is not inside a call's argument list.
int? _enclosingCallStart(String source, int open) {
  var depth = 0;
  for (var i = open; i >= 0; i--) {
    final char = source[i];
    if (char == ')') {
      depth++;
    } else if (char == '(') {
      if (depth == 0) return i;
      depth--;
    }
  }
  return null;
}
