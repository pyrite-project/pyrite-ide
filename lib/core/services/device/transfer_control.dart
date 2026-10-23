import 'dart:async';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';

/// Cooperative cancellation token for a long transfer.
///
/// Modelled on `SearchCancelToken` in the search service: the token only holds
/// a flag, and the owning loop checks it at file boundaries. Nothing in this
/// token touches the serial line, so cancelling never sends CTRL-C or otherwise
/// interrupts a REPL transaction that is mid-write — the in-flight file is
/// allowed to finish and the loop stops before starting the next one.
class FileTransferCancelToken {
  bool _cancelled = false;

  /// Whether [cancel] has been requested.
  bool get isCancelled => _cancelled;

  /// Requests cancellation. Idempotent.
  void cancel() => _cancelled = true;
}

/// Thrown inside a transfer loop when the user cancels.
///
/// Callers catch this to report "已取消" instead of a failure: the device and
/// the REPL are untouched, so no recovery is needed.
class FileTransferCancelledException implements Exception {
  const FileTransferCancelledException([this.message = 'Transfer cancelled']);

  final String message;

  @override
  String toString() => 'FileTransferCancelledException: $message';
}

/// Throws [FileTransferCancelledException] when [token] has been cancelled.
void throwIfTransferCancelled(FileTransferCancelToken? token) {
  if (token?.isCancelled ?? false) {
    throw const FileTransferCancelledException();
  }
}

/// Result of a cancellable batch.
class BatchTransferOutcome {
  const BatchTransferOutcome({
    required this.processed,
    required this.cancelled,
  });

  /// Number of items whose action ran to completion.
  final int processed;

  /// Whether the loop stopped because of cancellation.
  final bool cancelled;

  bool get completedAll => !cancelled;
}

/// Runs [action] for each item, checking [token] before every item.
///
/// Extracted so cancellation semantics can be unit tested without a device: a
/// cancelled batch must stop *before* the next item starts and must report how
/// many items it had already processed. `action` is expected to be one whole
/// file/transaction so cancelling never leaves a half-written file behind.
Future<BatchTransferOutcome> runCancellableFileBatch<T>({
  required Iterable<T> items,
  required FileTransferCancelToken? token,
  required Future<void> Function(T item, int index) action,
  Future<bool> Function(T item, int index)? shouldSkip,
}) async {
  final itemList = items.toList(growable: false);
  var processed = 0;
  for (var index = 0; index < itemList.length; index++) {
    if (token?.isCancelled ?? false) {
      return BatchTransferOutcome(processed: processed, cancelled: true);
    }
    final item = itemList[index];
    if (shouldSkip != null && await shouldSkip(item, index)) continue;
    try {
      await action(item, index);
    } on FileTransferCancelledException {
      // The in-flight file reported cancellation instead of completing; the
      // loop still owns a consistent device state, so report it as an outcome.
      return BatchTransferOutcome(processed: processed, cancelled: true);
    }
    processed++;
  }
  return BatchTransferOutcome(processed: processed, cancelled: false);
}

/// Human readable byte size used in transfer/preflight messages.
String formatTransferBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

/// Outcome of comparing a byte requirement against the space the device
/// reports as free.
enum SpaceBudgetStatus {
  /// The requirement fits.
  fits,

  /// The device cannot report free space, so the check is skipped.
  unknown,

  /// The requirement does not fit.
  insufficient,
}

/// Result of [checkSpaceBudget].
class SpaceBudgetResult {
  const SpaceBudgetResult({
    required this.status,
    required this.freeBytes,
    required this.requiredBytes,
  });

  final SpaceBudgetStatus status;

  /// Free bytes reported by the device, or `null` when unavailable.
  final int? freeBytes;

  /// Bytes the pending upload needs.
  final int requiredBytes;

  bool get canProceed => status != SpaceBudgetStatus.insufficient;

  /// Message for the UI.
  ///
  /// Deliberately states both numbers so the user can decide what to delete.
  /// The i18n catalogue is owned by another module, so the text is built here
  /// and surfaced by callers as a normal error message.
  String get message {
    switch (status) {
      case SpaceBudgetStatus.insufficient:
        return I18nKey.devicesSpaceInsufficient.fallback
            .replaceAll('{required}', formatTransferBytes(requiredBytes))
            .replaceAll('{requiredBytes}', '$requiredBytes')
            .replaceAll('{free}', formatTransferBytes(freeBytes ?? 0))
            .replaceAll('{freeBytes}', '${freeBytes ?? 0}');
      case SpaceBudgetStatus.unknown:
        return I18nKey.devicesSpaceUnknown.fallback;
      case SpaceBudgetStatus.fits:
        return I18nKey.devicesSpaceSufficient.fallback
            .replaceAll('{required}', formatTransferBytes(requiredBytes))
            .replaceAll('{free}', formatTransferBytes(freeBytes ?? 0));
    }
  }
}

/// Pure pre-upload space budget check.
///
/// [freeBytes] is nullable on purpose: many MicroPython ports either have no
/// `os.statvfs` or return a zeroed tuple, and blocking uploads in that case
/// would be worse than skipping the check. A zero-byte requirement always
/// fits.
SpaceBudgetResult checkSpaceBudget(int? freeBytes, int requiredBytes) {
  if (requiredBytes <= 0) {
    return SpaceBudgetResult(
      status: SpaceBudgetStatus.fits,
      freeBytes: freeBytes,
      requiredBytes: requiredBytes,
    );
  }
  if (freeBytes == null || freeBytes <= 0) {
    return SpaceBudgetResult(
      status: SpaceBudgetStatus.unknown,
      freeBytes: freeBytes,
      requiredBytes: requiredBytes,
    );
  }
  return SpaceBudgetResult(
    status: requiredBytes <= freeBytes
        ? SpaceBudgetStatus.fits
        : SpaceBudgetStatus.insufficient,
    freeBytes: freeBytes,
    requiredBytes: requiredBytes,
  );
}

/// Raised before a transfer starts when the device lacks space.
class InsufficientDeviceSpaceException implements Exception {
  const InsufficientDeviceSpaceException(this.result);

  final SpaceBudgetResult result;

  String get message => result.message;

  @override
  String toString() => 'InsufficientDeviceSpaceException: ${result.message}';
}
