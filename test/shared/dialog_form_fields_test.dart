import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/shared/dialog_form_fields.dart';

/// [DialogFormFields] is the single place dialog field controllers are owned.
/// These tests pin the contract every dialog depends on: the controllers must
/// outlive the dialog's own unmount, because `showDialog` completes its future
/// before that unmount happens.
void main() {
  testWidgets('controllers stay usable until the dialog is fully gone', (
    tester,
  ) async {
    final errors = <FlutterErrorDetails>[];
    final prevOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      errors.add(details);
      prevOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = prevOnError);

    final popped = Completer<String?>();

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              final value = await showDialog<String>(
                context: context,
                builder: (context) => DialogFormFields(
                  initialValues: ['seed'],
                  selectAll: true,
                  builder: (context, c) => AlertDialog(
                    content: TextField(controller: c[0], autofocus: true),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(c[0].text),
                        child: const Text('ok'),
                      ),
                    ],
                  ),
                ),
              );
              popped.complete(value);
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Change the value, then submit from inside the dialog.
    await tester.enterText(find.byType(TextField), 'typed');
    await tester.pump();
    await tester.tap(find.text('ok'));
    await tester.pump();

    // The route is popping but its subtree is still mounted and rebuilding.
    await tester.pump(const Duration(milliseconds: 50));

    expect(await popped.future, 'typed');

    // Let the exit animation finish and the subtree unmount.
    await tester.pumpAndSettle();

    expect(
      errors.map((d) => d.exceptionAsString()).toList(),
      isEmpty,
      reason:
          'a dialog that owns its controllers must tear down cleanly; a '
          "'used after being disposed' error means one was disposed before "
          'the TextField listening to it went away.\n'
          '${errors.map((d) => d.exceptionAsString()).join('\n---\n')}',
    );
  });

  testWidgets('selectAll pre-selects the initial value', (tester) async {
    late TextSelection selection;

    await tester.pumpWidget(
      MaterialApp(
        home: DialogFormFields(
          initialValues: ['hello'],
          selectAll: true,
          builder: (context, c) {
            selection = c[0].selection;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(selection.baseOffset, 0);
    expect(selection.extentOffset, 'hello'.length);
  });

  testWidgets('without selectAll the caret sits at the end', (tester) async {
    late TextSelection selection;

    await tester.pumpWidget(
      MaterialApp(
        home: DialogFormFields(
          initialValues: ['hello'],
          builder: (context, c) {
            selection = c[0].selection;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(selection.isCollapsed, isTrue);
  });

  testWidgets('one controller per initial value', (tester) async {
    late int count;

    await tester.pumpWidget(
      MaterialApp(
        home: DialogFormFields(
          initialValues: const ['a', 'b', 'c'],
          builder: (context, c) {
            count = c.length;
            expect(c[1].text, 'b');
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(count, 3);
  });
}
