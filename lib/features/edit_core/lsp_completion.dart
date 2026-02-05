import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/pylsp/completion.dart';
import 'package:pyrite_ide/core/services/pylsp/main.dart';
import 'package:pyrite_ide/tool_ds/tool_ds.dart';
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

    if (input.isEmpty && !triggeredByDot) return null;

    return CodeAutocompleteEditingValue(
      input: input,
      prompts: [LspStatusPrompt.loading(input: input)],
      index: 0,
    );
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

  final ValueNotifier<CodeAutocompleteEditingValue> notifier;
  final ValueChanged<CodeAutocompleteResult> onSelected;
  final String uri;
  final CodeLineEditingController editorController;

  static const double _width = 320;
  static const double _maxHeight = 220;
  static const double _itemHeight = 22;

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

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    widget.notifier.addListener(_onValueChanged);
    _fetch();
  }

  @override
  void didUpdateWidget(covariant LspAutocompleteListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.notifier != widget.notifier) {
      oldWidget.notifier.removeListener(_onValueChanged);
      widget.notifier.addListener(_onValueChanged);
      _fetch();
    }
  }

  @override
  void dispose() {
    widget.notifier.removeListener(_onValueChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onValueChanged() {
    final selectedIndex = widget.notifier.value.index;
    setState(() {});
    if (selectedIndex != _lastSelectedIndex) {
      _lastSelectedIndex = selectedIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _ensureIndexVisible(selectedIndex);
      });
    }
  }

  Future<void> _fetch() async {
    final epoch = ++_requestEpoch;

    final selection = widget.editorController.selection;
    if (!selection.isCollapsed) return;

    final client = await PythonLspService(ref).maybeClient;
    if (!mounted || epoch != _requestEpoch) return;

    if (client == null) {
      _setPrompts(
        [LspStatusPrompt.unavailable(input: widget.notifier.value.input)],
      );
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

      items = await fetchCompletions(
        client: client,
        uri: widget.uri,
        line: selection.extentIndex,
        character: selection.extentOffset,
        triggerCharacter: triggerCharacter,
      );
    } catch (_) {
      items = const [];
    }

    if (!mounted || epoch != _requestEpoch) return;

    final input = widget.notifier.value.input;
    final filtered = input.isEmpty
        ? items
        : items.where((item) {
            final label = item.label;
            return label.length >= input.length &&
                label.substring(0, input.length).toLowerCase() ==
                    input.toLowerCase();
          }).toList(growable: false);

    final prompts = filtered
        .take(80)
        .map((item) => LspCompletionPrompt(
              label: item.label,
              detail: item.detail,
              insertText: item.insertText,
              input: input,
            ))
        .toList(growable: false);

    _setPrompts(
      prompts.isEmpty
          ? [LspStatusPrompt.empty(input: input)]
          : prompts,
    );
  }

  void _setPrompts(List<CodePrompt> prompts) {
    final value = widget.notifier.value;
    widget.notifier.value = value.copyWith(prompts: prompts, index: 0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final tool = context.tool;
    final value = widget.notifier.value;
    final prompts = value.prompts;

    return ConstrainedBox(
      constraints: const BoxConstraints.tightFor(
        width: LspAutocompleteListView._width,
        height: LspAutocompleteListView._maxHeight,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tool.colors.panel,
          border: Border.all(color: tool.colors.border, width: 1),
          borderRadius: BorderRadius.circular(tool.radii.md),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(tool.radii.md),
          child: ListView.builder(
            controller: _scrollController,
            padding: EdgeInsets.zero,
            itemExtent: LspAutocompleteListView._itemHeight,
            itemCount: prompts.length,
            itemBuilder: (context, index) {
              final prompt = prompts[index];
              final selected = index == value.index;
              final enabled = prompt is! LspStatusPrompt;

              final fg = selected
                  ? tool.colors.selectionText
                  : tool.colors.text;
              final bg = selected
                  ? tool.colors.selection.withOpacity(0.22)
                  : tool.colors.panel.withOpacity(0);
              final detailColor = selected
                  ? tool.colors.selectionText.withOpacity(0.85)
                  : tool.colors.textFaint;

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
                    padding: EdgeInsets.symmetric(
                      horizontal: tool.space.sm,
                    ),
                    alignment: Alignment.centerLeft,
                    child: _PromptRow(
                      prompt: prompt,
                      fg: fg,
                      detailColor: detailColor,
                      tool: tool,
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
    required this.tool,
  });

  final CodePrompt prompt;
  final Color fg;
  final Color detailColor;
  final ToolTokens tool;

  @override
  Widget build(BuildContext context) {
    if (prompt is LspStatusPrompt) {
      final status = prompt as LspStatusPrompt;
      return Text(
        status.message,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: tool.type.uiDense.copyWith(color: detailColor),
      );
    }

    final item = prompt as LspCompletionPrompt;
    return Row(
      children: [
        Expanded(
          child: Text(
            item.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tool.type.monoDense.copyWith(color: fg),
          ),
        ),
        if (item.detail != null && item.detail!.isNotEmpty) ...[
          SizedBox(width: tool.space.sm),
          Flexible(
            child: Text(
              item.detail!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: tool.type.uiDense.copyWith(color: detailColor),
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
  const LspStatusPrompt._({
    required this.message,
    required this.input,
  }) : super(word: message);

  factory LspStatusPrompt.loading({required String input}) =>
      LspStatusPrompt._(message: '…', input: input);

  factory LspStatusPrompt.empty({required String input}) =>
      LspStatusPrompt._(message: '无建议', input: input);

  factory LspStatusPrompt.unavailable({required String input}) =>
      LspStatusPrompt._(message: 'LSP 不可用', input: input);

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
