import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/pylsp/completion.dart';
import 'package:pyrite_ide/core/services/pylsp/main.dart';
import 'package:re_editor/re_editor.dart';

class LspCompletionPromptsBuilder implements CodeAutocompletePromptsBuilder {
  const LspCompletionPromptsBuilder();

  @override
  CodeAutocompleteEditingValue? build(
    BuildContext context,
    CodeLine codeLine,
    CodeLineSelection selection,
  ) {
    if (!selection.isCollapsed) return null;

    final text = codeLine.text;
    final cursor = selection.extentOffset.clamp(0, text.length);
    final before = cursor == 0 ? '' : text.substring(0, cursor);

    final triggeredByDot = before.endsWith('.');
    final input = triggeredByDot ? '' : _extractIdentifierSuffix(before);
    // print(input);

    if (input.isEmpty && !triggeredByDot) return null;

    return CodeAutocompleteEditingValue(input: input, prompts: [], index: 0);
  }
}

String _extractIdentifierSuffix(String text) {
  var i = text.length;
  while (i > 0) {
    final code = text.codeUnitAt(i - 1);
    final isDigit = code >= 48 && code <= 57;
    final isUpper = code >= 65 && code <= 90;
    final isLower = code >= 97 && code <= 122;
    final isUnderscore = code == 95;
    if (!(isDigit || isUpper || isLower || isUnderscore)) break;
    i--;
  }
  return text.substring(i);
}

class LspAutocompleteListView extends ConsumerStatefulWidget
    implements PreferredSizeWidget {
  const LspAutocompleteListView({
    super.key,
    required this.notifier,
    required this.onSelected,
    required this.uri,
    required this.editorController,
  });

  final ValueNotifier<CodeAutocompleteEditingValue>? notifier;
  final ValueChanged<CodeAutocompleteResult> onSelected;
  final String uri;
  final CodeLineEditingController editorController;

  static const double _width = 320;
  static const double _maxHeight = 220;
  static const double _itemHeight = 25;

  @override
  Size get preferredSize => const Size(_width, _maxHeight);

  @override
  ConsumerState<LspAutocompleteListView> createState() =>
      _LspAutocompleteListViewState();
}

