import 'package:flutter/material.dart';

/// Host-owned draggable split layout for plugin component trees.
class PluginSplitView extends StatefulWidget {
  const PluginSplitView({
    super.key,
    required this.children,
    required this.direction,
    this.initialRatio = 0.5,
  });

  final List<Widget> children;
  final Axis direction;
  final double initialRatio;

  @override
  State<PluginSplitView> createState() => PluginSplitViewState();
}

class PluginSplitViewState extends State<PluginSplitView> {
  static const double _dividerExtent = 6;
  static const double _minimumRatio = 0.05;

  late List<double> _ratios = _initialRatios();

  List<double> get ratios => List.unmodifiable(_ratios);

  bool setRatio(int index, double ratio) {
    if (index < 0 || index >= _ratios.length || _ratios.length < 2) {
      return false;
    }
    final next = List<double>.from(_ratios);
    final remaining = 1 - ratio.clamp(_minimumRatio, 1 - _minimumRatio);
    final otherTotal = 1 - next[index];
    next[index] = 1 - remaining;
    for (var i = 0; i < next.length; i++) {
      if (i == index) continue;
      next[i] = otherTotal <= 0
          ? remaining / (next.length - 1)
          : next[i] / otherTotal * remaining;
    }
    return setRatios(next);
  }

  bool setRatios(List<double> ratios) {
    if (ratios.length != _ratios.length || ratios.any((value) => value <= 0)) {
      return false;
    }
    final total = ratios.fold<double>(0, (sum, value) => sum + value);
    if (total <= 0) return false;
    setState(() => _ratios = [for (final value in ratios) value / total]);
    return true;
  }

  void resetRatios() => setState(() => _ratios = _initialRatios());

  List<double> _initialRatios() {
    final count = widget.children.length;
    if (count == 0) return const [];
    if (count == 1) return const [1];
    final first = widget.initialRatio.clamp(_minimumRatio, 1 - _minimumRatio);
    final remaining = (1 - first) / (count - 1);
    return [first, for (var i = 1; i < count; i++) remaining];
  }

  @override
  void didUpdateWidget(covariant PluginSplitView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.children.length != widget.children.length) {
      _ratios = _initialRatios();
    }
  }

  void _drag(int divider, double delta, double extent) {
    if (extent <= 0) return;
    final pairTotal = _ratios[divider] + _ratios[divider + 1];
    final nextLeft = (_ratios[divider] + delta / extent).clamp(
      _minimumRatio,
      pairTotal - _minimumRatio,
    );
    setState(() {
      _ratios[divider] = nextLeft;
      _ratios[divider + 1] = pairTotal - nextLeft;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.children.isEmpty) return const SizedBox.shrink();
    if (widget.children.length == 1) return widget.children.single;

    return LayoutBuilder(
      builder: (context, constraints) {
        final vertical = widget.direction == Axis.vertical;
        final bounded = vertical
            ? constraints.hasBoundedHeight
            : constraints.hasBoundedWidth;
        if (!bounded) {
          return Flex(
            direction: widget.direction,
            mainAxisSize: MainAxisSize.min,
            children: widget.children,
          );
        }
        final extent = vertical ? constraints.maxHeight : constraints.maxWidth;
        return Flex(
          direction: widget.direction,
          children: [
            for (var index = 0; index < widget.children.length; index++) ...[
              Expanded(
                flex: (_ratios[index] * 10000).round().clamp(1, 10000),
                child: widget.children[index],
              ),
              if (index < widget.children.length - 1)
                _divider(context, index, extent),
            ],
          ],
        );
      },
    );
  }

  Widget _divider(BuildContext context, int index, double extent) {
    final vertical = widget.direction == Axis.vertical;
    return MouseRegion(
      cursor: vertical
          ? SystemMouseCursors.resizeUpDown
          : SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        key: ValueKey('plugin-split-divider-$index'),
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (details) => _drag(
          index,
          vertical ? details.delta.dy : details.delta.dx,
          extent,
        ),
        child: SizedBox(
          width: vertical ? double.infinity : _dividerExtent,
          height: vertical ? _dividerExtent : double.infinity,
          child: Center(
            child: ColoredBox(
              color: Theme.of(context).dividerColor,
              child: SizedBox(
                width: vertical ? double.infinity : 1,
                height: vertical ? 1 : double.infinity,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
