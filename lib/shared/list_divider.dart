import 'package:flutter/material.dart';
import 'package:pyrite_ide/shared/studio_text.dart';

class ListDivider extends StatelessWidget {
  const ListDivider(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextBodyMedium(label, color: Theme.of(context).colorScheme.secondary),
        Divider(),
      ],
    );
  }
}
