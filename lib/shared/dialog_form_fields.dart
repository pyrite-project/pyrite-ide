import 'package:flutter/material.dart';

/// Builds a dialog's body while owning the [TextEditingController]s it uses.
///
/// Every field gets a controller from [controllers], so no caller has to
/// create one. That matters because of when `showDialog` completes: its
/// future resolves inside `Route.didPop`, *before* the exit animation and the
/// dialog's unmount. A caller that disposes its own controller as soon as the
/// future resolves disposes one the dialog's `TextField` is still listening
/// to, and the resulting throw happens *inside* the route's teardown. The
/// framework then reports that interrupted unmount as an unrelated-looking
/// second assertion from `InheritedElement.debugDeactivated`
/// ("'_dependents.isEmpty': is not true), which sends you hunting through
/// inherited widgets for a bug that is really a controller outliving its
/// widget.
///
/// Disposing in [State.dispose] keeps each controller alive for exactly as
/// long as the widget that listens to it, whatever the dialog's animation or
/// teardown order turns out to be.
class DialogFormFields extends StatefulWidget {
  const DialogFormFields({
    super.key,
    this.initialValues = const [],
    this.selectAll = false,
    required this.builder,
  });

  /// Initial text per field, in field order. A shorter list leaves the
  /// remaining controllers empty.
  final List<String> initialValues;

  /// Whether each field starts with its whole text selected, so typing
  /// replaces it instead of appending. Use it for "rename"/"go to" prompts
  /// that are pre-filled with a value the user usually overwrites whole.
  final bool selectAll;

  /// Receives one controller per entry in [initialValues].
  final Widget Function(BuildContext context, List<TextEditingController> c)
  builder;

  @override
  State<DialogFormFields> createState() => _DialogFormFieldsState();
}

/// Builds a [TextEditingController] for a dialog field.
///
/// When [selectAll] is set the initial value starts fully selected so typing
/// replaces it instead of appending. The selection is assigned once, at
/// construction - doing it in `build()` would fight the user's own cursor
/// every time the field rebuilds.
TextEditingController _newController(String value, bool selectAll) {
  final controller = TextEditingController(text: value);
  if (selectAll) {
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: value.length,
    );
  }
  return controller;
}

class _DialogFormFieldsState extends State<DialogFormFields> {
  late final List<TextEditingController> _controllers = [
    for (final value in widget.initialValues)
      _newController(value, widget.selectAll),
  ];

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _controllers);
}
