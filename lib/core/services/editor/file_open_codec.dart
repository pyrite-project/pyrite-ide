import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:fast_gbk/fast_gbk.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/services/editor/editor_controller_provider.dart'
    show maxEditableFileLength;

/// How a file's bytes should enter the editor.
///
/// One helper decides between the four cases the open flow needs to tell
/// apart: clean UTF-8 text, oversized (read-only) text, obvious binary, and
/// valid text in some other encoding. The open flow then shows the matching
/// dialog — a binary warning, or an encoding picker — before anything is put
/// into a tab.
sealed class FileTextPreparation {
  const FileTextPreparation(
    this.text, {
    this.readOnly = false,
    this.encoding,
    this.byteOrderMark = false,
  });

  /// The text to put into the editor buffer.
  final String text;

  /// Whether the editor must open read-only (oversized or binary files).
  final bool readOnly;

  /// Encoding id the bytes were decoded with, or null when the content is
  /// binary and must never be written back.
  ///
  /// Carried onto the tab so a save can re-encode to the same family the file
  /// was read in. Saving a GBK buffer through Dart's default UTF-8 writer
  /// would silently transcode the file and mangle every non-ASCII character,
  /// so the open-time decision has to survive until the write.
  final String? encoding;

  /// Whether the source bytes began with a byte order mark for [encoding].
  final bool byteOrderMark;
}

/// Clean text within the editable size limit.
class TextFilePrepared extends FileTextPreparation {
  const TextFilePrepared(super.text, {super.encoding, super.byteOrderMark});
}

/// Larger than [maxEditableFileLength]; content is loaded but the editor must
/// open read-only, matching the historical oversized-file behavior.
class LargeFilePrepared extends FileTextPreparation {
  const LargeFilePrepared(super.text, {super.encoding, super.byteOrderMark})
    : super(readOnly: true);
}

/// NUL bytes with no text BOM: almost certainly binary. [text] is a
/// malformed-tolerant UTF-8 decode kept only for the "open anyway" escape
/// hatch, which always opens read-only so garbage is never written back.
class BinaryFilePrepared extends FileTextPreparation {
  const BinaryFilePrepared(super.text) : super(readOnly: true);
}

/// Valid bytes that failed strict UTF-8 decoding and carry no NUL bytes —
/// most likely GBK/UTF-16 text. The user picks the encoding; [bytes] stay
/// available for the retry.
class UndecodableFilePrepared extends FileTextPreparation {
  const UndecodableFilePrepared(this.bytes) : super('');

  final Uint8List bytes;
}

/// Encodings offered when UTF-8 decoding fails, with display labels.
/// Latin-1 accepts every byte, so it doubles as a "force open as text"
/// fallback that can never fail.
const List<(String, String)> fileEncodingChoices = [
  ('gbk', 'GBK'),
  ('utf16le', 'UTF-16 LE'),
  ('utf16be', 'UTF-16 BE'),
  ('latin1', 'Latin-1'),
];

String? encodingChoiceLabel(String id) {
  for (final (choiceId, label) in fileEncodingChoices) {
    if (choiceId == id) return label;
  }
  return null;
}

/// Reads [file] once and classifies it. FileSystemExceptions propagate to the
/// caller, which already handles unreadable files by not opening anything.
///
/// Every non-binary outcome carries the encoding the bytes were decoded with,
/// including whether a byte order mark was present, so a later save can
/// reproduce the same on-disk representation instead of forcing UTF-8.
Future<FileTextPreparation> prepareFileForEditing(File file) async {
  final bytes = await file.readAsBytes();

  // A BOM pins the encoding; honor it before any heuristic runs.
  final bomEncoding = _detectBomEncoding(bytes);
  if (bomEncoding != null) {
    final text = decodeWithEncoding(bytes, bomEncoding);
    if (text != null) {
      return bytes.length > maxEditableFileLength
          ? LargeFilePrepared(text, encoding: bomEncoding, byteOrderMark: true)
          : TextFilePrepared(text, encoding: bomEncoding, byteOrderMark: true);
    }
  }

  final isBinary = _looksBinary(bytes);
  if (isBinary) {
    return BinaryFilePrepared(utf8.decode(bytes, allowMalformed: true));
  }
  try {
    final text = utf8.decode(bytes);
    return bytes.length > maxEditableFileLength
        ? LargeFilePrepared(text, encoding: 'utf8')
        : TextFilePrepared(text, encoding: 'utf8');
  } on FormatException {
    return UndecodableFilePrepared(bytes);
  }
}

