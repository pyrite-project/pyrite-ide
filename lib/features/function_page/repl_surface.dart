import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/editor/repl_completion_controller.dart';
import 'package:pyrite_ide/core/services/editor/repl_input_controller.dart';
import 'package:pyrite_ide/core/services/editor/repl_lsp_completion_source.dart';
import 'package:pyrite_ide/core/services/editor/repl_transcript_controller.dart';
import 'package:pyrite_ide/core/services/editor/terminal.dart';
import 'package:pyrite_ide/core/services/editor/editor_controller_provider.dart';
import 'package:pyrite_ide/core/services/serial/base_usb_serial.dart';
import 'package:pyrite_ide/core/services/serial/device_executor.dart';
import 'package:pyrite_ide/core/services/serial/serial_provider.dart';
import 'package:pyrite_ide/core/services/serial/web_repl_provider.dart';
import 'package:pyrite_ide/core/services/settings.dart';
import 'package:pyrite_ide/core/services/status_bar/running_operation_provider.dart';

final replInputControllerProvider = Provider<ReplInputController>((ref) {
  final controller = ReplInputController();
  ref.onDispose(controller.dispose);
  return controller;
});

final replTranscriptControllerProvider = Provider<ReplTranscriptController>((
  ref,
) {
  final controller = ReplTranscriptController();
  ref.onDispose(controller.dispose);
  return controller;
});

class ReplSurface extends ConsumerStatefulWidget {
  const ReplSurface({
    super.key,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.textStyle,
  });

  final Color backgroundColor;
  final Color foregroundColor;
  final TextStyle textStyle;

  @override
  ConsumerState<ReplSurface> createState() => _ReplSurfaceState();
}

class _ReplSurfaceState extends ConsumerState<ReplSurface> {
  final _focusNode = FocusNode(debugLabel: 'repl-input');
  final _scrollController = ScrollController();
  final _selectionKey = GlobalKey<SelectionAreaState>();
  final _inputBlockKey = GlobalKey();
  final _editableTextKey = GlobalKey<EditableTextState>();
  final _completionLayerLink = LayerLink();

  late final ReplInputController _input;
  late final ReplTranscriptController _transcript;
  late final ReplPromptTracker _tracker;
  late final ReplCompletionController _completion;
  late final ReplLspCompletionSource _lspCompletion;
  late final ReplSignatureController _signature;
  late final void Function(String) _inputSink;
  late final void Function(String) _deviceOutputSink;
  late final void Function() _runStartedSink;
  late final void Function() _runFinishedSink;
  void Function(String)? _previousOutput;
  void Function(String)? _previousDeviceOutputSink;
  void Function()? _previousClearSink;
  void Function()? _previousRunStartedSink;
  void Function()? _previousRunFinishedSink;
  String? _selectedOutput;
  String _promptFilterPending = '';
  int _displayAnsiState = 0;
  bool _displayAtLineStart = true;
  bool _managedOutputAtLineStart = true;
  bool _hasClaimedInitialFocus = false;
  String? _activePrompt;
  String? _pendingDeviceEcho;
  double? _focusScrollAnchor;
  OverlayEntry? _completionOverlay;
  OverlayEntry? _signatureOverlay;
  Timer? _completionDebounce;
  Timer? _signatureDebounce;
  String _lastInputText = '';
  final Map<String, List<String>> _runtimeCompletionCache = {};
  Rect? _caretRectInTarget;
  bool _completionOpensAbove = false;

  @override
  void initState() {
    super.initState();
    _input = ref.read(replInputControllerProvider);
    _transcript = ref.read(replTranscriptControllerProvider);
    _tracker = ReplPromptTracker(onMode: _onPromptMode);
    _lspCompletion = ReplLspCompletionSource(
      currentController: () => ref
          .read(editorControllerMapProvider.notifier)
          .getSelectedController(),
    );
    _signature = ReplSignatureController(provider: _provideSignatureHint);
    _signature.addListener(_syncSignatureOverlay);
    _completion = ReplCompletionController(provider: _provideCompletionItems);
    _completion.addListener(_syncCompletionOverlay);
    _scrollController.addListener(_keepFocusScrollPosition);
    _inputSink = _sendInput;
    _deviceOutputSink = _handleDeviceOutput;
    _runStartedSink = _handleExternalRunStarted;
    _runFinishedSink = _handleExternalRunFinished;
    _previousOutput = repl.onOutput;
    _previousDeviceOutputSink = replOutputSink;
    _previousClearSink = replClearSink;
    _previousRunStartedSink = replRunStartedSink;
    _previousRunFinishedSink = replRunFinishedSink;
    repl.onOutput = _inputSink;
    replInputSink = _inputSink;
    replOutputSink = _deviceOutputSink;
    replClearSink = _clearTranscript;
    replRunStartedSink = _runStartedSink;
    replRunFinishedSink = _runFinishedSink;
    ref.listenManual(serialProvider, (_, _) => _syncConnection());
    ref.listenManual(webReplProvider, (_, _) => _syncConnection());
  }