class _LspAutocompleteListViewState
    extends ConsumerState<LspAutocompleteListView> {
  int _requestEpoch = 0;
  late final ScrollController _scrollController;
  int _lastSelectedIndex = 0;
  Timer? _debounceTimer; // 添加防抖定时器

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    widget.notifier?.addListener(_onValueChanged);
    _fetch();
  }

  @override
  void dispose() {
    widget.notifier?.removeListener(_onValueChanged);
    _scrollController.dispose();
    _debounceTimer?.cancel(); // 取消防抖定时器
    super.dispose();
  }

  void _onValueChanged() {
    _debounceTimer?.cancel(); // 取消之前的定时器
    _debounceTimer = Timer(const Duration(milliseconds: 100), () {
      // 300毫秒后执行请求
      _fetch();
    });

    final selectedIndex = widget.notifier?.value.index;
    if (selectedIndex != null) {
      setState(() {});
      if (selectedIndex != _lastSelectedIndex) {
        _lastSelectedIndex = selectedIndex;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _ensureIndexVisible(selectedIndex);
        });
      }
    }
  }

  // ... 其他方法保持不变

  Future<void> _fetch() async {
    final epoch = ++_requestEpoch;

    final selection = widget.editorController.selection;
    if (!selection.isCollapsed) return;

    final client = await PythonLspService(ref).maybeClient;
    if (!mounted || epoch != _requestEpoch) return;

    if (client == null) {
      _setPrompts([]);
      return;
    }

    List<LspCompletionItem> items;
    try {
      final lineText =
          widget.editorController.codeLines[selection.extentIndex].text;
      final triggerCharacter =
          selection.extentOffset > 0 &&
              selection.extentOffset <= lineText.length &&
              lineText.codeUnitAt(selection.extentOffset - 1) == 46
          ? '.'
          : null;
      // print(triggerCharacter);

      items = await fetchCompletions(
        client: client,
        uri: widget.uri,
        line: selection.extentIndex,
        character: selection.extentOffset,
        triggerCharacter: triggerCharacter,
      );
      print(
        'Fetched ${items.length} completion items with trigger: $triggerCharacter',
      );
      for (var item in items) {
        print('  - ${item.label} (${item.kind})');
      }
    } catch (_) {
      items = const [];
    }

    if (!mounted || epoch != _requestEpoch) return;

    final input = widget.notifier?.value.input;
    if (input != null) {
      final filtered = input.isEmpty
          ? items
          : items
                .where((item) {
                  final label = item.label;
                  return label.length >= input.length &&
                      label.substring(0, input.length).toLowerCase() ==
                          input.toLowerCase();
                })
                .toList(growable: false);

      final prompts = filtered
          .take(80)
          .map(
            (item) => LspCompletionPrompt(
              label: item.label,
              detail: item.detail,
              insertText: item.insertText,
              input: input,
            ),
          )
          .toList(growable: false);

      _setPrompts(prompts.isEmpty ? [] : prompts);
    }
  }

  void _setPrompts(List<CodePrompt> prompts) {
    final value = widget.notifier?.value;
    if (value != null) {
      widget.notifier?.value = value.copyWith(prompts: prompts);
    }

    /*
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
    });
    */
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.notifier?.value;
    final prompts = value?.prompts;

    if (value == null || value.prompts.isEmpty) {
      return SizedBox.shrink();
    }

    return ConstrainedBox(
      constraints: const BoxConstraints.tightFor(
        width: LspAutocompleteListView._width,
        height: LspAutocompleteListView._maxHeight,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          border: Border.all(
            color: Theme.of(context).colorScheme.outline,
            width: 1,
          ),
          borderRadius: BorderRadius.circular(5),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: ListView.builder(
            controller: _scrollController,
            itemExtent: LspAutocompleteListView._itemHeight,
            itemCount: prompts!.length,
            itemBuilder: (context, index) {
              final prompt = prompts[index];
              final selected = index == value.index;
              final enabled = prompt is! LspStatusPrompt;

              final fg = selected
                  ? Theme.of(context).colorScheme.onPrimary
                  : Theme.of(context).colorScheme.onSurfaceVariant;
              final bg = selected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.surfaceContainerHighest;
              final detailColor = selected
                  ? Theme.of(context).colorScheme.onPrimary
                  : Theme.of(context).colorScheme.onSurfaceVariant;

              return MouseRegion(
                cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: enabled
                      ? () {
                          widget.onSelected(prompt.autocomplete);
                        }
                      : null,
                  child: Container(
                    color: bg,
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    alignment: Alignment.centerLeft,
                    child: _PromptRow(
                      prompt: prompt,
                      fg: fg,
                      detailColor: detailColor,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  void _ensureIndexVisible(int index) {
    final controller = _scrollController;
    if (!controller.hasClients) return;

    final itemExtent = LspAutocompleteListView._itemHeight;
    final itemTop = index * itemExtent;
    final itemBottom = itemTop + itemExtent;
    final viewTop = controller.offset;
    final viewBottom = viewTop + controller.position.viewportDimension;

    if (itemTop < viewTop) {
      controller.jumpTo(itemTop);
      return;
    }
    if (itemBottom > viewBottom) {
      controller.jumpTo(itemBottom - controller.position.viewportDimension);
    }
  }
}

class _PromptRow extends StatelessWidget {
  const _PromptRow({
    required this.prompt,
    required this.fg,
    required this.detailColor,
  });

  final CodePrompt prompt;
  final Color fg;
  final Color detailColor;

  @override
  Widget build(BuildContext context) {
    if (prompt is LspStatusPrompt) {
      final status = prompt as LspStatusPrompt;
      return Text(
        status.message,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: fg),
      );
    }

    final item = prompt as LspCompletionPrompt;
    return Row(
      children: [
        Expanded(
          child: Text(
            item.label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: fg),
          ),
        ),
        if (item.detail != null && item.detail!.isNotEmpty) ...[
          SizedBox(width: 5),
          Flexible(
            child: Text(
              item.detail!,
              style: TextStyle(color: fg),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ],
    );
  }
}

class LspCompletionPrompt extends CodePrompt {
  const LspCompletionPrompt({
    required this.label,
    required this.insertText,
    required this.input,
    this.detail,
  }) : super(word: label);

  final String label;
  final String insertText;
  final String input;
  final String? detail;

  @override
  CodeAutocompleteResult get autocomplete => CodeAutocompleteResult(
    input: input,
    word: insertText,
    selection: TextSelection.collapsed(offset: insertText.length),
  );

  @override
  bool match(String input) => true;
}

class LspStatusPrompt extends CodePrompt {
  const LspStatusPrompt._({required this.message, required this.input})
    : super(word: message);

  final String message;
  final String input;

  @override
  CodeAutocompleteResult get autocomplete => CodeAutocompleteResult(
    input: input,
    word: input,
    selection: TextSelection.collapsed(offset: input.length),
  );

  @override
  bool match(String input) => false;
}