/// Re-encodes [text] for writing back, reproducing the encoding and byte order
/// mark the file was opened with.
///
/// Falls back to UTF-8 without a mark when [encoding] is null or unknown, and
/// when the target encoding cannot represent the text -- losing the original
/// bytes is better than writing nothing, and a BOM is always ASCII-safe.
Uint8List encodeFileText(
  String text, {
  required String? encoding,
  required bool byteOrderMark,
}) {
  if (encoding == null) {
    // The mark is a property of the file, not of the codec name: a tab that
    // lost its encoding record still has to write back the BOM it was opened
    // with, or the save silently strips it.
    final body = _utf8Bytes(text);
    if (!byteOrderMark) return Uint8List.fromList(body);
    return Uint8List.fromList([..._bomFor('utf8')!, ...body]);
  }
  final body = switch (encoding) {
    'gbk' => _tryEncode(() => gbk.encode(text)) ?? _utf8Bytes(text),
    'latin1' => _tryEncode(() => latin1.encode(text)) ?? _utf8Bytes(text),
    'utf16le' => _encodeUtf16(text, littleEndian: true),
    'utf16be' => _encodeUtf16(text, littleEndian: false),
    _ => _utf8Bytes(text),
  };
  if (!byteOrderMark) return Uint8List.fromList(body);
  final bom = _bomFor(encoding);
  if (bom == null) return Uint8List.fromList(body);
  return Uint8List.fromList([...bom, ...body]);
}

Uint8List _utf8Bytes(String text) => utf8.encode(text);

List<int>? _tryEncode(List<int> Function() encode) {
  try {
    return encode();
  } catch (_) {
    return null;
  }
}

List<int>? _bomFor(String encoding) => switch (encoding) {
  'utf8' => const [0xEF, 0xBB, 0xBF],
  'utf16le' => const [0xFF, 0xFE],
  'utf16be' => const [0xFE, 0xFF],
  _ => null,
};

List<int> _encodeUtf16(String text, {required bool littleEndian}) {
  final units = <int>[];
  for (final rune in text.runes) {
    if (rune > 0xFFFF) {
      final adjusted = rune - 0x10000;
      units
        ..add(0xD800 + (adjusted >> 10))
        ..add(0xDC00 + (adjusted & 0x3FF));
    } else {
      units.add(rune);
    }
  }
  final bytes = <int>[];
  for (final unit in units) {
    if (littleEndian) {
      bytes
        ..add(unit & 0xFF)
        ..add((unit >> 8) & 0xFF);
    } else {
      bytes
        ..add((unit >> 8) & 0xFF)
        ..add(unit & 0xFF);
    }
  }
  return bytes;
}

/// Decodes [bytes] with one of the [fileEncodingChoices]; returns null when
/// the encoding id is unknown or the bytes are invalid in that encoding.
String? decodeWithEncoding(Uint8List bytes, String encodingId) {
  try {
    switch (encodingId) {
      case 'utf8':
        return utf8.decode(bytes, allowMalformed: true);
      case 'gbk':
        return gbk.decode(bytes);
      case 'latin1':
        return latin1.decode(bytes);
      case 'utf16le':
        return _decodeUtf16(bytes, littleEndian: true);
      case 'utf16be':
        return _decodeUtf16(bytes, littleEndian: false);
    }
  } catch (_) {
    return null;
  }
  return null;
}

