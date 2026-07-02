import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:pyrite_ide/core/constants/editor_themes.dart';
import 'package:pyrite_ide/core/services/app.dart';
import 'package:pyrite_ide/core/services/settings.dart';
import 'package:pyrite_ide/core/services/shortcut_utils.dart';
import 'package:pyrite_ide/shared/md3_widgets.dart';

class EditorSettings extends ConsumerWidget {
  const EditorSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final body = ListView(
      padding: EdgeInsets.all(12),
      children: [
        SettingsSection(
          title: "字体",
          description: "影响代码编辑区域的阅读和输入体验。",
          children: [
            ListTile(
              title: const Text("字体"),
              subtitle: Text(ref.watch(editorTextFontProvider)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showTextFontDialog(context, ref),
            ),

            ListTile(
              title: const Text("字体大小"),
              subtitle: Text(
                "${ref.watch(editorFontSize).toStringAsFixed(0)} px",
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showFontSizeDialog(context),
            ),
          ],
        ),
        SettingsSection(
          title: "编辑器主题",
          description: "选择代码高亮配色方案，亮色/暗色随应用主题自动切换。",
          children: [
            ListTile(
              title: const Text("配色方案"),
              subtitle: Text(
                findEditorThemeByKey(ref.watch(editorThemeKey))?.label ??
                    "Atom One",
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showThemePickerDialog(context, ref),
            ),
          ],
        ),
        SettingsSection(
          title: "上传确认",
          description: "上传文件存在差异时的确认方式。",
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'toolbar',
                    icon: Icon(Icons.open_in_full),
                    label: Text("浮动工具栏"),
                  ),
                  ButtonSegment(
                    value: 'dialog',
                    icon: Icon(Icons.chat_bubble_outline),
                    label: Text("确认对话框"),
                  ),
                ],
                selected: {ref.watch(uploadConfirmStyleProvider)},
                onSelectionChanged: (value) {
                  ref.read(uploadConfirmStyleProvider.notifier).state =
                      value.first;
                },
              ),
            ),
          ],
        ),
        SettingsSection(
          title: "快捷键",
          description: "上传/下载确认的快捷键。",
          children: [
            ShortcutRecorderTile(
              title: "确认操作",
              value: ref.watch(confirmShortcutProvider),
              onChanged: (v) =>
                  ref.read(confirmShortcutProvider.notifier).state = v,
            ),

            ShortcutRecorderTile(
              title: "取消操作",
              value: ref.watch(cancelShortcutProvider),
              onChanged: (v) =>
                  ref.read(cancelShortcutProvider.notifier).state = v,
            ),
          ],
        ),
        SettingsSection(
          title: "编辑行为",
          children: [
            SwitchListTile(
              title: const Text("自动折行"),
              subtitle: const Text("长行在可视区域内换行显示"),
              value: ref.watch(editorWordWrap),
              onChanged: (value) {
                ref.read(editorWordWrap.notifier).state = value;
              },
            ),

            SwitchListTile(
              title: const Text("显示行号"),
              subtitle: const Text("显示左侧 gutter 行号区域"),
              value: ref.watch(editorLineNumber),
              onChanged: (value) =>
                  ref.read(editorLineNumber.notifier).state = value,
            ),

            SwitchListTile(
              title: const Text("显示 gutter 分隔线"),
              subtitle: const Text("在行号区域和代码之间显示分隔线"),
              value: ref.watch(editorGutterDivider),
              onChanged: (value) =>
                  ref.read(editorGutterDivider.notifier).state = value,
            ),

            SwitchListTile(
              title: const Text("代码折叠"),
              subtitle: const Text("显示折叠图标并允许折叠代码块"),
              value: ref.watch(editorCodeFolding),
              onChanged: (value) =>
                  ref.read(editorCodeFolding.notifier).state = value,
            ),

            SwitchListTile(
              title: const Text("缩进参考线"),
              subtitle: const Text("显示每级缩进的纵向参考线"),
              value: ref.watch(editorGuideLines),
              onChanged: (value) =>
                  ref.read(editorGuideLines.notifier).state = value,
            ),

            SwitchListTile(
              title: const Text("本地补全"),
              subtitle: const Text("启用非 LSP 的本地补全建议，较大文件可能有额外开销"),
              value: ref.watch(editorLocalSuggestions),
              onChanged: (value) =>
                  ref.read(editorLocalSuggestions.notifier).state = value,
            ),

            SwitchListTile(
              title: const Text("键盘补全建议"),
              subtitle: const Text("允许系统虚拟键盘显示输入建议"),
              value: ref.watch(editorKeyboardSuggestions),
              onChanged: (value) =>
                  ref.read(editorKeyboardSuggestions.notifier).state = value,
            ),

            SwitchListTile(
              title: const Text("Tab 输入空格"),
              subtitle: const Text("按 Tab 时插入空格而不是制表符"),
              value: ref.watch(editorUseSpaceAsTab),
              onChanged: (value) =>
                  ref.read(editorUseSpaceAsTab.notifier).state = value,
            ),

            ListTile(
              leading: const Icon(Icons.keyboard_tab),
              title: const Text("Tab 大小"),
              subtitle: Text("${ref.watch(editorTabSize)} 个字符"),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showIntSliderDialog(
                context,
                title: "Tab 大小",
                value: ref.read(editorTabSize),
                min: 1,
                max: 8,
                onChanged: (value) =>
                    ref.read(editorTabSize.notifier).state = value,
              ),
            ),
          ],
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(title: const Text("编辑器设置")),
      body: body,
    );
  }

  void showIntSliderDialog(
    BuildContext context, {
    required String title,
    required int value,
    required int min,
    required int max,
    required ValueChanged<int> onChanged,
  }) async {
    var current = value;
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text(title),
            content: Slider(
              min: min.toDouble(),
              max: max.toDouble(),
              divisions: max - min,
              value: current.toDouble(),
              label: current.toString(),
              onChanged: (next) {
                setState(() => current = next.round());
                onChanged(current);
              },
            ),
            actions: [
              FilledButton(
                onPressed: () => context.pop(),
                child: const Text("完成"),
              ),
            ],
          );
        },
      ),
    );
  }

  void showTextFontDialog(BuildContext context, WidgetRef ref) async {
    final List<SimpleDialogOption> children = [];
    editorTextFonts.forEach((name, value) {
      final selected = ref.read(editorTextFontProvider) == name;
      children.add(
        SimpleDialogOption(
          child: ListTile(
            title: Text(name),
            subtitle: Text(
              "print('Pyrite IDE')",
              style: TextStyle(fontFamily: value.isEmpty ? null : value),
            ),
            trailing: selected ? const Icon(Icons.check) : null,
            minTileHeight: 0,
            onTap: (name == "自定义")
                ? () {
                    customizationEditorTextFont();
                    context.pop(name);
                  }
                : () {
                    ref.read(editorTextFontProvider.notifier).state = name;
                    context.pop(name);
                  },
          ),
        ),
      );
    });
    await showDialog(
      context: context,
      builder: (context) =>
          SimpleDialog(title: const Text("选择编辑器字体"), children: children),
    );
  }

  void showFontSizeDialog(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final size = ref.watch(editorFontSize);
          return SimpleDialog(
            title: const Text("字体大小"),
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(24, 0, 24, 12),
                child: Text(
                  "print('Pyrite IDE')",
                  style: TextStyle(
                    fontFamily:
                        editorTextFonts[ref.watch(editorTextFontProvider)],
                    fontSize: size,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Slider(
                  min: 10,
                  max: 28,
                  divisions: 18,
                  value: size,
                  label: size.toStringAsFixed(0),
                  onChanged: (value) =>
                      ref.read(editorFontSize.notifier).state = value,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void showThemePickerDialog(BuildContext context, WidgetRef ref) async {
    final currentKey = ref.read(editorThemeKey);
    final brightness = Theme.of(context).brightness;
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("选择编辑器主题"),
        content: SizedBox(
          width: 360,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: editorThemes.length,
            itemBuilder: (context, index) {
              final entry = editorThemes[index];
              final selected = entry.key == currentKey;
              final previewTheme = resolveEditorTheme(entry, brightness);
              final bgColor =
                  previewTheme['root']?.backgroundColor ?? Colors.grey[900];
              final sampleStyle =
                  previewTheme['keyword'] ??
                  previewTheme['title'] ??
                  const TextStyle(color: Colors.blue);
              return ListTile(
                leading: Container(
                  width: 48,
                  height: 32,
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      "fn",
                      style: sampleStyle.copyWith(fontSize: 13),
                    ),
                  ),
                ),
                title: Text(entry.label),
                trailing: selected ? const Icon(Icons.check) : null,
                onTap: () {
                  ref.read(editorThemeKey.notifier).state = entry.key;
                  context.pop();
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => context.pop(), child: const Text("取消")),
        ],
      ),
    );
  }
}

class ShortcutRecorderTile extends StatefulWidget {
  final String title;
  final String value;
  final ValueChanged<String> onChanged;

  const ShortcutRecorderTile({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  @override
  State<ShortcutRecorderTile> createState() => _ShortcutRecorderTileState();
}

class _ShortcutRecorderTileState extends State<ShortcutRecorderTile> {
  bool _recording = false;
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) {
      setState(() => _recording = false);
    }
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (!_recording || event is KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent) {
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.escape) {
        setState(() => _recording = false);
        _focusNode.unfocus();
        return KeyEventResult.handled;
      }
      final physicalKey = event.physicalKey;
      final isModifier =
          physicalKey == PhysicalKeyboardKey.controlLeft ||
          physicalKey == PhysicalKeyboardKey.controlRight ||
          physicalKey == PhysicalKeyboardKey.shiftLeft ||
          physicalKey == PhysicalKeyboardKey.shiftRight ||
          physicalKey == PhysicalKeyboardKey.altLeft ||
          physicalKey == PhysicalKeyboardKey.altRight ||
          physicalKey == PhysicalKeyboardKey.metaLeft ||
          physicalKey == PhysicalKeyboardKey.metaRight;
      if (isModifier) return KeyEventResult.ignored;

      final hardwareKeyboard = HardwareKeyboard.instance;
      final control = hardwareKeyboard.isControlPressed;
      final shift = hardwareKeyboard.isShiftPressed;
      final alt = hardwareKeyboard.isAltPressed;
      final meta = hardwareKeyboard.isMetaPressed;

      if (!control && !shift && !alt && !meta) return KeyEventResult.ignored;

      final activator = SingleActivator(
        key,
        control: control,
        shift: shift,
        alt: alt,
        meta: meta,
      );
      widget.onChanged(activatorToString(activator));
      setState(() => _recording = false);
      _focusNode.unfocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _onKeyEvent,
      child: ListTile(
        leading: Icon(_recording ? Icons.keyboard : Icons.keyboard_command_key),
        title: Text(widget.title),
        subtitle: Text(
          _recording ? "按下快捷键（Esc 取消）..." : widget.value,
          style: TextStyle(
            fontFamily: 'monospace',
            color: _recording ? Theme.of(context).colorScheme.primary : null,
          ),
        ),
        trailing: _recording
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : null,
        onTap: () {
          setState(() => _recording = true);
          _focusNode.requestFocus();
        },
      ),
    );
  }
}
