import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:pyrite_ide/core/constants/editor_themes.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/services/app.dart';
import 'package:pyrite_ide/core/services/settings.dart';
import 'package:pyrite_ide/core/services/shortcut_utils.dart';
import 'package:pyrite_ide/shared/md3_widgets.dart';
import 'package:pyrite_ide/shared/studio_text.dart';

class EditorSettings extends ConsumerWidget {
  const EditorSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final body = ListView(
      padding: EdgeInsets.all(12),
      children: [
        SettingsSection(
          title: I18nKey.settingsEditorFontSection,
          description: I18nKey.settingsEditorFontDescription,
          children: [
            ListTile(
              title: const UseText(I18nKey.settingsTerminalFont),
              subtitle: Text(ref.watch(editorTextFontProvider)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showTextFontDialog(context, ref),
            ),

            ListTile(
              title: const UseText(I18nKey.settingsTerminalFontSize),
              subtitle: Text(
                "${ref.watch(editorFontSize).toStringAsFixed(0)} px",
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showFontSizeDialog(context),
            ),
          ],
        ),
        SettingsSection(
          title: I18nKey.settingsEditorThemeSection,
          description: I18nKey.settingsEditorThemeDescription,
          children: [
            ListTile(
              title: const UseText(I18nKey.settingsEditorColorScheme),
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
          title: I18nKey.settingsEditorUploadConfirmSection,
          description: I18nKey.settingsEditorUploadConfirmDescription,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'toolbar',
                    icon: Icon(Icons.open_in_full),
                    label: UseText(I18nKey.settingsEditorFloatingToolbar),
                  ),
                  ButtonSegment(
                    value: 'dialog',
                    icon: Icon(Icons.chat_bubble_outline),
                    label: UseText(I18nKey.settingsEditorConfirmDialog),
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
          title: I18nKey.settingsEditorShortcutsSection,
          description: I18nKey.settingsEditorShortcutsDescription,
          children: [
            ShortcutRecorderTile(
              title: I18nKey.settingsEditorConfirmAction,
              value: ref.watch(confirmShortcutProvider),
              onChanged: (v) =>
                  ref.read(confirmShortcutProvider.notifier).state = v,
            ),

            ShortcutRecorderTile(
              title: I18nKey.settingsEditorCancelAction,
              value: ref.watch(cancelShortcutProvider),
              onChanged: (v) =>
                  ref.read(cancelShortcutProvider.notifier).state = v,
            ),
          ],
        ),
        SettingsSection(
          title: I18nKey.settingsEditorBehaviorSection,
          children: [
            SwitchListTile(
              title: const UseText(I18nKey.settingsEditorWordWrap),
              subtitle: const UseText(I18nKey.settingsEditorWordWrapSubtitle),
              value: ref.watch(editorWordWrap),
              onChanged: (value) {
                ref.read(editorWordWrap.notifier).state = value;
              },
            ),

            SwitchListTile(
              title: const UseText(I18nKey.settingsEditorLineNumber),
              subtitle: const UseText(I18nKey.settingsEditorLineNumberSubtitle),
              value: ref.watch(editorLineNumber),
              onChanged: (value) =>
                  ref.read(editorLineNumber.notifier).state = value,
            ),

            SwitchListTile(
              title: const UseText(I18nKey.settingsEditorGutterDivider),
              subtitle: const UseText(
                I18nKey.settingsEditorGutterDividerSubtitle,
              ),
              value: ref.watch(editorGutterDivider),
              onChanged: (value) =>
                  ref.read(editorGutterDivider.notifier).state = value,
            ),

            SwitchListTile(
              title: const UseText(I18nKey.settingsEditorCodeFolding),
              subtitle: const UseText(
                I18nKey.settingsEditorCodeFoldingSubtitle,
              ),
              value: ref.watch(editorCodeFolding),
              onChanged: (value) =>
                  ref.read(editorCodeFolding.notifier).state = value,
            ),

            SwitchListTile(
              title: const UseText(I18nKey.settingsEditorGuideLines),
              subtitle: const UseText(I18nKey.settingsEditorGuideLinesSubtitle),
              value: ref.watch(editorGuideLines),
              onChanged: (value) =>
                  ref.read(editorGuideLines.notifier).state = value,
            ),

            SwitchListTile(
              title: const UseText(I18nKey.settingsEditorLocalSuggestions),
              subtitle: const UseText(
                I18nKey.settingsEditorLocalSuggestionsSubtitle,
              ),
              value: ref.watch(editorLocalSuggestions),
              onChanged: (value) =>
                  ref.read(editorLocalSuggestions.notifier).state = value,
            ),

            SwitchListTile(
              title: const UseText(I18nKey.settingsEditorKeyboardSuggestions),
              subtitle: const UseText(
                I18nKey.settingsEditorKeyboardSuggestionsSubtitle,
              ),
              value: ref.watch(editorKeyboardSuggestions),
              onChanged: (value) =>
                  ref.read(editorKeyboardSuggestions.notifier).state = value,
            ),

            SwitchListTile(
              title: const UseText(I18nKey.settingsEditorSpaceAsTab),
              subtitle: const UseText(I18nKey.settingsEditorSpaceAsTabSubtitle),
              value: ref.watch(editorUseSpaceAsTab),
              onChanged: (value) =>
                  ref.read(editorUseSpaceAsTab.notifier).state = value,
            ),

            ListTile(
              leading: const Icon(Icons.keyboard_tab),
              title: const UseText(I18nKey.settingsEditorTabSize),
              subtitle: Text(
                I18nKey.settingsEditorTabSizeValue.fallback.replaceAll(
                  '{count}',
                  ref.watch(editorTabSize).toString(),
                ),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showIntSliderDialog(
                context,
                title: I18nKey.settingsEditorTabSize,
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
      appBar: AppBar(title: const UseText(I18nKey.settingsEditorTitle)),
      body: body,
    );
  }

  void showIntSliderDialog(
    BuildContext context, {
    required Object title,
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
          return SimpleDialog(
            title: UseText(title),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                child: Slider(
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
      builder: (context) => SimpleDialog(
        title: const UseText(I18nKey.settingsEditorSelectFont),
        children: children,
      ),
    );
  }

  void showFontSizeDialog(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final size = ref.watch(editorFontSize);
          return SimpleDialog(
            title: const UseText(I18nKey.settingsTerminalFontSize),
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
        title: const UseText(I18nKey.settingsEditorSelectTheme),
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
          TextButton(
            onPressed: () => context.pop(),
            child: const UseText(I18nKey.commonCancel),
          ),
        ],
      ),
    );
  }
}

class ShortcutRecorderTile extends StatefulWidget {
  final Object title;
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
        title: UseText(widget.title),
        subtitle: UseText(
          _recording ? I18nKey.settingsEditorShortcutRecording : widget.value,
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