  @override
  void dispose() {
    if (repl.onOutput == _inputSink) repl.onOutput = _previousOutput;
    if (replInputSink == _inputSink) replInputSink = null;
    if (replOutputSink == _deviceOutputSink) {
      replOutputSink = _previousDeviceOutputSink;
    }
    if (replClearSink == _clearTranscript) replClearSink = _previousClearSink;
    if (replRunStartedSink == _runStartedSink) {
      replRunStartedSink = _previousRunStartedSink;
    }
    if (replRunFinishedSink == _runFinishedSink) {
      replRunFinishedSink = _previousRunFinishedSink;
    }
    _scrollController.removeListener(_keepFocusScrollPosition);
    _completion.removeListener(_syncCompletionOverlay);
    _completionDebounce?.cancel();
    _signature.removeListener(_syncSignatureOverlay);
    _signatureDebounce?.cancel();
    _completionOverlay?.remove();
    _completionOverlay = null;
    _signatureOverlay?.remove();
    _signatureOverlay = null;
    _completion.dispose();
    _signature.dispose();
    _lspCompletion.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: AnimatedBuilder(
        animation: Listenable.merge(<Listenable>[
          _input,
          _transcript,
          _completion,
        ]),
        builder: (context, _) {
          return Container(
            key: const ValueKey('repl-background'),
            color: widget.backgroundColor,
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (_) => _handleSurfacePointerDown(),
              child: LayoutBuilder(
                builder: (context, _) {
                  final inputVisible = _input.hasVisibleInput;
                  return Scrollbar(
                    controller: _scrollController,
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!_transcript.isEmpty) _buildTranscript(context),
                          _buildInputBlock(context, visible: inputVisible),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTranscript(BuildContext context) {
    final outputStyle = _outputStyle();
    final promptStyle = _promptStyle(context);
    return SelectionArea(
      key: _selectionKey,
      onSelectionChanged: (content) {
        final value = content?.plainText;
        if (!mounted || value == _selectedOutput) return;
        setState(() => _selectedOutput = value);
      },
      child: Text.rich(
        _buildTranscriptSpan(outputStyle, promptStyle),
        softWrap: true,
      ),
    );
  }

  Widget _buildInputBlock(BuildContext context, {required bool visible}) {
    final style = _inputStyle();
    if (_input.mode == ReplInteractionMode.unknown) {
      return const SizedBox.shrink();
    }
    if (!visible) {
      return SizedBox(
        height: 1,
        width: 1,
        child: IgnorePointer(
          child: Opacity(
            opacity: 0,
            child: _InlineReplEditor(
              editableKey: _editableTextKey,
              controller: _input,
              focusNode: _focusNode,
              style: style,
              onKeyEvent: _handleEditorKey,
              onChanged: _handleTextChanged,
            ),
          ),
        ),
      );
    }

    final lineCount = '\n'.allMatches(_input.text.text).length + 1;
    return CompositedTransformTarget(
      link: _completionLayerLink,
      child: Row(
        key: _inputBlockKey,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PromptGutter(
            lineCount: lineCount,
            showPrompt: _input.isInlineEditable,
            continuation: _input.mode == ReplInteractionMode.continuation,
            style: _promptStyle(context),
          ),
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 20, maxHeight: 160),
              child: _InlineReplEditor(
                editableKey: _editableTextKey,
                controller: _input,
                focusNode: _focusNode,
                style: style,
                onKeyEvent: _handleEditorKey,
                onChanged: _handleTextChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }

  TextStyle _outputStyle() {
    return widget.textStyle.copyWith(
      color: widget.foregroundColor.withValues(alpha: .78),
      height: 1.15,
    );
  }

  TextStyle _inputStyle() {
    return widget.textStyle.copyWith(
      color: widget.foregroundColor,
      height: 1.15,
    );
  }

  TextStyle _promptStyle(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _inputStyle().copyWith(
      color: scheme.primary,
      fontWeight: FontWeight.w600,
    );
  }

  TextSpan _buildTranscriptSpan(TextStyle outputStyle, TextStyle promptStyle) {
    final text = _transcript.text;
    final spans = <InlineSpan>[];
    final promptPattern = RegExp(r'^(>>> |\.\.\. )', multiLine: true);
    var offset = 0;
    for (final match in promptPattern.allMatches(text)) {
      if (match.start > offset) {
        spans.add(
          TextSpan(
            text: text.substring(offset, match.start),
            style: outputStyle,
          ),
        );
      }
      spans.add(TextSpan(text: match.group(0), style: promptStyle));
      offset = match.end;
    }
    if (offset < text.length) {
      spans.add(TextSpan(text: text.substring(offset), style: outputStyle));
    }
    return TextSpan(children: spans, style: outputStyle);
  }

  void _handleSurfacePointerDown() {
    _clearOutputSelection();
    if (_input.hasVisibleInput) {
      _requestInputFocus(force: true, preserveScroll: true);
    }
  }

  void _onPromptMode(ReplInteractionMode mode) {
    if (!mounted) return;
    if (mode != ReplInteractionMode.prompt &&
        mode != ReplInteractionMode.continuation) {
      _signature.dismiss();
    }
    if (mode == ReplInteractionMode.prompt ||
        mode == ReplInteractionMode.continuation) {
      if (mode == ReplInteractionMode.prompt) {
        _runtimeCompletionCache.clear();
      }
      _activePrompt = mode == ReplInteractionMode.prompt ? '>>> ' : '... ';
      _input.setMode(mode);
      _requestInputFocus(force: !_hasClaimedInitialFocus);
      _scheduleScrollToBottom(force: true);
    } else if (_input.mode == ReplInteractionMode.submitting) {
      _activePrompt = null;
      _input.setMode(ReplInteractionMode.passthrough);
    } else if (_input.text.text.isEmpty) {
      _activePrompt = null;
      _input.setMode(mode);
    }
  }

  void _sendInput(String data) {
    final encode = ref.read(chineseToUnicodeConversion);
    final outbound = encode ? encodeReplInputForDevice(data) : data;
    final web = ref.read(webReplProvider);
    if (web.state == WebReplState.connected ||
        web.state == WebReplState.waitingPassword) {
      ref.read(webReplProvider.notifier).sendText(outbound);
      return;
    }
    if (ref.read(serialProvider).isConnected) {
      ref.read(serialProvider.notifier).sendCommand(outbound, chunked: false);
    }
  }

  void _handleDeviceOutput(String data) {
    if (data.isNotEmpty) {
      _managedOutputAtLineStart = data.endsWith('\n') || data.endsWith('\r');
    }
    _tracker.add(data);
    _appendFilteredDeviceOutput(data);
    _scheduleScrollToBottom();
  }

  void _syncConnection() {
    if (!mounted) return;
    final serialConnected = ref.read(serialProvider).isConnected;
    final webState = ref.read(webReplProvider).state;
    final webConnected =
        webState == WebReplState.connected ||
        webState == WebReplState.waitingPassword;
    if (!serialConnected && !webConnected) {
      _runtimeCompletionCache.clear();
      _flushPromptFilter();
      _displayAnsiState = 0;
      _tracker.reset();
    }
  }

  KeyEventResult _handleEditorKey(FocusNode _, KeyEvent event) {
    if (event is KeyRepeatEvent) {
      if (_completion.isOpen &&
          (event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.tab ||
              event.logicalKey == LogicalKeyboardKey.arrowUp ||
              event.logicalKey == LogicalKeyboardKey.arrowDown)) {
        return KeyEventResult.handled;
      }
      return event.logicalKey == LogicalKeyboardKey.enter
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final control =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    if (control && key == LogicalKeyboardKey.keyC && _copyOutputSelection()) {
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.escape && _signature.isOpen) {
      _signature.dismiss();
      return KeyEventResult.handled;
    }

    if (_completion.isOpen) {
      switch (key) {
        case LogicalKeyboardKey.escape:
          _completion.dismiss();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.arrowUp:
          _completion.move(-1);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.arrowDown:
          _completion.move(1);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.enter:
        case LogicalKeyboardKey.tab:
          _acceptCompletion();
          return KeyEventResult.handled;
        default:
          break;
      }
    }

    if (!_input.isInlineEditable) {
      if (_input.mode == ReplInteractionMode.passthrough) {
        if (control && key == LogicalKeyboardKey.keyC) {
          if (!_input.text.selection.isCollapsed) return KeyEventResult.ignored;
          if (!_interruptManagedRun()) _sendInput('\x03');
          return KeyEventResult.handled;
        }
        if (control && key == LogicalKeyboardKey.keyD) {
          if (_input.text.text.isEmpty) _sendInput('\x04');
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.enter) {
          _submitPassthroughInput();
          return KeyEventResult.handled;
        }
        // Keep arrows, backspace, delete and paste in the local line editor.
        return KeyEventResult.ignored;
      }
      _completion.dismiss();
      if (_input.mode == ReplInteractionMode.submitting) {
        if (control && key == LogicalKeyboardKey.keyC) {
          if (!_interruptManagedRun()) _sendInput('\x03');
        }
        return KeyEventResult.handled;
      }
      if (control && key == LogicalKeyboardKey.keyC && _interruptManagedRun()) {
        return KeyEventResult.handled;
      }
      if (control && key == LogicalKeyboardKey.keyV) {
        unawaited(_pasteToDevice());
        return KeyEventResult.handled;
      }
      final encoded = _encodePassthroughKey(key, control: control);
      if (encoded != null) {
        _sendInput(encoded);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (control && key == LogicalKeyboardKey.keyC) {
      if (!_input.text.selection.isCollapsed) return KeyEventResult.ignored;
      _commitActivePrompt();
      _input.text.clear();
      _input.setMode(ReplInteractionMode.passthrough);
      _sendInput('\x03');
      return KeyEventResult.handled;
    }
    if (control && key == LogicalKeyboardKey.keyD) {
      if (_input.text.text.isEmpty) {
        _commitActivePrompt();
        _input.setMode(ReplInteractionMode.passthrough);
        _sendInput('\x04');
      }
      return KeyEventResult.handled;
    }
    if (control && key == LogicalKeyboardKey.enter) {
      _submit();
      return KeyEventResult.handled;
    }
    if (control && key == LogicalKeyboardKey.space) {
      unawaited(_requestCompletion(manual: true));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp && _input.showPreviousHistory()) {
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown && _input.showNextHistory()) {
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.tab) {
      final context = _completionContext();
      if (context.hasQuery) {
        unawaited(_requestCompletion(manual: true));
      } else {
        _input.insert('    ');
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.backspace && _input.deleteIndentationUnit()) {
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter) {
      if (_input.text.text.trim().isEmpty) {
        _commitActivePrompt();
        _input.text.clear();
        _sendInput('\r\n');
        _input.setMode(ReplInteractionMode.passthrough);
        return KeyEventResult.handled;
      }
      if (_input.handleEnter()) _submit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  String? _encodePassthroughKey(
    LogicalKeyboardKey key, {
    required bool control,
  }) {
    if (control && key.keyLabel.length == 1) {
      final code = key.keyLabel.toUpperCase().codeUnitAt(0);
      if (code >= 0x41 && code <= 0x5a) {
        return String.fromCharCode(code - 0x40);
      }
    }
    return switch (key) {
      LogicalKeyboardKey.arrowUp => '\x1b[A',
      LogicalKeyboardKey.arrowDown => '\x1b[B',
      LogicalKeyboardKey.arrowRight => '\x1b[C',
      LogicalKeyboardKey.arrowLeft => '\x1b[D',
      LogicalKeyboardKey.home => '\x1b[H',
      LogicalKeyboardKey.end => '\x1b[F',
      LogicalKeyboardKey.pageUp => '\x1b[5~',
      LogicalKeyboardKey.pageDown => '\x1b[6~',
      LogicalKeyboardKey.delete => '\x1b[3~',
      LogicalKeyboardKey.backspace => '\x08',
      LogicalKeyboardKey.tab => '\t',
      LogicalKeyboardKey.enter => '\r',
      LogicalKeyboardKey.escape => '\x1b',
      _ => null,
    };
  }

  void _submit() {
    _completion.dismiss();
    _signature.dismiss();
    final wasContinuation = _input.mode == ReplInteractionMode.continuation;
    final value = _input.takeSubmission();
    if (value == null) return;
    final prompt = _activePrompt ?? (wasContinuation ? '... ' : '>>> ');
    _activePrompt = null;
    if (!value.contains('\n')) {
      final source = '$value\r\n';
      _pendingDeviceEcho = encodeReplInputForDevice(source);
      _transcript.append('$prompt$value\r\n');
      _displayAtLineStart = true;
      _sendInput('$value\r\n');
      _input.setMode(ReplInteractionMode.passthrough);
      return;
    }
    _transcript.append('$prompt${formatReplSubmissionEcho(value)}');
    _managedOutputAtLineStart = true;
    _scheduleScrollToBottom(force: true);
    unawaited(_executeManagedSubmission(value));
  }

  void _requestInputFocus({bool force = false, bool preserveScroll = false}) {
    final primary = FocusManager.instance.primaryFocus;
    if (!force && primary != null && primary != _focusNode) return;
    final preservedOffset = preserveScroll && _scrollController.hasClients
        ? _scrollController.offset
        : null;
    _focusScrollAnchor = preservedOffset;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _hasClaimedInitialFocus = true;
      _focusNode.requestFocus();
      if (preservedOffset != null) {
        _restoreFocusScrollOffset(preservedOffset, 4);
      }
    });
  }

  void _keepFocusScrollPosition() {
    final anchor = _focusScrollAnchor;
    if (anchor == null || !_scrollController.hasClients) return;
    final position = _scrollController.position;
    if ((position.pixels - anchor).abs() < .5) return;
    final target = anchor.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    position.jumpTo(target.toDouble());
  }

  void _restoreFocusScrollOffset(double offset, int framesRemaining) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final position = _scrollController.position;
      final target = offset.clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      position.jumpTo(target.toDouble());
      if (framesRemaining > 1) {
        _restoreFocusScrollOffset(offset, framesRemaining - 1);
      } else {
        _focusScrollAnchor = null;
      }
    });
  }

  void _handleTextChanged(String value) {
    if (_input.isInlineEditable) {
      _scheduleScrollToBottom(force: true);
      final previous = _lastInputText;
      _lastInputText = value;
      final appendedOneCharacter =
          value.length == previous.length + 1 && value.startsWith(previous);
      final appendedCharacter = appendedOneCharacter
          ? value.substring(value.length - 1)
          : null;
      if (appendedCharacter == '(' || appendedCharacter == ',') {
        _signatureDebounce?.cancel();
        _signatureDebounce = Timer(const Duration(milliseconds: 80), () {
          if (mounted) unawaited(_requestSignature(appendedCharacter));
        });
      } else if (appendedCharacter == ')' || appendedCharacter == '\n') {
        _signature.dismiss();
      }
      if (appendedOneCharacter && RegExp(r'[A-Za-z0-9_.]$').hasMatch(value)) {
        _completionDebounce?.cancel();
        _completionDebounce = Timer(const Duration(milliseconds: 120), () {
          if (mounted) unawaited(_requestCompletion());
        });
      } else if (_completion.isOpen && !appendedOneCharacter) {
        _completion.dismiss();
      }
      return;
    }
    if (value.isEmpty) return;
    if (_input.mode == ReplInteractionMode.submitting) {
      _input.text.clear();
      return;
    }
    if (!_input.text.value.composing.isCollapsed) return;
    if (_input.mode == ReplInteractionMode.passthrough) return;
    _sendInput(value);
    _input.text.clear();
  }

  void _submitPassthroughInput() {
    final value = _input.text.text;
    final source = '$value\r\n';
    _pendingDeviceEcho = encodeReplInputForDevice(source);
    _transcript.append(source);
    _displayAtLineStart = true;
    _input.text.clear();
    _sendInput(source);
    _scheduleScrollToBottom(force: true);
  }

  ReplCompletionContext _completionContext({bool manual = false}) {
    final selection = _input.text.selection;
    final cursor = selection.extentOffset < 0
        ? _input.text.text.length
        : selection.extentOffset;
    return ReplCompletionContext.fromText(
      _input.text.text,
      cursor,
      manual: manual,
    );
  }

  Future<void> _requestCompletion({bool manual = false}) async {
    if (!_input.isInlineEditable) {
      _completion.dismiss();
      return;
    }
    final context = _completionContext(manual: manual);
    if (!manual && !context.shouldAutoTrigger) {
      _completion.dismiss();
      return;
    }
    await _completion.request(context);
  }

  Future<void> _requestSignature(String? triggerCharacter) async {
    if (!_input.isInlineEditable) {
      _signature.dismiss();
      return;
    }
    final selection = _input.text.selection;
    final cursor = selection.extentOffset < 0
        ? _input.text.text.length
        : selection.extentOffset;
    final context = ReplSignatureContext.fromText(
      _input.text.text,
      cursor,
      triggerCharacter: triggerCharacter,
    );
    if (context == null) {
      _signature.dismiss();
      return;
    }
    await _signature.request(context);
  }

  Future<ReplSignatureHint?> _provideSignatureHint(
    ReplSignatureContext context,
  ) async {
    final lsp = await _lspCompletion
        .signature(context)
        .timeout(const Duration(milliseconds: 700), onTimeout: () => null);
    return lsp ?? ReplSignatureCatalog.find(context);
  }

  Future<List<ReplCompletionItem>> _provideCompletionItems(
    ReplCompletionContext context,
  ) async {
    final staticItems = await ReplCompletionCatalog.complete(context);
    final backendAllowed = context.manual || context.isMemberAccess;
    final lspFuture = backendAllowed
        ? _lspCompletion
              .complete(context)
              .timeout(
                const Duration(milliseconds: 700),
                onTimeout: () => const <ReplCompletionItem>[],
              )
        : Future.value(const <ReplCompletionItem>[]);
    final dynamicAllowed = context.shouldQueryRuntime;
    final serial = ref.read(serialProvider);
    final web = ref.read(webReplProvider);
    final runtimeFuture =
        dynamicAllowed &&
            serial.isConnected &&
            web.state != WebReplState.connected &&
            web.state != WebReplState.waitingPassword
        ? _runtimeCompletionItems(context)
        : Future.value(const <ReplCompletionItem>[]);
    final results = await Future.wait([lspFuture, runtimeFuture]);
    return _mergeCompletionItems([staticItems, results[0], results[1]]);
  }

  Future<List<ReplCompletionItem>> _runtimeCompletionItems(
    ReplCompletionContext context,
  ) async {
    final key = context.owner ?? '<globals>';
    var names = _runtimeCompletionCache[key];
    if (names == null) {
      names = await queryReplNamesAtPrompt(ref, owner: context.owner);
      if (names != null) _runtimeCompletionCache[key] = names;
    }
    if (names == null) return const [];
    return [
      for (final name in names)
        if (name.startsWith(context.token))
          ReplCompletionItem(
            label: name,
            insertText: name,
            replaceStart: context.replaceStart,
            replaceEnd: context.replaceEnd,
            kind: context.owner == null
                ? ReplCompletionKind.variable
                : ReplCompletionKind.property,
            source: ReplCompletionSource.runtime,
            detail: 'device',
          ),
    ];
  }

  List<ReplCompletionItem> _mergeCompletionItems(
    List<List<ReplCompletionItem>> groups,
  ) {
    final merged = <String, ReplCompletionItem>{
      for (final group in groups)
        for (final item in group) item.label: item,
    };
    final result = merged.values.toList()
      ..sort((a, b) {
        final source = a.source.index.compareTo(b.source.index);
        return source != 0 ? source : a.label.compareTo(b.label);
      });
    return result.take(80).toList(growable: false);
  }

  void _acceptCompletion() {
    final selected = _completion.selected;
    if (selected == null) return;
    _completion.dismiss();
    _input.applyCompletion(selected);
    _lastInputText = _input.text.text;
    _scheduleScrollToBottom(force: true);
  }

  void _syncCompletionOverlay() {
    if (!mounted) return;
    if (_completion.isOpen && _completionOverlay == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_completion.isOpen || _completionOverlay != null) {
          return;
        }
        _updateCaretAnchor();
        final caret = _caretRectInTarget;
        final target = _inputBlockKey.currentContext?.findRenderObject();
        final targetWidth = target is RenderBox ? target.size.width : 320.0;
        final viewport = MediaQuery.sizeOf(context);
        final popupWidth = math.min(
          360.0,
          math.max(1.0, math.min(targetWidth, viewport.width - 24.0)),
        );
        final popupHeight = math.min(
          math.max(1.0, viewport.height - 24.0),
          math.max(36.0, math.min(_completion.items.length * 36.0, 240.0)),
        );
        final left = (caret?.left ?? 0).clamp(
          0.0,
          (targetWidth - popupWidth).clamp(0.0, targetWidth),
        );
        final anchor = _completionOpensAbove
            ? (caret?.topLeft ?? Offset.zero)
            : (caret?.bottomLeft ?? Offset.zero);
        final overlay = Overlay.of(context, rootOverlay: true);
        final entry = OverlayEntry(
          builder: (_) => Positioned(
            left: 0,
            top: 0,
            width: popupWidth,
            height: popupHeight,
            child: CompositedTransformFollower(
              link: _completionLayerLink,
              targetAnchor: Alignment.topLeft,
              followerAnchor: _completionOpensAbove
                  ? Alignment.bottomLeft
                  : Alignment.topLeft,
              offset: Offset(
                left,
                anchor.dy + (_completionOpensAbove ? -4 : 4),
              ),
              showWhenUnlinked: false,
              child: _ReplCompletionPopup(
                controller: _completion,
                onSelected: (index) {
                  _completion.select(index);
                  _acceptCompletion();
                },
              ),
            ),
          ),
        );
        _completionOverlay = entry;
        overlay.insert(entry);
      });
    } else if (!_completion.isOpen && _completionOverlay != null) {
      _completionOverlay!.remove();
      _completionOverlay = null;
    }
  }

  void _syncSignatureOverlay() {
    if (!mounted) return;
    if (_signature.isOpen && _signatureOverlay == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_signature.isOpen || _signatureOverlay != null) {
          return;
        }
        _updateCaretAnchor();
        final caret = _caretRectInTarget ?? Rect.zero;
        final target = _inputBlockKey.currentContext?.findRenderObject();
        final targetWidth = target is RenderBox ? target.size.width : 320.0;
        final viewport = MediaQuery.sizeOf(context);
        final popupWidth = math.min(
          480.0,
          math.max(1.0, math.min(targetWidth, viewport.width - 24.0)),
        );
        final popupHeight = math.min(
          64.0,
          math.max(1.0, viewport.height - 24.0),
        );
        final left = caret.left.clamp(
          0.0,
          (targetWidth - popupWidth).clamp(0.0, targetWidth),
        );
        final overlay = Overlay.of(context, rootOverlay: true);
        final entry = OverlayEntry(
          builder: (_) => Positioned(
            left: 0,
            top: 0,
            width: popupWidth,
            height: popupHeight,
            child: CompositedTransformFollower(
              link: _completionLayerLink,
              targetAnchor: Alignment.topLeft,
              followerAnchor: Alignment.bottomLeft,
              offset: Offset(left, caret.top - 4),
              showWhenUnlinked: false,
              child: _ReplSignaturePopup(controller: _signature),
            ),
          ),
        );
        _signatureOverlay = entry;
        overlay.insert(entry);
      });
    } else if (!_signature.isOpen && _signatureOverlay != null) {
      _signatureOverlay!.remove();
      _signatureOverlay = null;
    }
  }

  void _updateCaretAnchor() {
    final editable = _editableTextKey.currentState?.renderEditable;
    final target = _inputBlockKey.currentContext?.findRenderObject();
    if (editable == null || target is! RenderBox) return;
    final selection = _input.text.selection;
    final offset = selection.extentOffset < 0
        ? _input.text.text.length
        : selection.extentOffset.clamp(0, _input.text.text.length);
    final caret = editable.getLocalRectForCaret(TextPosition(offset: offset));
    final globalTopLeft = editable.localToGlobal(caret.topLeft);
    final globalBottomRight = editable.localToGlobal(caret.bottomRight);
    final targetTopLeft = target.localToGlobal(Offset.zero);
    _caretRectInTarget = Rect.fromLTRB(
      globalTopLeft.dx - targetTopLeft.dx,
      globalTopLeft.dy - targetTopLeft.dy,
      globalBottomRight.dx - targetTopLeft.dx,
      globalBottomRight.dy - targetTopLeft.dy,
    );
    final screenHeight = MediaQuery.sizeOf(context).height;
    _completionOpensAbove =
        screenHeight - globalBottomRight.dy < 200 && globalTopLeft.dy > 200;
  }

  bool _copyOutputSelection() {
    final text = _selectedOutput;
    if (text == null || text.isEmpty) return false;
    unawaited(Clipboard.setData(ClipboardData(text: text)));
    return true;
  }

  void _clearOutputSelection() {
    _selectionKey.currentState?.selectableRegion.clearSelection();
    if (_selectedOutput != null && mounted) {
      setState(() => _selectedOutput = null);
    }
  }

  void _clearTranscript() {
    _clearOutputSelection();
    _completion.dismiss();
    _signature.dismiss();
    _promptFilterPending = '';
    _displayAnsiState = 0;
    _pendingDeviceEcho = null;
    _runtimeCompletionCache.clear();
    _displayAtLineStart = true;
    _managedOutputAtLineStart = true;
    _transcript.clear();
  }

  void _handleExternalRunStarted() {
    if (!mounted) return;
    _completion.dismiss();
    _signature.dismiss();
    if (_input.isInlineEditable) {
      _transcript.append('${_takeActivePrompt()}\r\n');
    }
    _pendingDeviceEcho = null;
    _runtimeCompletionCache.clear();
    _managedOutputAtLineStart = true;
    _input.setMode(ReplInteractionMode.passthrough);
    _scheduleScrollToBottom(force: true);
  }

  void _handleExternalRunFinished() {
    if (!mounted) return;
    _completion.dismiss();
    _signature.dismiss();
    if (!_managedOutputAtLineStart) _transcript.append('\r\n');
    _managedOutputAtLineStart = true;
    _runtimeCompletionCache.clear();
    _activePrompt = '>>> ';
    _input.setMode(ReplInteractionMode.prompt);
    _requestInputFocus();
    _scheduleScrollToBottom(force: true);
  }

  String _takeActivePrompt() {
    final prompt =
        _activePrompt ??
        (_input.mode == ReplInteractionMode.continuation ? '... ' : '>>> ');
    _activePrompt = null;
    return prompt;
  }

  void _commitActivePrompt() {
    _transcript.append(_takeActivePrompt());
    _scheduleScrollToBottom(force: true);
  }

  bool _interruptManagedRun() {
    for (final operation in ref.read(runningOperationsProvider)) {
      if (operation.id == 'repl-console' && operation.onInterrupt != null) {
        operation.onInterrupt!();
        return true;
      }
    }
    return false;
  }

  Future<void> _pasteToDevice() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null && text.isNotEmpty) _sendInput(text);
  }

  Future<void> _executeManagedSubmission(String source) async {
    final output = _terminalDecoder();
    final error = _terminalDecoder();
    try {
      final web = ref.read(webReplProvider);
      if (web.state == WebReplState.connected) {
        await ref
            .read(webReplProvider.notifier)
            .executeStreaming(
              source,
              onStarted: _markManagedRunStarted,
              onStdout: output.add,
              onStderr: error.add,
            );
      } else if (ref.read(serialProvider).isConnected) {
        await runPythonOnDeviceStreaming(
          ref,
          source,
          runningOperationId: 'repl-console',
          onStarted: _markManagedRunStarted,
          onStdout: output.add,
          onStderr: error.add,
        );
      } else {
        throw StateError('Device is not connected.');
      }
    } catch (exception) {
      _writeManagedOutput('[REPL] $exception\r\n');
    } finally {
      output.close();
      error.close();
      if (mounted) {
        _transcript.append(_managedOutputAtLineStart ? '' : '\r\n');
        _input.setMode(ReplInteractionMode.prompt);
        _requestInputFocus();
        _scheduleScrollToBottom(force: true);
      }
    }
  }

  ByteConversionSink _terminalDecoder() {
    return const Utf8Decoder(allowMalformed: true).startChunkedConversion(
      StringConversionSink.fromStringSink(_ReplStringSink(_writeManagedOutput)),
    );
  }

  void _markManagedRunStarted() {
    if (mounted) _input.setMode(ReplInteractionMode.passthrough);
  }

  void _writeManagedOutput(String data) {
    if (data.isEmpty) return;
    _transcript.append(data);
    _managedOutputAtLineStart = data.endsWith('\n') || data.endsWith('\r');
    _scheduleScrollToBottom();
  }

  void _appendFilteredDeviceOutput(String data) {
    final visible = StringBuffer();
    for (final code in data.codeUnits) {
      if (_displayAnsiState == 0) {
        if (code == 0x1b) {
          _displayAnsiState = 1;
        } else {
          visible.writeCharCode(code);
        }
        continue;
      }
      if (_displayAnsiState == 1) {
        if (code == 0x5b) {
          _displayAnsiState = 2;
        } else if (code == 0x5d) {
          _displayAnsiState = 3;
        } else {
          _displayAnsiState = 0;
        }
        continue;
      }
      if (_displayAnsiState == 2) {
        if (code >= 0x40 && code <= 0x7e) _displayAnsiState = 0;
        continue;
      }
      if (_displayAnsiState == 3) {
        if (code == 0x07) {
          _displayAnsiState = 0;
        } else if (code == 0x1b) {
          _displayAnsiState = 4;
        }
        continue;
      }
      if (code == 0x5c) {
        _displayAnsiState = 0;
      } else {
        _displayAnsiState = 3;
      }
    }

    var displayData = visible.toString();
    final pendingEcho = _pendingDeviceEcho;
    if (pendingEcho != null && displayData.isNotEmpty) {
      if (pendingEcho.startsWith(displayData)) {
        _pendingDeviceEcho = pendingEcho.substring(displayData.length);
        displayData = '';
      } else if (displayData.startsWith(pendingEcho)) {
        displayData = displayData.substring(pendingEcho.length);
        _pendingDeviceEcho = null;
      } else {
        _pendingDeviceEcho = null;
      }
    }
    _promptFilterPending += displayData;
    final output = StringBuffer();
    while (_promptFilterPending.isNotEmpty) {
      if (_displayAtLineStart &&
          (_promptFilterPending.startsWith('>>> ') ||
              _promptFilterPending.startsWith('... '))) {
        _promptFilterPending = _promptFilterPending.substring(4);
        _displayAtLineStart = false;
        continue;
      }
      if (_displayAtLineStart &&
          ('>>> '.startsWith(_promptFilterPending) ||
              '... '.startsWith(_promptFilterPending))) {
        break;
      }
      final rune = _promptFilterPending.runes.first;
      final length = String.fromCharCode(rune).length;
      _promptFilterPending = _promptFilterPending.substring(length);
      output.write(String.fromCharCode(rune));
      _displayAtLineStart = rune == 0x0a || rune == 0x0d;
    }
    if (output.isNotEmpty) _transcript.append(output.toString());
  }

  void _flushPromptFilter() {
    if (_promptFilterPending.isEmpty) return;
    _transcript.append(_promptFilterPending);
    _promptFilterPending = '';
  }

  void _scheduleScrollToBottom({bool force = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        final position = _scrollController.position;
        if (force || position.pixels >= position.maxScrollExtent - 32) {
          position.jumpTo(position.maxScrollExtent);
        }
      });
    });
  }
}

