import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/editor/repl_input_controller.dart';
import 'package:pyrite_ide/core/services/editor/repl_transcript_controller.dart';
import 'package:pyrite_ide/core/services/editor/terminal.dart';
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
    required this.textStyle,
  });

  final Color backgroundColor;
  final TextStyle textStyle;

  @override
  ConsumerState<ReplSurface> createState() => _ReplSurfaceState();
}

class _ReplSurfaceState extends ConsumerState<ReplSurface> {
  final _focusNode = FocusNode(debugLabel: 'repl-input');
  final _scrollController = ScrollController();
  final _selectionKey = GlobalKey<SelectionAreaState>();
  final _inputBlockKey = GlobalKey();

  late final ReplInputController _input;
  late final ReplTranscriptController _transcript;
  late final ReplPromptTracker _tracker;
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

  @override
  void initState() {
    super.initState();
    _input = ref.read(replInputControllerProvider);
    _transcript = ref.read(replTranscriptControllerProvider);
    _tracker = ReplPromptTracker(onMode: _onPromptMode);
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
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[_input, _transcript]),
      builder: (context, _) {
        return Container(
          color: widget.backgroundColor,
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => _handleSurfacePointerDown(),
            child: LayoutBuilder(
              builder: (context, _) {
                final inputVisible = _input.isInlineEditable;
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
    );
  }

  Widget _buildTranscript(BuildContext context) {
    final outputStyle = _outputStyle(context);
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
    final style = _inputStyle(context);
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
    return Row(
      key: _inputBlockKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PromptGutter(
          lineCount: lineCount,
          continuation: _input.mode == ReplInteractionMode.continuation,
          style: _promptStyle(context),
        ),
        Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 20, maxHeight: 160),
            child: _InlineReplEditor(
              controller: _input,
              focusNode: _focusNode,
              style: style,
              onKeyEvent: _handleEditorKey,
              onChanged: _handleTextChanged,
            ),
          ),
        ),
      ],
    );
  }

  TextStyle _outputStyle(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return widget.textStyle.copyWith(
      color: scheme.onSurface.withValues(alpha: .78),
      height: 1.15,
    );
  }

  TextStyle _inputStyle(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return widget.textStyle.copyWith(color: scheme.onSurface, height: 1.15);
  }

  TextStyle _promptStyle(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _inputStyle(
      context,
    ).copyWith(color: scheme.primary, fontWeight: FontWeight.w600);
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
    if (_input.isInlineEditable) {
      _requestInputFocus(force: true, preserveScroll: true);
    }
  }

  void _onPromptMode(ReplInteractionMode mode) {
    if (!mounted) return;
    if (mode == ReplInteractionMode.prompt ||
        mode == ReplInteractionMode.continuation) {
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
      _flushPromptFilter();
      _displayAnsiState = 0;
      _tracker.reset();
    }
  }

  KeyEventResult _handleEditorKey(FocusNode _, KeyEvent event) {
    if (event is KeyRepeatEvent) {
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

    if (!_input.isInlineEditable) {
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
    if (key == LogicalKeyboardKey.arrowUp && _input.showPreviousHistory()) {
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown && _input.showNextHistory()) {
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.tab) {
      _input.insert('    ');
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
      return;
    }
    if (value.isEmpty) return;
    if (_input.mode == ReplInteractionMode.submitting) {
      _input.text.clear();
      return;
    }
    if (!_input.text.value.composing.isCollapsed) return;
    _sendInput(value);
    _input.text.clear();
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
    _promptFilterPending = '';
    _displayAnsiState = 0;
    _pendingDeviceEcho = null;
    _displayAtLineStart = true;
    _managedOutputAtLineStart = true;
    _transcript.clear();
  }

  void _handleExternalRunStarted() {
    if (!mounted) return;
    if (_input.isInlineEditable) {
      _transcript.append('${_takeActivePrompt()}\r\n');
    }
    _pendingDeviceEcho = null;
    _managedOutputAtLineStart = true;
    _input.setMode(ReplInteractionMode.passthrough);
    _scheduleScrollToBottom(force: true);
  }

  void _handleExternalRunFinished() {
    if (!mounted) return;
    if (!_managedOutputAtLineStart) _transcript.append('\r\n');
    _managedOutputAtLineStart = true;
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
    required this.continuation,
    required this.style,
  });

  final int lineCount;
  final bool continuation;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final continuationStyle = style.copyWith(
      color: style.color?.withValues(alpha: .72),
      fontWeight: FontWeight.normal,
    );
    return SizedBox(
      width: 42,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var index = 0; index < lineCount; index++)
            Text(
              index == 0 && !continuation ? '>>> ' : '... ',
              style: continuation || index > 0 ? continuationStyle : style,
              maxLines: 1,
            ),
        ],
      ),
    );
  }
}

class _InlineReplEditor extends StatelessWidget {
  const _InlineReplEditor({
    required this.controller,
    required this.focusNode,
    required this.style,
    required this.onKeyEvent,
    required this.onChanged,
  });

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
