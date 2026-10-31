import 'package:flutter/material.dart';

/// One action of [PyriteFloatingToolbar].
class PyriteFloatingToolbarAction {
  const PyriteFloatingToolbarAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
}

/// Floating pill toolbar for editor-wide confirmations (pending upload and
/// download).
///
/// The packaged M3 toolbar sized each button tightly around its content, so
/// the button's highlight background hugged the icon and label and read as a
/// thin sliver inside the pill. Here every action fills the pill up to a
/// small inset instead, so the highlight is a full-height chip several sizes
/// larger than the content it wraps.
class PyriteFloatingToolbar extends StatelessWidget {
  const PyriteFloatingToolbar({super.key, required this.actions});

  final List<PyriteFloatingToolbarAction> actions;

  @override
  Widget build(BuildContext context) {
    assert(actions.isNotEmpty, 'PyriteFloatingToolbar requires an action');
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 2,
      color: scheme.primaryContainer,
      shape: const StadiumBorder(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < actions.length; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              _ToolbarButton(action: actions[i]),
            ],
          ],
        ),
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({required this.action});

  final PyriteFloatingToolbarAction action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = scheme.onPrimaryContainer;
    return Semantics(
      button: true,
      label: action.label,
      child: Material(
        color: Colors.transparent,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          hoverColor: foreground.withValues(alpha: 0.08),
          focusColor: foreground.withValues(alpha: 0.10),
          highlightColor: foreground.withValues(alpha: 0.10),
          onTap: action.onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(action.icon, size: 18, color: foreground),
                const SizedBox(width: 8),
                Text(
                  action.label,
                  style: TextStyle(color: foreground, fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