class _PromptGutter extends StatelessWidget {
  const _PromptGutter({
    required this.lineCount,
    required this.showPrompt,
    required this.continuation,
    required this.style,
  });

  final int lineCount;
  final bool showPrompt;
  final bool continuation;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final continuationStyle = style.copyWith(
      color: style.color?.withValues(alpha: .72),
      fontWeight: FontWeight.normal,
    );
    return SizedBox(
      width: showPrompt ? 42 : 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var index = 0; index < lineCount; index++)
            Text(
              showPrompt ? (index == 0 && !continuation ? '>>> ' : '... ') : '',
              style: continuation || index > 0 ? continuationStyle : style,
              maxLines: 1,
            ),
        ],
      ),
    );
  }
}

class _ReplSignaturePopup extends StatelessWidget {
  const _ReplSignaturePopup({required this.controller});

  final ReplSignatureController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final hint = controller.hint;
        if (hint == null) return const SizedBox.shrink();
        return TapRegion(
          onTapOutside: (_) => controller.dismiss(),
          child: Material(
            key: const ValueKey('repl-signature-popup'),
            elevation: 6,
            color: scheme.surfaceContainer,
            borderRadius: BorderRadius.circular(4),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: Row(
                children: [
                  Icon(Icons.functions, size: 16, color: scheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      hint.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${hint.activeParameter + 1}',
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ReplCompletionPopup extends StatelessWidget {
  const _ReplCompletionPopup({
    required this.controller,
    required this.onSelected,
  });

  final ReplCompletionController controller;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final items = controller.items;
        if (items.isEmpty) return const SizedBox.shrink();
        return TapRegion(
          onTapOutside: (_) => controller.dismiss(),
          child: Material(
            key: const ValueKey('repl-completion-popup'),
            elevation: 8,
            color: scheme.surfaceContainer,
            borderRadius: BorderRadius.circular(4),
            clipBehavior: Clip.antiAlias,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                final selected = index == controller.selectedIndex;
                return InkWell(
                  onTap: () => onSelected(index),
                  child: Container(
                    height: 34,
                    color: selected
                        ? scheme.primary.withValues(alpha: .14)
                        : Colors.transparent,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        Icon(
                          _completionIcon(item.kind),
                          size: 16,
                          color: selected
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            item.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: scheme.onSurface,
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                        if (item.detail != null)
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 130),
                            child: Text(
                              item.detail!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontSize: 11,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

IconData _completionIcon(ReplCompletionKind kind) => switch (kind) {
  ReplCompletionKind.keyword => Icons.code,
  ReplCompletionKind.builtin => Icons.functions,
  ReplCompletionKind.module => Icons.folder_open,
  ReplCompletionKind.function => Icons.functions_outlined,
  ReplCompletionKind.className => Icons.category_outlined,
  ReplCompletionKind.variable => Icons.data_object,
  ReplCompletionKind.property => Icons.tune,
  ReplCompletionKind.constant => Icons.pin,
  ReplCompletionKind.text => Icons.text_fields,
};

class _InlineReplEditor extends StatelessWidget {
  const _InlineReplEditor({
    required this.editableKey,
    required this.controller,
    required this.focusNode,
    required this.style,
    required this.onKeyEvent,
    required this.onChanged,
  });

  final GlobalKey<EditableTextState> editableKey;
  final ReplInputController controller;
  final FocusNode focusNode;
  final TextStyle style;
  final FocusOnKeyEventCallback onKeyEvent;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: onKeyEvent,
      child: EditableText(
        key: editableKey,
        controller: controller.text,
        focusNode: focusNode,
        style: style,
        cursorColor: Theme.of(context).colorScheme.primary,
        backgroundCursorColor: Colors.transparent,
        keyboardType: TextInputType.multiline,
        textInputAction: TextInputAction.newline,
        scrollPadding: EdgeInsets.zero,
        maxLines: null,
        autofocus: false,
        onChanged: onChanged,
        selectionColor: Theme.of(
          context,
        ).colorScheme.primary.withValues(alpha: .25),
      ),
    );
  }
}

class _ReplStringSink implements StringSink {
  const _ReplStringSink(this.onWrite);

  final void Function(String data) onWrite;

  @override
  void write(Object? object) => onWrite(object?.toString() ?? '');

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) {
    onWrite(objects.join(separator));
  }

  @override
  void writeCharCode(int charCode) => onWrite(String.fromCharCode(charCode));

  @override
  void writeln([Object? object = '']) => onWrite('${object ?? ''}\n');
}
