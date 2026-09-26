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
      CodeForge().markdownCodeBlockBorderRadius,
      CodeForge.defaultMarkdownCodeBlockBorderRadius,
    );
    expect(
      defaultShape.borderRadius,
      CodeForge.defaultHoverDetailsBorderRadius,
    );
    expect(customShape.borderRadius, customOuterRadius);
  });
}