String? _detectBomEncoding(Uint8List bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    return 'utf8';
  }
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    return 'utf16le';
  }
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    return 'utf16be';
  }
  return null;
}

/// The standard Git-style heuristic: any NUL byte in the first 8 KiB means
/// binary. GBK/UTF-8 text never contains NUL bytes; UTF-16 text does, which
/// is why BOM-marked UTF-16 is decoded before this check runs.
bool _looksBinary(Uint8List bytes) {
  final scanEnd = min(bytes.length, 8192);
  for (var i = 0; i < scanEnd; i++) {
    if (bytes[i] == 0) return true;
  }
  return false;
}

String _decodeUtf16(Uint8List bytes, {required bool littleEndian}) {
  var start = 0;
  if (bytes.length >= 2 &&
      ((littleEndian && bytes[0] == 0xFF && bytes[1] == 0xFE) ||
          (!littleEndian && bytes[0] == 0xFE && bytes[1] == 0xFF))) {
    start = 2;
  }
  final units = <int>[];
  for (var i = start; i + 1 < bytes.length; i += 2) {
    units.add(
      littleEndian
          ? bytes[i] | (bytes[i + 1] << 8)
          : (bytes[i] << 8) | bytes[i + 1],
    );
  }
  // 16-bit code units, so surrogate pairs survive as written.
  return String.fromCharCodes(units);
}

/// Binary-file warning: "仍要打开" opens the file read-only, cancel aborts
/// the open.
Future<bool> showBinaryFileDialog(
  Ref ref,
  BuildContext context, {
  required String filePath,
}) {
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(translate(ref, I18nKey.editorFileBinaryDialogTitle)),
      content: Text(
        translate(
          ref,
          I18nKey.editorFileBinaryDialogBody,
        ).replaceAll('{path}', path.basename(filePath)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(translate(ref, I18nKey.commonCancel)),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(translate(ref, I18nKey.editorFileBinaryDialogOpen)),
        ),
      ],
    ),
  ).then((proceed) => proceed ?? false);
}

/// Encoding picker shown when UTF-8 decoding failed. Stays open with an
/// error note when the chosen encoding cannot decode the bytes; returns the
/// decoded text together with the encoding that produced it, or null when the
/// user cancels (the file stays closed).
///
/// The encoding travels back to the caller so the tab can write the file back
/// in the same character set it was read in.
Future<({String text, String encoding})?> showEncodingRetryDialog(
  Ref ref,
  BuildContext context, {
  required String filePath,
  required Uint8List bytes,
}) {
  var selected = fileEncodingChoices.first.$1;
  String? errorText;
  return showDialog<({String text, String encoding})>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) => AlertDialog(
        title: Text(translate(ref, I18nKey.editorFileEncodingRetryTitle)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              translate(
                ref,
                I18nKey.editorFileEncodingRetryBody,
              ).replaceAll('{path}', path.basename(filePath)),
            ),
            const SizedBox(height: 8),
            RadioGroup<String>(
              groupValue: selected,
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  selected = value;
                  errorText = null;
                });
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (id, label) in fileEncodingChoices)
                    RadioListTile<String>(
                      value: id,
                      title: Text(label),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                ],
              ),
            ),
            if (errorText != null)
              Text(
                errorText!,
                style: TextStyle(
                  color: Theme.of(dialogContext).colorScheme.error,
                  fontSize: 12,
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(translate(ref, I18nKey.commonCancel)),
          ),
          FilledButton(
            onPressed: () {
              final text = decodeWithEncoding(bytes, selected);
              if (text == null) {
                setState(
                  () => errorText = translate(
                    ref,
                    I18nKey.editorFileEncodingRetryFailed,
                  ).replaceAll('{encoding}', encodingChoiceLabel(selected)!),
                );
                return;
              }
              Navigator.of(dialogContext).pop((text: text, encoding: selected));
            },
            child: Text(translate(ref, I18nKey.editorJumpGoToLocation)),
          ),
        ],
      ),
    ),
  );
}
